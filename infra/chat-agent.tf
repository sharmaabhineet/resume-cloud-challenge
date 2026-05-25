# ============================================================
# Portfolio Chat Agent
# - Claude Haiku 4.5 via Bedrock Converse API
# - DynamoDB: per-IP rate limiting + daily/monthly token caps
# - SNS: cap breach alerts (daily + monthly, first breach only)
# - SES: transcript email after every chat turn
# - API key validated via Secrets Manager (value surfaced in config.js)
# ============================================================

# --- API key (generated once, stored in Secrets Manager + surfaced in config.js) ---
resource "random_password" "chat_api_key" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "chat_api_key" {
  name        = "resume/chat-api-key"
  description = "Portfolio chat agent API key — written to config.js by Terraform"

  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_secretsmanager_secret_version" "chat_api_key" {
  secret_id     = aws_secretsmanager_secret.chat_api_key.id
  secret_string = jsonencode({ key = random_password.chat_api_key.result })
}

# --- DynamoDB table (rate limiting + token cap counters) ---
resource "aws_dynamodb_table" "chat_limits" {
  name         = "resume-chat-limits"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Project = "resume-cloud-challenge"
  }
}

# --- SNS topic + email subscription for cap breach alerts ---
resource "aws_sns_topic" "chat_alerts" {
  name = "resume-chat-alerts"
}

resource "aws_sns_topic_subscription" "chat_alerts_email" {
  topic_arn = aws_sns_topic.chat_alerts.arn
  protocol  = "email"
  endpoint  = var.to_email
}

# --- Lambda package ---
data "archive_file" "chat_agent" {
  type        = "zip"
  source_file = "${path.module}/lambda/chat_agent.py"
  output_path = "${path.module}/lambda/chat_agent.zip"
}

# --- IAM role ---
resource "aws_iam_role" "lambda_chat_agent" {
  name = "resume-chat-agent-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_chat_agent" {
  name = "resume-chat-agent-lambda-policy"
  role = aws_iam_role.lambda_chat_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoDB"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.chat_limits.arn
      },
      {
        Sid    = "S3Read"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "${aws_s3_bucket.website.arn}/posts.json",
          "${aws_s3_bucket.website.arn}/repos.json",
        ]
      },
      {
        Sid      = "SecretsManager"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.chat_api_key.arn
      },
      {
        Sid    = "Bedrock"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku*",
          "arn:aws:bedrock:*:*:inference-profile/us.anthropic.claude-haiku*",
        ]
      },
      {
        Sid      = "SNS"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.chat_alerts.arn
      },
      {
        Sid      = "SES"
        Effect   = "Allow"
        Action   = ["ses:SendEmail"]
        Resource = "*"
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

# --- CloudWatch log group ---
resource "aws_cloudwatch_log_group" "chat_agent" {
  name              = "/aws/lambda/resume-chat-agent"
  retention_in_days = 14
}

# --- Lambda function ---
resource "aws_lambda_function" "chat_agent" {
  function_name    = "resume-chat-agent"
  filename         = data.archive_file.chat_agent.output_path
  source_code_hash = data.archive_file.chat_agent.output_base64sha256
  role             = aws_iam_role.lambda_chat_agent.arn
  handler          = "chat_agent.handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      DYNAMODB_TABLE     = aws_dynamodb_table.chat_limits.name
      API_KEY_SECRET_ARN = aws_secretsmanager_secret.chat_api_key.arn
      SNS_TOPIC_ARN      = aws_sns_topic.chat_alerts.arn
      BEDROCK_MODEL      = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
      FROM_EMAIL         = "noreply@${var.domain_name}"
      TO_EMAIL           = var.to_email
      ALLOWED_ORIGIN     = "https://${var.subdomain}.${var.domain_name}"
      S3_BUCKET          = aws_s3_bucket.website.bucket
    }
  }

  depends_on = [aws_cloudwatch_log_group.chat_agent]
}

# --- API Gateway integration (POST /chat on existing API) ---
resource "aws_apigatewayv2_integration" "chat_agent" {
  api_id                 = aws_apigatewayv2_api.visitor_counter.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.chat_agent.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "chat_agent" {
  api_id    = aws_apigatewayv2_api.visitor_counter.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.chat_agent.id}"
}

resource "aws_apigatewayv2_route" "chat_token" {
  api_id    = aws_apigatewayv2_api.visitor_counter.id
  route_key = "GET /chat-token"
  target    = "integrations/${aws_apigatewayv2_integration.chat_agent.id}"
}

resource "aws_lambda_permission" "chat_agent" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat_agent.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.visitor_counter.execution_arn}/*/*"
}

# --- CloudWatch alarm: Lambda error rate ---
resource "aws_cloudwatch_metric_alarm" "chat_agent_errors" {
  alarm_name          = "resume-chat-agent-errors"
  alarm_description   = "Chat agent Lambda error rate exceeded threshold"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.chat_agent.function_name }
  statistic           = "Sum"
  period              = 300 # 5-minute window
  evaluation_periods  = 1
  threshold           = 5 # alert if >5 errors in any 5-minute window
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.chat_alerts.arn]
  ok_actions          = [aws_sns_topic.chat_alerts.arn]
}

# --- Outputs ---
output "chat_api_url" {
  description = "Chat agent API endpoint"
  value       = "${aws_apigatewayv2_stage.visitor_counter.invoke_url}/chat"
}

output "chat_alerts_topic_arn" {
  description = "SNS topic ARN for chat cap alerts — confirm the email subscription after first apply"
  value       = aws_sns_topic.chat_alerts.arn
}
