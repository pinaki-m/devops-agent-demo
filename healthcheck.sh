#!/usr/bin/env bash
# healthcheck.sh — verify all four demo scenarios are healthy
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-2}"
FAIL=0

log()  { echo "[$(date -u +%H:%M:%SZ)] $*"; }
ok()   { echo "  ✓ $*"; }
fail() { echo "  ✗ $*"; FAIL=$((FAIL + 1)); }
sep()  { echo "──────────────────────────────────────────────"; }

check_aws_auth() {
  sep
  log "Checking AWS authentication"
  if aws sts get-caller-identity --region "$REGION" > /dev/null 2>&1; then
    IDENTITY=$(aws sts get-caller-identity --region "$REGION" --query 'Arn' --output text)
    ok "Authenticated as $IDENTITY"
  else
    fail "AWS authentication failed — check credentials or IAM role"
  fi
}

# ── Scenario 1 ────────────────────────────────────────────────────────────────
check_scenario1() {
  sep
  log "Scenario 1: Lambda + SQS + DynamoDB"
  PREFIX="devops-agent-demo-demo-s1"

  # Lambda
  STATUS=$(aws lambda get-function-configuration \
    --function-name "${PREFIX}-processor" \
    --region "$REGION" \
    --query 'State' --output text 2>/dev/null || echo "NOT_FOUND")
  if [[ "$STATUS" == "Active" ]]; then
    ok "Lambda ${PREFIX}-processor is Active"
  else
    fail "Lambda ${PREFIX}-processor — State: $STATUS"
  fi

  # Concurrency (throttle check)
  CONCURRENCY=$(aws lambda get-function-concurrency \
    --function-name "${PREFIX}-processor" \
    --region "$REGION" \
    --query 'ReservedConcurrentExecutions' --output text 2>/dev/null || echo "None")
  if [[ "$CONCURRENCY" == "0" ]]; then
    fail "Lambda ${PREFIX}-processor has reserved concurrency = 0 (THROTTLED)"
  else
    ok "Lambda concurrency: ${CONCURRENCY:-unreserved}"
  fi

  # SQS — check DLQ depth
  DLQ_URL=$(aws sqs get-queue-url \
    --queue-name "${PREFIX}-events-dlq" \
    --region "$REGION" \
    --query QueueUrl --output text 2>/dev/null || echo "")
  if [[ -n "$DLQ_URL" ]]; then
    DLQ_DEPTH=$(aws sqs get-queue-attributes \
      --queue-url "$DLQ_URL" \
      --attribute-names ApproximateNumberOfMessages \
      --region "$REGION" \
      --query 'Attributes.ApproximateNumberOfMessages' --output text)
    if [[ "$DLQ_DEPTH" -gt 0 ]]; then
      fail "SQS DLQ ${PREFIX}-events-dlq has $DLQ_DEPTH messages"
    else
      ok "SQS DLQ is empty"
    fi
  else
    fail "SQS DLQ ${PREFIX}-events-dlq not found"
  fi

  # DynamoDB
  TBL_STATUS=$(aws dynamodb describe-table \
    --table-name "${PREFIX}-events" \
    --region "$REGION" \
    --query 'Table.TableStatus' --output text 2>/dev/null || echo "NOT_FOUND")
  if [[ "$TBL_STATUS" == "ACTIVE" ]]; then
    ok "DynamoDB table ${PREFIX}-events is ACTIVE"
  else
    fail "DynamoDB table ${PREFIX}-events — Status: $TBL_STATUS"
  fi
}

# ── Scenario 2 ────────────────────────────────────────────────────────────────
check_scenario2() {
  sep
  log "Scenario 2: MWAA + EMR Serverless"
  PREFIX="devops-agent-demo-demo-s2"

  MWAA_STATUS=$(aws mwaa get-environment \
    --name "$PREFIX" \
    --region "$REGION" \
    --query 'Environment.Status' --output text 2>/dev/null || echo "NOT_FOUND")
  if [[ "$MWAA_STATUS" == "AVAILABLE" ]]; then
    ok "MWAA environment $PREFIX is AVAILABLE"
  elif [[ "$MWAA_STATUS" == "CREATING" || "$MWAA_STATUS" == "UPDATING" ]]; then
    fail "MWAA environment $PREFIX — Status: $MWAA_STATUS (still provisioning)"
  else
    fail "MWAA environment $PREFIX — Status: $MWAA_STATUS"
  fi

  EMR_STATE=$(aws emr-serverless list-applications \
    --region "$REGION" \
    --query "applications[?name=='${PREFIX}-spark'].state" \
    --output text 2>/dev/null || echo "NOT_FOUND")
  if [[ "$EMR_STATE" == "STARTED" || "$EMR_STATE" == "CREATED" ]]; then
    ok "EMR Serverless ${PREFIX}-spark — State: $EMR_STATE"
  else
    fail "EMR Serverless ${PREFIX}-spark — State: $EMR_STATE"
  fi
}

# ── Scenario 3 ────────────────────────────────────────────────────────────────
check_scenario3() {
  sep
  log "Scenario 3: SageMaker Endpoint"
  PREFIX="devops-agent-demo-demo-s3"

  EP_STATUS=$(aws sagemaker describe-endpoint \
    --endpoint-name "${PREFIX}-endpoint" \
    --region "$REGION" \
    --query 'EndpointStatus' --output text 2>/dev/null || echo "NOT_FOUND")
  if [[ "$EP_STATUS" == "InService" ]]; then
    ok "SageMaker endpoint ${PREFIX}-endpoint is InService"
  else
    fail "SageMaker endpoint ${PREFIX}-endpoint — Status: $EP_STATUS"
  fi

  # CloudWatch alarms
  ALARMS_IN_ALARM=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "${PREFIX}-endpoint" \
    --state-value ALARM \
    --region "$REGION" \
    --query 'length(MetricAlarms)' --output text 2>/dev/null || echo "0")
  if [[ "$ALARMS_IN_ALARM" -gt 0 ]]; then
    fail "SageMaker — $ALARMS_IN_ALARM CloudWatch alarm(s) in ALARM state"
  else
    ok "SageMaker CloudWatch alarms — all OK"
  fi
}

# ── Scenario 4 ────────────────────────────────────────────────────────────────
check_scenario4() {
  sep
  log "Scenario 4: ECS Fargate + ALB"
  PREFIX="devops-agent-demo-demo-s4"

  # ECS service
  SVC_INFO=$(aws ecs describe-services \
    --cluster "${PREFIX}-cluster" \
    --services "${PREFIX}-app" \
    --region "$REGION" \
    --query 'services[0].{desired:desiredCount,running:runningCount,status:status}' \
    --output json 2>/dev/null || echo '{}')
  DESIRED=$(echo "$SVC_INFO" | jq -r '.desired // 0')
  RUNNING=$(echo "$SVC_INFO" | jq -r '.running // 0')
  STATUS=$(echo "$SVC_INFO" | jq -r '.status // "NOT_FOUND"')

  if [[ "$STATUS" == "ACTIVE" && "$RUNNING" -ge 1 ]]; then
    ok "ECS service ${PREFIX}-app — $RUNNING/$DESIRED tasks running"
  else
    fail "ECS service ${PREFIX}-app — $RUNNING/$DESIRED running, status=$STATUS"
  fi

  # ALB target health
  TG_ARN=$(aws elbv2 describe-target-groups \
    --region "$REGION" \
    --query "TargetGroups[?contains(TargetGroupName,'${PREFIX}')].TargetGroupArn" \
    --output text 2>/dev/null | head -1 || echo "")
  if [[ -n "$TG_ARN" ]]; then
    UNHEALTHY=$(aws elbv2 describe-target-health \
      --target-group-arn "$TG_ARN" \
      --region "$REGION" \
      --query "length(TargetHealthDescriptions[?TargetHealth.State!='healthy' && TargetHealth.State!='draining'])" \
      --output text)
    if [[ "$UNHEALTHY" -eq 0 ]]; then
      ok "ALB target group — all targets healthy"
    else
      fail "ALB target group — $UNHEALTHY unhealthy target(s)"
    fi
  else
    fail "ALB target group for ${PREFIX} not found"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
check_aws_auth
check_scenario1
check_scenario2
check_scenario3
check_scenario4

sep
if [[ "$FAIL" -eq 0 ]]; then
  log "All checks passed — system healthy."
  exit 0
else
  log "$FAIL check(s) FAILED — review output above."
  exit 1
fi
