#!/usr/bin/env bash

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_ROOT/utils/validation.sh"
source "$SCRIPT_ROOT/utils/s3.sh"

PLAN_S3_PERMISSION_LEVEL=""

select_s3_permission_level() {
  echo "\nChoose the S3 permission level for the IAM user:"
  echo "1) ReadOnly"
  echo "2) ReadWrite"
  echo "3) FullBucketAdmin"
  while true; do
    read -r -p "Choose an option [1-3]: " choice
    case "$choice" in
      1) PLAN_S3_PERMISSION_LEVEL="ReadOnly"; break ;;
      2) PLAN_S3_PERMISSION_LEVEL="ReadWrite"; break ;;
      3) PLAN_S3_PERMISSION_LEVEL="FullBucketAdmin"; break ;;
      *) echo "Invalid selection. Choose 1, 2 or 3." ;;
    esac
  done
}

# Simulate block_b1 flow
echo "=== Simulating block_b1 flow ==="
bucket_name="demo-bucket-for-testing-policyscript"

echo "Testing bucket: $bucket_name"

if ! is_valid_s3_bucket_name "$bucket_name"; then
  echo "Invalid S3 bucket name format. Lowercase, 3-63 chars, no underscores."
  exit 1
fi

echo "Bucket name is valid, checking status..."
s3_bucket_status "$bucket_name"
case $? in
  0)
    echo "Bucket '$bucket_name' already exists. Choose another name."
    exit 0
    ;;
  2)
    echo "Bucket name '$bucket_name' is already taken by another AWS account. Choose a different name."
    exit 0
    ;;
  *)
    echo "Bucket does not exist (good for creation)"
    select_s3_permission_level
    echo "✓ Selected permission level: $PLAN_S3_PERMISSION_LEVEL"
    ;;
esac

echo "Debug test completed successfully"
