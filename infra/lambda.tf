data "archive_file" "visitor_counter" {
  type        = "zip"
  source_file = "${path.module}/lambda/visitor_counter.py"
  output_path = "${path.module}/lambda/visitor_counter.zip"
}

resource "aws_iam_role" "lambda_visitor_counter" {
  name = "resume-visitor-counter-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_visitor_counter" {
  name = "resume-visitor-counter-lambda-policy"
  role = aws_iam_role.lambda_visitor_counter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoDB"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.visitor_counter.arn
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

resource "aws_cloudwatch_log_group" "visitor_counter" {
  name              = "/aws/lambda/resume-visitor-counter"
  retention_in_days = 14
}

resource "aws_lambda_function" "visitor_counter" {
  function_name    = "resume-visitor-counter"
  filename         = data.archive_file.visitor_counter.output_path
  source_code_hash = data.archive_file.visitor_counter.output_base64sha256
  role             = aws_iam_role.lambda_visitor_counter.arn
  handler          = "visitor_counter.handler"
  runtime          = "python3.12"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitor_counter.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.visitor_counter]
}
