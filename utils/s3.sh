#!/usr/bin/env bash

set -euo pipefail

s3_bucket_status() {
  local bucket_name="$1"
  local output

  if output=$(aws s3api head-bucket --bucket "$bucket_name" --region "$AWS_REGION" 2>&1); then
    return 0
  fi

  if s3_bucket_owned_by_account "$bucket_name"; then
    return 0
  fi

  if [[ "$output" =~ NoSuchBucket|Not[[:space:]]Found|404 ]]; then
    return 1
  fi

  if [[ "$output" =~ Forbidden|403|301|PermanentRedirect|AccessDenied ]]; then
    return 2
  fi

  return 1
}

s3_bucket_owned_by_account() {
  local bucket_name="$1"
  local found

  found=$(aws s3api list-buckets \
    --query "Buckets[?Name=='${bucket_name}'].Name | [0]" \
    --output text 2>/dev/null) || return 1

  [[ "$found" == "$bucket_name" ]]
}

s3_bucket_exists() {
  local bucket_name="$1"
  if s3_bucket_status "$bucket_name"; then
    return 0
  fi
  return 1
}

create_s3_bucket() {
  local bucket_name="$1"
  local region="$2"
  local output

  if [[ "$region" == "us-east-1" ]]; then
    if output=$(aws s3api create-bucket --bucket "$bucket_name" 2>&1); then
      return 0
    fi
  else
    if output=$(aws s3api create-bucket --bucket "$bucket_name" --create-bucket-configuration LocationConstraint="$region" 2>&1); then
      return 0
    fi
  fi

  if [[ "$output" =~ BucketAlreadyExists ]]; then
    echo "Bucket name '$bucket_name' is already taken by another AWS account." >&2
  elif [[ "$output" =~ BucketAlreadyOwnedByYou ]]; then
    echo "Bucket '$bucket_name' is already owned by this account." >&2
  else
    echo "$output" >&2
  fi
  return 1
}

s3_policy_actions() {
  local level="$1"
  case "$level" in
    ReadOnly)
      cat <<'EOF'
["s3:GetObject","s3:ListBucket","s3:GetBucketLocation"]
EOF
      ;;
    ReadWrite)
      cat <<'EOF'
["s3:GetObject","s3:ListBucket","s3:GetBucketLocation","s3:PutObject","s3:DeleteObject","s3:PutObjectAcl","s3:GetObjectAcl"]
EOF
      ;;
    FullBucketAdmin)
      cat <<'EOF'
["s3:GetObject","s3:ListBucket","s3:GetBucketLocation","s3:PutObject","s3:DeleteObject","s3:PutObjectAcl","s3:GetObjectAcl","s3:PutBucketAcl","s3:PutBucketPolicy","s3:PutBucketCORS","s3:PutBucketLogging","s3:PutBucketVersioning","s3:PutBucketWebsite","s3:PutBucketTagging","s3:GetBucketPolicy","s3:GetBucketAcl"]
EOF
      ;;
    *)
      echo "[]"
      ;;
  esac
}

build_s3_policy_json() {
  local bucket_name="$1"
  local permission_level="$2"
  local output_file="$3"
  local actions
  actions="$(s3_policy_actions "$permission_level")"
  cp "$POLICY_DIR/s3-template.json" "$output_file"
  sed -i.bak "s|{{ACTIONS}}|${actions}|g" "$output_file"
  sed -i.bak "s|\${BUCKET_NAME}|${bucket_name}|g" "$output_file"
  rm -f "$output_file.bak"
}
