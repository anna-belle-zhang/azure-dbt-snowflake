"""
Decrypt Parquet files using Fernet (symmetric encryption)

This simulates Azure Function decryption in local environment.
Implements security controls:
- Key from secure location (simulates Key Vault)
- File hash validation (idempotency check)
- Temporary decrypted files (TTL simulation)
- Metadata tracking (batch_id, run_id)
"""

import sys
import hashlib
import json
from pathlib import Path
from cryptography.fernet import Fernet
from datetime import datetime
import pandas as pd


def load_key(key_file):
    """Load encryption key from file (simulates Azure Key Vault)"""
    if not key_file.exists():
        print(f"✗ Key file not found: {key_file}")
        print("  Run: python scripts/encrypt_parquet.py <file> first")
        sys.exit(1)

    with open(key_file, 'rb') as f:
        key = f.read()
    return key


def calculate_file_hash(file_path):
    """Calculate SHA-256 hash of file"""
    sha256 = hashlib.sha256()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b''):
            sha256.update(chunk)
    return sha256.hexdigest()


def decrypt_file(input_file, output_file, key):
    """Decrypt file using Fernet"""
    # Read encrypted file
    with open(input_file, 'rb') as f:
        encrypted_data = f.read()

    # Decrypt
    fernet = Fernet(key)
    try:
        decrypted_data = fernet.decrypt(encrypted_data)
    except Exception as e:
        print(f"✗ Decryption failed: {e}")
        print("  Possible causes:")
        print("    - Wrong encryption key")
        print("    - File is corrupted")
        print("    - File is not encrypted")
        sys.exit(1)

    # Write decrypted file
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, 'wb') as f:
        f.write(decrypted_data)

    # Calculate hash of decrypted file
    decrypted_hash = calculate_file_hash(output_file)

    return {
        'encrypted_size_bytes': len(encrypted_data),
        'decrypted_size_bytes': len(decrypted_data),
        'decrypted_file_hash': decrypted_hash,
        'decryption_timestamp': datetime.now().isoformat(),
    }


def validate_parquet(parquet_file):
    """Validate decrypted Parquet file"""
    try:
        df = pd.read_parquet(parquet_file)
        return {
            'is_valid': True,
            'row_count': len(df),
            'column_count': len(df.columns),
            'columns': list(df.columns),
            'memory_usage_mb': df.memory_usage(deep=True).sum() / 1024 / 1024,
        }
    except Exception as e:
        return {
            'is_valid': False,
            'error': str(e),
        }


def load_encryption_metadata(metadata_file):
    """Load original encryption metadata for validation"""
    if not metadata_file.exists():
        return None

    with open(metadata_file, 'r') as f:
        return json.load(f)


def main():
    """Decrypt Parquet file with security controls"""

    if len(sys.argv) < 2:
        print("Usage: python decrypt_parquet.py <encrypted_filename>")
        print("Example: python decrypt_parquet.py customers_20240106_120000.parquet.encrypted")
        sys.exit(1)

    # Setup paths
    base_dir = Path(__file__).parent.parent
    input_filename = sys.argv[1]
    input_file = base_dir / 'data' / 'encrypted' / input_filename

    if not input_file.exists():
        print(f"✗ Encrypted file not found: {input_file}")
        sys.exit(1)

    # Output to decrypted directory (temporary staging)
    output_filename = input_file.stem  # Remove .encrypted extension
    output_file = base_dir / 'data' / 'decrypted' / f'{output_filename}'
    key_file = base_dir / 'keys' / 'encryption.key'
    metadata_file = input_file.with_suffix('.json')

    print("=" * 80)
    print("PARQUET FILE DECRYPTION (Secure Compute Boundary)")
    print("=" * 80)
    print(f"Encrypted file: {input_file}")
    print(f"Decrypted file: {output_file}")
    print(f"Key file:       {key_file}")
    print(f"Metadata file:  {metadata_file}")
    print()

    # Load encryption metadata (for validation)
    original_metadata = load_encryption_metadata(metadata_file)
    if original_metadata:
        print("Original encryption metadata:")
        print(f"  File hash:  {original_metadata.get('file_hash_sha256', 'N/A')}")
        print(f"  Encrypted:  {original_metadata.get('encryption_timestamp', 'N/A')}")
        print(f"  Size:       {original_metadata.get('original_size_bytes', 0):,} bytes")
        print()

    # Load key (simulates Azure Key Vault access via managed identity)
    print("Fetching decryption key from secure storage...")
    key = load_key(key_file)
    print("✓ Key retrieved")
    print()

    # Decrypt file
    print("Decrypting file...")
    decrypt_metadata = decrypt_file(input_file, output_file, key)
    print("✓ Decryption complete!")
    print()

    # Validate hash (idempotency check)
    if original_metadata and 'file_hash_sha256' in original_metadata:
        if decrypt_metadata['decrypted_file_hash'] == original_metadata['file_hash_sha256']:
            print("✓ File hash matches (idempotency validated)")
        else:
            print("✗ WARNING: File hash mismatch!")
            print(f"  Expected: {original_metadata['file_hash_sha256']}")
            print(f"  Got:      {decrypt_metadata['decrypted_file_hash']}")

    print()
    print("=" * 80)
    print("PARQUET VALIDATION")
    print("=" * 80)

    # Validate Parquet file
    validation = validate_parquet(output_file)

    if validation['is_valid']:
        print("✓ Decrypted file is valid Parquet")
        print(f"  Rows:    {validation['row_count']:,}")
        print(f"  Columns: {validation['column_count']}")
        print(f"  Memory:  {validation['memory_usage_mb']:.2f} MB")
        print(f"  Schema:  {', '.join(validation['columns'])}")

        # Preview data
        df = pd.read_parquet(output_file)
        print()
        print("Sample data (first 3 rows):")
        print(df.head(3))
    else:
        print(f"✗ Decrypted file is not valid Parquet: {validation['error']}")
        sys.exit(1)

    # Create processing metadata (for Airflow/dbt)
    processing_metadata = {
        'batch_id': f"batch_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
        'run_id': datetime.now().isoformat(),
        'source_file': input_filename,
        'decrypted_file': output_file.name,
        'file_hash': decrypt_metadata['decrypted_file_hash'],
        'row_count': validation['row_count'],
        'schema': validation['columns'],
        'decryption_timestamp': decrypt_metadata['decryption_timestamp'],
        'status': 'ready_for_load',
    }

    processing_metadata_file = output_file.with_suffix('.meta.json')
    with open(processing_metadata_file, 'w') as f:
        json.dump(processing_metadata, f, indent=2)

    print()
    print("=" * 80)
    print("PROCESSING METADATA")
    print("=" * 80)
    print(f"Batch ID: {processing_metadata['batch_id']}")
    print(f"Run ID:   {processing_metadata['run_id']}")
    print(f"Metadata: {processing_metadata_file}")
    print()
    print("Next steps:")
    print("  1. Load to MySQL bronze layer (via Airflow DAG)")
    print("  2. Run dbt transformations")
    print("  3. Archive encrypted file")
    print()
    print("⚠️  Security Note:")
    print("   Decrypted file is temporary and should be deleted after loading")
    print("   In production, TTL would be enforced by Azure Blob Storage lifecycle policy")


if __name__ == '__main__':
    main()
