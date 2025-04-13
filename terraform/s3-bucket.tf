###################################
# S3
###################################
resource "aws_s3_bucket" "resume" {
  bucket = "${var.bucket_name}"
}

resource "aws_s3_bucket_website_configuration" "website-config" {
  bucket = aws_s3_bucket.resume.bucket
index_document {
    suffix = "index.html"
  }
error_document {
    key = "images/404.jpg"
  }
}

resource "aws_s3_bucket_acl" "bucket-acl" {
  bucket = aws_s3_bucket.resume.bucket
  acl    = "public-read"
}

resource "aws_s3_bucket_policy" "read-resume" {
  bucket = aws_s3_bucket.resume.id
  policy = data.aws_iam_policy_document.read-resume-policy.json
}

data "aws_iam_policy_document" "read-resume-policy" {
  statement {
    sid    = "AllowPublicRead"
    effect = "Allow"
resources = [
      "arn:aws:s3:::www.${var.domain_name}",
      "arn:aws:s3:::www.${var.domain_name}/*",
    ]
actions = ["S3:GetObject"]
principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

###################################
# S3 Bucket Public Access Block
###################################
resource "aws_s3_bucket_public_access_block" "resume" {
  bucket = aws_s3_bucket.resume.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = false
}

data "aws_s3_bucket" "selected-bucket" {
  bucket = aws_s3_bucket.resume.bucket
}