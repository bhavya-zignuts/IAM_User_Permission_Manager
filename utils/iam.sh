#!/usr/bin/env bash

set -euo pipefail

get_account_id() {
  aws sts get-caller-identity --query "Account" --output text 2>/dev/null
}

iam_user_exists() {
  local user_name="$1"
  if aws iam get-user --user-name "$user_name" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

create_iam_user() {
  local user_name="$1"
  aws iam create-user --user-name "$user_name" >/dev/null
}

iam_policy_exists() {
  local policy_name="$1"
  if aws iam list-policies --scope Local --query "Policies[?PolicyName=='${policy_name}'] | [0].Arn" --output text | grep -q 'arn:'; then
    return 0
  fi
  return 1
}

get_policy_arn_by_name() {
  local policy_name="$1"
  aws iam list-policies --scope Local --query "Policies[?PolicyName=='${policy_name}'] | [0].Arn" --output text
}

create_policy_from_file() {
  local policy_name="$1"
  local file_path="$2"
  aws iam create-policy --policy-name "$policy_name" --policy-document file://"$file_path" --query "Policy.Arn" --output text
}

attach_policy_to_user() {
  local user_name="$1"
  local policy_arn="$2"
  aws iam attach-user-policy --user-name "$user_name" --policy-arn "$policy_arn"
}

detach_policy_from_user() {
  local user_name="$1"
  local policy_arn="$2"
  aws iam detach-user-policy --user-name "$user_name" --policy-arn "$policy_arn"
}

render_template() {
  local template_path="$1"
  local output_file="$2"
  shift 2
  cp "$template_path" "$output_file"
  for kv in "$@"; do
    local key="${kv%%=*}"
    local value="${kv#*=}"
    sed -i.bak "s|\\\${${key}}|${value}|g" "$output_file"
    rm -f "$output_file.bak"
  done
}
