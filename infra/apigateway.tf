resource "aws_apigatewayv2_api" "visitor_counter" {
  name          = "resume-visitor-counter"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://${var.subdomain}.${var.domain_name}"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "X-Chat-Key"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "visitor_counter" {
  api_id      = aws_apigatewayv2_api.visitor_counter.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = 10 # max sustained requests/sec across all routes
    throttling_burst_limit = 5  # max concurrent burst
  }
}

resource "aws_apigatewayv2_integration" "visitor_counter" {
  api_id                 = aws_apigatewayv2_api.visitor_counter.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.visitor_counter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "visitor_counter" {
  api_id    = aws_apigatewayv2_api.visitor_counter.id
  route_key = "GET /count"
  target    = "integrations/${aws_apigatewayv2_integration.visitor_counter.id}"
}

resource "aws_lambda_permission" "visitor_counter" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.visitor_counter.execution_arn}/*/*"
}

# Write API URLs to local file (used by mock dev server)
locals {
  config_js = <<-JS
    window.COUNTER_API_URL = '${aws_apigatewayv2_stage.visitor_counter.invoke_url}/count';
    window.CONTACT_API_URL = '${aws_apigatewayv2_stage.visitor_counter.invoke_url}/contact';
    window.CHAT_API_URL    = '${aws_apigatewayv2_stage.visitor_counter.invoke_url}/chat';
    window.CHAT_API_KEY    = '${random_password.chat_api_key.result}';
  JS
}

resource "local_file" "api_config" {
  content  = local.config_js
  filename = "${path.module}/../scripts/config.js"
}

# Upload config.js directly to S3 — explicit resource so CI/CD doesn't need the file on disk
resource "aws_s3_object" "api_config" {
  bucket       = aws_s3_bucket.website.bucket
  key          = "scripts/config.js"
  content      = local.config_js
  content_type = "application/javascript"
  etag         = md5(local.config_js)
}
