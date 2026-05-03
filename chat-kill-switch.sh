#!/usr/bin/env bash
# ============================================================
# Chat Agent Kill Switch
# Usage:
#   ./chat-kill-switch.sh          — show current status
#   ./chat-kill-switch.sh off      — disable the chat agent (emergency stop)
#   ./chat-kill-switch.sh on       — re-enable the chat agent
# Requires: AWS_PROFILE=resume-deployer (or valid AWS credentials)
# ============================================================
set -euo pipefail

FUNCTION="resume-chat-agent"
PROFILE="${AWS_PROFILE:-resume-deployer}"

status() {
  CONCURRENCY=$(aws lambda get-function-concurrency \
    --function-name "$FUNCTION" \
    --profile "$PROFILE" \
    --query "ReservedConcurrentExecutions" \
    --output text 2>/dev/null || echo "None")

  if [ "$CONCURRENCY" = "0" ]; then
    echo "🔴  Chat agent is DISABLED (reserved concurrency = 0)"
  else
    echo "🟢  Chat agent is ENABLED (reserved concurrency = ${CONCURRENCY:-unrestricted})"
  fi
}

case "${1:-status}" in
  off)
    echo "Disabling chat agent..."
    aws lambda put-function-concurrency \
      --function-name "$FUNCTION" \
      --reserved-concurrent-executions 0 \
      --profile "$PROFILE" \
      --output text > /dev/null
    echo "🔴  Chat agent DISABLED. All incoming requests will return 429 immediately."
    ;;
  on)
    echo "Re-enabling chat agent..."
    aws lambda delete-function-concurrency \
      --function-name "$FUNCTION" \
      --profile "$PROFILE" \
      --output text > /dev/null
    echo "🟢  Chat agent ENABLED. Concurrency limit removed."
    ;;
  status)
    status
    ;;
  *)
    echo "Usage: $0 [off|on|status]"
    exit 1
    ;;
esac
