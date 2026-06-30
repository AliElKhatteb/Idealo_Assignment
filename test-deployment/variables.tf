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