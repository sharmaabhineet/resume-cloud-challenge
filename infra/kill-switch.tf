# ============================================================
# Cost Kill Switch
#
# Flow: AWS Budget threshold breached
#         → SNS topic (cost-kill-switch-trigger)
#           → this Lambda
#             → sets reserved concurrency = 0 on all at-risk Lambdas
#             → disables their EventBridge rules
#             → sends summary to notification SNS topic
#
# To RESTORE after activation:
#   For each Lambda: remove reserved concurrency (set to -1 via CLI or console)
#   For each rule:   re-enable in EventBridge console or via CLI
# ============================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  # All Lambdas the kill switch will throttle (concurrency → 0)
  kill_switch_lambdas = [
    # resume — HTTP-accessible
    "resume-visitor-counter",
    "resume-contact-handler",
    # resume — Bedrock-backed scheduled (EventBridge-only, but throttle as defence-in-depth)
    "resume-github-fetcher",
    "resume-medium-fetcher",
    # auto-trader dev
    "autotrader-dev-webhook-executor",
    "autotrader-dev-order-reconciler",
    "autotrader-dev-daily-summary",
    # auto-trader prod
    "autotrader-prod-webhook-executor",
    "autotrader-prod-order-reconciler",
    "autotrader-prod-daily-summary",
  ]

  # EventBridge rules to disable (scheduled triggers)
  kill_switch_rules = [
    "resume-github-fetcher-weekly",
    "resume-medium-fetcher-weekly",
    "autotrader-dev-reconciler-schedule",
    "autotrader-dev-daily-summary-schedule",
    "autotrader-prod-reconciler-schedule",
    "autotrader-prod-daily-summary-schedule",
  ]
}

# ---- SNS: trigger topic (Budget Action publishes here) -----

resource "aws_sns_topic" "kill_switch_trigger" {
  name = "cost-kill-switch-trigger"
}

# Budget notifications require the topic policy to allow budgets.amazonaws.com to publish
resource "aws_sns_topic_policy" "kill_switch_trigger" {
  arn = aws_sns_topic.kill_switch_trigger.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBudgetsPublish"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.kill_switch_trigger.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# ---- SNS: notification topic (kill switch sends summary here) ----

resource "aws_sns_topic" "kill_switch_notify" {
  name = "cost-kill-switch-notify"
}

resource "aws_sns_topic_subscription" "kill_switch_notify_email" {
  topic_arn = aws_sns_topic.kill_switch_notify.arn
  protocol  = "email"
  endpoint  = var.to_email
}

# ---- Lambda package ----

data "archive_file" "kill_switch" {
  type        = "zip"
  source_file = "${path.module}/lambda/kill_switch.py"
  output_path = "${path.module}/lambda/kill_switch.zip"
}

# ---- IAM role ----

resource "aws_iam_role" "kill_switch" {
  name = "resume-cost-kill-switch-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "kill_switch" {
  name = "resume-cost-kill-switch-lambda-policy"
  role = aws_iam_role.kill_switch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "ThrottleLambdas"
        Effect = "Allow"
        Action = ["lambda:PutFunctionConcurrency"]
        Resource = [
          for fn in local.kill_switch_lambdas :
          "arn:aws:lambda:${local.region}:${local.account_id}:function:${fn}"
        ]
      },
      {
        Sid    = "DisableEventBridgeRules"
        Effect = "Allow"
        Action = ["events:DisableRule"]
        Resource = [
          for rule in local.kill_switch_rules :
          "arn:aws:events:${local.region}:${local.account_id}:rule/${rule}"
        ]
      },
      {
        Sid      = "PublishNotification"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.kill_switch_notify.arn
      }
    ]
  })
}

# ---- CloudWatch log group ----

resource "aws_cloudwatch_log_group" "kill_switch" {
  name              = "/aws/lambda/resume-cost-kill-switch"
  retention_in_days = 7
}

# ---- Lambda function ----

resource "aws_lambda_function" "kill_switch" {
  function_name    = "resume-cost-kill-switch"
  filename         = data.archive_file.kill_switch.output_path
  source_code_hash = data.archive_file.kill_switch.output_base64sha256
  role             = aws_iam_role.kill_switch.arn
  handler          = "kill_switch.handler"
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      LAMBDAS_TO_THROTTLE          = join(",", local.kill_switch_lambdas)
      EVENTBRIDGE_RULES_TO_DISABLE = join(",", local.kill_switch_rules)
      NOTIFY_TOPIC_ARN             = aws_sns_topic.kill_switch_notify.arn
      DRY_RUN                      = "false"
    }
  }

  depends_on = [aws_cloudwatch_log_group.kill_switch]
}

# Allow SNS to invoke the kill switch Lambda
resource "aws_lambda_permission" "kill_switch_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kill_switch.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.kill_switch_trigger.arn
}

# Wire SNS trigger topic → Lambda
resource "aws_sns_topic_subscription" "kill_switch_trigger_lambda" {
  topic_arn = aws_sns_topic.kill_switch_trigger.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.kill_switch.arn
}

# ---- Budget: $5 threshold with kill switch notification ----
# If you already have "My Zero-Spend Budget" in the console, either:
#   a) import it: terraform import aws_budgets_budget.cost_protection <account_id>:My Zero-Spend Budget
#   b) or just add the SNS topic ARN to that budget's notifications manually in the console
#      (Budgets → select budget → Edit → Configure alerts → add SNS ARN)
# This resource creates a separate $5 budget managed by Terraform.

resource "aws_budgets_budget" "cost_protection" {
  name         = "cost-protection-kill-switch"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100 # 100% of $50 = $50 actual spend
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.kill_switch_trigger.arn]
  }

  # Early warning: alert at 50% ($25) — email only, no kill switch
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.to_email]
  }
}

# ---- Outputs ----

output "kill_switch_trigger_topic_arn" {
  description = "Add this SNS ARN to your existing AWS Budget notifications to wire the kill switch"
  value       = aws_sns_topic.kill_switch_trigger.arn
}

output "kill_switch_function_name" {
  description = "Kill switch Lambda — invoke manually to test (set DRY_RUN=true first)"
  value       = aws_lambda_function.kill_switch.function_name
}
