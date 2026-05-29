#!/usr/bin/env bash

set -euo pipefail

get_account_id() {
  aws sts get-caller-identity --query "Account" --output text 2>/dev/null
}

get_account_alias() {
  local alias
  alias="$(aws iam list-account-aliases --query "AccountAliases[0]" --output text 2>/dev/null)" || return 1
  if [[ "$alias" == "None" ]]; then
    return 1
  fi
  printf '%s\n' "$alias"
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

create_login_profile() {
  local user_name="$1"
  local password="$2"
  aws iam create-login-profile \
    --user-name "$user_name" \
    --password "$password" \
    --no-password-reset-required >/dev/null
}

login_profile_exists() {
  local user_name="$1"
  if aws iam get-login-profile --user-name "$user_name" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

delete_login_profile() {
  local user_name="$1"
  aws iam delete-login-profile --user-name "$user_name" >/dev/null
}

get_account_password_policy_value() {
  local key="$1"
  aws iam get-account-password-policy \
    --query "PasswordPolicy.${key}" \
    --output text 2>/dev/null
}

create_access_key_for_user() {
  local user_name="$1"
  aws iam create-access-key \
    --user-name "$user_name" \
    --query "AccessKey.[AccessKeyId,SecretAccessKey]" \
    --output text
}

delete_access_key_for_user() {
  local user_name="$1"
  local access_key_id="$2"
  aws iam delete-access-key --user-name "$user_name" --access-key-id "$access_key_id" >/dev/null
}

codecommit_service_credential_exists() {
  local user_name="$1"
  local count
  count="$(aws iam list-service-specific-credentials \
    --user-name "$user_name" \
    --service-name codecommit.amazonaws.com \
    --query "length(ServiceSpecificCredentials)" \
    --output text 2>/dev/null)" || return 1
  [[ "$count" =~ ^[1-9][0-9]*$ ]]
}

create_codecommit_service_credential_for_user() {
  local user_name="$1"
  aws iam create-service-specific-credential \
    --user-name "$user_name" \
    --service-name codecommit.amazonaws.com \
    --query "ServiceSpecificCredential.[ServiceUserName,ServicePassword,ServiceSpecificCredentialId]" \
    --output text
}

delete_codecommit_service_credential_for_user() {
  local user_name="$1"
  local credential_id="$2"
  aws iam delete-service-specific-credential \
    --user-name "$user_name" \
    --service-specific-credential-id "$credential_id" >/dev/null
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
