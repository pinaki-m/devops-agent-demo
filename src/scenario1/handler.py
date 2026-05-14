import json
import os
import uuid
import boto3
from datetime import datetime, timezone, timedelta

dynamodb = boto3.resource("dynamodb")
ssm = boto3.client("ssm")

TABLE_NAME = os.environ["DYNAMODB_TABLE"]
SLACK_SSM_PREFIX = os.environ.get("SLACK_SSM_PREFIX", "/cloudops/slack")


def _get_slack_webhook() -> str | None:
    try:
        resp = ssm.get_parameter(
            Name=f"{SLACK_SSM_PREFIX}/webhook_url",
            WithDecryption=True,
        )
        return resp["Parameter"]["Value"]
    except ssm.exceptions.ParameterNotFound:
        return None


def _persist_event(event_data: dict) -> None:
    table = dynamodb.Table(TABLE_NAME)
    now = datetime.now(timezone.utc)
    table.put_item(
        Item={
            "event_id": str(uuid.uuid4()),
            "timestamp": now.isoformat(),
            "payload": json.dumps(event_data),
            "expires_at": int((now + timedelta(days=7)).timestamp()),
        }
    )


def lambda_handler(event: dict, context) -> dict:
    records = event.get("Records", [{"body": json.dumps(event)}])

    processed = 0
    for record in records:
        try:
            body = json.loads(record.get("body", "{}"))
            _persist_event(body)
            processed += 1
        except Exception as exc:
            print(f"ERROR processing record: {exc}")
            raise

    return {"statusCode": 200, "processed": processed}
