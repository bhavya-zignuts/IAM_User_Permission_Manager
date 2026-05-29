# IAM User & Policy Automation

This repository contains a bash-based automation workflow to create or use an existing IAM user, manage S3 or CodeCommit resources, create or attach IAM policies, and review changes before applying them.

## Project Structure

- `main.sh` - main interactive script to run the workflow
- `rollback.sh` - rollback helper for created resources when the user cancels before apply
- `config.sh` - shared config and log file setup
- `policies/`
  - `s3-template.json` - S3 policy template
  - `codecommit-dev.json` - legacy CodeCommit developer policy template
  - `codecommit-lead.json` - legacy CodeCommit lead policy template
  - `../repo-access-backpackercars-backend-developer.json` - CodeCommit developer policy source used by the script
  - `../repo-access-backpackercars-backend-lead.json` - CodeCommit lead policy source used by the script
- `logs/` - directory for runtime logs
- `utils/`
  - `validation.sh` - input validation helpers
  - `iam.sh` - IAM helper functions
  - `s3.sh` - S3 helper functions
  - `codecommit.sh` - CodeCommit helper functions

## Prerequisites

1. macOS or Linux with bash.
2. AWS CLI installed and configured.
   - Recommended: AWS CLI v2
   - Install instructions: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
3. AWS credentials configured for the account where you want to run operations.
   - Example:
     ```bash
     aws configure
     ```
   - Or set environment variables:
     ```bash
     export AWS_ACCESS_KEY_ID="YOUR_ACCESS_KEY_ID"
     export AWS_SECRET_ACCESS_KEY="YOUR_SECRET_ACCESS_KEY"
     export AWS_DEFAULT_REGION="ap-south-1"
     ```
4. IAM permissions for the configured identity to perform:
   - `iam:GetUser`, `iam:CreateUser`, `iam:ListPolicies`, `iam:CreatePolicy`, `iam:AttachUserPolicy`
   - `s3:HeadBucket`, `s3:CreateBucket`, `s3:DeleteBucket`, `s3:PutBucketPolicy`
   - `codecommit:GetRepository`, `codecommit:CreateRepository`, `codecommit:DeleteRepository`
   - `sts:GetCallerIdentity`

> Only AWS CLI and bash are required to run the script from this project folder. AWS CLI must be configured with valid credentials first.

## Setup

1. Open a terminal.
2. Change to the project folder:
   ```bash
   cd /Users/ztlab57/Desktop/IAM_user_management
   ```
3. Ensure the scripts are executable:
   ```bash
   chmod +x main.sh rollback.sh config.sh utils/*.sh
   ```
4. Confirm your AWS CLI credentials are configured:
   ```bash
   aws sts get-caller-identity
   ```
   If this returns your account ID and ARN, the CLI is configured correctly.

## Run the Script

Run the main script from the repository root:

```bash
./main.sh
```

The script will guide you through:

1. Selecting AWS region
2. Choosing an existing IAM user or creating a new one
3. Choosing S3 or CodeCommit permissions
4. Selecting or creating the target bucket/repository
5. Creating or attaching a policy
6. Reviewing the planned changes before applying them
7. Printing resource links, attached policy details, and any generated credentials in the result summary

## Logging

All actions are logged to:

- `logs/iam-automation.log`

## Rollback

If you cancel at the review stage, no AWS changes are applied. If an AWS command fails after the apply step starts, the script runs rollback logic for resources created or attached during that run.

## Notes

- The script uses dynamic policy templates, so bucket and repository ARNs are rendered at runtime.
- For S3 policy actions the script supports:
  - `ReadOnly`
  - `ReadWrite`
  - `FullBucketAdmin`
- For S3, the script can optionally create a console sign-in password. Existing IAM users are checked first.
- S3 `FullBucketAdmin` policies are rendered from `s3-policy.json`.
- CodeCommit developer and lead policies are rendered from the matching `repo-access-backpackercars-backend-*.json` files.
- For CodeCommit, the script asks before creating CodeCommit HTTPS username/password credentials. Existing IAM users are checked first, and new credentials are printed once in the result summary when created.
- CodeCommit results include a direct HTTPS clone URL and `git clone` command.

## Important

- Always verify your AWS IAM permissions before running the script.
- The script applies real AWS changes when confirmed in the review step.
- Use a test AWS account or sandbox environment if you want to validate behavior safely.
