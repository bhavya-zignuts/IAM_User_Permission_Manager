#!/usr/bin/env bash

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_ROOT/utils/validation.sh"
source "$SCRIPT_ROOT/utils/s3.sh"

echo "Testing bucket name validation..."
bucket_name="demo-bucket-for-testing-policyscript"

if is_valid_s3_bucket_name "$bucket_name"; then
  echo "✓ Bucket name '$bucket_name' is valid"
else
  echo "✗ Bucket name '$bucket_name' is INVALID"
  exit 1
fi

echo "Testing s3_bucket_status function..."
echo "Calling: s3_bucket_status '$bucket_name'"
if s3_bucket_status "$bucket_name"; then
  echo "Status: Bucket exists (return code 0)"
else
  rc=$?
  case $rc in
    1) echo "Status: Bucket does not exist (return code 1)" ;;
    2) echo "Status: Bucket exists but not accessible (return code 2)" ;;
    *) echo "Status: Unknown return code $rc" ;;
  esac
fi

echo "All tests completed successfully"
