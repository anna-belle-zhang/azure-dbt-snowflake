"""
Encrypt Parquet files using Fernet (symmetric encryption)

This simulates Azure Key Vault encryption in local environment.
"""

import sys
import hashlib
from pathlib import Path
from cryptography.fernet import Fernet
from datetime import datetime
import json


def generate_key(key_file):
    """Generate and save encryption key"""
    key = Fernet.generate_key()
    key_file.parent.mkdir(parents=True, exist_ok=True)
    with open(key_file, 'wb') as f:
        f.write(key)
    print(f"✓ Generated encryption key: {key_file}")
    return key


def load_key(key_file):
    """Load encryption key from file"""
    if not key_file.exists():
        print(f"✗ Key file not found. Generating new key...")
        return generate_key(key_file)

    with open(key_file, 'rb') as f:
        key = f.read()
    return key


def calculate_file_hash(file_path):
    """Calculate SHA-256 hash of file (for idempotency check)"""
    sha256 = hashlib.sha256()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b''):
            sha256.update(chunk)
    return sha256.hexdigest()


def encrypt_file(input_file, output_file, key):
    """Encrypt file using Fernet"""
    # Read file
    with open(input_file, 'rb') as f:
        data = f.read()

    # Calculate hash before encryption
    file_hash = calculate_file_hash(input_file)

    # Encrypt
    fernet = Fernet(key)
    encrypted_data = fernet.encrypt(data)

    # Write encrypted file
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, 'wb') as f:
        f.write(encrypted_data)

    # Create metadata file
    metadata = {
        'original_filename': input_file.name,
        'encrypted_filename': output_file.name,
        'file_hash_sha256': file_hash,
        'original_size_bytes': len(data),
        'encrypted_size_bytes': len(encrypted_data),
        'encryption_timestamp': datetime.now().isoformat(),
        'encryption_method': 'Fernet (AES-128)',
    }

    metadata_file = output_file.with_suffix('.json')
    with open(metadata_file, 'w') as f:
        json.dump(metadata, f, indent=2)

    return metadata


def main():
    """Encrypt Parquet file"""

    if len(sys.argv) < 2:
        print("Usage: python encrypt_parquet.py <filename>")
        print("Example: python encrypt_parquet.py customers_20240106_120000.parquet")
        sys.exit(1)

    # Setup paths
    base_dir = Path(__file__).parent.parent
    input_filename = sys.argv[1]
    input_file = base_dir / 'data' / 'decrypted' / input_filename

    if not input_file.exists():
        print(f"✗ File not found: {input_file}")
        sys.exit(1)

    output_file = base_dir / 'data' / 'encrypted' / f'{input_file.stem}.parquet.encrypted'
    key_file = base_dir / 'keys' / 'encryption.key'

    print("=" * 80)
    print("PARQUET FILE ENCRYPTION")
    print("=" * 80)
    print(f"Input file:  {input_file}")
    print(f"Output file: {output_file}")
    print(f"Key file:    {key_file}")
    print()

    # Load or generate key
    key = load_key(key_file)

    # Encrypt file
    print("Encrypting file...")
    metadata = encrypt_file(input_file, output_file, key)

    print("✓ Encryption complete!")
    print()
    print("Metadata:")
    for key_name, value in metadata.items():
        print(f"  {key_name}: {value}")

    print()
    print("=" * 80)
    print("VERIFICATION")
    print("=" * 80)

    # Verify encrypted file cannot be read as Parquet
    try:
        import pandas as pd
        df = pd.read_parquet(output_file)
        print("✗ WARNING: Encrypted file can still be read as Parquet (encryption may have failed)")
    except Exception as e:
        print(f"✓ Encrypted file is not readable as Parquet (expected)")
        print(f"  Error: {type(e).__name__}")

    print()
    print("Next steps:")
    print(f"  1. Decrypt: python scripts/decrypt_parquet.py {output_file.name}")
    print(f"  2. Trigger Airflow DAG to process encrypted file")


if __name__ == '__main__':
    main()
