#!/usr/bin/env bash

set -euo pipefail

is_valid_iam_username() {
  local name="$1"
  if [[ "$name" =~ ^[A-Za-z0-9+=,.@_-]{1,64}$ ]]; then
    return 0
  fi
  return 1
}

is_valid_s3_bucket_name() {
  local name="$1"
  if [[ ${#name} -lt 3 || ${#name} -gt 63 ]]; then
    return 1
  fi
  if [[ "$name" =~ [A-Z_] ]]; then
    return 1
  fi
  if [[ ! "$name" =~ ^[a-z0-9][a-z0-9.-]+[a-z0-9]$ ]]; then
    return 1
  fi
  if [[ "$name" =~ [.]\. ]]; then
    return 1
  fi
  if [[ "$name" =~ [-][.]|[.][-] ]]; then
    return 1
  fi
  return 0
}

is_valid_policy_name() {
  local name="$1"
  if [[ "$name" =~ ^[A-Za-z0-9+=,.@_-]{1,128}$ ]]; then
    return 0
  fi
  return 1
}

is_valid_repo_name() {
  local name="$1"
  if [[ ${#name} -lt 1 || ${#name} -gt 100 ]]; then
    return 1
  fi
  if [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    return 0
  fi
  return 1
}

confirm() {
  local prompt="$1"
  local response
  while true; do
    read -r -p "$prompt [y/N]: " response
    response="$(printf '%s' "$response" | tr '[:upper:]' '[:lower:]')"
    case "$response" in
      y|yes) return 0 ;; 
      n|no|"") return 1 ;; 
      *) echo "Please answer yes or no." ;;
    esac
  done
}
