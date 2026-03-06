#!/usr/bin/env bash
# Manually invoke the GitHub fetcher Lambda.
# Usage: ./fetch-repos.sh

set -euo pipefail

FUNCTION_NAME="resume-github-fetcher"
PROFILE="resume-deployer"
REGION="us-east-1"
OUTPUT_FILE="/tmp/github-fetcher-response.json"

echo "Invoking $FUNCTION_NAME..."

LOG=$(aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --profile "$PROFILE" \
  --region "$REGION" \
  --log-type Tail \
  --query 'LogResult' \
  --output text \
  "$OUTPUT_FILE")

echo ""
echo "--- Lambda logs ---"
echo "$LOG" | base64 -d
echo ""
echo "--- Response ---"
cat "$OUTPUT_FILE"
echo ""
