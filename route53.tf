resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = var.domain_name

  tags = {
    Name = var.domain_name
  }
}

resource "aws_route53_record" "website" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apex_redirect" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.apex_redirect.domain_name
    zone_id                = aws_cloudfront_distribution.apex_redirect.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "google_site_verification" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300
  records = ["google-site-verification=aJ0nkqUollBv9IuFXoOL00i5TfSNM1TMwAkZIeRAkGU"]
}

resource "aws_route53_record" "resume_redirect" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "resume.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.resume_redirect.domain_name
    zone_id                = aws_cloudfront_distribution.resume_redirect.hosted_zone_id
    evaluate_target_health = false
  }
}
