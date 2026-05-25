locals {
  website_src = "${path.module}/.."
}

resource "aws_s3_object" "css" {
  for_each     = fileset("${local.website_src}/css/", "**/*.css")
  bucket       = aws_s3_bucket.website.bucket
  key          = "css/${each.value}"
  source       = "${local.website_src}/css/${each.value}"
  content_type = "text/css"
  etag         = filemd5("${local.website_src}/css/${each.value}")
}

resource "aws_s3_object" "css_map" {
  for_each     = fileset("${local.website_src}/css/", "**/*.css.map")
  bucket       = aws_s3_bucket.website.bucket
  key          = "css/${each.value}"
  source       = "${local.website_src}/css/${each.value}"
  content_type = "application/json"
  etag         = filemd5("${local.website_src}/css/${each.value}")
}

resource "aws_s3_object" "js" {
  for_each     = { for f in fileset("${local.website_src}/scripts/", "**/*.js") : f => f if f != "config.js" }
  bucket       = aws_s3_bucket.website.bucket
  key          = "scripts/${each.value}"
  source       = "${local.website_src}/scripts/${each.value}"
  content_type = "text/javascript"
  etag         = filemd5("${local.website_src}/scripts/${each.value}")
}

resource "aws_s3_object" "js_map" {
  for_each     = fileset("${local.website_src}/scripts/", "**/*.js.map")
  bucket       = aws_s3_bucket.website.bucket
  key          = "scripts/${each.value}"
  source       = "${local.website_src}/scripts/${each.value}"
  content_type = "application/json"
  etag         = filemd5("${local.website_src}/scripts/${each.value}")
}

resource "aws_s3_object" "fonts_eot" {
  for_each     = fileset("${local.website_src}/css/", "**/*.eot")
  bucket       = aws_s3_bucket.website.bucket
  key          = "css/${each.value}"
  source       = "${local.website_src}/css/${each.value}"
  content_type = "application/vnd.ms-fontobject"
  etag         = filemd5("${local.website_src}/css/${each.value}")
}

resource "aws_s3_object" "fonts_woff" {
  for_each     = fileset("${local.website_src}/css/", "**/*.woff")
  bucket       = aws_s3_bucket.website.bucket
  key          = "css/${each.value}"
  source       = "${local.website_src}/css/${each.value}"
  content_type = "font/woff"
  etag         = filemd5("${local.website_src}/css/${each.value}")
}

resource "aws_s3_object" "fonts_woff2" {
  for_each     = fileset("${local.website_src}/css/", "**/*.woff2")
  bucket       = aws_s3_bucket.website.bucket
  key          = "css/${each.value}"
  source       = "${local.website_src}/css/${each.value}"
  content_type = "font/woff2"
  etag         = filemd5("${local.website_src}/css/${each.value}")
}

resource "aws_s3_object" "fonts_svg" {
  for_each     = fileset("${local.website_src}/css/", "**/*.svg")
  bucket       = aws_s3_bucket.website.bucket
  key          = "css/${each.value}"
  source       = "${local.website_src}/css/${each.value}"
  content_type = "image/svg+xml"
  etag         = filemd5("${local.website_src}/css/${each.value}")
}

resource "aws_s3_object" "html" {
  bucket       = aws_s3_bucket.website.bucket
  key          = "index.html"
  source       = "${local.website_src}/index.html"
  content_type = "text/html"
  etag         = filemd5("${local.website_src}/index.html")
}

resource "aws_s3_object" "projects_html" {
  for_each     = fileset("${local.website_src}/projects/", "**/*.html")
  bucket       = aws_s3_bucket.website.bucket
  key          = "projects/${each.value}"
  source       = "${local.website_src}/projects/${each.value}"
  content_type = "text/html"
  etag         = filemd5("${local.website_src}/projects/${each.value}")
}

resource "aws_s3_object" "images_png" {
  for_each     = fileset("${local.website_src}/images/", "**/*.png")
  bucket       = aws_s3_bucket.website.bucket
  key          = "images/${each.value}"
  source       = "${local.website_src}/images/${each.value}"
  content_type = "image/png"
  etag         = filemd5("${local.website_src}/images/${each.value}")
}

resource "aws_s3_object" "images_jpg" {
  for_each     = fileset("${local.website_src}/images/", "**/*.{jpg,jpeg}")
  bucket       = aws_s3_bucket.website.bucket
  key          = "images/${each.value}"
  source       = "${local.website_src}/images/${each.value}"
  content_type = "image/jpeg"
  etag         = filemd5("${local.website_src}/images/${each.value}")
}

resource "aws_s3_object" "favicon" {
  bucket       = aws_s3_bucket.website.bucket
  key          = "favicon.ico"
  source       = "${local.website_src}/favicon.ico"
  content_type = "image/x-icon"
  etag         = filemd5("${local.website_src}/favicon.ico")
}

resource "aws_s3_object" "files" {
  for_each = fileset("${local.website_src}/files/", "*")
  bucket   = aws_s3_bucket.website.bucket
  key      = "files/${each.value}"
  source   = "${local.website_src}/files/${each.value}"
  etag     = filemd5("${local.website_src}/files/${each.value}")
}

resource "aws_s3_object" "sitemap" {
  bucket       = aws_s3_bucket.website.bucket
  key          = "sitemap.xml"
  source       = "${local.website_src}/sitemap.xml"
  content_type = "application/xml"
  etag         = filemd5("${local.website_src}/sitemap.xml")
}

resource "aws_s3_object" "robots" {
  bucket       = aws_s3_bucket.website.bucket
  key          = "robots.txt"
  source       = "${local.website_src}/robots.txt"
  content_type = "text/plain"
  etag         = filemd5("${local.website_src}/robots.txt")
}
