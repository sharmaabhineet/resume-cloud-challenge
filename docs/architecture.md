# Resume Cloud Challenge — Architecture & Project Documentation

> Personal resume website for Abhineet Sharma, built as part of the
> [Cloud Resume Challenge](https://cloudresumechallenge.dev/).
> Built on AWS · Managed with Terraform

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Infrastructure](#3-infrastructure)
4. [IAM & Security](#4-iam--security)
5. [Visitor Counter](#5-visitor-counter)
6. [Medium Blog Fetcher](#6-medium-blog-fetcher)
7. [GitHub Repo Fetcher](#7-github-repo-fetcher)
8. [Contact Form](#8-contact-form)
9. [Website Design](#9-website-design)
10. [SEO & Analytics](#10-seo--analytics)
11. [Cost](#11-cost)
12. [Operations Runbook](#12-operations-runbook)
13. [Repository Structure](#13-repository-structure)

---

## 1. Project Overview

A fully cloud-hosted portfolio website that demonstrates real-world AWS skills:

- Static site hosted on **S3**, served via **CloudFront** with HTTPS
- Custom domain (`portfolio.sharmaabhineet.com`) via **Route53** and **ACM**; `resume.sharmaabhineet.com` 301 redirects to `portfolio.`
- Serverless **visitor counter** (Lambda + API Gateway + DynamoDB)
- **Contact form** with spam protection (Lambda + API Gateway + SES)
- Weekly **Medium blog post fetcher** with AI-generated summaries (Lambda + EventBridge + Bedrock)
- Weekly **GitHub repo fetcher** with AI-generated activity summaries (Lambda + EventBridge + Secrets Manager + Bedrock)
- **Google Analytics** (GA4) for real-world traffic insights
- All infrastructure managed as code with **Terraform**
- Least-privilege IAM via **AWS IAM Identity Center** (SSO Permission Set)
- CI/CD via **GitHub Actions** (OIDC, Terraform apply, CloudFront invalidation)

---

## 2. Architecture

```
  resume.sharmaabhineet.com          portfolio.sharmaabhineet.com
  (Route53 A record)                 (Route53 A record)
          │                                   │
  ┌───────▼──────────────┐      ┌────────────▼────────────────┐
  │  CloudFront (redirect)│      │  CloudFront (portfolio)      │
  │  CloudFront Function  │      │  TLS 1.2 · CachingOptimized │
  │  → 301 to portfolio.  │      │  ACM wildcard cert           │
  └───────────────────────┘      └──────┬──────────┬───────────┘
                                        │          │
                          ┌─────────────▼──┐  ┌───▼──────────────────┐
                          │  S3 Bucket      │  │  API Gateway (HTTP)   │
                          │  com.sharmaabhi │  │  GET  /count          │
                          │  - index.html   │  │  POST /contact        │
                          │  - css/         │  └───┬──────────┬────────┘
                          │  - scripts/     │      │          │
                          │  - images/      │  ┌───▼───┐  ┌───▼────────┐
                          │  - posts.json   │  │Lambda │  │Lambda      │
                          │  - repos.json   │  │visitor│  │contact_    │
                          │  - sitemap.xml  │  │counter│  │handler.py  │
                          └─────────────────┘  └───┬───┘  └───┬────────┘
                                                   │          │
                                              ┌────▼────┐  ┌──▼──┐
                                              │DynamoDB │  │ SES │
                                              └─────────┘  └─────┘

  ┌──────────────────────────────────────────────────────────────────┐
  │  EventBridge cron — every Monday 09:00 UTC                        │
  └────────────────────┬─────────────────────┬────────────────────────┘
                       │                     │
           ┌───────────▼───────┐   ┌─────────▼──────────┐
           │  Lambda            │   │  Lambda             │
           │  medium_fetcher.py │   │  github_fetcher.py  │
           │  - Medium RSS feed │   │  - GitHub GraphQL   │
           │  - Bedrock summary │   │  - Bedrock summary  │
           │  - posts.json → S3 │   │  - repos.json → S3  │
           └────────────────────┘   └──────────┬──────────┘
                                               │
                                    ┌──────────▼──────────┐
                                    │  Secrets Manager     │
                                    │  GitHub PAT          │
                                    └─────────────────────┘
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
| `variables.tf` | `domain_name`, `bucket_name`, `region`, `subdomain`, `to_email` |
| `s3-bucket.tf` | `aws_s3_bucket` |
| `s3-bucket-policy.tf` | Ownership controls, public access block, bucket policy |
| `s3-website.tf` | Static website configuration |
| `s3-versioning.tf` | Bucket versioning |
| `s3-cors.tf` | CORS configuration |
| `s3-object-upload.tf` | All website assets (HTML, CSS, JS, images, fonts, sitemap, robots.txt) |
| `acm.tf` | ACM wildcard certificate, DNS validation records, certificate validation |
| `cloudfront.tf` | Portfolio CloudFront distribution + CloudFront Function + redirect distribution for `resume.` |
| `route53.tf` | Hosted zone, A alias records → both CloudFront distributions |
| `dynamodb.tf` | Visitor counter table (`PAY_PER_REQUEST`) |
| `lambda.tf` | Visitor counter Lambda, IAM role, CloudWatch log group |
| `apigateway.tf` | HTTP API Gateway, stage, throttling, integrations, routes, Lambda permissions, `local_file` for config.js |
| `medium-fetcher.tf` | Medium fetcher Lambda, IAM role, EventBridge rule + target, Lambda permission |
| `github-fetcher.tf` | GitHub fetcher Lambda, IAM role, Secrets Manager secret, EventBridge rule + target |
| `contact-form.tf` | Contact handler Lambda, SES domain + DKIM + MAIL FROM, IAM role, API Gateway integration |
| `github-actions.tf` | OIDC provider, GitHub Actions IAM role + policy |
| `outputs.tf` | Website URL, CloudFront domain/ID, bucket name, Route53 zone/NS, visitor counter API URL |
| `.checkov.yaml` | Checkov security scan — skip-list for rules not applicable to a personal static site |

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

### CloudFront Distributions

**Portfolio distribution** (`portfolio.sharmaabhineet.com`):

| Setting | Value |
|---|---|
| Origin | S3 website endpoint (HTTP custom origin) |
| Protocol policy | `redirect-to-https` |
| Minimum TLS | `TLSv1.2_2021` |
| Cache policy | AWS managed `CachingOptimized` |
| IPv6 | Enabled |
| Price class | `PriceClass_All` |
| Aliases | `portfolio.sharmaabhineet.com` |

**Redirect distribution** (`resume.sharmaabhineet.com`):

| Setting | Value |
|---|---|
| Aliases | `resume.sharmaabhineet.com` |
| CloudFront Function | `resume-to-portfolio-redirect` (viewer-request) |
| Behaviour | Returns HTTP 301 → `https://portfolio.sharmaabhineet.com` + original URI |
| Certificate | Same ACM wildcard `*.sharmaabhineet.com` |

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
| `CloudFrontManagement` | Distributions, OAC, invalidations, CloudFront Functions | `*` |
| `ACMManagement` | Certificates | `*` |
| `DynamoDBManagement` | Table lifecycle operations | `*` |
| `LambdaManagement` | Function lifecycle + invoke | `*` |
| `APIGatewayManagement` | HTTP API CRUD | `*` |
| `IAMRoleManagement` | Role lifecycle (no PassRole) | `arn:aws:iam::*:role/resume-*` |
| `IAMPassRoleLambdaOnly` | `iam:PassRole` to Lambda only | `arn:aws:iam::*:role/resume-*` + `iam:PassedToService: lambda.amazonaws.com` |
| `CloudWatchLogsManagement` | Log groups, retention | `*` |
| `EventBridgeManagement` | Rules and targets | `*` |
| `IAMOIDCManagement` | OIDC provider lifecycle (GitHub Actions) | `*` |
| `SecretsManagerManagement` | Secret lifecycle | `arn:aws:secretsmanager:*:*:secret:resume/*` |
| `SESManagement` | Domain identity, DKIM, send email | `*` |

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
| CORS | Allowed origin: `https://portfolio.sharmaabhineet.com` |
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
| Max posts | `6` (configurable via `MAX_POSTS` env var) |
| Bedrock model | `anthropic.claude-3-haiku-20240307-v1:0` |
| Output | `posts.json` in S3 website bucket |
| Log group | `/aws/lambda/resume-medium-fetcher` (14-day retention) |

### posts.json schema

```json
{
  "updated": "2026-03-06T12:00:00Z",
  "total_posts": 12,
  "top_tags": [
    { "tag": "aws", "count": 4 },
    { "tag": "java", "count": 3 }
  ],
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

## 7. GitHub Repo Fetcher

### Flow

```
EventBridge (weekly) → Lambda → GitHub GraphQL API (pinned repos) → fallback: REST (recent repos)
                                                                              ↓
                                                           Bedrock (Claude Haiku activity summary)
                                                                              ↓
                                                                repos.json written to S3
                                                                              ↓
                                                     Page fetches /repos.json → renders GitHub section
```

### Components

| Component | Name / Value |
|---|---|
| Lambda | `resume-github-fetcher` (Python 3.12, 60s timeout) |
| Schedule | Every Monday at 09:30 UTC (`cron(30 9 ? * MON *)`) |
| GitHub user | `sharmaabhineet` |
| Max repos | `6` (configurable via `MAX_REPOS` env var) |
| Repo source | Pinned repos (GraphQL) → fallback to recently pushed (REST) |
| PAT storage | AWS Secrets Manager — `resume/github-pat` |
| Bedrock model | `anthropic.claude-3-haiku-20240307-v1:0` |
| Output | `repos.json` in S3 website bucket |
| Log group | `/aws/lambda/resume-github-fetcher` (14-day retention) |

### repos.json schema

```json
{
  "generated_at": "2026-03-10T14:00:00Z",
  "source": "pinned",
  "repos": [
    {
      "name":        "resume-cloud-challenge",
      "description": "Cloud resume portfolio on AWS",
      "url":         "https://github.com/sharmaabhineet/resume-cloud-challenge",
      "private":     false,
      "language":    "HCL",
      "stars":       0,
      "forks":       0,
      "topics":      ["aws", "terraform", "serverless"],
      "updated_at":  "2026-03-10T00:00:00Z"
    }
  ],
  "activity": {
    "commits_30d":     12,
    "repos_active":    1,
    "active_repo_list": ["sharmaabhineet/resume-cloud-challenge"]
  },
  "ai_summary": "Active across cloud infrastructure and backend projects with recent commits in Terraform and Python."
}
```

### GitHub PAT

The Lambda uses a Personal Access Token stored in Secrets Manager. The PAT requires `repo` + `read:user` scopes and expires every 90 days. See [Rotate GitHub PAT](#rotate-github-pat-every-90-days) in the runbook.

---

## 8. Contact Form

### Flow

```
User submits form → POST /contact → API Gateway → Lambda → SES → email delivered to TO_EMAIL
```

### Components

| Component | Name / Value |
|---|---|
| Lambda | `resume-contact-handler` (Python 3.12, 15s timeout) |
| API route | `POST /contact` on the same HTTP API as visitor counter |
| From address | `noreply@sharmaabhineet.com` (SES verified domain) |
| To address | Configured via `var.to_email` (stored in `terraform.tfvars`, gitignored) |
| CORS | Allowed origin: `https://portfolio.sharmaabhineet.com` |
| Spam protection | Honeypot field + API Gateway throttling (10 req/s, burst 5) |
| Log group | `/aws/lambda/resume-contact-handler` (14-day retention) |

### SES Setup

- Domain identity: `sharmaabhineet.com` (verified via DKIM CNAME records in Route53)
- MAIL FROM domain: `mail.sharmaabhineet.com` (MX + SPF records in Route53)
- Outbound only — SES sandbox restrictions apply unless production access is requested

---

## 9. Website Design

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
| **GitHub** | Pinned repo cards (language, stars, forks, topics) + AI activity summary banner |
| **Education** | MS (Iowa State, GPA 3.82) + BS (Thapar, 7.96/10), thesis card |
| **Research** | ISU Agronomy Department Raspberry Pi project |
| **Certifications** | Two Sun Java certifications |
| **Contact** | Contact form (name, email, message) with honeypot spam protection |
| **Footer** | Social links, "Built on AWS" |

### Dynamic JS

- `calculateAgeWithBreak()` — overall experience accounting for MS break (Jul 2014 – Jun 2016)
- `yearsFrom()` — cloud experience from Sep 2017
- `durationStr()` — current role tenure in "X yrs Y mos" format
- Visitor counter fetch with stat badge display
- Medium posts fetch with graceful fallback
- GitHub repos fetch with repo cards and AI activity summary banner
- Contact form submission via `POST /contact` with honeypot field validation

---

## 10. SEO & Analytics

### SEO (`index.html` head)

| Tag | Value |
|---|---|
| `<title>` | `Abhineet Sharma — Staff Engineer` |
| `<meta description>` | Professional summary |
| `<link rel="canonical">` | `https://portfolio.sharmaabhineet.com/` |
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

- Add property: `https://portfolio.sharmaabhineet.com`
- Submit `sitemap.xml`
- Request indexing via URL Inspection tool

---

## 11. Cost

| Resource | Baseline/month | Usage-based |
|---|---|---|
| Route53 hosted zone | **$0.50** | + $0.40/1M DNS queries |
| CloudFront (portfolio) | $0 | $0.085/GB transfer, $0.01/10k HTTPS requests |
| CloudFront (redirect) | $0 | Minimal (redirects only) |
| S3 | $0 | $0.023/GB storage |
| API Gateway | $0 | $1.00/1M requests |
| Lambda (visitor counter) | $0 | Free tier: 1M requests/month |
| DynamoDB | $0 | Free tier: 200M requests/month |
| Lambda (medium fetcher) | $0 | Negligible (weekly runs) |
| Lambda (github fetcher) | $0 | Negligible (weekly runs) |
| Lambda (contact handler) | $0 | Negligible (on-demand) |
| Bedrock (Claude Haiku) | $0 | ~$0.12/year at weekly cadence |
| Secrets Manager (GitHub PAT) | **$0.40** | Per secret/month |
| CloudWatch Logs | $0 | $0.50/GB ingested |
| **Total baseline** | **$0.90/month** | |

---

## 12. Operations Runbook

### Deploy changes

CI/CD is handled automatically by GitHub Actions on every push to `master`. For manual deploys:

```bash
terraform apply -auto-approve
DIST_ID=$(terraform output -raw cloudfront_id)
aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths "/*" \
  --profile resume-deployer
```

### Fetch Medium posts manually

```bash
./fetch-posts.sh
```

### Fetch GitHub repos manually

```bash
./fetch-repos.sh
```

### Test contact form

```bash
curl -X POST https://api.sharmaabhineet.com/contact \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","email":"test@example.com","message":"Hello"}'
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
DIST_ID=$(terraform output -raw cloudfront_id)
aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
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

## 13. Repository Structure

```
resume-cloud-challenge/
├── docs/
│   └── architecture.md          # This document
│
├── lambda/
│   ├── visitor_counter.py        # Visitor counter Lambda (Python 3.12)
│   ├── medium_fetcher.py         # Medium RSS + Bedrock summarizer (Python 3.12)
│   ├── github_fetcher.py         # GitHub GraphQL + Bedrock summarizer (Python 3.12)
│   └── contact_handler.py        # Contact form handler + SES (Python 3.12)
│
├── .github/
│   └── workflows/
│       └── deploy.yml            # GitHub Actions CI/CD (OIDC, Terraform, invalidation)
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
│   ├── Avatar.jpg
│   ├── Avatar.png
│   └── 404.jpg
│
├── files/
│   └── abhineet-resume.pdf
│
├── index.html                    # Portfolio website
├── sitemap.xml                   # SEO sitemap
├── robots.txt                    # Crawler permissions
├── favicon.ico
│
├── providers.tf                  # Terraform providers (aws, archive, local)
├── variables.tf                  # Input variables (domain_name, bucket_name, region, subdomain, to_email)
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
├── cloudfront.tf                 # Portfolio + redirect CloudFront distributions, CloudFront Function
├── route53.tf                    # Hosted zone + A records (portfolio + resume redirect)
│
├── dynamodb.tf                   # Visitor counter table
├── lambda.tf                     # Visitor counter Lambda + IAM
├── apigateway.tf                 # HTTP API Gateway + local_file config
│
├── medium-fetcher.tf             # Medium fetcher Lambda + IAM + EventBridge
├── github-fetcher.tf             # GitHub fetcher Lambda + IAM + Secrets Manager + EventBridge
├── contact-form.tf               # Contact handler Lambda + SES + IAM + API Gateway integration
├── github-actions.tf             # OIDC provider + GitHub Actions IAM role + policy
│
├── fetch-posts.sh                # Manual medium-fetcher Lambda invocation script
├── fetch-repos.sh                # Manual github-fetcher Lambda invocation script
├── mock-counter-server.py        # Local dev mock API (gitignored)
│
├── iam-permission-set-policy.json  # ResumeDeployer least-privilege policy
├── .checkov.yaml                   # Checkov security scan skip-list with justifications
│
├── .gitignore
└── .terraform.lock.hcl
```
