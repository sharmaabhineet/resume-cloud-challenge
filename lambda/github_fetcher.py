"""
GitHub Repos & Activity Fetcher
- Fetches pinned repos via GraphQL (works with private repos using PAT)
- Falls back to recently-pushed repos via REST API
- Summarises 30-day activity with AWS Bedrock (Claude 3 Haiku)
- Writes repos.json to S3
"""
import json
import os
import urllib.request
import urllib.error
import boto3
from datetime import datetime, timezone, timedelta

S3_BUCKET      = os.environ["S3_BUCKET"]
SECRET_ARN     = os.environ["GITHUB_PAT_SECRET_ARN"]
BEDROCK_MODEL  = os.environ.get("BEDROCK_MODEL", "anthropic.claude-3-haiku-20240307-v1:0")
GITHUB_USER    = os.environ.get("GITHUB_USER", "sharmaabhineet")
MAX_REPOS      = int(os.environ.get("MAX_REPOS", "6"))

s3       = boto3.client("s3")
sm       = boto3.client("secretsmanager")
bedrock  = boto3.client("bedrock-runtime", region_name="us-east-1")


def get_pat():
    resp = sm.get_secret_value(SecretId=SECRET_ARN)
    secret = json.loads(resp["SecretString"])
    return secret["pat"]


def graphql(query, token):
    data = json.dumps({"query": query}).encode()
    req = urllib.request.Request(
        "https://api.github.com/graphql",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "resume-github-fetcher/1.0",
        },
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())


def rest_get(path, token):
    req = urllib.request.Request(
        f"https://api.github.com{path}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "resume-github-fetcher/1.0",
        },
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())


def fetch_pinned_repos(token):
    query = f"""
    {{
      user(login: "{GITHUB_USER}") {{
        pinnedItems(first: {MAX_REPOS}, types: REPOSITORY) {{
          nodes {{
            ... on Repository {{
              name
              description
              url
              isPrivate
              primaryLanguage {{ name }}
              stargazerCount
              forkCount
              repositoryTopics(first: 5) {{
                nodes {{ topic {{ name }} }}
              }}
              updatedAt
            }}
          }}
        }}
      }}
    }}
    """
    result = graphql(query, token)
    nodes = result.get("data", {}).get("user", {}).get("pinnedItems", {}).get("nodes", [])
    repos = []
    for n in nodes:
        if not n:
            continue
        repos.append({
            "name":        n["name"],
            "description": n.get("description") or "",
            "url":         n["url"],
            "private":     n.get("isPrivate", False),
            "language":    (n.get("primaryLanguage") or {}).get("name", ""),
            "stars":       n.get("stargazerCount", 0),
            "forks":       n.get("forkCount", 0),
            "topics":      [t["topic"]["name"] for t in n.get("repositoryTopics", {}).get("nodes", [])],
            "updated_at":  n.get("updatedAt", ""),
        })
    return repos


def fetch_recent_repos(token):
    repos_raw = rest_get(
        f"/users/{GITHUB_USER}/repos?sort=pushed&per_page={MAX_REPOS}&type=owner",
        token,
    )
    repos = []
    for r in repos_raw[:MAX_REPOS]:
        repos.append({
            "name":        r["name"],
            "description": r.get("description") or "",
            "url":         r["html_url"],
            "private":     r.get("private", False),
            "language":    r.get("language") or "",
            "stars":       r.get("stargazers_count", 0),
            "forks":       r.get("forks_count", 0),
            "topics":      r.get("topics", []),
            "updated_at":  r.get("updated_at", ""),
        })
    return repos


def fetch_activity_stats(token):
    """Returns commit count and active repo set over the last 30 days."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=30)
    commits = 0
    active_repos = set()
    page = 1
    while page <= 5:  # cap at 5 pages (150 events)
        try:
            events = rest_get(
                f"/users/{GITHUB_USER}/events?per_page=30&page={page}",
                token,
            )
        except Exception:
            break
        if not events:
            break
        for ev in events:
            created = ev.get("created_at", "")
            try:
                ts = datetime.fromisoformat(created.replace("Z", "+00:00"))
            except Exception:
                continue
            if ts < cutoff:
                page = 999  # signal done
                break
            if ev["type"] == "PushEvent":
                commits += ev.get("payload", {}).get("size", 0)
                active_repos.add(ev["repo"]["name"])
        page += 1

    return {
        "commits_30d":    commits,
        "repos_active":   len(active_repos),
        "active_repo_list": sorted(active_repos),
    }


def bedrock_summary(repos, activity):
    repo_list = "\n".join(
        f"- {r['name']} ({r['language']}): {r['description'][:120]}"
        for r in repos
    )
    prompt = (
        f"You are summarising a software engineer's GitHub activity for their resume website.\n\n"
        f"Pinned repositories:\n{repo_list}\n\n"
        f"Last 30 days: {activity['commits_30d']} commits across {activity['repos_active']} active repos.\n\n"
        f"Write 1-2 sentences (max 40 words) highlighting the breadth of their work and recent momentum. "
        f"Write in third person. Do not start with 'Abhineet'."
    )
    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 120,
        "messages": [{"role": "user", "content": prompt}],
    })
    resp = bedrock.invoke_model(
        modelId=BEDROCK_MODEL,
        body=body,
        contentType="application/json",
        accept="application/json",
    )
    result = json.loads(resp["body"].read())
    return result["content"][0]["text"].strip()


def handler(event, context):
    token = get_pat()

    # Fetch repos — pinned preferred, fall back to recently pushed
    try:
        repos = fetch_pinned_repos(token)
        source = "pinned"
    except Exception as e:
        print(f"Pinned repos failed ({e}), falling back to recent repos")
        repos = fetch_recent_repos(token)
        source = "recent"

    # If GraphQL returned no pinned repos, fall back
    if not repos:
        repos = fetch_recent_repos(token)
        source = "recent"

    activity = fetch_activity_stats(token)

    try:
        ai_summary = bedrock_summary(repos, activity)
    except Exception as e:
        print(f"Bedrock summary failed: {e}")
        ai_summary = ""

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source":        source,
        "repos":         repos,
        "activity":      activity,
        "ai_summary":    ai_summary,
    }

    s3.put_object(
        Bucket=S3_BUCKET,
        Key="repos.json",
        Body=json.dumps(payload, ensure_ascii=False),
        ContentType="application/json",
        CacheControl="no-cache, no-store, must-revalidate",
    )

    print(f"Wrote repos.json — {len(repos)} repos, {activity['commits_30d']} commits/30d")
    return {"statusCode": 200, "body": f"{len(repos)} repos written"}
