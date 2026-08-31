terraform {
  required_version = ">= 1.5"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

data "aws_caller_identity" "current" {}

variable "confluence_url" {
  type = string
}

variable "confluence_email" {
  type      = string
  sensitive = true
}

variable "confluence_api_token" {
  type      = string
  sensitive = true
}

variable "confluence_space_key" {
  type = string
}

variable "departures_parent_page_id" {
  type = string
}

variable "arrivals_parent_page_id" {
  type = string
}

locals {
  name = "s3-confluence-data-flows"
}

resource "aws_s3_bucket" "documents" {
  bucket        = "${local.name}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_notification" "documents" {
  bucket      = aws_s3_bucket.documents.id
  eventbridge = true
}

resource "terraform_data" "package" {
  triggers_replace = [
    filesha256("${path.module}/requirements.txt"),
    filesha256("${path.module}/publisher.py"),
    filesha256("${path.module}/exporter.py"),
    filesha256("${path.module}/build.sh"),
  ]

  provisioner "local-exec" {
    command = "bash ${path.module}/build.sh"
  }
}

data "archive_file" "lambda" {
  depends_on  = [terraform_data.package]
  type        = "zip"
  source_dir  = "${path.module}/.build/package"
  output_path = "${path.module}/.build/lambda.zip"
}

resource "aws_iam_role" "lambda" {
  name = "${local.name}-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "documents-and-logs"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.documents.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = [
          "${aws_cloudwatch_log_group.publisher.arn}:*",
          "${aws_cloudwatch_log_group.exporter.arn}:*",
        ]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "publisher" {
  name              = "/aws/lambda/${local.name}-publisher"
  retention_in_days = 1
}

resource "aws_cloudwatch_log_group" "exporter" {
  name              = "/aws/lambda/${local.name}-exporter"
  retention_in_days = 1
}

resource "aws_lambda_function" "publisher" {
  function_name    = "${local.name}-publisher"
  role             = aws_iam_role.lambda.arn
  handler          = "publisher.handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  memory_size      = 512
  timeout          = 60

  environment {
    variables = {
      CONFLUENCE_API_TOKEN = var.confluence_api_token
      CONFLUENCE_EMAIL     = var.confluence_email
      CONFLUENCE_SPACE_KEY = var.confluence_space_key
      CONFLUENCE_URL       = trimsuffix(var.confluence_url, "/")
      PARENT_PAGE_ID       = var.arrivals_parent_page_id
    }
  }

  depends_on = [aws_cloudwatch_log_group.publisher]
}

resource "aws_lambda_function" "exporter" {
  function_name    = "${local.name}-exporter"
  role             = aws_iam_role.lambda.arn
  handler          = "exporter.handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  memory_size      = 256
  timeout          = 60

  environment {
    variables = {
      BUCKET_NAME          = aws_s3_bucket.documents.id
      CONFLUENCE_API_TOKEN = var.confluence_api_token
      CONFLUENCE_EMAIL     = var.confluence_email
      CONFLUENCE_URL       = trimsuffix(var.confluence_url, "/")
      PARENT_PAGE_ID       = var.departures_parent_page_id
    }
  }

  depends_on = [aws_cloudwatch_log_group.exporter]
}

resource "aws_cloudwatch_event_rule" "markdown_created" {
  name = "${local.name}-markdown-created"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.documents.id] }
      object = {
        key = [
          { wildcard = "departures/*.json" },
          { wildcard = "departures/*.md" },
          { wildcard = "departures/*.vtt" },
        ]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "publisher" {
  rule = aws_cloudwatch_event_rule.markdown_created.name
  arn  = aws_lambda_function.publisher.arn
}

resource "aws_lambda_permission" "publisher" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.publisher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.markdown_created.arn
}

resource "aws_cloudwatch_event_rule" "export" {
  name                = "${local.name}-export"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "exporter" {
  rule = aws_cloudwatch_event_rule.export.name
  arn  = aws_lambda_function.exporter.arn
}

resource "aws_lambda_permission" "exporter" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.exporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.export.arn
}

output "bucket_name" {
  value = aws_s3_bucket.documents.id
}
