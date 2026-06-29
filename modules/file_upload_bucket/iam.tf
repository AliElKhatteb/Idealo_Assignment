resource "aws_cloudwatch_log_group" "validator" {
  name              = "/aws/lambda/${var.name}-validator"
  retention_in_days = 30
}

# let lambda to assume the role and access the S3 bucket and CloudWatch logs
resource "aws_iam_role" "validator" {
  name = "${var.name}-validator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "validator" {
  name = "${var.name}-validator"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      {
        Effect = "Allow"

        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = [
          "${aws_cloudwatch_log_group.validator.arn}:*" # covering all log streams in the log group
        ]
      },

      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",                              # allow the lambda to read the object metadata from S3
          "s3:GetObjectAttributes",
          "s3:HeadObject"
        ]

        Resource = "${aws_s3_bucket.uploads.arn}/*"
      }

    ]
  })
}

resource "aws_iam_role_policy_attachment" "validator" {
  role       = aws_iam_role.validator.name
  policy_arn = aws_iam_policy.validator.arn
}