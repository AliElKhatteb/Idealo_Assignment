data "archive_file" "validator" {
  type = "zip"

  source_file = "${path.module}/lambda/validator.py"
  output_path = "${path.module}/lambda/validator.zip"
}

# lambda function to validate uploaded files based on allowed extensions and required metadata
resource "aws_lambda_function" "validator" {
  function_name = "${var.name}-validator"

  filename         = data.archive_file.validator.output_path
  source_code_hash = data.archive_file.validator.output_base64sha256

  role = aws_iam_role.validator.arn

  handler = "validator.lambda_handler"

  runtime = "python3.12"

  timeout = 10

  environment {
    variables = {
      ALLOWED_EXTENSIONS = join(",", var.allowed_extensions)
      REQUIRED_METADATA  = join(",", var.required_metadata)
    }
  }
}

# allowing S3 to invoke the Lambda function when an object is created in the bucket
resource "aws_lambda_permission" "allow_s3" {
  statement_id = "AllowExecutionFromS3"

  action = "lambda:InvokeFunction"

  function_name = aws_lambda_function.validator.function_name

  principal = "s3.amazonaws.com"

  source_arn = aws_s3_bucket.uploads.arn
}