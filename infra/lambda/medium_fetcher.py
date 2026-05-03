"""
Fetches the latest posts from a Medium RSS feed, generates AI summaries via
AWS Bedrock (Claude Haiku), and writes posts.json to S3.
Triggered weekly by EventBridge; can also be invoked manually.
"""
import json
import os
import re
import urllib.request
from datetime import datetime, timezone
from xml.etree import ElementTree as ET

import boto3

S3_BUCKET       = os.environ["S3_BUCKET"]
MEDIUM_FEED_URL = os.environ["MEDIUM_FEED_URL"]
MAX_POSTS       = int(os.environ.get("MAX_POSTS", "6"))
BEDROCK_MODEL   = os.environ.get("BEDROCK_MODEL", "anthropic.claude-3-haiku-20240307-v1:0")
AWS_REGION      = os.environ.get("AWS_REGION", "us-east-1")

NS = {
    "content": "http://purl.org/rss/1.0/modules/content/",
    "media":   "http://search.yahoo.com/mrss/",
}


def strip_html(html):
    return re.sub(r"<[^>]+>", " ", html or "")


def estimate_reading_time(html):
    words = len(strip_html(html).split())
    return max(1, round(words / 200))


def extract_thumbnail(item):
    for ns_key, local in [("media", "thumbnail"), ("media", "content")]:
        el = item.find(f"{{{NS[ns_key]}}}{local}")
        if el is not None and el.get("url"):
            return el.get("url")
    return None


def summarize(title, text):
    """Generate a 1-2 sentence summary using Claude Haiku via Bedrock."""
    bedrock = boto3.client("bedrock-runtime", region_name=AWS_REGION)

    # Truncate to keep costs minimal (~3000 chars ≈ 750 tokens)
    truncated = text[:3000].strip()

    prompt = (
        f'Blog post title: "{title}"\n\n'
        f"Content:\n{truncated}\n\n"
        "Write a single sentence (max 25 words) summarizing the key insight of this post. "
        "Be direct and specific. No filler phrases like 'This post explores'."
    )

    response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL,
        body=json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 80,
            "messages": [{"role": "user", "content": prompt}],
        }),
    )

    result = json.loads(response["body"].read())
    return result["content"][0]["text"].strip()


def resolve_max_posts(event):
    if isinstance(event, dict):
        override = event.get("max_posts")
        if override is not None:
            try:
                return max(1, int(override))
            except Exception:
                print(f"Ignoring invalid max_posts override: {override}")
    return MAX_POSTS


def parse_feed(xml_bytes, max_posts):
    root    = ET.fromstring(xml_bytes)
    channel = root.find("channel")
    items   = channel.findall("item") if channel is not None else []
    posts   = []
    tag_counts = {}

    for item in items:
        for category in item.findall("category"):
            tag = category.text
            if tag:
                tag_counts[tag] = tag_counts.get(tag, 0) + 1

    top_tags = [
        {"tag": tag, "count": count}
        for tag, count in sorted(tag_counts.items(), key=lambda entry: (-entry[1], entry[0]))[:5]
    ]

    for item in items[:max_posts]:
        title   = (item.findtext("title") or "").strip()
        link    = (item.findtext("link")  or "").strip()
        pub_raw = (item.findtext("pubDate") or "").strip()

        try:
            published = datetime.strptime(pub_raw, "%a, %d %b %Y %H:%M:%S %Z").strftime("%b %d, %Y")
        except Exception:
            published = pub_raw

        tags = [c.text for c in item.findall("category") if c.text][:3]

        content_el   = item.find(f"{{{NS['content']}}}encoded")
        content_html = content_el.text if content_el is not None else ""
        reading_time = estimate_reading_time(content_html)
        plain_text   = strip_html(content_html)
        thumbnail    = extract_thumbnail(item)

        # Generate summary
        try:
            summary = summarize(title, plain_text)
        except Exception as e:
            print(f"Bedrock summarization failed for '{title}': {e}")
            summary = ""

        posts.append({
            "title":        title,
            "url":          link,
            "published":    published,
            "tags":         tags,
            "reading_time": reading_time,
            "thumbnail":    thumbnail,
            "summary":      summary,
        })

    return {
        "posts":       posts,
        "total_posts": len(items),
        "top_tags":    top_tags,
    }


def handler(event, context):
    req = urllib.request.Request(
        MEDIUM_FEED_URL,
        headers={"User-Agent": "Mozilla/5.0 (compatible; ResumeSiteBot/1.0)"},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        xml_bytes = resp.read()

    max_posts = resolve_max_posts(event)
    feed = parse_feed(xml_bytes, max_posts)

    payload = {
        "updated":     datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "posts":       feed["posts"],
        "total_posts": feed["total_posts"],
        "top_tags":    feed["top_tags"],
    }

    s3 = boto3.client("s3")
    s3.put_object(
        Bucket=S3_BUCKET,
        Key="posts.json",
        Body=json.dumps(payload, ensure_ascii=False, indent=2),
        ContentType="application/json",
        CacheControl="no-cache, no-store, must-revalidate",
    )

    print(f"Wrote {len(feed['posts'])} posts to s3://{S3_BUCKET}/posts.json")
    return {"statusCode": 200, "posts_written": len(feed["posts"])}
