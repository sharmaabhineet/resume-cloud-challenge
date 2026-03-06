resource "aws_apigatewayv2_api" "visitor_counter" {
  name          = "resume-visitor-counter"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://${var.subdomain}.${var.domain_name}"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "visitor_counter" {
  api_id      = aws_apigatewayv2_api.visitor_counter.id
  name        = "$default"
  auto_deploy = true
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

# Write API URLs to a local JS config file picked up by S3 upload
resource "local_file" "api_config" {
  content  = <<-JS
    window.COUNTER_API_URL = '${aws_apigatewayv2_stage.visitor_counter.invoke_url}/count';
    window.CONTACT_API_URL = '${aws_apigatewayv2_stage.visitor_counter.invoke_url}/contact';
  JS
  filename = "${path.module}/scripts/config.js"
}
