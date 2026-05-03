#!/usr/bin/env bash
# Manually invoke the Medium post fetcher Lambda.
# Usage: ./fetch-posts.sh

set -euo pipefail

FUNCTION_NAME="resume-medium-fetcher"
PROFILE="resume-deployer"
REGION="us-east-1"
MAX_POSTS=6
OUTPUT_FILE="/tmp/medium-fetcher-response.json"

echo "Invoking $FUNCTION_NAME..."

LOG=$(aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --profile "$PROFILE" \
  --region "$REGION" \
  --cli-binary-format raw-in-base64-out \
  --payload "{\"max_posts\":$MAX_POSTS}" \
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
