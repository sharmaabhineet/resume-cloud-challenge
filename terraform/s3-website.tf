resource "aws_s3_bucket_website_configuration" "website-config" {
  bucket = data.aws_s3_bucket.selected-bucket.bucket
index_document {
    suffix = "index.html"
  }
error_document {
    key = "images/404.jpeg"
  }
}