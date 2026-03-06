resource "aws_cloudwatch_dashboard" "resume" {
  dashboard_name = "resume-website"

  dashboard_body = jsonencode({
    widgets = [
      # ---- API Gateway requests ----
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "API Gateway — Requests"
          region = var.region
          metrics = [
            ["AWS/ApiGateway", "Count",
             "ApiId", aws_apigatewayv2_api.visitor_counter.id,
             { stat = "Sum", period = 86400, label = "Daily Requests" }]
          ]
          view   = "timeSeries"
          period = 86400
        }
      },
      # ---- Lambda invocations ----
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "Lambda — Invocations"
          region = var.region
          metrics = [
            ["AWS/Lambda", "Invocations",
             "FunctionName", aws_lambda_function.visitor_counter.function_name,
             { stat = "Sum", period = 86400, label = "Visitor Counter" }],
            ["AWS/Lambda", "Invocations",
             "FunctionName", aws_lambda_function.medium_fetcher.function_name,
             { stat = "Sum", period = 86400, label = "Medium Fetcher" }],
            ["AWS/Lambda", "Invocations",
             "FunctionName", aws_lambda_function.github_fetcher.function_name,
             { stat = "Sum", period = 86400, label = "GitHub Fetcher" }],
            ["AWS/Lambda", "Invocations",
             "FunctionName", aws_lambda_function.contact_handler.function_name,
             { stat = "Sum", period = 86400, label = "Contact Handler" }],
          ]
          view   = "timeSeries"
          period = 86400
        }
      },
      # ---- Lambda errors ----
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "Lambda — Errors"
          region = var.region
          metrics = [
            ["AWS/Lambda", "Errors",
             "FunctionName", aws_lambda_function.visitor_counter.function_name,
             { stat = "Sum", period = 86400, color = "#d62728", label = "Visitor Counter" }],
            ["AWS/Lambda", "Errors",
             "FunctionName", aws_lambda_function.medium_fetcher.function_name,
             { stat = "Sum", period = 86400, color = "#ff7f0e", label = "Medium Fetcher" }],
            ["AWS/Lambda", "Errors",
             "FunctionName", aws_lambda_function.github_fetcher.function_name,
             { stat = "Sum", period = 86400, color = "#9467bd", label = "GitHub Fetcher" }],
            ["AWS/Lambda", "Errors",
             "FunctionName", aws_lambda_function.contact_handler.function_name,
             { stat = "Sum", period = 86400, color = "#8c564b", label = "Contact Handler" }],
          ]
          view   = "timeSeries"
          period = 86400
        }
      },
      # ---- DynamoDB consumed capacity ----
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB — Consumed Capacity"
          region = var.region
          metrics = [
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits",
             "TableName", aws_dynamodb_table.visitor_counter.name,
             { stat = "Sum", period = 3600, label = "Write CU/hr" }],
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits",
             "TableName", aws_dynamodb_table.visitor_counter.name,
             { stat = "Sum", period = 3600, label = "Read CU/hr" }],
          ]
          view   = "timeSeries"
          period = 3600
        }
      },
      # ---- Lambda duration p95 ----
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda — Duration p95 (ms)"
          region = var.region
          metrics = [
            ["AWS/Lambda", "Duration",
             "FunctionName", aws_lambda_function.visitor_counter.function_name,
             { stat = "p95", period = 86400, label = "Visitor Counter p95" }],
            ["AWS/Lambda", "Duration",
             "FunctionName", aws_lambda_function.contact_handler.function_name,
             { stat = "p95", period = 86400, label = "Contact Handler p95" }],
          ]
          view   = "timeSeries"
          period = 86400
        }
      },
    ]
  })
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.resume.dashboard_name}"
}
