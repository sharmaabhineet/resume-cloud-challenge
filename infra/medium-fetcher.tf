data "archive_file" "medium_fetcher" {
  type        = "zip"
  source_file = "${path.module}/lambda/medium_fetcher.py"
  output_path = "${path.module}/lambda/medium_fetcher.zip"
}

resource "aws_iam_role" "lambda_medium_fetcher" {
  name = "resume-medium-fetcher-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_medium_fetcher" {
  name = "resume-medium-fetcher-lambda-policy"
  role = aws_iam_role.lambda_medium_fetcher.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3Write"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.website.arn}/posts.json"
      },
      {
        Sid      = "Bedrock"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
      },
      {
        Sid      = "BedrockMarketplace"
        Effect   = "Allow"
        Action   = ["aws-marketplace:ViewSubscriptions", "aws-marketplace:Subscribe"]
        Resource = "*"
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "medium_fetcher" {
  name              = "/aws/lambda/resume-medium-fetcher"
  retention_in_days = 14
}

resource "aws_lambda_function" "medium_fetcher" {
  function_name    = "resume-medium-fetcher"
  filename         = data.archive_file.medium_fetcher.output_path
  source_code_hash = data.archive_file.medium_fetcher.output_base64sha256
  role             = aws_iam_role.lambda_medium_fetcher.arn
  handler          = "medium_fetcher.handler"
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      S3_BUCKET       = aws_s3_bucket.website.bucket
      MEDIUM_FEED_URL = "https://medium.com/feed/@sharmaabhineet"
      MAX_POSTS       = "6"
      BEDROCK_MODEL   = "anthropic.claude-3-haiku-20240307-v1:0"
    }
  }

  depends_on = [aws_cloudwatch_log_group.medium_fetcher]
}

# EventBridge — every Monday at 09:00 UTC
resource "aws_cloudwatch_event_rule" "medium_fetcher_weekly" {
  name                = "resume-medium-fetcher-weekly"
  description         = "Fetch latest Medium posts weekly"
  schedule_expression = "cron(0 9 ? * MON *)"
}

resource "aws_cloudwatch_event_target" "medium_fetcher" {
  rule      = aws_cloudwatch_event_rule.medium_fetcher_weekly.name
  target_id = "MediumFetcher"
  arn       = aws_lambda_function.medium_fetcher.arn
}

resource "aws_lambda_permission" "medium_fetcher_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.medium_fetcher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.medium_fetcher_weekly.arn
}
