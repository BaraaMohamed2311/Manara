import json
import os
import smtplib
from datetime import datetime, timezone
from email.mime.text import MIMEText

APP_NAME = "Image Processing Pipeline"

SMTP_HOST = os.environ["SMTP_HOST"]                    # e.g. "smtp.gmail.com" or "smtp.sendgrid.net"
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))    # 587 = STARTTLS, 465 = implicit TLS
SMTP_USER = os.environ["SMTP_USER"]
SMTP_PASSWORD = os.environ["SMTP_PASSWORD"]
SENDER = os.environ["SENDER"]
RECIPIENTS = [addr.strip() for addr in os.environ["RECIPIENT"].split(",") if addr.strip()]


def _fmt_step(name: str, data: dict) -> str:
    """Render one step's recorded info as a single readable line."""
    status = data.get("status", "unknown").upper()
    details = {k: v for k, v in data.items() if k != "status"}
    detail_str = ", ".join(f"{k}={v}" for k, v in details.items())
    line = f"  • {name.capitalize():<10} [{status}]"
    if detail_str:
        line += f" — {detail_str}"
    return line


def _build_success_message(event: dict) -> tuple[str, str]:
    key = event.get("final_key") or event.get("key", "unknown")
    bucket = event.get("bucket", "unknown")
    image_id = event.get("imageId") or event.get("image_id", "unknown")
    steps = event.get("steps", {})
    started = event.get("metadata", {}).get("uploaded_at", "unknown")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    subject = f"✅ {APP_NAME} — Completed: {os.path.basename(key)}"

    step_lines = "\n".join(_fmt_step(name, data) for name, data in steps.items()) or "  (no step details recorded)"

    body = f"""\
{APP_NAME}
Status: SUCCESS
{'-' * 40}

Your image has finished processing and is ready.

  Image ID        : {image_id}
  Final location  : s3://{bucket}/{key}
  Uploaded at     : {started}
  Completed at    : {now}

Pipeline steps:
{step_lines}

{'-' * 40}
This is an automated notification. No action is needed.
"""
    return subject, body


def _build_failure_message(event: dict, context) -> tuple[str, str]:
    error = event.get("error", {}) if isinstance(event.get("error"), dict) else {}
    error_type = error.get("Error", "UnknownError")
    error_cause = error.get("Cause", "No further details were provided by the failed step.")
    key = event.get("key", "unknown")
    bucket = event.get("bucket", "unknown")
    image_id = event.get("imageId") or event.get("image_id", "unknown")
    steps = event.get("steps", {})
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    execution_arn = event.get("execution_arn") or (
        context.invoked_function_arn if context else "unknown"
    )

    subject = f"❌ {APP_NAME} — Failed: {os.path.basename(key)}"

    step_lines = "\n".join(_fmt_step(name, data) for name, data in steps.items()) or "  (failed before any step completed)"

    body = f"""\
{APP_NAME}
Status: FAILED
{'-' * 40}

Image processing could not be completed.

  Image ID        : {image_id}
  Source file     : s3://{bucket}/{key}
  Failed at       : {now}
  Error type      : {error_type}

Steps completed before failure:
{step_lines}

Error details:
  {error_cause}

{'-' * 40}
Execution reference: {execution_arn}
This is an automated notification. Please check CloudWatch Logs for the full stack trace.
"""
    return subject, body


def _send_email(subject: str, body: str) -> None:
    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = subject[:998]
    msg["From"] = SENDER
    msg["To"] = ", ".join(RECIPIENTS)

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=10) as server:
        server.starttls()
        server.login(SMTP_USER, SMTP_PASSWORD)
        server.sendmail(SENDER, RECIPIENTS, msg.as_string())


def lambda_handler(event, context):

    processed = []

    for record in event.get("Records", []):
        sns_msg = record["Sns"]
        payload = json.loads(sns_msg["Message"])  # the raw pipeline state the Step Function published

        status = payload.get("status", "success").lower()

        if status == "failure":
            subject, body = _build_failure_message(payload, context)
        else:
            subject, body = _build_success_message(payload)

        _send_email(subject, body)
        processed.append({"subject": subject})

    return {"sent": len(processed), "emails": processed}