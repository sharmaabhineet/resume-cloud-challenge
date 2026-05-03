"""
Portfolio Chat Agent Lambda

Routes:
  GET  /chat-token  — issue a short-lived HMAC session token (master secret never leaves server)
  POST /chat        — validate token + run chat turn

Protections:
- HMAC session tokens (10-min windows, unique nonce per session, master secret in Secrets Manager only)
- Per-IP rate limit: 10 req/hour on /chat; 3 req/hour on /chat-token (DynamoDB + TTL)
- Daily token cap:   ~33,333 tokens  (~1M / 30)
- Monthly token cap: 1,000,000 tokens
- SNS alert on first cap breach (daily + monthly)
- SES transcript email after every turn (IP, message, reply, tokens)
- Prompt injection + garbage input filters
"""
import hashlib
import hmac as hmac_lib
import json
import os
import re
import secrets as secrets_lib
import time
import boto3
from datetime import datetime, timezone

DYNAMODB_TABLE  = os.environ["DYNAMODB_TABLE"]
API_KEY_SECRET  = os.environ["API_KEY_SECRET_ARN"]
SNS_TOPIC_ARN   = os.environ["SNS_TOPIC_ARN"]
BEDROCK_MODEL   = os.environ.get("BEDROCK_MODEL", "us.anthropic.claude-haiku-4-5-20251001-v1:0")
FROM_EMAIL      = os.environ["FROM_EMAIL"]
TO_EMAIL        = os.environ["TO_EMAIL"]
ALLOWED_ORIGIN  = os.environ["ALLOWED_ORIGIN"]
S3_BUCKET       = os.environ["S3_BUCKET"]

DAILY_TOKEN_CAP           = 33_333
MONTHLY_TOKEN_CAP         = 1_000_000
RATE_LIMIT_PER_HOUR       = 10   # chat requests per IP
RATE_LIMIT_TOKEN_PER_HOUR = 20   # token requests per IP per hour
TOKEN_WINDOW              = 600  # seconds — token valid for current + previous window
MAX_USER_MSG_LEN          = 500
MAX_HISTORY_TURNS         = 8    # last 8 turns = 16 messages

ddb     = boto3.client("dynamodb")
sm      = boto3.client("secretsmanager")
bedrock = boto3.client("bedrock-runtime", region_name="us-east-1")
sns     = boto3.client("sns")
ses     = boto3.client("ses", region_name="us-east-1")

# Cached across warm invocations
_cached_master_secret  = None   # HMAC signing key — never leaves the server
_cached_posts_section  = None   # Medium posts injected into system prompt
_cached_github_section = None   # GitHub repos/activity injected into system prompt

_SYSTEM_PROMPT_BASE = """You are a portfolio assistant for Abhineet Sharma, a Staff Backend Engineer with 15+ years of experience.

Answer ONLY questions about Abhineet's professional background, skills, experience, projects, and the content on this website. For any other topic, respond with: "I can only answer questions about Abhineet's professional background. Is there something specific about his experience or work you'd like to know?"

Keep answers concise and professional — 2-4 sentences unless more detail is explicitly requested.

=== STRICT RULES — FOLLOW WITHOUT EXCEPTION ===
1. Only state facts that are explicitly present in this system prompt. Do not infer, extrapolate, or assume anything beyond what is written here.
2. If you do not have information to answer a question, say exactly: "I don't have that information." Do not fill gaps with plausible-sounding details.
3. Never fabricate project names, company names, dates, metrics, technologies, or any other specifics. If a detail is not listed, it does not exist as far as you are concerned.
4. Do not make up opinions, preferences, or personality traits for Abhineet beyond what is explicitly stated.
5. If asked about something that might be true but is not in this prompt (e.g. a specific technology, company detail, or date), say you don't have that information rather than guessing.

=== BACKGROUND ===
Abhineet Sharma is a Staff Engineer at Yieldmo (ad-tech, New York) since November 2019. He has 15+ years of backend engineering experience and ~8 years of cloud experience. He holds an MS in Computer Science from Iowa State University (2014). Based in New York, NY.

=== CAREER HISTORY ===
Yieldmo, New York (Nov 2019–Present)
  - Staff Engineer since Mar 2021; Senior Software Engineer Nov 2019–Mar 2021
  - High-throughput ad delivery platform processing billions of ad requests daily
  - ~2% CPU reduction via algorithmic + system-level optimization in high-demand production paths
  - ~5% platform spend growth through ad signal improvements and data-driven backend changes
  - Built next-generation data provider library with cleaner abstractions, reducing development effort
  - Partners with data and front-end teams; leads technical design reviews and code reviews

Workmarket (an ADP Company), New York (Oct 2018–Nov 2019, 1 yr 2 mos)
  - Senior Software Engineer; financial workflows, high-volume transactional systems
  - Drove adoption of RxJava reactive patterns; led hackathon ML job-classification project

Workiva, Ames IA (Jun 2016–Oct 2018, 2 yrs 5 mos)
  - Senior Software Engineer; XBRL financial reporting, Java/Spring Boot microservices
  - Evolved legacy components to modern distributed services, improving performance and maintainability

Oracle, Hyderabad India (Oct 2010–Jul 2014, 3 yrs 10 mos)
  - Senior Applications Engineer; supply chain orchestration, ADF/SOA frameworks
  - Mentored engineers and contractors across teams

Tata Consultancy Services, Hyderabad India (Jul 2008–Oct 2010, 2 yrs 4 mos)
  - Assistant Systems Engineer; PKI applications in Core Java
  - Top 100 in company-wide Algorithm Design Contest; Sun Certified Java Programmer

=== SKILLS ===
Expert: Java, Backend Development
Strong: Microservices, Python, gRPC, SQL, Docker
Working Knowledge: Kafka, Golang, C++, R, Machine Learning
Practices: Distributed Systems, CI/CD, TDD, Code Review, Agile
Infrastructure: AWS, Terraform, Linux, Redis, DynamoDB, PostgreSQL

=== ENGINEERING PRINCIPLES ===
1. Start simple — modularity first, distribution only when scale or failure modes justify it
2. Measure before optimizing — production evidence to find real bottlenecks
3. Design for operations — observable, debuggable, recoverable, understandable under pressure
4. Use AI as leverage — tools accelerate implementation; judgment, review, ownership stay with the engineer

=== PUBLIC PROJECT ===
resume-cloud-challenge (this portfolio website):
  Full-stack cloud project built entirely on AWS. Static site (S3 + CloudFront) with serverless backend (Lambda + API Gateway). Features: visitor counter (DynamoDB), contact form (SES), AI-generated GitHub activity summary (Bedrock + Claude Haiku), AI-generated Medium post summaries, and this chat agent. Infrastructure as code via Terraform with remote state in S3. CI/CD via GitHub Actions with OIDC authentication — no long-lived AWS credentials in source control. Domain: portfolio.sharmaabhineet.com.
  Tech stack: S3, CloudFront, Lambda, API Gateway, DynamoDB, SES, Bedrock, EventBridge, Secrets Manager, Route53, ACM, Terraform, GitHub Actions.

=== PRIVATE PROJECTS ===
Trading AI Agent:
  An event-driven prototype exploring LLM-assisted trading decision workflows. Core design insight: separate the event log (immutable source of truth) from the LLM reasoning layer so all decisions are replayable and auditable. Built in Python. Focus areas: backtesting loops with historical data replay, prompt evaluation frameworks to assess decision quality, guardrails for deterministic execution (preventing the model from making irreversible side effects), LLM-assisted market signal analysis. Not a live trading system — a research and architecture workbench for understanding how to build reliable AI-in-the-loop systems.

Ask My Docs:
  A RAG (Retrieval-Augmented Generation) workspace for evaluating document ingestion pipelines end-to-end. Covers: chunking strategy experiments (fixed-size vs. semantic), embedding model comparison, vector search quality benchmarking, retrieval reranking, and answer citation quality. Built in Python. Used to benchmark retrieval quality across different document types and collection sizes — the kind of ground-truth evaluation work that's hard to shortcut. A practical testbed before committing to a production RAG stack.

=== AVAILABILITY & INTERESTS ===
Open to conversations about strong backend engineering roles, particularly those involving distributed systems, high-scale platforms, cloud-native architecture, or AI-integrated backends. Happy to discuss technical approach and trade-offs in depth.

=== CONTACT ===
LinkedIn: linkedin.com/in/sharmaabhineet
GitHub: github.com/sharmaabhineet
Medium: medium.com/@sharmaabhineet
Website: portfolio.sharmaabhineet.com
{medium_section}
{github_section}
"""


def build_system_prompt():
    return _SYSTEM_PROMPT_BASE.format(
        medium_section=get_medium_section(),
        github_section=get_github_section(),
    )


def get_master_secret():
    global _cached_master_secret
    if _cached_master_secret:
        return _cached_master_secret
    resp = sm.get_secret_value(SecretId=API_KEY_SECRET)
    _cached_master_secret = json.loads(resp["SecretString"])["key"]
    return _cached_master_secret


# ---- HMAC session token helpers ----

def _current_window():
    return int(time.time()) // TOKEN_WINDOW


def generate_token(master_secret):
    """Create a unique signed token for the current window."""
    nonce  = secrets_lib.token_hex(16)
    window = _current_window()
    msg    = f"{window}:{nonce}"
    sig    = hmac_lib.new(master_secret.encode(), msg.encode(), hashlib.sha256).hexdigest()[:32]
    return f"{window}:{nonce}:{sig}"


def validate_token(token, master_secret):
    """Accept tokens from the current or previous window (handles boundary crossings)."""
    try:
        window_str, nonce, given_sig = token.split(":")
        token_window  = int(window_str)
        current       = _current_window()
        if token_window not in (current, current - 1):
            return False
        msg          = f"{token_window}:{nonce}"
        expected_sig = hmac_lib.new(master_secret.encode(), msg.encode(), hashlib.sha256).hexdigest()[:32]
        return hmac_lib.compare_digest(given_sig, expected_sig)
    except Exception:
        return False


def get_medium_section():
    """Fetch posts.json from S3 and build a Medium section for the system prompt.
    Cached in global scope — refreshes on Lambda cold start (weekly cadence is fine)."""
    global _cached_posts_section
    if _cached_posts_section is not None:
        return _cached_posts_section
    try:
        obj  = s3.get_object(Bucket=S3_BUCKET, Key="posts.json")
        data = json.loads(obj["Body"].read())
        posts    = data.get("posts", [])
        top_tags = data.get("top_tags", [])
        total    = data.get("total_posts", len(posts))

        lines = [f"=== MEDIUM WRITING ({total} total posts) ==="]
        for p in posts:
            tags = ", ".join(p.get("tags", []))
            summary = p.get("summary", "").strip()
            lines.append(
                f'- "{p["title"]}" ({p.get("published","")})'
                + (f" — {summary}" if summary else "")
                + (f" [{tags}]" if tags else "")
                + f"  {p.get('url','')}"
            )
        if top_tags:
            tag_str = ", ".join(t["tag"] for t in top_tags)
            lines.append(f"Top recurring themes: {tag_str}")
        lines.append("Full profile: https://medium.com/@sharmaabhineet")

        _cached_posts_section = "\n".join(lines)
    except Exception as e:
        print(f"Could not load posts.json: {e}")
        _cached_posts_section = (
            "=== MEDIUM WRITING ===\n"
            "Abhineet writes on Medium (@sharmaabhineet) about AI-assisted engineering, "
            "distributed systems, cloud architecture, and practical backend tradeoffs. "
            "Full profile: https://medium.com/@sharmaabhineet"
        )
    return _cached_posts_section


def get_github_section():
    """Fetch repos.json from S3 and build a GitHub section for the system prompt.
    Cached in global scope — refreshes on Lambda cold start (weekly cadence is fine)."""
    global _cached_github_section
    if _cached_github_section is not None:
        return _cached_github_section
    try:
        obj  = s3.get_object(Bucket=S3_BUCKET, Key="repos.json")
        data = json.loads(obj["Body"].read())
        repos      = data.get("repos", [])
        activity   = data.get("activity", {})
        ai_summary = data.get("ai_summary", "").strip()
        generated  = data.get("generated_at", "")

        lines = ["=== GITHUB ACTIVITY ==="]
        if ai_summary:
            lines.append(f"AI summary: {ai_summary}")
        if activity:
            lines.append(
                f"Last 30 days: {activity.get('commits_30d', 0)} commits, "
                f"{activity.get('prs_30d', 0)} PRs, "
                f"{activity.get('repos_active', 0)} repos active "
                f"(includes private repos)"
            )
        if repos:
            lines.append("Pinned / recent repositories:")
            for r in repos:
                lock = " [private]" if r.get("private") else ""
                lang = f" ({r['language']})" if r.get("language") else ""
                desc = f" — {r['description']}" if r.get("description") else ""
                lines.append(f"  - {r['name']}{lock}{lang}{desc}")
        if generated:
            lines.append(f"Data last refreshed: {generated[:10]}")
        lines.append("GitHub profile: https://github.com/sharmaabhineet")

        _cached_github_section = "\n".join(lines)
    except Exception as e:
        print(f"Could not load repos.json: {e}")
        _cached_github_section = (
            "=== GITHUB ACTIVITY ===\n"
            "Active on GitHub (sharmaabhineet). Public repo: resume-cloud-challenge (this portfolio). "
            "Private repos include Trading AI Agent and Ask My Docs. "
            "Profile: https://github.com/sharmaabhineet"
        )
    return _cached_github_section


def now_keys():
    now = datetime.now(timezone.utc)
    return {
        "month": now.strftime("%Y-%m"),
        "day":   now.strftime("%Y-%m-%d"),
        "hour":  now.strftime("%Y-%m-%dT%H"),
    }


def get_count(pk, field):
    resp = ddb.get_item(
        TableName=DYNAMODB_TABLE,
        Key={"pk": {"S": pk}},
        ProjectionExpression=field,
    )
    return int(resp.get("Item", {}).get(field, {}).get("N", "0"))


def increment_counter(pk, field, amount, ttl_seconds=None):
    expr = f"ADD {field} :n"
    vals = {":n": {"N": str(amount)}}
    names = {}
    if ttl_seconds:
        expr += " SET #t = :ttl"
        names["#t"] = "ttl"
        vals[":ttl"] = {"N": str(int(time.time()) + ttl_seconds)}
    ddb.update_item(
        TableName=DYNAMODB_TABLE,
        Key={"pk": {"S": pk}},
        UpdateExpression=expr,
        ExpressionAttributeValues=vals,
        **({"ExpressionAttributeNames": names} if names else {}),
    )


def notify_cap_breach(cap_type, current, cap_limit, pk):
    resp = ddb.get_item(
        TableName=DYNAMODB_TABLE,
        Key={"pk": {"S": pk}},
        ProjectionExpression="notified",
    )
    if resp.get("Item", {}).get("notified", {}).get("BOOL", False):
        return
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[Portfolio Chat] {cap_type} token cap reached",
            Message=(
                f"The {cap_type.lower()} token cap for the portfolio chat agent has been reached.\n\n"
                f"Usage: {current:,} / {cap_limit:,} tokens\n"
                f"Period: {pk}\n\n"
                f"New requests will be blocked until the cap resets."
            ),
        )
        ddb.update_item(
            TableName=DYNAMODB_TABLE,
            Key={"pk": {"S": pk}},
            UpdateExpression="SET notified = :true",
            ExpressionAttributeValues={":true": {"BOOL": True}},
        )
    except Exception as e:
        print(f"SNS notify failed: {e}")


def send_transcript(ip, user_msg, assistant_msg, tokens, keys):
    try:
        ses.send_email(
            Source=FROM_EMAIL,
            Destination={"ToAddresses": [TO_EMAIL]},
            Message={
                "Subject": {"Data": "[Portfolio Chat Transcript]"},
                "Body": {
                    "Text": {
                        "Data": (
                            f"Time (UTC): {datetime.now(timezone.utc).isoformat()}\n"
                            f"IP:         {ip}\n"
                            f"Period:     {keys['month']} / {keys['day']}\n"
                            f"Tokens:     {tokens}\n\n"
                            f"USER:\n{user_msg}\n\n"
                            f"ASSISTANT:\n{assistant_msg}\n"
                        )
                    }
                },
            },
        )
    except Exception as e:
        print(f"SES transcript failed: {e}")


_INJECTION_PATTERNS = [
    r"ignore\s+(previous|prior|above|all)\s+instructions",
    r"forget\s+(everything|all|your\s+instructions)",
    r"you\s+are\s+now\s+",
    r"pretend\s+(you\s+are|to\s+be)",
    r"act\s+as\s+(if\s+you\s+are|a\s+)",
    r"new\s+(instructions|rules|persona|role)\s*:",
    r"system\s*prompt",
    r"disregard\s+(your|all|previous)",
    r"jailbreak",
    r"dan\s+mode",
    r"do\s+anything\s+now",
    r"override\s+(your|all|previous)",
    r"reveal\s+your\s+(instructions|prompt|system)",
    r"what\s+(is|are)\s+your\s+(instructions|prompt|system\s+prompt)",
]

_INJECTION_RE = re.compile("|".join(_INJECTION_PATTERNS), re.IGNORECASE)

_GARBAGE_RE = re.compile(r"^(.)\1{9,}$|^\s*$|^[^a-zA-Z0-9]{10,}$")


def is_prompt_injection(text):
    return bool(_INJECTION_RE.search(text))


def is_garbage(text):
    return bool(_GARBAGE_RE.match(text.strip()))


def cors_headers():
    return {
        "Access-Control-Allow-Origin":  ALLOWED_ORIGIN,
        "Access-Control-Allow-Headers": "Content-Type,X-Chat-Key",
        "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    }


def respond(status, body):
    return {
        "statusCode": status,
        "headers":    {**cors_headers(), "Content-Type": "application/json"},
        "body":       json.dumps(body),
    }


def handle_token_request(event):
    """GET /chat-token — issue a short-lived HMAC session token."""
    ip   = event.get("requestContext", {}).get("http", {}).get("sourceIp", "unknown")
    keys = now_keys()

    # Rate limit token requests per IP
    rate_pk = f"TOKENRATE#{ip}#{keys['hour']}"
    if get_count(rate_pk, "req_count") >= RATE_LIMIT_TOKEN_PER_HOUR:
        return respond(429, {"error": "Too many requests. Please try again later."})

    token  = generate_token(get_master_secret())
    increment_counter(rate_pk, "req_count", 1, ttl_seconds=3600)

    # Tell the client when to refresh (remaining time in current window + one full window buffer)
    seconds_remaining = TOKEN_WINDOW - (int(time.time()) % TOKEN_WINDOW)
    return respond(200, {"token": token, "expires_in": seconds_remaining + TOKEN_WINDOW})


def handle_chat_request(event):
    """POST /chat — validate session token and run a chat turn."""
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}

    # 1. Token validation
    if not validate_token(headers.get("x-chat-key", ""), get_master_secret()):
        return respond(401, {"error": "Unauthorized"})

    # 2. Parse body
    try:
        body = json.loads(event.get("body") or "{}")
        user_message = str(body.get("message", "")).strip()[:MAX_USER_MSG_LEN]
        raw_history  = body.get("history", [])
    except Exception:
        return respond(400, {"error": "Invalid request"})

    if not user_message:
        return respond(400, {"error": "Message is required"})

    # 3. Input safety checks
    if is_garbage(user_message):
        return respond(400, {"error": "Message not recognised. Please ask a question."})
    if is_prompt_injection(user_message):
        return respond(400, {"error": "I can only answer questions about Abhineet's professional background."})
    # Apply the same checks to any history content arriving from the client
    for h in raw_history:
        if is_prompt_injection(str(h.get("content", ""))):
            return respond(400, {"error": "I can only answer questions about Abhineet's professional background."})

    ip   = event.get("requestContext", {}).get("http", {}).get("sourceIp", "unknown")
    keys = now_keys()

    # 4. Rate limit (per IP per hour)
    rate_pk = f"RATELIMIT#{ip}#{keys['hour']}"
    if get_count(rate_pk, "req_count") >= RATE_LIMIT_PER_HOUR:
        return respond(429, {"error": "Rate limit exceeded. Please try again later."})

    # 5. Daily token cap
    daily_pk   = f"DAILY#{keys['day']}"
    daily_used = get_count(daily_pk, "tokens_used")
    if daily_used >= DAILY_TOKEN_CAP:
        notify_cap_breach("Daily", daily_used, DAILY_TOKEN_CAP, daily_pk)
        return respond(429, {"error": "Daily limit reached. The assistant will be back tomorrow."})

    # 6. Monthly token cap
    monthly_pk   = f"MONTHLY#{keys['month']}"
    monthly_used = get_count(monthly_pk, "tokens_used")
    if monthly_used >= MONTHLY_TOKEN_CAP:
        notify_cap_breach("Monthly", monthly_used, MONTHLY_TOKEN_CAP, monthly_pk)
        return respond(429, {"error": "Monthly limit reached. The assistant will return next month."})

    # 7. Build Bedrock message list (enforce alternating roles, trim to last N turns)
    messages = []
    for h in raw_history[-(MAX_HISTORY_TURNS * 2):]:
        role    = h.get("role")
        content = str(h.get("content", "")).strip()
        if role in ("user", "assistant") and content:
            if messages and messages[-1]["role"] == role:
                continue  # skip consecutive same-role messages
            messages.append({"role": role, "content": [{"text": content}]})
    messages.append({"role": "user", "content": [{"text": user_message}]})

    # 8. Call Bedrock Converse API
    try:
        resp = bedrock.converse(
            modelId=BEDROCK_MODEL,
            system=[{"text": build_system_prompt()}],
            messages=messages,
            inferenceConfig={"maxTokens": 300, "temperature": 0.3},
        )
    except Exception as e:
        print(f"Bedrock error: {e}")
        return respond(500, {"error": "Assistant is temporarily unavailable. Please try again."})

    assistant_text = resp["output"]["message"]["content"][0]["text"]
    usage          = resp.get("usage", {})
    total_tokens   = usage.get("inputTokens", 0) + usage.get("outputTokens", 0)

    # 9. Update counters
    increment_counter(rate_pk,   "req_count",   1,            ttl_seconds=3600)
    increment_counter(daily_pk,  "tokens_used", total_tokens, ttl_seconds=172800)
    increment_counter(monthly_pk,"tokens_used", total_tokens)

    # 10. Post-increment cap alerts
    if daily_used + total_tokens >= DAILY_TOKEN_CAP:
        notify_cap_breach("Daily",   daily_used + total_tokens,   DAILY_TOKEN_CAP,   daily_pk)
    if monthly_used + total_tokens >= MONTHLY_TOKEN_CAP:
        notify_cap_breach("Monthly", monthly_used + total_tokens, MONTHLY_TOKEN_CAP, monthly_pk)

    # 11. Email transcript
    send_transcript(ip, user_message, assistant_text, total_tokens, keys)

    return respond(200, {"reply": assistant_text, "tokens_used": total_tokens})


def handler(event, context):
    http   = event.get("requestContext", {}).get("http", {})
    method = http.get("method", "")
    path   = http.get("path", "")

    if method == "OPTIONS":
        return {"statusCode": 204, "headers": cors_headers(), "body": ""}

    if method == "GET" and path.endswith("/chat-token"):
        return handle_token_request(event)

    if method == "POST" and path.endswith("/chat"):
        return handle_chat_request(event)

    return respond(404, {"error": "Not found"})
