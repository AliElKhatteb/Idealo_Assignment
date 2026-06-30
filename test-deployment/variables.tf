variable "name" {
  description = "Name to be used as a prefix for resources."
  type        = string
}

variable "environment" {
  description = "Environment to deploy resources."
  type        = string
}

variable "region" {
  description = "AWS region to deploy resources."
  type        = string
  default     = "eu-central-1"
}

variable "allowed_extensions" {
  type        = list(string)
  description = "List of allowed file extensions."
}

variable "required_metadata" {
  type        = list(string)
  description = "List of required metadata keys."
}