# GitHub PAT stored in Secrets Manager
# After terraform apply, populate the secret manually:
#   aws secretsmanager put-secret-value \
#     --secret-id <secret_arn> \
#     --secret-string '{"pat":"ghp_..."}' \
#     --profile resume-deployer
resource "aws_secretsmanager_secret" "github_pat" {
  name        = "resume/github-pat"
  description = "GitHub Personal Access Token for resume-github-fetcher Lambda"

  lifecycle {
    ignore_changes = [name]
  }
}

# Lambda package
data "archive_file" "github_fetcher" {
  type        = "zip"
  source_file = "${path.module}/lambda/github_fetcher.py"
  output_path = "${path.module}/lambda/github_fetcher.zip"
}

# IAM role
resource "aws_iam_role" "lambda_github_fetcher" {
  name = "resume-github-fetcher-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_github_fetcher" {
  name = "resume-github-fetcher-lambda-policy"
  role = aws_iam_role.lambda_github_fetcher.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3Write"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.website.arn}/repos.json"
      },
      {
        Sid      = "SecretsManager"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.github_pat.arn
      },
      {
        Sid      = "Bedrock"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "github_fetcher" {
  name              = "/aws/lambda/resume-github-fetcher"
  retention_in_days = 14
}

resource "aws_lambda_function" "github_fetcher" {
  function_name    = "resume-github-fetcher"
  filename         = data.archive_file.github_fetcher.output_path
  source_code_hash = data.archive_file.github_fetcher.output_base64sha256
  role             = aws_iam_role.lambda_github_fetcher.arn
  handler          = "github_fetcher.handler"
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      S3_BUCKET            = aws_s3_bucket.website.bucket
      GITHUB_PAT_SECRET_ARN = aws_secretsmanager_secret.github_pat.arn
      GITHUB_USER          = "sharmaabhineet"
      MAX_REPOS            = "6"
      BEDROCK_MODEL        = "anthropic.claude-3-haiku-20240307-v1:0"
    }
  }

  depends_on = [aws_cloudwatch_log_group.github_fetcher]
}

# EventBridge — every Monday at 09:30 UTC (30 min after medium fetcher)
resource "aws_cloudwatch_event_rule" "github_fetcher_weekly" {
  name                = "resume-github-fetcher-weekly"
  description         = "Fetch GitHub repos and activity weekly"
  schedule_expression = "cron(30 9 ? * MON *)"
}

resource "aws_cloudwatch_event_target" "github_fetcher" {
  rule      = aws_cloudwatch_event_rule.github_fetcher_weekly.name
  target_id = "GithubFetcher"
  arn       = aws_lambda_function.github_fetcher.arn
}

resource "aws_lambda_permission" "github_fetcher_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.github_fetcher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.github_fetcher_weekly.arn
}

output "github_pat_secret_arn" {
  description = "Secrets Manager ARN — populate with: aws secretsmanager put-secret-value --secret-id <arn> --secret-string '{\"pat\":\"ghp_...\"}'"
  value       = aws_secretsmanager_secret.github_pat.arn
}
