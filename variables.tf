variable "domain_name" {
  type        = string
  description = "The domain name for the resume website (e.g. example.com)"
}

variable "bucket_name" {
  type        = string
  description = "The S3 bucket name for website hosting (must be globally unique)"
}

variable "region" {
  type        = string
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "subdomain" {
  type        = string
  description = "Subdomain for the resume website (e.g. resume, www)"
  default     = "resume"
}
