#!/usr/bin/env bash

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_ROOT/config.sh"
source "$SCRIPT_ROOT/utils/validation.sh"
source "$SCRIPT_ROOT/utils/iam.sh"
source "$SCRIPT_ROOT/utils/s3.sh"
source "$SCRIPT_ROOT/utils/codecommit.sh"

declare -a CREATED_RESOURCES=()
APPLY_STARTED=0
ROLLBACK_IN_PROGRESS=0
PLAN_USER_ACTION=""
PLAN_IAM_USER=""
PLAN_S3_ACTION=""
PLAN_S3_BUCKET=""
PLAN_S3_PERMISSION_LEVEL=""
PLAN_CODECOMMIT_ACTION=""
PLAN_CODECOMMIT_REPO=""
PLAN_CODECOMMIT_POLICY_NAME=""
PLAN_CODECOMMIT_POLICY_TYPE=""
PLAN_S3_POLICY_NAME=""
PLAN_EXISTING_POLICY_NAME=""

log_info() {
  local message="$1"
  echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S') $message" | tee -a "$LOG_FILE"
}

log_error() {
  local message="$1"
  echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S') $message" | tee -a "$LOG_FILE" >&2
}

handle_error() {
  local line_no="$1"
  local exit_code="$2"
  log_error "Line $line_no failed with status $exit_code."
  if [[ "$APPLY_STARTED" -eq 1 && "$ROLLBACK_IN_PROGRESS" -eq 0 ]]; then
    log_error "Apply failed after changes started. Rolling back resources created by this run."
    rollback_resources
  fi
  exit "$exit_code"
}

trap 'handle_error "$LINENO" "$?"' ERR

select_region() {
  echo "Select AWS Region for S3/CodeCommit operations:"
  echo "1) ap-south-1"
  echo "2) us-east-1"
  echo "3) custom"
  while true; do
    read -r -p "Choose region [1-3]: " choice
    case "$choice" in
      1) AWS_REGION="ap-south-1"; break ;; 
      2) AWS_REGION="us-east-1"; break ;; 
      3)
        read -r -p "Enter AWS region: " custom_region
        if [[ -n "$custom_region" ]]; then
          AWS_REGION="$custom_region"
          break
        fi
        ;;
      *) echo "Invalid selection. Choose 1, 2, or 3." ;;
    esac
  done
  log_info "Selected region: $AWS_REGION"
}

queue_resource() {
  CREATED_RESOURCES+=("$1")
}

rollback_resources() {
  ROLLBACK_IN_PROGRESS=1
  if [[ ${#CREATED_RESOURCES[@]} -eq 0 ]]; then
    log_info "No resources to rollback."
    ROLLBACK_IN_PROGRESS=0
    return
  fi
  export AWS_REGION
  export ROLLBACK_RESOURCES="${CREATED_RESOURCES[*]}"
  bash "$SCRIPT_ROOT/rollback.sh" || true
  ROLLBACK_IN_PROGRESS=0
}

review_changes() {
  echo
  echo "====== REVIEW CHANGES ======"
  echo "IAM User:          $PLAN_IAM_USER"
  if [[ "$PLAN_USER_ACTION" == "new" ]]; then
    echo "IAM User Action:   Create user"
  else
    echo "IAM User Action:   Existing user"
  fi
  if [[ "$PLAN_S3_ACTION" != "" ]]; then
    echo "Service:           S3"
    if [[ "$PLAN_S3_ACTION" == "new" ]]; then
      echo "S3 Bucket Action:  Create bucket"
    else
      echo "S3 Bucket Action:  Existing bucket"
    fi
    echo "S3 Bucket:         $PLAN_S3_BUCKET"
    echo "S3 Permission:     $PLAN_S3_PERMISSION_LEVEL"
  fi
  if [[ "$PLAN_CODECOMMIT_ACTION" != "" ]]; then
    echo "Service:           CodeCommit"
    if [[ "$PLAN_CODECOMMIT_ACTION" == "new" ]]; then
      echo "Repo Action:       Create repository"
    else
      echo "Repo Action:       Existing repository"
    fi
    echo "Repository:        $PLAN_CODECOMMIT_REPO"
    if [[ "$PLAN_CODECOMMIT_POLICY_TYPE" != "" ]]; then
      echo "Policy Type:       $(codecommit_policy_type_label)"
    fi
  fi
  if [[ "$PLAN_S3_POLICY_NAME" != "" ]]; then
    echo "S3 Policy Name:    $PLAN_S3_POLICY_NAME"
  fi
  if [[ "$PLAN_EXISTING_POLICY_NAME" != "" ]]; then
    echo "Attach Policy:     $PLAN_EXISTING_POLICY_NAME"
  fi
  echo "Region:            $AWS_REGION"
  echo "==========================="

  if confirm "Proceed with these changes?"; then
    return 0
  fi
  log_info "User canceled before applying changes. Starting rollback/exit."
  rollback_resources
  echo "No changes were applied."
  exit 0
}

block_a() {
  echo -e "\n=== Block A: IAM User Selection ==="
  echo "1) IAM user already exists"
  echo "2) Create a new IAM user"
  echo "3) Terminate the script"
  while true; do
    read -r -p "Choose an option [1-3]: " choice
    case "$choice" in
      1)
        PLAN_USER_ACTION="existing"
        read -r -p "Enter existing IAM user name: " PLAN_IAM_USER
        if ! is_valid_iam_username "$PLAN_IAM_USER"; then
          echo "Invalid IAM username format. Allowed: [a-zA-Z0-9+=,.@_-]"
          continue
        fi
        if ! iam_user_exists "$PLAN_IAM_USER"; then
          echo "IAM user '$PLAN_IAM_USER' was not found."
          continue
        fi
        break
        ;;
      2)
        PLAN_USER_ACTION="new"
        read -r -p "Enter new IAM user name: " PLAN_IAM_USER
        if ! is_valid_iam_username "$PLAN_IAM_USER"; then
          echo "Invalid IAM username format. Allowed: [a-zA-Z0-9+=,.@_-]"
          continue
        fi
        if iam_user_exists "$PLAN_IAM_USER"; then
          echo "IAM user '$PLAN_IAM_USER' already exists. Choose a different name."
          continue
        fi
        break
        ;;
      3)
        log_info "Script terminated by user before changes."
        exit 0
        ;;
      *) echo "Invalid selection. Choose 1, 2 or 3." ;;
    esac
  done
}

block_b() {
  echo -e "\n=== Block B: Permission Type ==="
  echo "1) S3 permissions"
  echo "2) CodeCommit permissions"
  echo "3) Terminate the script"
  while true; do
    read -r -p "Choose an option [1-3]: " choice
    case "$choice" in
      1)
        block_b1
        break
        ;;
      2)
        block_b2
        break
        ;;
      3)
        log_info "Script terminated by user before changes."
        exit 0
        ;;
      *) echo "Invalid selection. Choose 1, 2, or 3." ;;
    esac
  done
}

block_b1() {
  echo -e "\n=== Block B1: S3 Bucket Selection ==="
  echo "1) S3 bucket already exists"
  echo "2) Create a new S3 bucket"
  echo "3) Back to Block B"
  while true; do
    read -r -p "Choose an option [1-3]: " choice
    case "$choice" in
      1)
        read -r -p "Enter existing S3 bucket name: " PLAN_S3_BUCKET
        if ! is_valid_s3_bucket_name "$PLAN_S3_BUCKET"; then
          echo "Invalid S3 bucket name format. Lowercase, 3-63 chars, no underscores.";
          continue
        fi
        rc=0
        s3_bucket_status "$PLAN_S3_BUCKET" || rc=$?
        case $rc in
          0)
            PLAN_S3_ACTION="existing"
            select_s3_permission_level
            break
            ;;
          2)
            echo "Bucket '$PLAN_S3_BUCKET' exists but is not accessible from this AWS account. Choose a bucket you own or switch credentials."
            continue
            ;;
          *)
            echo "Bucket '$PLAN_S3_BUCKET' does not exist."
            continue
            ;;
        esac
        ;;
      2)
        read -r -p "Enter new S3 bucket name: " PLAN_S3_BUCKET
        if ! is_valid_s3_bucket_name "$PLAN_S3_BUCKET"; then
          echo "Invalid S3 bucket name format. Lowercase, 3-63 chars, no underscores.";
          continue
        fi
        rc=0
        s3_bucket_status "$PLAN_S3_BUCKET" || rc=$?
        case $rc in
          0)
            echo "Bucket '$PLAN_S3_BUCKET' already exists. Choose another name."
            continue
            ;;
          2)
            echo "Bucket name '$PLAN_S3_BUCKET' is already taken by another AWS account. Choose a different name."
            continue
            ;;
          *)
            PLAN_S3_ACTION="new"
            select_s3_permission_level
            break
            ;;
        esac
        ;;
      3)
        block_b
        return
        ;;
      *) echo "Invalid selection. Choose 1, 2, or 3." ;;
    esac
  done
}

select_s3_permission_level() {
  echo -e "\nChoose the S3 permission level for the IAM user:"
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

block_b2() {
  echo -e "\n=== Block B2: CodeCommit Repository Selection ==="
  echo "1) CodeCommit repo already exists"
  echo "2) Create a new CodeCommit repo"
  echo "3) Back to Block B"
  while true; do
    read -r -p "Choose an option [1-3]: " choice
    case "$choice" in
      1)
        read -r -p "Enter existing CodeCommit repository name: " PLAN_CODECOMMIT_REPO
        if ! is_valid_repo_name "$PLAN_CODECOMMIT_REPO"; then
          echo "Invalid repository name format. Use letters, numbers, '.', '-' or '_' only."
          continue
        fi
        if ! codecommit_repo_exists "$PLAN_CODECOMMIT_REPO"; then
          echo "Repository '$PLAN_CODECOMMIT_REPO' does not exist."
          continue
        fi
        PLAN_CODECOMMIT_ACTION="existing"
        break
        ;;
      2)
        read -r -p "Enter new CodeCommit repository name: " PLAN_CODECOMMIT_REPO
        if ! is_valid_repo_name "$PLAN_CODECOMMIT_REPO"; then
          echo "Invalid repository name format. Use letters, numbers, '.', '-' or '_' only."
          continue
        fi
        if codecommit_repo_exists "$PLAN_CODECOMMIT_REPO"; then
          echo "Repository '$PLAN_CODECOMMIT_REPO' already exists. Choose another name."
          continue
        fi
        PLAN_CODECOMMIT_ACTION="new"
        break
        ;;
      3)
        block_b
        return
        ;;
      *) echo "Invalid selection. Choose 1, 2 or 3." ;;
    esac
  done
}

block_c() {
  echo -e "\n=== Block C: S3 IAM Policy ==="
  echo "1) Create a new IAM policy for bucket access"
  echo "2) Attach an existing IAM policy"
  echo "3) Terminate the script"
  while true; do
    read -r -p "Choose an option [1-3]: " choice
    case "$choice" in
      1)
        read -r -p "Enter the new IAM policy name: " PLAN_S3_POLICY_NAME
        if ! is_valid_policy_name "$PLAN_S3_POLICY_NAME"; then
          echo "Invalid policy name. Avoid spaces and use allowed characters."
          continue
        fi
        if iam_policy_exists "$PLAN_S3_POLICY_NAME"; then
          echo "Policy '$PLAN_S3_POLICY_NAME' already exists. Choose another name."
          continue
        fi
        break
        ;;
      2)
        read -r -p "Enter existing IAM policy name to attach: " PLAN_EXISTING_POLICY_NAME
        if ! is_valid_policy_name "$PLAN_EXISTING_POLICY_NAME"; then
          echo "Invalid policy name. Avoid spaces and use allowed characters."
          continue
        fi
        if ! iam_policy_exists "$PLAN_EXISTING_POLICY_NAME"; then
          echo "Policy '$PLAN_EXISTING_POLICY_NAME' does not exist."
          continue
        fi
        break
        ;;
      3)
        log_info "Script terminated by user before changes."
        exit 0
        ;;
      *) echo "Invalid selection. Choose 1, 2 or 3." ;;
    esac
  done
}

block_d() {
  echo -e "\n=== Block D: CodeCommit IAM Policy ==="
  echo "1) Create a CodeCommit IAM policy"
  echo "2) Attach an existing IAM policy"
  echo "3) Terminate the script"
  while true; do
    read -r -p "Choose an option [1-3]: " choice
    case "$choice" in
      1)
        read -r -p "Enter the new IAM policy name: " PLAN_CODECOMMIT_POLICY_NAME
        if ! is_valid_policy_name "$PLAN_CODECOMMIT_POLICY_NAME"; then
          echo "Invalid policy name. Avoid spaces and use allowed characters."
          continue
        fi
        if iam_policy_exists "$PLAN_CODECOMMIT_POLICY_NAME"; then
          echo "Policy '$PLAN_CODECOMMIT_POLICY_NAME' already exists. Choose a different name."
          continue
        fi
        block_f
        break
        ;;
      2)
        read -r -p "Enter existing IAM policy name to attach: " PLAN_EXISTING_POLICY_NAME
        if ! is_valid_policy_name "$PLAN_EXISTING_POLICY_NAME"; then
          echo "Invalid policy name. Avoid spaces and use allowed characters."
          continue
        fi
        if ! iam_policy_exists "$PLAN_EXISTING_POLICY_NAME"; then
          echo "Policy '$PLAN_EXISTING_POLICY_NAME' does not exist."
          continue
        fi
        break
        ;;
      3)
        log_info "Script terminated by user before changes."
        exit 0
        ;;
      *) echo "Invalid selection. Choose 1, 2 or 3." ;;
    esac
  done
}

block_f() {
  echo -e "\n=== Block F: CodeCommit Policy Type ==="
  echo "1) Developer policy"
  echo "2) Lead policy"
  while true; do
    read -r -p "Choose an option [1-2]: " choice
    case "$choice" in
      1) PLAN_CODECOMMIT_POLICY_TYPE="dev"; break ;;
      2) PLAN_CODECOMMIT_POLICY_TYPE="lead"; break ;;
      *) echo "Invalid selection. Choose 1 or 2." ;;
    esac
  done
}

codecommit_policy_type_label() {
  case "$PLAN_CODECOMMIT_POLICY_TYPE" in
    dev) echo "developer" ;;
    lead) echo "lead" ;;
    *) echo "${PLAN_CODECOMMIT_POLICY_TYPE:-existing policy}" ;;
  esac
}

perform_plan() {
  APPLY_STARTED=1

  if [[ "$PLAN_USER_ACTION" == "new" ]]; then
    log_info "Creating IAM user '$PLAN_IAM_USER'."
    create_iam_user "$PLAN_IAM_USER"
    queue_resource "user:$PLAN_IAM_USER"
  fi

  if [[ "$PLAN_S3_ACTION" != "" ]]; then
    if [[ "$PLAN_S3_ACTION" == "new" ]]; then
      log_info "Creating new S3 bucket '$PLAN_S3_BUCKET' in region $AWS_REGION."
      create_s3_bucket "$PLAN_S3_BUCKET" "$AWS_REGION"
      queue_resource "bucket:$PLAN_S3_BUCKET"
    else
      log_info "Using existing S3 bucket '$PLAN_S3_BUCKET'."
    fi

    if [[ "$PLAN_S3_POLICY_NAME" != "" ]]; then
      log_info "Creating S3 policy '$PLAN_S3_POLICY_NAME'."
      local policy_file
      policy_file="$(mktemp "${TMPDIR:-/tmp}/s3-policy.json.XXXXXX")"
      if ! build_s3_policy_json "$PLAN_S3_BUCKET" "$PLAN_S3_PERMISSION_LEVEL" "$policy_file"; then
        rm -f "$policy_file"
        log_error "Failed to render S3 policy document."
        return 1
      fi
      local policy_arn
      if ! policy_arn="$(create_policy_from_file "$PLAN_S3_POLICY_NAME" "$policy_file")"; then
        rm -f "$policy_file"
        log_error "Failed to create S3 IAM policy '$PLAN_S3_POLICY_NAME'."
        return 1
      fi
      queue_resource "policy:$PLAN_S3_POLICY_NAME"
      rm -f "$policy_file"
      log_info "Attaching policy '$PLAN_S3_POLICY_NAME' to IAM user '$PLAN_IAM_USER'."
      attach_policy_to_user "$PLAN_IAM_USER" "$policy_arn"
      queue_resource "attachment:$PLAN_IAM_USER|$policy_arn"
    elif [[ "$PLAN_EXISTING_POLICY_NAME" != "" ]]; then
      log_info "Attaching existing policy '$PLAN_EXISTING_POLICY_NAME' to IAM user '$PLAN_IAM_USER'."
      local policy_arn
      policy_arn="$(get_policy_arn_by_name "$PLAN_EXISTING_POLICY_NAME")"
      attach_policy_to_user "$PLAN_IAM_USER" "$policy_arn"
      queue_resource "attachment:$PLAN_IAM_USER|$policy_arn"
    fi
  fi

  if [[ "$PLAN_CODECOMMIT_ACTION" != "" ]]; then
    if [[ "$PLAN_CODECOMMIT_ACTION" == "new" ]]; then
      log_info "Creating new CodeCommit repo '$PLAN_CODECOMMIT_REPO'."
      create_codecommit_repo "$PLAN_CODECOMMIT_REPO"
      queue_resource "repo:$PLAN_CODECOMMIT_REPO"
    else
      log_info "Using existing CodeCommit repo '$PLAN_CODECOMMIT_REPO'."
    fi

    if [[ "$PLAN_CODECOMMIT_POLICY_NAME" != "" ]]; then
      log_info "Creating CodeCommit policy '$PLAN_CODECOMMIT_POLICY_NAME' for '$(codecommit_policy_type_label)'."
      local template_path
      template_path="$POLICY_DIR/codecommit-${PLAN_CODECOMMIT_POLICY_TYPE}.json"
      local account_id
      if ! account_id="$(get_account_id)" || [[ -z "$account_id" ]]; then
        log_error "Unable to determine AWS account ID for CodeCommit policy."
        return 1
      fi
      local policy_file
      policy_file="$(mktemp "${TMPDIR:-/tmp}/codecommit-policy.json.XXXXXX")"
      if ! render_template "$template_path" "$policy_file" \
        "ACCOUNT_ID=$account_id" \
        "REGION=$AWS_REGION" \
        "REPO_NAME=$PLAN_CODECOMMIT_REPO"; then
        rm -f "$policy_file"
        log_error "Failed to render CodeCommit policy template '$template_path'."
        return 1
      fi
      local policy_arn
      if ! policy_arn="$(create_policy_from_file "$PLAN_CODECOMMIT_POLICY_NAME" "$policy_file")"; then
        rm -f "$policy_file"
        log_error "Failed to create CodeCommit IAM policy '$PLAN_CODECOMMIT_POLICY_NAME'."
        return 1
      fi
      queue_resource "policy:$PLAN_CODECOMMIT_POLICY_NAME"
      rm -f "$policy_file"
      attach_policy_to_user "$PLAN_IAM_USER" "$policy_arn"
      queue_resource "attachment:$PLAN_IAM_USER|$policy_arn"
    elif [[ "$PLAN_EXISTING_POLICY_NAME" != "" ]]; then
      log_info "Attaching existing policy '$PLAN_EXISTING_POLICY_NAME' to IAM user '$PLAN_IAM_USER'."
      local policy_arn
      policy_arn="$(get_policy_arn_by_name "$PLAN_EXISTING_POLICY_NAME")"
      attach_policy_to_user "$PLAN_IAM_USER" "$policy_arn"
      queue_resource "attachment:$PLAN_IAM_USER|$policy_arn"
    fi
  fi
}

block_result() {
  echo -e "\n====== RESULT SUMMARY ======"
  echo "IAM User: $PLAN_IAM_USER"
  if [[ "$PLAN_USER_ACTION" == "new" ]]; then
    echo "Created: new IAM user"
  else
    echo "Used: existing IAM user"
  fi
  if [[ "$PLAN_S3_ACTION" != "" ]]; then
    echo "S3 Bucket: $PLAN_S3_BUCKET"
    echo "S3 Bucket Action: $PLAN_S3_ACTION"
    echo "S3 Permission Level: $PLAN_S3_PERMISSION_LEVEL"
  fi
  if [[ "$PLAN_CODECOMMIT_ACTION" != "" ]]; then
    echo "CodeCommit Repo: $PLAN_CODECOMMIT_REPO"
    echo "CodeCommit Repo Action: $PLAN_CODECOMMIT_ACTION"
    echo "Policy Type: $(codecommit_policy_type_label)"
  fi
  if [[ "$PLAN_S3_POLICY_NAME" != "" ]]; then
    echo "Created Policy: $PLAN_S3_POLICY_NAME"
  fi
  if [[ "$PLAN_CODECOMMIT_POLICY_NAME" != "" ]]; then
    echo "Created Policy: $PLAN_CODECOMMIT_POLICY_NAME"
  fi
  if [[ "$PLAN_EXISTING_POLICY_NAME" != "" ]]; then
    echo "Attached Existing Policy: $PLAN_EXISTING_POLICY_NAME"
  fi
  if [[ "$PLAN_S3_ACTION" != "" ]]; then
    echo "S3 Console URL: https://s3.console.aws.amazon.com/s3/buckets/$PLAN_S3_BUCKET?region=$AWS_REGION"
  fi
  if [[ "$PLAN_CODECOMMIT_ACTION" != "" ]]; then
    echo "CodeCommit Console URL: https://$AWS_REGION.console.aws.amazon.com/codesuite/codecommit/repositories/$PLAN_CODECOMMIT_REPO/browse"
  fi
  echo "==========================="
}

main() {
  select_region
  block_a
  block_b

  if [[ "$PLAN_S3_ACTION" != "" ]]; then
    block_c
  fi
  if [[ "$PLAN_CODECOMMIT_ACTION" != "" ]]; then
    block_d
  fi

  review_changes
  perform_plan
  block_result
  log_info "Completed all requested operations."
}

main "$@"
