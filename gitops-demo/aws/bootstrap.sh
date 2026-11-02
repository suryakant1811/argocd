#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
ECR_REPOSITORY="${ECR_REPOSITORY:-gitops-demo}"
ARTIFACT_BUCKET="${ARTIFACT_BUCKET:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${ARTIFACT_BUCKET}" ]]; then
  echo "ARTIFACT_BUCKET is required and must be globally unique." >&2
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

if ! aws ecr describe-repositories --region "${AWS_REGION}" \
  --repository-names "${ECR_REPOSITORY}" >/dev/null 2>&1; then
  aws ecr create-repository --region "${AWS_REGION}" \
    --repository-name "${ECR_REPOSITORY}" \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability IMMUTABLE \
    --encryption-configuration encryptionType=AES256 >/dev/null
fi

aws ecr put-lifecycle-policy --region "${AWS_REGION}" \
  --repository-name "${ECR_REPOSITORY}" \
  --lifecycle-policy-text "file://${SCRIPT_DIR}/ecr-lifecycle-policy.json" >/dev/null

if ! aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" >/dev/null 2>&1; then
  args=(--bucket "${ARTIFACT_BUCKET}" --region "${AWS_REGION}")
  if [[ "${AWS_REGION}" != "us-east-1" ]]; then
    args+=(--create-bucket-configuration "LocationConstraint=${AWS_REGION}")
  fi
  aws s3api create-bucket "${args[@]}" >/dev/null
fi

aws s3api put-public-access-block --bucket "${ARTIFACT_BUCKET}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "${ARTIFACT_BUCKET}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-versioning --bucket "${ARTIFACT_BUCKET}" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-lifecycle-configuration --bucket "${ARTIFACT_BUCKET}" \
  --lifecycle-configuration "file://${SCRIPT_DIR}/s3-lifecycle-configuration.json"

cat <<EOF
AWS bootstrap complete.
ECR image: ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}
Artifacts:  s3://${ARTIFACT_BUCKET}/gitops-demo/
EOF
