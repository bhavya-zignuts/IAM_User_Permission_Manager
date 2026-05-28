#!/usr/bin/env bash

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_ROOT/config.sh"
source "$SCRIPT_ROOT/utils/iam.sh"
source "$SCRIPT_ROOT/utils/s3.sh"
source "$SCRIPT_ROOT/utils/codecommit.sh"

echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S') Starting rollback" | tee -a "$LOG_FILE"

if [[ -n "${ROLLBACK_RESOURCES:-}" ]]; then
  IFS=$' ' read -ra resources <<< "$ROLLBACK_RESOURCES"
  for ((idx=${#resources[@]}-1; idx>=0; idx--)); do
    item="${resources[$idx]}"
    type="${item%%:*}"
    name="${item#*:}"
    case "$type" in
      access-key)
        user_name="${name%%|*}"
        access_key_id="${name#*|}"
        echo "[INFO] Rolling back access key for $user_name" | tee -a "$LOG_FILE"
        delete_access_key_for_user "$user_name" "$access_key_id" || true
        ;;
      login-profile)
        echo "[INFO] Rolling back console login profile for $name" | tee -a "$LOG_FILE"
        delete_login_profile "$name" || true
        ;;
      attachment)
        user_name="${name%%|*}"
        policy_arn="${name#*|}"
        echo "[INFO] Rolling back policy attachment from $user_name" | tee -a "$LOG_FILE"
        detach_policy_from_user "$user_name" "$policy_arn" || true
        ;;
      user)
        if iam_user_exists "$name"; then
          echo "[INFO] Rolling back IAM user: $name" | tee -a "$LOG_FILE"
          aws iam delete-user --user-name "$name" || true
        fi
        ;;
      policy)
        if iam_policy_exists "$name"; then
          echo "[INFO] Rolling back IAM policy: $name" | tee -a "$LOG_FILE"
          policy_arn="$(get_policy_arn_by_name "$name")"
          if [[ -n "$policy_arn" ]]; then
            aws iam delete-policy --policy-arn "$policy_arn" || true
          fi
        fi
        ;;
      bucket)
        if s3_bucket_exists "$name"; then
          echo "[INFO] Rolling back S3 bucket: $name" | tee -a "$LOG_FILE"
          aws s3 rb "s3://$name" --force || true
        fi
        ;;
      repo)
        if codecommit_repo_exists "$name"; then
          echo "[INFO] Rolling back CodeCommit repo: $name" | tee -a "$LOG_FILE"
          delete_codecommit_repo "$name" || true
        fi
        ;;
      *)
        echo "[WARN] Unknown rollback type: $item" | tee -a "$LOG_FILE"
        ;;
    esac
  done
fi

echo "[INFO] Rollback completed" | tee -a "$LOG_FILE"
