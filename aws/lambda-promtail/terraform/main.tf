terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region     = var.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

resource "aws_iam_role" "lambda" {
  name = "lambda-promtail"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "promtail" {
  function_name = "lambda-promtail"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "public.ecr.aws/grafana/lambda-promtail:main"
  timeout       = 60
  memory_size   = 128

  environment {
    variables = {
      WRITE_ADDRESS = var.loki_push_url
      KEEP_STREAM   = "true"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_lambda_permission" "allow_cloudwatch" {
  for_each      = toset(var.log_group_names)
  statement_id  = "AllowCW-${replace(each.value, "/", "_")}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.promtail.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:${each.value}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "to_loki" {
  for_each        = toset(var.log_group_names)
  name            = "to-lambda-promtail"
  log_group_name  = each.value
  filter_pattern  = ""
  destination_arn = aws_lambda_function.promtail.arn
  depends_on      = [aws_lambda_permission.allow_cloudwatch]
}
