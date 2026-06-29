resource "aws_iam_role" "ingest_lambda" {
  name = "${local.name_prefix}-ingest-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

data "aws_iam_policy_document" "ingest_lambda" {
  statement {
    sid    = "WriteLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.common["/aws/lambda/${local.name_prefix}-ingest-alert"].arn}:*"]
  }

  statement {
    sid    = "SendIncidentAlert"
    effect = "Allow"

    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]

    resources = [aws_sqs_queue.incident.arn]
  }

  statement {
    sid    = "ReadWebhookSecret"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [aws_secretsmanager_secret.runtime["webhook_signing_key"].arn]
  }

  dynamic "statement" {
    for_each = var.enable_kms ? [1] : []

    content {
      sid    = "UseKms"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]

      resources = [aws_kms_key.this[0].arn]
    }
  }
}

resource "aws_iam_policy" "ingest_lambda" {
  name   = "${local.name_prefix}-ingest-lambda-policy"
  policy = data.aws_iam_policy_document.ingest_lambda.json
}

resource "aws_iam_role_policy_attachment" "ingest_lambda" {
  role       = aws_iam_role.ingest_lambda.name
  policy_arn = aws_iam_policy.ingest_lambda.arn
}

data "archive_file" "ingest_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/ingest"
  output_path = "${path.module}/.terraform/build/ingest-alert.zip"
}

resource "aws_lambda_function" "ingest_alert" {
  function_name = "${local.name_prefix}-ingest-alert"
  role          = aws_iam_role.ingest_lambda.arn
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 10
  memory_size   = 256

  filename         = data.archive_file.ingest_lambda.output_path
  source_code_hash = data.archive_file.ingest_lambda.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency >= 0 ? var.lambda_reserved_concurrency : null
  kms_key_arn                    = var.enable_kms ? aws_kms_key.this[0].arn : null

  environment {
    variables = {
      INCIDENT_QUEUE_URL         = aws_sqs_queue.incident.url
      WEBHOOK_SIGNING_SECRET_ARN = aws_secretsmanager_secret.runtime["webhook_signing_key"].arn
      AUDIT_BUCKET_NAME          = aws_s3_bucket.audit.bucket
      ENVIRONMENT                = var.environment
      PROJECT                    = var.project
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ingest_lambda,
    aws_cloudwatch_log_group.common,
  ]

  tags = {
    Name = "${local.name_prefix}-ingest-alert"
  }
}

resource "aws_lambda_function_url" "ingest_alert" {
  count = var.enable_ingest_lambda_function_url ? 1 : 0

  function_name      = aws_lambda_function.ingest_alert.function_name
  authorization_type = var.ingest_function_url_auth_type

  cors {
    allow_credentials = false
    allow_methods     = ["POST"]
    allow_origins     = ["*"]
    allow_headers     = ["content-type", "x-tenant-id", "x-tf1-signature", "x-tf1-timestamp"]
    max_age           = 300
  }

  lifecycle {
    precondition {
      condition     = var.environment != "prod" || var.ingest_function_url_auth_type != "NONE"
      error_message = "Prod ingest Lambda Function URL must use AWS_IAM auth. Use NONE only for demo with HMAC validation."
    }
  }
}
