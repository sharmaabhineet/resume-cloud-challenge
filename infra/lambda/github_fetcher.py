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
    """Returns commit/PR/issue counts and contributed repo list over the last 30 days, including private repos."""
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=30)
    query = f"""
    {{
      user(login: "{GITHUB_USER}") {{
        contributionsCollection(
          from: "{cutoff.strftime('%Y-%m-%dT%H:%M:%SZ')}",
          to:   "{now.strftime('%Y-%m-%dT%H:%M:%SZ')}"
        ) {{
          totalCommitContributions
          totalPullRequestContributions
          totalIssueContributions
          totalRepositoriesWithContributedCommits
          commitContributionsByRepository(maxRepositories: 10) {{
            repository {{
              nameWithOwner
              isPrivate
            }}
          }}
        }}
      }}
    }}
    """
    result = graphql(query, token)
    col = (
        result.get("data", {})
              .get("user", {})
              .get("contributionsCollection", {})
    )
    contributed_repos = [
        {
            "name":    entry["repository"]["nameWithOwner"],
            "private": entry["repository"]["isPrivate"],
        }
        for entry in col.get("commitContributionsByRepository", [])
        if entry.get("repository")
    ]
    return {
        "commits_30d":       col.get("totalCommitContributions", 0),
        "prs_30d":           col.get("totalPullRequestContributions", 0),
        "issues_30d":        col.get("totalIssueContributions", 0),
        "repos_active":      col.get("totalRepositoriesWithContributedCommits", 0),
        "includes_private":  True,
        "contributed_repos": contributed_repos,
    }


def fetch_commit_messages(token, contributed_repos, since_iso):
    """Fetch recent commit messages from PUBLIC repos only. Private repos contribute counts only."""
    messages = []
    for repo in contributed_repos[:8]:  # cap at 8 repos
        if repo["private"]:
            continue  # never fetch content from private repos
        repo_name = repo["name"]
        label = repo_name.split("/")[-1]
        try:
            commits = rest_get(
                f"/repos/{repo_name}/commits"
                f"?author={GITHUB_USER}&since={since_iso}&per_page=15",
                token,
            )
            for c in commits[:15]:
                msg = c.get("commit", {}).get("message", "").split("\n")[0].strip()
                if msg:
                    messages.append(f"[{label}] {msg}")
        except Exception as e:
            print(f"Could not fetch commits for {repo_name}: {e}")
    return messages


def bedrock_summary(repos, activity, commit_messages):
    repo_list = "\n".join(
        f"- {r['name']} ({r['language']}): {r['description'][:120]}"
        for r in repos
    )
    private_repos = activity["repos_active"] - sum(
        1 for r in activity.get("contributed_repos", []) if not r["private"]
    )
    commits_excerpt = "\n".join(commit_messages[:40]) if commit_messages else "No public commit messages available."
    prompt = (
        f"You are summarising a software engineer's GitHub activity for their resume website.\n\n"
        f"Pinned repositories:\n{repo_list}\n\n"
        f"Last 30 days — total activity (public + private repos): {activity['commits_30d']} commits, "
        f"{activity['prs_30d']} pull requests, {activity['issues_30d']} issues "
        f"across {activity['repos_active']} repos "
        f"({private_repos} of which are private — no details available).\n\n"
        f"Recent commit messages from public repos only:\n{commits_excerpt}\n\n"
        f"Write 2-3 sentences (max 60 words) summarising the kinds of projects and technical areas "
        f"worked on, based on the public commit messages. Acknowledge that additional private work "
        f"is reflected in the activity counts. Focus on themes and technologies, not repo names. "
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

    since_iso = (datetime.now(timezone.utc) - timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ")
    commit_messages = fetch_commit_messages(token, activity.get("contributed_repos", []), since_iso)

    try:
        ai_summary = bedrock_summary(repos, activity, commit_messages)
    except Exception as e:
        print(f"Bedrock summary failed: {e}")
        ai_summary = ""

    public_activity = {k: v for k, v in activity.items() if k != "contributed_repos"}
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source":        source,
        "repos":         repos,
        "activity":      public_activity,
        "ai_summary":    ai_summary,
    }

    s3.put_object(
        Bucket=S3_BUCKET,
        Key="repos.json",
        Body=json.dumps(payload, ensure_ascii=False),
        ContentType="application/json",
        CacheControl="no-cache, no-store, must-revalidate",
    )

    print(f"Wrote repos.json — {len(repos)} repos, {activity['commits_30d']} commits, {activity['prs_30d']} PRs, {activity['issues_30d']} issues/30d (incl. private)")
    return {"statusCode": 200, "body": f"{len(repos)} repos written"}
