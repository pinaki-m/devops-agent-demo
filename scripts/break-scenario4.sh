#!/usr/bin/env bash
# Break Scenario 4: ECS Fargate + ALB
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-2}"
PREFIX="devops-agent-demo-demo-s4"
CLUSTER="${PREFIX}-cluster"
SERVICE="${PREFIX}-app"
TASK_DEF="${PREFIX}-app"

usage() {
  cat <<EOF
Usage: $0 <fault>

Faults:
  scale-to-zero       Set ECS service desired count to 0 (no tasks running)
  restore-scale       Set ECS service desired count to 2
  bad-image           Update task definition to a non-existent image tag
  restore-image       Update task definition back to nginx:alpine (safe default)
  oom-task            Lower task memory to 32 MB (triggers OOM kills)
  restore-memory      Restore task memory to 512 MB
  block-health-check  Modify the ALB TG health check path to a non-existent route
  restore-health-check Restore health check path to /health
  stop-all-tasks      Manually stop all running tasks (service will restart them)
  status              Show current state of cluster, service, and ALB
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage
FAULT="$1"

log() { echo "[$(date -u +%H:%M:%SZ)] $*"; }

_update_task_def() {
  local jq_filter="$1"
  local CURRENT
  CURRENT=$(aws ecs describe-task-definition \
    --task-definition "$TASK_DEF" \
    --region "$REGION" \
    --query taskDefinition --output json)

  local NEW_DEF
  NEW_DEF=$(echo "$CURRENT" | jq "$jq_filter" | \
    jq 'del(.taskDefinitionArn,.revision,.status,.requiresAttributes,.compatibilities,.registeredAt,.registeredBy)')

  aws ecs register-task-definition \
    --cli-input-json "$NEW_DEF" \
    --region "$REGION" > /dev/null

  aws ecs update-service \
    --cluster "$CLUSTER" \
    --service "$SERVICE" \
    --task-definition "$TASK_DEF" \
    --force-new-deployment \
    --region "$REGION" > /dev/null

  log "Task definition updated and new deployment started."
}

case "$FAULT" in
  scale-to-zero)
    log "Setting ECS service desired count to 0"
    aws ecs update-service \
      --cluster "$CLUSTER" \
      --service "$SERVICE" \
      --desired-count 0 \
      --region "$REGION" > /dev/null
    log "Done. No tasks will be running — ALB will return 503."
    ;;

  restore-scale)
    log "Setting ECS service desired count to 2"
    aws ecs update-service \
      --cluster "$CLUSTER" \
      --service "$SERVICE" \
      --desired-count 2 \
      --region "$REGION" > /dev/null
    log "Done."
    ;;

  bad-image)
    log "Updating task definition to use a non-existent image tag"
    _update_task_def '.containerDefinitions[0].image = "devops-agent-demo-demo-s4-app:this-tag-does-not-exist"'
    log "New tasks will fail to pull image — service will roll back via circuit breaker."
    ;;

  restore-image)
    log "Restoring task definition to nginx:alpine"
    _update_task_def '.containerDefinitions[0].image = "nginx:alpine"'
    ;;

  oom-task)
    log "Lowering task memory to 32 MB (below nginx minimum — triggers OOM)"
    _update_task_def '.memory = "32"'
    log "Tasks will be OOM-killed shortly after starting."
    ;;

  restore-memory)
    log "Restoring task memory to 512 MB"
    _update_task_def '.memory = "512"'
    ;;

  block-health-check)
    log "Changing ALB target group health check path to /this-will-404"
    TG_ARN=$(aws elbv2 describe-target-groups \
      --region "$REGION" \
      --query "TargetGroups[?contains(TargetGroupName,'${PREFIX}')].TargetGroupArn" \
      --output text | head -1)
    aws elbv2 modify-target-group \
      --target-group-arn "$TG_ARN" \
      --health-check-path "/this-will-404" \
      --region "$REGION" > /dev/null
    log "Done. Targets will start failing health checks — unhealthy after 3 × 30s."
    ;;

  restore-health-check)
    log "Restoring ALB target group health check path to /health"
    TG_ARN=$(aws elbv2 describe-target-groups \
      --region "$REGION" \
      --query "TargetGroups[?contains(TargetGroupName,'${PREFIX}')].TargetGroupArn" \
      --output text | head -1)
    aws elbv2 modify-target-group \
      --target-group-arn "$TG_ARN" \
      --health-check-path "/health" \
      --region "$REGION" > /dev/null
    log "Done."
    ;;

  stop-all-tasks)
    log "Stopping all running tasks in $CLUSTER/$SERVICE"
    TASK_ARNS=$(aws ecs list-tasks \
      --cluster "$CLUSTER" \
      --service-name "$SERVICE" \
      --region "$REGION" \
      --query 'taskArns[]' \
      --output text)
    for ARN in $TASK_ARNS; do
      aws ecs stop-task --cluster "$CLUSTER" --task "$ARN" --region "$REGION" > /dev/null
      log "Stopped $ARN"
    done
    log "Done. ECS will restart tasks to meet desired count."
    ;;

  status)
    log "=== ECS Service ==="
    aws ecs describe-services \
      --cluster "$CLUSTER" \
      --services "$SERVICE" \
      --region "$REGION" \
      --query 'services[0].{Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount}' \
      --output table

    log "=== ALB Target Health ==="
    TG_ARN=$(aws elbv2 describe-target-groups \
      --region "$REGION" \
      --query "TargetGroups[?contains(TargetGroupName,'${PREFIX}')].TargetGroupArn" \
      --output text | head -1)
    aws elbv2 describe-target-health \
      --target-group-arn "$TG_ARN" \
      --region "$REGION" \
      --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,Health:TargetHealth.State}' \
      --output table
    ;;

  *)
    log "Unknown fault: $FAULT"
    usage
    ;;
esac
