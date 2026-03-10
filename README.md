# Cloud Resume Challenge

Personal portfolio website built as part of the [Cloud Resume Challenge](https://cloudresumechallenge.dev/), hosted on AWS at [portfolio.sharmaabhineet.com](https://portfolio.sharmaabhineet.com).

---

## Features

- **Static site** hosted on S3, served via CloudFront with HTTPS and custom domain
- **Visitor counter** — serverless hit counter (Lambda + API Gateway + DynamoDB)
- **Contact form** — spam-protected email delivery via SES
- **Medium blog fetcher** — weekly Lambda pulls latest posts with AI-generated summaries (Bedrock)
- **GitHub repo fetcher** — weekly Lambda pulls pinned repos with AI activity summary (Bedrock)
- **301 redirect** — `resume.sharmaabhineet.com` → `portfolio.sharmaabhineet.com` via CloudFront Function
- **CI/CD** — GitHub Actions deploys on every push to `master` (OIDC, Terraform apply, cache invalidation)
- **Security scanning** — Checkov runs on every deploy with documented skip justifications

## Tech Stack

| Layer | Technology |
|---|---|
| Hosting | AWS S3 + CloudFront |
| DNS & TLS | Route53 + ACM wildcard cert |
| Serverless | AWS Lambda (Python 3.12) |
| API | AWS API Gateway (HTTP API v2) |
| Database | AWS DynamoDB |
| Email | AWS SES |
| AI Summaries | AWS Bedrock (Claude 3 Haiku) |
| Secrets | AWS Secrets Manager |
| Scheduling | AWS EventBridge cron |
| IaC | Terraform (local state) |
| CI/CD | GitHub Actions (OIDC) |
| IAM | AWS IAM Identity Center (SSO) |

## Architecture

```
resume.sharmaabhineet.com          portfolio.sharmaabhineet.com
        │ (301 redirect)                       │
  CloudFront Function              CloudFront (TLS 1.2)
                                          │
                              S3 Bucket ──┤── API Gateway
                              (static)    │   GET  /count  → Lambda → DynamoDB
                                          └── POST /contact → Lambda → SES

EventBridge (weekly)
  ├── medium_fetcher  → Medium RSS → Bedrock → posts.json → S3
  └── github_fetcher  → GitHub API → Bedrock → repos.json → S3
```

## Documentation

Full architecture and operations docs are in [`docs/architecture.md`](docs/architecture.md):

| Section | Description |
|---|---|
| [Project Overview](docs/architecture.md#1-project-overview) | Features and goals |
| [Architecture](docs/architecture.md#2-architecture) | Full system diagram |
| [Infrastructure](docs/architecture.md#3-infrastructure) | Terraform files, S3, CloudFront config |
| [IAM & Security](docs/architecture.md#4-iam--security) | SSO permission set, least-privilege policy |
| [Visitor Counter](docs/architecture.md#5-visitor-counter) | Lambda + DynamoDB flow |
| [Medium Blog Fetcher](docs/architecture.md#6-medium-blog-fetcher) | RSS + Bedrock AI summaries |
| [GitHub Repo Fetcher](docs/architecture.md#7-github-repo-fetcher) | GraphQL + Bedrock + PAT rotation |
| [Contact Form](docs/architecture.md#8-contact-form) | SES + honeypot spam protection |
| [Website Design](docs/architecture.md#9-website-design) | Stack, design tokens, sections |
| [SEO & Analytics](docs/architecture.md#10-seo--analytics) | Canonical URL, GA4, sitemap |
| [Cost](docs/architecture.md#11-cost) | ~$0.90/month baseline breakdown |
| [Operations Runbook](docs/architecture.md#12-operations-runbook) | Deploy, invalidate, rotate PAT, local dev |
| [Repository Structure](docs/architecture.md#13-repository-structure) | File tree with descriptions |
