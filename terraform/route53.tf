resource "aws_route53_zone" "main" {
  name = var.domain_name
  tags = {
    Name = "www.${var.domain_name}"
    description = var.domain_name
  }
  comment = var.domain_name
}

resource "aws_route53_record" "alias-record" {
      zone_id = "${aws_route53_zone.main.zone_id}"
      name = "resume.sharmaabhineet.com"
      type = "A"

   alias {
        name = aws_cloudfront_distribution.resume.domain_name
        zone_id = aws_cloudfront_distribution.resume.hosted_zone_id
        evaluate_target_health = false
    }
}

resource "aws_route53_record" "site_cert_dns" {
  allow_overwrite = true
  name            = tolist(aws_acm_certificate.site_cert.domain_validation_options)[0].resource_record_name
  records         = [tolist(aws_acm_certificate.site_cert.domain_validation_options)[0].resource_record_value]
  type            = tolist(aws_acm_certificate.site_cert.domain_validation_options)[0].resource_record_type
  zone_id         = aws_route53_zone.main.zone_id
  ttl             = 60
}