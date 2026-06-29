module "uploads" {
  source = "../modules/file_upload_bucket"

  name = var.name

  allowed_extensions = [
    "pdf",
    "png",
    "jpg"
  ]

  required_metadata = [
    "customer-id",
    "document-type"
  ]

  tags = {
    Project     = "Idealo-Assigment"
    Environment = "dev"
  }
}