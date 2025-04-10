resource "aws_s3_bucket_cors_configuration" "cors_rule" {
  bucket = data.aws_s3_bucket.selected-bucket.bucket
cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
    expose_headers = ["ETag"]
  }
}