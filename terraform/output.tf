output "module_path" {
  value = path.module
}

output "root_path" {
  value = path.root
}

output "cwd_path" {
  value = path.cwd
}

output "s3_bucket_regional_domain" {
  value = data.aws_s3_bucket.selected-bucket.bucket_regional_domain_name
}