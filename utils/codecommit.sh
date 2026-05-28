#!/usr/bin/env bash

set -euo pipefail

codecommit_repo_exists() {
  local repo_name="$1"
  if aws codecommit get-repository --repository-name "$repo_name" --region "$AWS_REGION" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

create_codecommit_repo() {
  local repo_name="$1"
  aws codecommit create-repository \
    --repository-name "$repo_name" \
    --repository-description "Managed by IAM automation script" \
    --region "$AWS_REGION" >/dev/null
}

delete_codecommit_repo() {
  local repo_name="$1"
  aws codecommit delete-repository --repository-name "$repo_name" --region "$AWS_REGION" >/dev/null
}
