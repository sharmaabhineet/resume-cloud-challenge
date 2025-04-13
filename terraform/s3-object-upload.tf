resource "aws_s3_object" "file" {
  for_each     = fileset(path.cwd, "**/*.{html,css,js,map,eot,woff,woff2,png,jpg,jpeg,ico,pdf}")
  bucket       = data.aws_s3_bucket.selected-bucket.id
  key          = each.value
  source       = "../${each.value}"
  content_type = lookup(local.content_types, regex("\\.[^.]+$", each.value), null)
  source_hash  = filemd5("../${each.value}")
}