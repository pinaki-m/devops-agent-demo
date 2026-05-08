#!/usr/bin/env bash
# Break Scenario 1: Lambda + SQS + DynamoDB
# Introduces faults for the DevOps Agent to detect and remediate.
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-2}"
PREFIX="devops-agent-demo-demo-s1"
LAMBDA_NAME="${PREFIX}-processor"
TABLE_NAME="${PREFIX}-events"
QUEUE_NAME="${PREFIX}-events"

usage() {
  cat <<EOF
Usage: $0 <fault>

Faults:
  throttle-lambda     Set Lambda reserved concurrency to 0 (throttle all invocations)
  restore-lambda      Remove concurrency limit
  corrupt-env         Inject a bad DynamoDB table name into Lambda env vars
  restore-env         Restore correct DynamoDB table name
  disable-trigger     Disable SQS→Lambda event source mapping
  restore-trigger     Re-enable SQS→Lambda event source mapping
  flood-dlq           Send 20 messages that will fail processing and land in DLQ
  delete-table        Delete the DynamoDB table (destructive — use with care)
  status              Show current state of all resources
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage
FAULT="$1"

log() { echo "[$(date -u +%H:%M:%SZ)] $*"; }

case "$FAULT" in
  throttle-lambda)
    log "Setting Lambda reserved concurrency to 0 — all invocations will be throttled"
    aws lambda put-function-concurrency \
      --function-name "$LAMBDA_NAME" \
      --reserved-concurrent-executions 0 \
      --region "$REGION"
    log "Done. Lambda $LAMBDA_NAME is now throttled."
    ;;

  restore-lambda)
    log "Removing Lambda concurrency limit"
    aws lambda delete-function-concurrency \
      --function-name "$LAMBDA_NAME" \
      --region "$REGION"
    log "Done. Lambda $LAMBDA_NAME is no longer throttled."
    ;;

  corrupt-env)
    log "Injecting bad DYNAMODB_TABLE env var into Lambda"
    CURRENT=$(aws lambda get-function-configuration \
      --function-name "$LAMBDA_NAME" \
      --region "$REGION" \
      --query 'Environment.Variables' --output json)
    PATCHED=$(echo "$CURRENT" | jq '. + {"DYNAMODB_TABLE":"does-not-exist-table"}')
    aws lambda update-function-configuration \
      --function-name "$LAMBDA_NAME" \
      --environment "Variables=${PATCHED}" \
      --region "$REGION" > /dev/null
    log "Done. Lambda will now fail with ResourceNotFoundException."
    ;;

  restore-env)
    log "Restoring correct DYNAMODB_TABLE env var"
    CURRENT=$(aws lambda get-function-configuration \
      --function-name "$LAMBDA_NAME" \
      --region "$REGION" \
      --query 'Environment.Variables' --output json)
    PATCHED=$(echo "$CURRENT" | jq --arg v "$TABLE_NAME" '. + {"DYNAMODB_TABLE":$v}')
    aws lambda update-function-configuration \
      --function-name "$LAMBDA_NAME" \
      --environment "Variables=${PATCHED}" \
      --region "$REGION" > /dev/null
    log "Done. DYNAMODB_TABLE restored to $TABLE_NAME."
    ;;

  disable-trigger)
    log "Disabling SQS event source mapping"
    UUID=$(aws lambda list-event-source-mappings \
      --function-name "$LAMBDA_NAME" \
      --region "$REGION" \
      --query 'EventSourceMappings[0].UUID' --output text)
    aws lambda update-event-source-mapping \
      --uuid "$UUID" \
      --no-enabled \
      --region "$REGION" > /dev/null
    log "Done. Event source mapping $UUID disabled."
    ;;

  restore-trigger)
    log "Re-enabling SQS event source mapping"
    UUID=$(aws lambda list-event-source-mappings \
      --function-name "$LAMBDA_NAME" \
      --region "$REGION" \
      --query 'EventSourceMappings[0].UUID' --output text)
    aws lambda update-event-source-mapping \
      --uuid "$UUID" \
      --enabled \
      --region "$REGION" > /dev/null
    log "Done. Event source mapping $UUID enabled."
    ;;

  flood-dlq)
    QUEUE_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --region "$REGION" --query QueueUrl --output text)
    log "Sending 20 malformed messages to $QUEUE_NAME (they will exhaust retries and land in DLQ)"
    for i in $(seq 1 20); do
      aws sqs send-message \
        --queue-url "$QUEUE_URL" \
        --message-body '{"__break":true,"seq":'"$i"'}' \
        --region "$REGION" > /dev/null
    done
    log "Done. Monitor DLQ depth in CloudWatch."
    ;;

  delete-table)
    read -r -p "WARNING: This will DELETE DynamoDB table '$TABLE_NAME'. Type 'yes' to confirm: " CONFIRM
    if [[ "$CONFIRM" == "yes" ]]; then
      aws dynamodb delete-table --table-name "$TABLE_NAME" --region "$REGION"
      log "Table $TABLE_NAME deleted."
    else
      log "Aborted."
    fi
    ;;

  status)
    log "=== Lambda ==="
    aws lambda get-function-configuration \
      --function-name "$LAMBDA_NAME" --region "$REGION" \
      --query '{State:State,Concurrency:Architectures,DynamoTable:Environment.Variables.DYNAMODB_TABLE}' \
      --output table

    log "=== SQS Queue ==="
    QUEUE_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --region "$REGION" --query QueueUrl --output text)
    aws sqs get-queue-attributes \
      --queue-url "$QUEUE_URL" \
      --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
      --region "$REGION" --output table

    log "=== DynamoDB ==="
    aws dynamodb describe-table \
      --table-name "$TABLE_NAME" --region "$REGION" \
      --query 'Table.{Status:TableStatus,ItemCount:ItemCount}' \
      --output table
    ;;

  *)
    log "Unknown fault: $FAULT"
    usage
    ;;
esac
