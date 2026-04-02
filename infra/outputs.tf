output "website_url" {
  description = "Public HTTPS URL of the resume website"
  value       = "https://${var.subdomain}.${var.domain_name}"
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "cloudfront_id" {
  description = "CloudFront distribution ID (use for cache invalidations)"
  value       = aws_cloudfront_distribution.website.id
}

output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.website.bucket
}

output "route53_name_servers" {
  description = "Name servers for the hosted zone (must match your domain registrar)"
  value       = aws_route53_zone.main.name_servers
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "visitor_counter_api_url" {
  description = "Visitor counter API endpoint"
  value       = "${aws_apigatewayv2_stage.visitor_counter.invoke_url}/count"
}
