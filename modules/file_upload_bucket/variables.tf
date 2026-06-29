variable "name" {
  description = "Name to be used as a prefix for resources."
  type        = string
}

variable "allowed_extensions" {
  description = "Allowed file extensions."
  type        = list(string)

  default = [
    "jpg",
    "jpeg",
    "png",
    "pdf"
  ]
}

variable "required_metadata" {
  description = "Metadata keys required on uploaded objects."
  type        = list(string)

  default = [
    "customer-id"
  ]
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)

  default = {}
}