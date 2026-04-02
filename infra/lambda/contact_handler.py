"""
Contact Form Handler
Receives POST body with name/email/message, sends email via SES.
"""
import json
import os
import re
import boto3

SES_REGION  = os.environ.get("SES_REGION", "us-east-1")
FROM_EMAIL  = os.environ["FROM_EMAIL"]    # noreply@sharmaabhineet.com
TO_EMAIL    = os.environ["TO_EMAIL"]

ses = boto3.client("ses", region_name=SES_REGION)

CORS_HEADERS = {
    "Access-Control-Allow-Origin":  os.environ.get("ALLOWED_ORIGIN", "*"),
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Content-Type":                 "application/json",
}

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def respond(status, body):
    return {
        "statusCode": status,
        "headers":    CORS_HEADERS,
        "body":       json.dumps(body),
    }


def handler(event, context):
    # Handle CORS preflight
    if event.get("requestContext", {}).get("http", {}).get("method", "") == "OPTIONS":
        return respond(200, {"ok": True})

    try:
        body = json.loads(event.get("body") or "{}")
    except Exception:
        return respond(400, {"error": "Invalid JSON"})

    # Honeypot — bots fill hidden fields, humans don't
    if body.get("website") or body.get("phone"):
        print("Honeypot triggered — likely bot submission")
        return respond(200, {"ok": True, "message": "Thanks! I'll get back to you soon."})

    name    = (body.get("name")    or "").strip()[:100]
    email   = (body.get("email")   or "").strip()[:200]
    message = (body.get("message") or "").strip()[:2000]

    if not name or not email or not message:
        return respond(400, {"error": "name, email, and message are required"})

    if not EMAIL_RE.match(email):
        return respond(400, {"error": "Invalid email address"})

    subject = f"Resume Contact: {name}"
    text_body = (
        f"Name:    {name}\n"
        f"Email:   {email}\n\n"
        f"Message:\n{message}\n"
    )
    html_body = f"""
<p><strong>Name:</strong> {name}</p>
<p><strong>Email:</strong> <a href="mailto:{email}">{email}</a></p>
<hr />
<p>{message.replace(chr(10), '<br>')}</p>
"""

    try:
        ses.send_email(
            Source=FROM_EMAIL,
            Destination={"ToAddresses": [TO_EMAIL]},
            ReplyToAddresses=[email],
            Message={
                "Subject": {"Data": subject, "Charset": "UTF-8"},
                "Body": {
                    "Text": {"Data": text_body, "Charset": "UTF-8"},
                    "Html": {"Data": html_body, "Charset": "UTF-8"},
                },
            },
        )
    except Exception as e:
        print(f"SES send failed: {e}")
        return respond(500, {"error": "Failed to send message. Please try emailing directly."})

    return respond(200, {"ok": True, "message": "Thanks! I'll get back to you soon."})
