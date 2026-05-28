#!/usr/bin/env bash

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_ROOT/logs"
POLICY_DIR="$SCRIPT_ROOT/policies"
LOG_FILE="$LOG_DIR/iam-automation.log"
REGION_OPTIONS=("ap-south-1" "us-east-1")
AWS_REGION="${AWS_REGION:-ap-south-1}"

mkdir -p "$LOG_DIR"

echo "[INFO] $(date +'%Y-%m-%d %H:%M:%S') Loading configuration" | tee -a "$LOG_FILE"
