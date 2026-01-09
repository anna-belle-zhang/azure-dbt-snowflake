"""
Local Test Pipeline DAG - Encrypted Parquet to MySQL

This DAG simulates the production architecture:
1. Detect encrypted files
2. Decrypt using Python script
3. Load to MySQL bronze layer
4. Run dbt transformations (bronze -> silver -> gold -> semantic)
5. Validate data quality
6. Archive processed files
"""

from airflow import DAG
from airflow.decorators import task
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta
import subprocess
import pandas as pd
from pathlib import Path
import shutil

# DAG default arguments
default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=1),
}


@task
def detect_encrypted_files():
    """Detect new encrypted files in landing zone"""
    # Using container-accessible path
    encrypted_dir = Path('/mnt/e/A/azure-dbt-snowflake/local_test/data/encrypted')

    if not encrypted_dir.exists():
        print(f"Directory not found: {encrypted_dir}")
        print("This directory needs to be mounted in the container")
        return None

    encrypted_files = list(encrypted_dir.glob('*.parquet.encrypted'))

    if not encrypted_files:
        print("No encrypted files found")
        return None

    # For now, process the first file
    file_to_process = str(encrypted_files[0])

    print(f"Found {len(encrypted_files)} encrypted file(s)")
    print(f"Processing: {file_to_process}")

    return file_to_process


@task
def decrypt_file(encrypted_file: str):
    """Decrypt Parquet file using Python script"""
    if not encrypted_file:
        print("No encrypted file to process - skipping")
        return None

    script_path = '/mnt/e/A/azure-dbt-snowflake/local_test/scripts/decrypt_parquet.py'

    if not Path(script_path).exists():
        print(f"Decryption script not found: {script_path}")
        print("Required directories need to be mounted in the container")
        return None

    # Run decryption script
    result = subprocess.run(
        ['python', script_path, Path(encrypted_file).name],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print("STDOUT:", result.stdout)
        print("STDERR:", result.stderr)
        raise RuntimeError(f"Decryption failed: {result.stderr}")

    print("Decryption output:")
    print(result.stdout)

    # Parse output
    decrypted_file = encrypted_file.replace('.encrypted', '').replace('encrypted', 'decrypted')

    return decrypted_file


@task
def create_mysql_databases():
    """Create MySQL databases if they don't exist"""
    import pymysql

    try:
        conn = pymysql.connect(
            host='openmetadata_mysql',
            user='nocodb',
            password='nocodb123',
            port=3306
        )
        cursor = conn.cursor()

        # We'll use nocodb_db as per permissions
        cursor.execute("SHOW DATABASES LIKE 'nocodb_db'")
        result = cursor.fetchone()

        if result:
            print("Database nocodb_db already exists - using it for all layers")
        else:
            print("Database nocodb_db not found")

        cursor.close()
        conn.close()

        return "nocodb_db"

    except Exception as e:
        print(f"Database check error: {str(e)}")
        raise


@task
def load_to_mysql(decrypted_file: str):
    """Load decrypted Parquet to MySQL bronze layer"""
    if not decrypted_file or not Path(decrypted_file).exists():
        print(f"Decrypted file not found: {decrypted_file}")
        return 0

    # Read Parquet
    df = pd.read_parquet(decrypted_file)

    # Determine table name
    file_name = Path(decrypted_file).stem
    if 'customers' in file_name:
        table_name = 'src_customers'
    elif 'orders' in file_name:
        table_name = 'src_orders'
    else:
        raise ValueError(f"Unknown file type: {file_name}")

    # Load to MySQL
    from sqlalchemy import create_engine
    engine = create_engine('mysql+pymysql://nocodb:nocodb123@openmetadata_mysql:3306/nocodb_db')

    # Ensure CDC columns exist for customer files even if the source parquet lacks them
    if table_name == 'src_customers':
        current_ts = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S')
        if 'change_type' not in df.columns:
            df['change_type'] = 'insert'
        else:
            df['change_type'] = df['change_type'].fillna('insert')

        if 'effective_at' not in df.columns:
            df['effective_at'] = current_ts
        else:
            df['effective_at'] = df['effective_at'].fillna(current_ts)

    df.to_sql(table_name, engine, if_exists='replace', index=False)

    print(f"Loaded {len(df)} rows to nocodb_db.{table_name}")

    return len(df)


@task(trigger_rule='all_done')
def cleanup_decrypted_files(decrypted_file: str):
    """Remove temporary decrypted files (TTL simulation)"""
    if decrypted_file and Path(decrypted_file).exists():
        decrypted_path = Path(decrypted_file)
        decrypted_path.unlink()
        print(f"Deleted temporary file: {decrypted_file}")

        # Also delete metadata file
        meta_file = decrypted_path.with_suffix('.meta.json')
        if meta_file.exists():
            meta_file.unlink()
            print(f"Deleted metadata file: {meta_file}")
        else:
            print(f"No decrypted metadata file found for cleanup: {meta_file}")
    else:
        print(f"No file to clean up: {decrypted_file}")


@task(trigger_rule='all_success')
def archive_encrypted_file(encrypted_file: str):
    """Move processed encrypted file to archive"""
    if not encrypted_file:
        print("No file to archive")
        return

    archive_dir = Path('/mnt/e/A/azure-dbt-snowflake/local_test/data/archive')
    archive_dir.mkdir(parents=True, exist_ok=True)

    source = Path(encrypted_file)
    if not source.exists():
        print(f"Source encrypted file not found: {encrypted_file}")
        return

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    archived_target = archive_dir / f"{timestamp}_{source.name}"
    try:
        shutil.move(str(source), archived_target)
        print(f"Archived encrypted file: {source.name} -> {archived_target}")
    except Exception as exc:
        print(f"Failed to move encrypted file {source} to archive: {exc}")
        raise

    # Move encryption metadata (if present)
    metadata_source = source.with_suffix('.json')
    if metadata_source.exists():
        metadata_target = archive_dir / f"{timestamp}_{metadata_source.name}"
        try:
            shutil.move(str(metadata_source), metadata_target)
            print(f"Archived metadata file: {metadata_source.name} -> {metadata_target}")
        except Exception as exc:
            print(f"Failed to move metadata file {metadata_source} to archive: {exc}")
            raise
    else:
        print(f"No metadata JSON found for {source.name}")


# Define DAG
with DAG(
    'local_encrypted_pipeline',
    default_args=default_args,
    description='Local test pipeline for encrypted Parquet to MySQL',
    schedule=None,  # Manual trigger
    start_date=datetime(2026, 1, 1),
    tags=['local', 'test', 'encrypted'],
    catchup=False,
) as dag:

    # Task flow using TaskFlow API
    # Step 1: Detect encrypted files
    encrypted_file = detect_encrypted_files()

    # Step 2: Decrypt the file
    decrypted_file = decrypt_file(encrypted_file)

    # Step 3: Verify MySQL database (can run in parallel with decryption)
    db_name = create_mysql_databases()

    # Step 4: Load to MySQL (depends on both decrypted file AND database being ready)
    row_count = load_to_mysql(decrypted_file)

    # Task 5: Install dbt packages (dbt_utils, etc.) before any run/test
    dbt_deps = BashOperator(
        task_id='dbt_deps',
        bash_command="""
            if [ -d "/mnt/e/A/azure-dbt-snowflake/local_test/dbt_local" ]; then
                cd /mnt/e/A/azure-dbt-snowflake/local_test/dbt_local && \
                dbt deps --profiles-dir .
            else
                echo "dbt directory not mounted - skipping package install"
                echo "Mount /mnt/e/A/azure-dbt-snowflake/local_test to /mnt/e/A/azure-dbt-snowflake/local_test in container"
            fi
        """,
    )

    # Task 6: Run dbt (all layers) - only if dbt is available in container
    dbt_run = BashOperator(
        task_id='dbt_run',
        bash_command="""
            if [ -d "/mnt/e/A/azure-dbt-snowflake/local_test/dbt_local" ]; then
                cd /mnt/e/A/azure-dbt-snowflake/local_test/dbt_local && \
                dbt run --profiles-dir . --vars '{batch_id: "{{ run_id }}", execution_date: "{{ ds }}"}'
            else
                echo "dbt directory not mounted - skipping transformations"
                echo "Mount /mnt/e/A/azure-dbt-snowflake/local_test to /mnt/e/A/azure-dbt-snowflake/local_test in container"
            fi
        """,
    )

    # Task 7: Run dbt tests
    dbt_test = BashOperator(
        task_id='dbt_test',
        bash_command="""
            if [ -d "/mnt/e/A/azure-dbt-snowflake/local_test/dbt_local" ]; then
                cd /mnt/e/A/azure-dbt-snowflake/local_test/dbt_local && \
                dbt test --profiles-dir .
            else
                echo "dbt directory not mounted - skipping tests"
            fi
        """,
    )

    cleanup = cleanup_decrypted_files(decrypted_file)
    archive = archive_encrypted_file(encrypted_file)

    # Define task dependencies
    # Ensure database check completes before loading data
    db_name >> row_count

    # Main pipeline flow: load → dbt deps → dbt_run → dbt_test → cleanup/archive
    row_count >> dbt_deps >> dbt_run >> dbt_test >> [cleanup, archive]
