#!/usr/bin/env bash
# Break Scenario 3: SageMaker Endpoint
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-2}"
PREFIX="devops-agent-demo-demo-s3"
ENDPOINT_NAME="${PREFIX}-endpoint"
ENDPOINT_CONFIG="${PREFIX}-endpoint-config"
MODEL_NAME="${PREFIX}-sklearn-iris-classifier"

usage() {
  cat <<EOF
Usage: $0 <fault>

Faults:
  delete-endpoint     Delete the SageMaker endpoint (simulates accidental deletion)
  recreate-endpoint   Recreate the endpoint from the existing config
  bad-invocation      Send a malformed payload to trigger InvocationError alarms
  scale-to-zero       Update endpoint config to 0 instances (not supported — triggers error)
  change-instance     Update endpoint config to a non-existent instance type
  restore-config      Restore endpoint config to ml.t2.medium × 1
  status              Show current endpoint status and metrics
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage
FAULT="$1"

log() { echo "[$(date -u +%H:%M:%SZ)] $*"; }

case "$FAULT" in
  delete-endpoint)
    read -r -p "WARNING: This will DELETE the SageMaker endpoint '$ENDPOINT_NAME'. Type 'yes' to confirm: " CONFIRM
    if [[ "$CONFIRM" == "yes" ]]; then
      aws sagemaker delete-endpoint --endpoint-name "$ENDPOINT_NAME" --region "$REGION"
      log "Endpoint $ENDPOINT_NAME deleted."
    else
      log "Aborted."
    fi
    ;;

  recreate-endpoint)
    log "Creating endpoint $ENDPOINT_NAME from config $ENDPOINT_CONFIG"
    aws sagemaker create-endpoint \
      --endpoint-name "$ENDPOINT_NAME" \
      --endpoint-config-name "$ENDPOINT_CONFIG" \
      --region "$REGION"
    log "Done. Endpoint creation initiated — may take several minutes."
    ;;

  bad-invocation)
    log "Sending 10 malformed invocations to $ENDPOINT_NAME to trigger 4xx alarms"
    for i in $(seq 1 10); do
      aws sagemaker-runtime invoke-endpoint \
        --endpoint-name "$ENDPOINT_NAME" \
        --content-type "application/json" \
        --body '{"completely":"wrong","format":true}' \
        --region "$REGION" \
        /tmp/sm-response-${i}.json 2>&1 | tail -1 || true
    done
    log "Done. Check CloudWatch for Invocation4XXErrors metric."
    ;;

  change-instance)
    NEW_CONFIG="${ENDPOINT_CONFIG}-broken-$(date +%s)"
    log "Creating broken endpoint config with non-existent instance type"
    aws sagemaker create-endpoint-config \
      --endpoint-config-name "$NEW_CONFIG" \
      --production-variants "[{
        \"VariantName\":\"AllTraffic\",
        \"ModelName\":\"${MODEL_NAME}\",
        \"InstanceType\":\"ml.x99.quadrillion\",
        \"InitialInstanceCount\":1
      }]" \
      --region "$REGION"
    aws sagemaker update-endpoint \
      --endpoint-name "$ENDPOINT_NAME" \
      --endpoint-config-name "$NEW_CONFIG" \
      --region "$REGION"
    log "Done. Endpoint update to invalid instance type will fail and rollback."
    ;;

  restore-config)
    log "Restoring endpoint to original config $ENDPOINT_CONFIG"
    aws sagemaker update-endpoint \
      --endpoint-name "$ENDPOINT_NAME" \
      --endpoint-config-name "$ENDPOINT_CONFIG" \
      --region "$REGION"
    log "Done. Waiting for endpoint to reach InService state..."
    aws sagemaker wait endpoint-in-service \
      --endpoint-name "$ENDPOINT_NAME" \
      --region "$REGION"
    log "Endpoint is InService."
    ;;

  status)
    log "=== SageMaker Endpoint ==="
    aws sagemaker describe-endpoint \
      --endpoint-name "$ENDPOINT_NAME" \
      --region "$REGION" \
      --query 'Endpoint.{Status:EndpointStatus,Created:CreationTime,LastModified:LastModifiedTime}' \
      --output table

    log "=== CloudWatch Alarms ==="
    aws cloudwatch describe-alarms \
      --alarm-name-prefix "${PREFIX}-endpoint" \
      --region "$REGION" \
      --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
      --output table
    ;;

  *)
    log "Unknown fault: $FAULT"
    usage
    ;;
esac
