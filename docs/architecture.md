# Resume Cloud Challenge — Architecture & Project Documentation

> Personal resume website for Abhineet Sharma, built as part of the
> [Cloud Resume Challenge](https://cloudresumechallenge.dev/).
> Designed by Claude · Built on AWS · Managed with Terraform

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Infrastructure](#3-infrastructure)
4. [IAM & Security](#4-iam--security)
5. [Visitor Counter](#5-visitor-counter)
6. [Medium Blog Fetcher](#6-medium-blog-fetcher)
7. [Website Design](#7-website-design)
8. [SEO & Analytics](#8-seo--analytics)
9. [Cost](#9-cost)
10. [Operations Runbook](#10-operations-runbook)
11. [Repository Structure](#11-repository-structure)

---

## 1. Project Overview

A fully cloud-hosted resume website that demonstrates real-world AWS skills:

- Static site hosted on **S3**, served via **CloudFront** with HTTPS
- Custom domain (`resume.sharmaabhineet.com`) via **Route53** and **ACM**
- Serverless **visitor counter** (Lambda + API Gateway + DynamoDB)
- Weekly **Medium blog post fetcher** with AI-generated summaries (Lambda + EventBridge + Bedrock)
- **Google Analytics** (GA4) for real-world traffic insights
- All infrastructure managed as code with **Terraform**
- Least-privilege IAM via **AWS IAM Identity Center** (SSO Permission Set)

---

## 2. Architecture

```
                          ┌─────────────────────────────────────┐
                          │           resume.sharmaabhineet.com  │
                          │              (Route53 A record)       │
                          └──────────────────┬──────────────────┘
                                             │
                          ┌──────────────────▼──────────────────┐
                          │         CloudFront Distribution       │
                          │   TLS 1.2 · CachingOptimized policy  │
                          │   ACM wildcard cert (*.sharmaabhineet)│
                          └──────┬──────────────────┬───────────┘
                                 │                  │
               ┌─────────────────▼──┐          ┌───▼─────────────────┐
               │   S3 Bucket         │          │  API Gateway (HTTP)  │
               │   com.sharmaabhineet│          │  GET /count          │
               │   - index.html      │          └───────────┬─────────┘
               │   - css/            │                      │
               │   - scripts/        │          ┌───────────▼─────────┐
               │   - images/         │          │  Lambda              │
               │   - posts.json      │          │  visitor_counter.py  │
               │   - sitemap.xml     │          └───────────┬─────────┘
               │   - robots.txt      │                      │
               └─────────────────────┘          ┌───────────▼─────────┐
                                                 │  DynamoDB            │
                                                 │  resume-visitor-     │
                                                 │  counter             │
                                                 └─────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │  EventBridge (cron: every Monday 09:00 UTC)                      │
  └──────────────────────────┬──────────────────────────────────────┘
                             │
               ┌─────────────▼──────────────┐
               │  Lambda                     │
               │  medium_fetcher.py          │
               │  - Fetch Medium RSS feed    │
               │  - Strip HTML               │
               │  - Summarize via Bedrock    │
               │    (Claude 3 Haiku)         │
               │  - Write posts.json → S3    │
               └─────────────────────────────┘
```

---

## 3. Infrastructure

All resources are managed by Terraform (local state). Provider versions are pinned in `.terraform.lock.hcl`.

### Providers

| Provider | Version | Purpose |
|---|---|---|
| `hashicorp/aws` | ~> 5.0 | All AWS resources |
| `hashicorp/archive` | ~> 2.0 | Zip Lambda deployment packages |
| `hashicorp/local` | ~> 2.0 | Write `scripts/config.js` with API URL post-apply |

### Terraform Files

| File | Resources |
|---|---|
| `providers.tf` | Provider configuration, AWS profile (`resume-deployer`) |
| `variables.tf` | `domain_name`, `bucket_name`, `region`, `subdomain` |
| `s3-bucket.tf` | `aws_s3_bucket` |
| `s3-bucket-policy.tf` | Ownership controls, public access block, bucket policy |
| `s3-website.tf` | Static website configuration |
| `s3-versioning.tf` | Bucket versioning |
| `s3-cors.tf` | CORS configuration |
| `s3-object-upload.tf` | All website assets (HTML, CSS, JS, images, fonts, sitemap, robots.txt) |
| `acm.tf` | ACM wildcard certificate, DNS validation records, certificate validation |
| `cloudfront.tf` | CloudFront distribution |
| `route53.tf` | Hosted zone, A alias record → CloudFront |
| `dynamodb.tf` | Visitor counter table (`PAY_PER_REQUEST`) |
| `lambda.tf` | Visitor counter Lambda, IAM role, CloudWatch log group |
| `apigateway.tf` | HTTP API Gateway, stage, integration, route, Lambda permission, `local_file` for config.js |
| `medium-fetcher.tf` | Medium fetcher Lambda, IAM role, EventBridge rule + target, Lambda permission |
| `outputs.tf` | Website URL, CloudFront domain/ID, bucket name, Route53 zone/NS, visitor counter API URL |

### S3 Bucket Configuration

| Setting | Value |
|---|---|
| Object ownership | `BucketOwnerEnforced` (ACLs disabled) |
| Block public ACLs | `true` |
| Block public policy | `false` |
| Restrict public buckets | `false` |
| Versioning | Enabled |
| Website hosting | `index.html` / `images/404.jpg` |
| Bucket policy | `s3:GetObject` allow for `Principal: *` |

### CloudFront Distribution

| Setting | Value |
|---|---|
| Origin | S3 website endpoint (HTTP custom origin) |
| Protocol policy | `redirect-to-https` |
| Minimum TLS | `TLSv1.2_2021` |
| Cache policy | AWS managed `CachingOptimized` |
| IPv6 | Enabled |
| Price class | `PriceClass_All` |
| Aliases | `resume.sharmaabhineet.com` |

### ACM Certificate

- Wildcard cert: `*.sharmaabhineet.com`
- Validation: DNS (CNAME record in Route53)
- Region: `us-east-1` (required for CloudFront)

---

## 4. IAM & Security

### AWS Profile

```ini
# ~/.aws/config
[profile resume-deployer]
sso_session    = <your-sso-session-name>
sso_account_id = <your-aws-account-id>
sso_role_name  = ResumeDeployer
```

### IAM Identity Center — ResumeDeployer Permission Set

Least-privilege inline policy defined in `iam-permission-set-policy.json`.

| Statement | Actions | Resource |
|---|---|---|
| `S3BucketManagement` | Bucket-level S3 operations | `arn:aws:s3:::*` |
| `S3ObjectManagement` | Object-level S3 operations | `arn:aws:s3:::*/*` |
| `Route53Management` | Hosted zones, record sets | `*` |
| `CloudFrontManagement` | Distributions, OAC, invalidations | `*` |
| `ACMManagement` | Certificates | `*` |
| `DynamoDBManagement` | Table lifecycle operations | `*` |
| `LambdaManagement` | Function lifecycle + invoke | `*` |
| `APIGatewayManagement` | HTTP API CRUD | `*` |
| `IAMRoleManagement` | Role lifecycle (no PassRole) | `arn:aws:iam::*:role/resume-*` |
| `IAMPassRoleLambdaOnly` | `iam:PassRole` to Lambda only | `arn:aws:iam::*:role/resume-*` + `iam:PassedToService: lambda.amazonaws.com` |
| `CloudWatchLogsManagement` | Log groups, retention | `*` |
| `EventBridgeManagement` | Rules and targets | `*` |

> `iam:PassRole` is scoped to `resume-*` prefixed roles and restricted to the Lambda service via condition — mitigates privilege escalation risk.

---

## 5. Visitor Counter

### Flow

```
Page load → fetch(COUNTER_API_URL) → API Gateway → Lambda → DynamoDB (ADD 1) → return count → display badge
```

### Components

| Component | Name |
|---|---|
| Lambda | `resume-visitor-counter` (Python 3.12) |
| DynamoDB table | `resume-visitor-counter` |
| API Gateway | HTTP API, `GET /count` |
| CORS | Allowed origin: `https://resume.sharmaabhineet.com` |
| Log group | `/aws/lambda/resume-visitor-counter` (14-day retention) |

### How it works

- DynamoDB uses an atomic `ADD` expression on a single item (`id: "visitors"`) — no race conditions
- API Gateway returns the new count as JSON: `{"count": 1234}`
- `scripts/config.js` (generated by Terraform `local_file`, gitignored) sets `window.COUNTER_API_URL`
- The page displays the count as a "Page Views" stat badge in the About section
- Fails silently if the API is unreachable (local dev, before first deploy)

---

## 6. Medium Blog Fetcher

### Flow

```
EventBridge (weekly) → Lambda → Medium RSS feed → strip HTML → Bedrock (Claude Haiku summary)
                                                                        ↓
                                                          posts.json written to S3
                                                                        ↓
                                                       Page fetches /posts.json → renders Writing section
```

### Components

| Component | Name / Value |
|---|---|
| Lambda | `resume-medium-fetcher` (Python 3.12, 60s timeout) |
| Schedule | Every Monday at 09:00 UTC (`cron(0 9 ? * MON *)`) |
| Medium feed | `https://medium.com/feed/@sharmaabhineet` |
| Max posts | `5` (configurable via `MAX_POSTS` env var) |
| Bedrock model | `anthropic.claude-3-haiku-20240307-v1:0` |
| Output | `posts.json` in S3 website bucket |
| Log group | `/aws/lambda/resume-medium-fetcher` (14-day retention) |

### posts.json schema

```json
{
  "updated": "2026-03-06T12:00:00Z",
  "posts": [
    {
      "title":        "Post title",
      "url":          "https://medium.com/@sharmaabhineet/...",
      "published":    "Mar 06, 2026",
      "tags":         ["aws", "java", "engineering"],
      "reading_time": 4,
      "thumbnail":    null,
      "summary":      "One-sentence AI-generated summary."
    }
  ]
}
```

### AI Summary

- Post content HTML is stripped to plain text and truncated to ~3,000 characters
- Sent to Claude 3 Haiku via AWS Bedrock with a prompt requesting a max 25-word summary
- Stored in `posts.json` — generated once per Lambda run, not on page load
- Cost: ~$0.12/year at weekly cadence
- Attribution shown on each post card: "Summary by Claude Haiku · AWS Bedrock"

### Manual Invocation

```bash
./fetch-posts.sh
```

---

## 7. Website Design

### Stack

- **Bootstrap 5** — grid, navbar collapse, tooltips
- **AOS** (Animate On Scroll) — fade-in animations
- **Font Awesome 6** — icons
- **Google Fonts** — Poppins (headings), Roboto (body)

### Design System (`css/main.css`)

| Token | Value |
|---|---|
| `--primary` | `#0f172a` (dark navy) |
| `--accent` | `#6366f1` (indigo) |
| `--accent-light` | `#818cf8` |
| `--accent-pale` | `#eef2ff` |
| `--text` | `#1e293b` |
| `--text-muted` | `#64748b` |
| `--bg` | `#f1f5f9` |

### Sections

| Section | Content |
|---|---|
| **Nav** | Sticky dark navbar, mobile collapse, Download CV CTA |
| **Hero** | Photo, name, tagline, CTA buttons, social links |
| **About** | Professional summary, stat badges (years exp, cloud exp, companies, degree, page views) |
| **Skills** | Expert / Strong / Working Knowledge / Practices / Infrastructure chip groups |
| **Experience** | Horizontal career timeline (2008 → present) + detailed timeline cards |
| **Writing** | Medium post cards (title, date, reading time, tags, AI summary) |
| **Education** | MS (Iowa State, GPA 3.82) + BS (Thapar, 7.96/10), projects, thesis card |
| **Research** | ISU Agronomy Department Raspberry Pi project |
| **Certifications** | Two Sun Java certifications |
| **Footer** | Social links, "Designed by Claude · Built on AWS" |

### Dynamic JS

- `calculateAgeWithBreak()` — overall experience accounting for MS break (Jul 2014 – Jun 2016)
- `yearsFrom()` — cloud experience from Sep 2017
- `durationStr()` — current role tenure in "X yrs Y mos" format
- Visitor counter fetch with stat badge display
- Medium posts fetch with graceful fallback

---

## 8. SEO & Analytics

### SEO (`index.html` head)

| Tag | Value |
|---|---|
| `<title>` | `Abhineet Sharma — Staff Engineer` |
| `<meta description>` | Professional summary |
| `<link rel="canonical">` | `https://resume.sharmaabhineet.com/` |
| Open Graph | `og:type=profile`, title, description, image |
| Twitter Card | `summary` card with title, description, image |
| JSON-LD | `Person` schema — name, jobTitle, worksFor, alumniOf, sameAs, knowsAbout |

### Sitemap & Robots

- `sitemap.xml` — single URL, `changefreq: monthly`, `priority: 1.0`
- `robots.txt` — `Allow: /`, points to sitemap

### Analytics

- **Google Analytics GA4** — Measurement ID: `G-M8BLYHHLC2`
- Loaded via `<script async>` in `<head>`, non-blocking

### Google Search Console

- Add property: `https://resume.sharmaabhineet.com`
- Submit `sitemap.xml`
- Request indexing via URL Inspection tool

---

## 9. Cost

| Resource | Baseline/month | Usage-based |
|---|---|---|
| Route53 hosted zone | **$0.50** | + $0.40/1M DNS queries |
| CloudFront | $0 | $0.085/GB transfer, $0.01/10k HTTPS requests |
| S3 | $0 | $0.023/GB storage |
| API Gateway | $0 | $1.00/1M requests |
| Lambda (visitor counter) | $0 | Free tier: 1M requests/month |
| DynamoDB | $0 | Free tier: 200M requests/month |
| Lambda (medium fetcher) | $0 | Negligible (weekly runs) |
| Bedrock (Claude Haiku) | $0 | ~$0.12/year at weekly cadence |
| CloudWatch Logs | $0 | $0.50/GB ingested |
| **Total baseline** | **$0.50/month** | |

---

## 10. Operations Runbook

### Deploy changes

```bash
terraform apply -auto-approve
aws cloudfront create-invalidation \
  --distribution-id E253DNUVI33C1O \
  --paths "/*" \
  --profile resume-deployer
```

### Fetch Medium posts manually

```bash
./fetch-posts.sh
```

### Local development

```bash
# Terminal 1 — website
python3 -m http.server 8080

# Terminal 2 — mock visitor counter API (optional)
python3 mock-counter-server.py
```

Create `scripts/config.js` pointing to the mock:
```js
window.COUNTER_API_URL = 'http://localhost:3001/count';
```

> Remember to delete `scripts/config.js` before running `terraform apply` — Terraform will regenerate it with the real API URL.

### SSO login (if token expired)

```bash
aws sso login --profile resume-deployer
```

### Invalidate CloudFront cache

```bash
aws cloudfront create-invalidation \
  --distribution-id E253DNUVI33C1O \
  --paths "/*" \
  --profile resume-deployer
```

### Rotate GitHub PAT (every 90 days)

The GitHub Personal Access Token used by the `resume-github-fetcher` Lambda expires every 90 days. When it does, the Lambda will fail with an authentication error and `repos.json` will stop updating.

**Steps to rotate:**

1. **Generate a new PAT on GitHub**
   - Go to: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Click **Generate new token (classic)**
   - Name: `resume-github-fetcher` (or append the date)
   - Expiration: 90 days
   - Scopes: `repo` + `read:user`
   - Copy the new token immediately

2. **Update the secret in AWS Secrets Manager**
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id arn:aws:secretsmanager:us-east-1:<your-aws-account-id>:secret:resume/github-pat-<suffix> \
     --secret-string '{"pat":"ghp_YOUR_NEW_TOKEN_HERE"}' \
     --profile resume-deployer
   ```

3. **Verify by invoking the Lambda manually**
   ```bash
   ./fetch-repos.sh
   ```
   Check the logs — it should show `Wrote repos.json — N repos` without any authentication errors.

> **Tip:** Set a calendar reminder ~85 days from when you create each token so you rotate it before it expires.

---

## 11. Repository Structure

```
resume-cloud-challenge/
├── docs/
│   └── architecture.md          # This document
│
├── lambda/
│   ├── visitor_counter.py        # Visitor counter Lambda (Python 3.12)
│   └── medium_fetcher.py         # Medium RSS + Bedrock summarizer (Python 3.12)
│
├── css/
│   ├── main.css                  # Custom design system
│   ├── bootstrap.min.css
│   ├── aos.css
│   └── font-awesome/
│
├── scripts/
│   ├── bootstrap.bundle.min.js
│   ├── aos.js
│   ├── main.js
│   └── config.js                 # Generated by Terraform (gitignored)
│
├── images/
│   ├── Avatar.png
│   └── 404.jpg
│
├── files/
│   └── abhineet-resume.pdf
│
├── index.html                    # Resume website
├── sitemap.xml                   # SEO sitemap
├── robots.txt                    # Crawler permissions
├── favicon.ico
│
├── providers.tf                  # Terraform providers (aws, archive, local)
├── variables.tf                  # Input variables
├── terraform.tfvars              # Values (gitignored)
├── terraform.tfvars.example      # Template for tfvars
├── outputs.tf                    # Output values
│
├── s3-bucket.tf                  # S3 bucket
├── s3-bucket-policy.tf           # Ownership, public access, bucket policy
├── s3-website.tf                 # Static website configuration
├── s3-versioning.tf              # Versioning
├── s3-cors.tf                    # CORS
├── s3-object-upload.tf           # All asset uploads
│
├── acm.tf                        # ACM certificate + DNS validation
├── cloudfront.tf                 # CloudFront distribution
├── route53.tf                    # Hosted zone + A record
│
├── dynamodb.tf                   # Visitor counter table
├── lambda.tf                     # Visitor counter Lambda + IAM
├── apigateway.tf                 # HTTP API Gateway + local_file config
│
├── medium-fetcher.tf             # Medium fetcher Lambda + IAM + EventBridge
├── fetch-posts.sh                # Manual Lambda invocation script
├── mock-counter-server.py        # Local dev mock API (gitignored)
│
├── iam-permission-set-policy.json  # ResumeDeployer least-privilege policy
│
├── .gitignore
└── .terraform.lock.hcl
```
