resource "aws_s3_object" "object-upload-css" {
    for_each        = fileset("css/", "**/*.css")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "css/${each.value}"
    source          = "css/${each.value}"
    content_type    = "text/css"
    etag            = filemd5("css/${each.value}")
    acl             = "public-read"
}

resource "aws_s3_object" "object-upload-css-map" {
    for_each        = fileset("css/", "**/*.css.map")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "css/${each.value}"
    source          = "css/${each.value}"
    content_type    = "application/json"
    etag            = filemd5("css/${each.value}")
    acl             = "public-read"
}

resource "aws_s3_object" "object-upload-js" {
    for_each        = fileset("scripts/", "**/*.js")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "scripts/${each.value}"
    source          = "scripts/${each.value}"
    content_type    = "text/javascript"
    etag            = filemd5("scripts/${each.value}")
    acl             = "public-read"
}

resource "aws_s3_object" "object-upload-js-map" {
    for_each        = fileset("scripts/", "**/*.js.map")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "scripts/${each.value}"
    source          = "scripts/${each.value}"
    content_type    = "application/json"
    etag            = filemd5("scripts/${each.value}")
    acl             = "public-read"
}

resource "aws_s3_object" "object-upload-eot" {
    for_each        = fileset("css/", "**/*.eot")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "css/${each.value}"
    source          = "css/${each.value}"
    content_type    = "application/vnd.ms-fontobject"
    etag            = filemd5("css/${each.value}")
    acl             = "public-read"
}

resource "aws_s3_object" "object-upload-woff" {
    for_each        = fileset("css/", "**/*.woff")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "css/${each.value}"
    source          = "css/${each.value}"
    content_type    = "font/woff"
    etag            = filemd5("css/${each.value}")
    acl             = "public-read"
}

resource "aws_s3_object" "object-upload-woff2" {
    for_each        = fileset("css/", "**/*.woff2")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "css/${each.value}"
    source          = "css/${each.value}"
    content_type    = "font/woff2"
    etag            = filemd5("css/${each.value}")
    acl             = "public-read"
}

resource "aws_s3_object" "object-upload-svg" {
    for_each        = fileset("css/", "**/*.svg")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "css/${each.value}"
    source          = "css/${each.value}"
    content_type    = "image/svg+xml"
    etag            = filemd5("css/${each.value}")
    acl             = "public-read"
}

resource "aws_s3_object" "object-upload-html" {
    for_each        = fileset(".", "index.html")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = each.value
    source          = "${each.value}"
    content_type    = "text/html"
    etag            = filemd5("${each.value}")
    acl             = "public-read"
}

resource "aws_s3_object" "object-upload-images-png" {
    for_each        = fileset("images/", "**/*.png")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "images/${each.value}"
    source          = "images/${each.value}"
    content_type    = "image/png"
    etag            = filemd5("images/${each.value}")
    acl             = "public-read"
}

resource "aws_s3_object" "object-upload-images-jpg" {
    for_each        = fileset("images/", "**/*.jpg")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "images/${each.value}"
    source          = "images/${each.value}"
    content_type    = "image/jpeg"
    etag            = filemd5("images/${each.value}")
    acl             = "public-read"
}

resource "aws_s3_object" "object-upload-images-ico" {
    for_each        = fileset(".", "favicon.ico")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "favicon.ico"
    source          = "favicon.ico"
    content_type    = "image/png"
    etag            = filemd5("${each.value}")
    acl             = "public-read"
}

resource "aws_s3_object" "object-upload-images-jpeg" {
    for_each        = fileset("images/", "**/*.jpeg")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "images/${each.value}"
    source          = "images/${each.value}"
    content_type    = "image/jpeg"
    etag            = filemd5("images/${each.value}")
    acl             = "public-read"
}


resource "aws_s3_object" "object-upload-files" {
    for_each        = fileset("files/", "*")
    bucket          = data.aws_s3_bucket.selected-bucket.bucket
    key             = "files/${each.value}"
    source          = "files/${each.value}"
    etag            = filemd5("files/${each.value}")
    acl             = "public-read"
}