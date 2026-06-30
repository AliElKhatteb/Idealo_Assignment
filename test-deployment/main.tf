module "uploads" {
  source = "../modules/file_upload_bucket"

  name = var.name

  allowed_extensions = var.allowed_extensions

  required_metadata = var.required_metadata

  tags = {
    Project     = "Idealo-Assigment"
    Environment = "dev"
  }
}