resource "aws_s3_object" "css" {
  for_each     = fileset("css/", "**/*.css")
  bucket       = aws_s3_bucket.website.bucket
  key          = "css/${each.value}"
  source       = "css/${each.value}"
  content_type = "text/css"
  etag         = filemd5("css/${each.value}")
}

resource "aws_s3_object" "css_map" {
  for_each     = fileset("css/", "**/*.css.map")
  bucket       = aws_s3_bucket.website.bucket
  key          = "css/${each.value}"
  source       = "css/${each.value}"
  content_type = "application/json"
  etag         = filemd5("css/${each.value}")
}

resource "aws_s3_object" "js" {
  for_each     = fileset("scripts/", "**/*.js")
  bucket       = aws_s3_bucket.website.bucket
  key          = "scripts/${each.value}"
  source       = "scripts/${each.value}"
  content_type = "text/javascript"
  etag         = filemd5("scripts/${each.value}")
}

resource "aws_s3_object" "js_map" {
  for_each     = fileset("scripts/", "**/*.js.map")
  bucket       = aws_s3_bucket.website.bucket
  key          = "scripts/${each.value}"
  source       = "scripts/${each.value}"
  content_type = "application/json"
  etag         = filemd5("scripts/${each.value}")
}

resource "aws_s3_object" "fonts_eot" {
  for_each     = fileset("css/", "**/*.eot")
  bucket       = aws_s3_bucket.website.bucket
  key          = "css/${each.value}"
  source       = "css/${each.value}"
  content_type = "application/vnd.ms-fontobject"
  etag         = filemd5("css/${each.value}")
}

resource "aws_s3_object" "fonts_woff" {
  for_each     = fileset("css/", "**/*.woff")
  bucket       = aws_s3_bucket.website.bucket
  key          = "css/${each.value}"
  source       = "css/${each.value}"
  content_type = "font/woff"
  etag         = filemd5("css/${each.value}")
}

resource "aws_s3_object" "fonts_woff2" {
  for_each     = fileset("css/", "**/*.woff2")
  bucket       = aws_s3_bucket.website.bucket
  key          = "css/${each.value}"
  source       = "css/${each.value}"
  content_type = "font/woff2"
  etag         = filemd5("css/${each.value}")
}

resource "aws_s3_object" "fonts_svg" {
  for_each     = fileset("css/", "**/*.svg")
  bucket       = aws_s3_bucket.website.bucket
  key          = "css/${each.value}"
  source       = "css/${each.value}"
  content_type = "image/svg+xml"
  etag         = filemd5("css/${each.value}")
}

resource "aws_s3_object" "html" {
  bucket       = aws_s3_bucket.website.bucket
  key          = "index.html"
  source       = "index.html"
  content_type = "text/html"
  etag         = filemd5("index.html")
}

resource "aws_s3_object" "images_png" {
  for_each     = fileset("images/", "**/*.png")
  bucket       = aws_s3_bucket.website.bucket
  key          = "images/${each.value}"
  source       = "images/${each.value}"
  content_type = "image/png"
  etag         = filemd5("images/${each.value}")
}

resource "aws_s3_object" "images_jpg" {
  for_each     = fileset("images/", "**/*.{jpg,jpeg}")
  bucket       = aws_s3_bucket.website.bucket
  key          = "images/${each.value}"
  source       = "images/${each.value}"
  content_type = "image/jpeg"
  etag         = filemd5("images/${each.value}")
}

resource "aws_s3_object" "favicon" {
  bucket       = aws_s3_bucket.website.bucket
  key          = "favicon.ico"
  source       = "favicon.ico"
  content_type = "image/x-icon"
  etag         = filemd5("favicon.ico")
}

resource "aws_s3_object" "files" {
  for_each = fileset("files/", "*")
  bucket   = aws_s3_bucket.website.bucket
  key      = "files/${each.value}"
  source   = "files/${each.value}"
  etag     = filemd5("files/${each.value}")
}

resource "aws_s3_object" "sitemap" {
  bucket       = aws_s3_bucket.website.bucket
  key          = "sitemap.xml"
  source       = "sitemap.xml"
  content_type = "application/xml"
  etag         = filemd5("sitemap.xml")
}

resource "aws_s3_object" "robots" {
  bucket       = aws_s3_bucket.website.bucket
  key          = "robots.txt"
  source       = "robots.txt"
  content_type = "text/plain"
  etag         = filemd5("robots.txt")
}
