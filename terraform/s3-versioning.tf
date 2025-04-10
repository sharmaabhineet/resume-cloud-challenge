resource "aws_s3_bucket_versioning" "s3_versioning" {
  bucket = data.aws_s3_bucket.selected-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}