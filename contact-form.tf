# SES — domain identity for sharmaabhineet.com
resource "aws_ses_domain_identity" "main" {
  domain = var.domain_name
}

resource "aws_ses_domain_dkim" "main" {
  domain = aws_ses_domain_identity.main.domain
}

# DKIM DNS records in Route53
resource "aws_route53_record" "ses_dkim" {
  count   = 3
  zone_id = aws_route53_zone.main.zone_id
  name    = "${aws_ses_domain_dkim.main.dkim_tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["${aws_ses_domain_dkim.main.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# SES MAIL FROM domain
resource "aws_ses_domain_mail_from" "main" {
  domain           = aws_ses_domain_identity.main.domain
  mail_from_domain = "mail.${var.domain_name}"
}

resource "aws_route53_record" "ses_mail_from_mx" {
  zone_id = aws_route53_zone.main.zone_id
  name    = aws_ses_domain_mail_from.main.mail_from_domain
  type    = "MX"
  ttl     = 300
  records = ["10 feedback-smtp.${var.region}.amazonses.com"]
}

resource "aws_route53_record" "ses_mail_from_spf" {
  zone_id = aws_route53_zone.main.zone_id
  name    = aws_ses_domain_mail_from.main.mail_from_domain
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 include:amazonses.com ~all"]
}

# Lambda package
data "archive_file" "contact_handler" {
  type        = "zip"
  source_file = "${path.module}/lambda/contact_handler.py"
  output_path = "${path.module}/lambda/contact_handler.zip"
}

# IAM role
resource "aws_iam_role" "lambda_contact_handler" {
  name = "resume-contact-handler-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_contact_handler" {
  name = "resume-contact-handler-lambda-policy"
  role = aws_iam_role.lambda_contact_handler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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

resource "aws_cloudwatch_log_group" "contact_handler" {
  name              = "/aws/lambda/resume-contact-handler"
  retention_in_days = 14
}

resource "aws_lambda_function" "contact_handler" {
  function_name    = "resume-contact-handler"
  filename         = data.archive_file.contact_handler.output_path
  source_code_hash = data.archive_file.contact_handler.output_base64sha256
  role             = aws_iam_role.lambda_contact_handler.arn
  handler          = "contact_handler.handler"
  runtime          = "python3.12"
  timeout          = 15

  environment {
    variables = {
      FROM_EMAIL     = "noreply@${var.domain_name}"
      TO_EMAIL       = "sharma.abhineet31@gmail.com"
      ALLOWED_ORIGIN = "https://${var.subdomain}.${var.domain_name}"
      SES_REGION     = var.region
    }
  }

  depends_on = [aws_cloudwatch_log_group.contact_handler]
}

# API Gateway integration — contact route (POST /contact) on existing API
resource "aws_apigatewayv2_integration" "contact_handler" {
  api_id                 = aws_apigatewayv2_api.visitor_counter.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.contact_handler.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "contact_handler" {
  api_id    = aws_apigatewayv2_api.visitor_counter.id
  route_key = "POST /contact"
  target    = "integrations/${aws_apigatewayv2_integration.contact_handler.id}"
}

resource "aws_lambda_permission" "contact_handler" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.visitor_counter.execution_arn}/*/*"
}
