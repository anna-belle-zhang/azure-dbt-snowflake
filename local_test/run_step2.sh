#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DECRYPTED_DIR="${REPO_ROOT}/local_test/data/decrypted"

echo "==> Step 2: Generate sample data"
cd "${REPO_ROOT}"
python local_test/scripts/generate_data.py

echo
echo "==> Locating latest generated Parquet files"
customers_file="$(ls -t "${DECRYPTED_DIR}"/customers_*.parquet 2>/dev/null | head -n 1 || true)"
orders_file="$(ls -t "${DECRYPTED_DIR}"/orders_*.parquet 2>/dev/null | head -n 1 || true)"

if [[ -z "${customers_file}" || -z "${orders_file}" ]]; then
  echo "Could not find generated Parquet files in ${DECRYPTED_DIR}"
  exit 1
fi

customers_base="$(basename "${customers_file}")"
orders_base="$(basename "${orders_file}")"

echo "Latest customers file: ${customers_base}"
echo "Latest orders file:    ${orders_base}"
echo

echo "==> Encrypting customers file"
python local_test/scripts/encrypt_parquet.py "${customers_base}"

echo
echo "==> Encrypting orders file"
python local_test/scripts/encrypt_parquet.py "${orders_base}"

echo
echo "Step 2 complete. Encrypted files are in local_test/data/encrypted."
