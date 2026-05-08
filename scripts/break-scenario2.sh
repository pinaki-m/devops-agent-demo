#!/usr/bin/env bash
# Break Scenario 2: MWAA + EMR Serverless
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-2}"
PREFIX="devops-agent-demo-demo-s2"
MWAA_ENV="${PREFIX}"
ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
BUCKET="${PREFIX}-mwaa-${ACCOUNT_ID}"

usage() {
  cat <<EOF
Usage: $0 <fault>

Faults:
  bad-dag             Upload a syntactically broken DAG to trigger import errors
  restore-dag         Remove the broken DAG
  revoke-emr-perms    Remove EMR job submission permission from MWAA execution role
  restore-emr-perms   Re-attach EMR permission policy
  corrupt-requirements  Upload a requirements.txt with a non-existent package version
  restore-requirements  Upload a clean requirements.txt
  stop-emr-app        Stop the EMR Serverless application
  start-emr-app       Start the EMR Serverless application
  status              Show current state
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage
FAULT="$1"

log() { echo "[$(date -u +%H:%M:%SZ)] $*"; }

case "$FAULT" in
  bad-dag)
    log "Uploading broken DAG to s3://$BUCKET/dags/broken_dag.py"
    cat > /tmp/broken_dag.py <<'PYEOF'
# Intentionally broken — unclosed parenthesis triggers Airflow import error
from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

with DAG("broken_dag", start_date=datetime(2024, 1, 1), schedule="@daily") as dag:
    t1 = PythonOperator(
        task_id="fail_import",
        python_callable=lambda: None
    # missing closing parenthesis and missing `)`
PYEOF
    aws s3 cp /tmp/broken_dag.py "s3://${BUCKET}/dags/broken_dag.py" --region "$REGION"
    log "Done. Airflow will surface an import error within ~30 seconds."
    ;;

  restore-dag)
    log "Removing broken DAG from S3"
    aws s3 rm "s3://${BUCKET}/dags/broken_dag.py" --region "$REGION"
    log "Done."
    ;;

  revoke-emr-perms)
    ROLE="${PREFIX}-mwaa-exec"
    log "Attaching deny policy for EMR Serverless on role $ROLE"
    aws iam put-role-policy \
      --role-name "$ROLE" \
      --policy-name "break-deny-emr" \
      --policy-document '{
        "Version":"2012-10-17",
        "Statement":[{"Effect":"Deny","Action":"emr-serverless:*","Resource":"*"}]
      }' \
      --region "$REGION"
    log "Done. MWAA tasks that submit EMR jobs will now receive AccessDenied."
    ;;

  restore-emr-perms)
    ROLE="${PREFIX}-mwaa-exec"
    log "Removing deny policy from role $ROLE"
    aws iam delete-role-policy \
      --role-name "$ROLE" \
      --policy-name "break-deny-emr" \
      --region "$REGION" 2>/dev/null || true
    log "Done."
    ;;

  corrupt-requirements)
    log "Uploading requirements.txt with a non-existent package"
    echo "apache-airflow-providers-amazon==99.99.99" > /tmp/requirements-broken.txt
    aws s3 cp /tmp/requirements-broken.txt "s3://${BUCKET}/requirements.txt" --region "$REGION"
    log "Done. MWAA will fail to install packages on next update cycle."
    ;;

  restore-requirements)
    log "Restoring empty requirements.txt"
    echo "" | aws s3 cp - "s3://${BUCKET}/requirements.txt" --region "$REGION"
    log "Done."
    ;;

  stop-emr-app)
    APP_ID=$(aws emr-serverless list-applications \
      --region "$REGION" \
      --query "applications[?name=='${PREFIX}-spark'].id" \
      --output text)
    log "Stopping EMR Serverless application $APP_ID"
    aws emr-serverless stop-application --application-id "$APP_ID" --region "$REGION"
    log "Done."
    ;;

  start-emr-app)
    APP_ID=$(aws emr-serverless list-applications \
      --region "$REGION" \
      --query "applications[?name=='${PREFIX}-spark'].id" \
      --output text)
    log "Starting EMR Serverless application $APP_ID"
    aws emr-serverless start-application --application-id "$APP_ID" --region "$REGION"
    log "Done."
    ;;

  status)
    log "=== MWAA ==="
    aws mwaa get-environment --name "$MWAA_ENV" --region "$REGION" \
      --query 'Environment.{Status:Status,AirflowVersion:AirflowVersion}' \
      --output table

    log "=== EMR Serverless ==="
    aws emr-serverless list-applications --region "$REGION" \
      --query "applications[?name=='${PREFIX}-spark'].{Name:name,State:state,Id:id}" \
      --output table
    ;;

  *)
    log "Unknown fault: $FAULT"
    usage
    ;;
esac
