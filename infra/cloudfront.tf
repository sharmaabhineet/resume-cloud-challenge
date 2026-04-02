# CloudFront Function: 301 redirect apex → portfolio.
resource "aws_cloudfront_function" "apex_redirect" {
  name    = "apex-to-portfolio-redirect"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOF
    function handler(event) {
      return {
        statusCode: 301,
        statusDescription: "Moved Permanently",
        headers: {
          location: { value: "https://portfolio.${var.domain_name}" + event.request.uri }
        }
      };
    }
  EOF
}

# Redirect distribution: sharmaabhineet.com → portfolio.sharmaabhineet.com
resource "aws_cloudfront_distribution" "apex_redirect" {
  enabled         = true
  http_version    = "http2"
  is_ipv6_enabled = true
  price_class     = "PriceClass_All"
  aliases         = [var.domain_name]

  origin {
    origin_id   = aws_s3_bucket_website_configuration.website.website_endpoint
    domain_name = aws_s3_bucket_website_configuration.website.website_endpoint

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = aws_s3_bucket_website_configuration.website.website_endpoint
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.apex_redirect.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.website.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_acm_certificate_validation.website]
}

# CloudFront Function: 301 redirect resume. → portfolio.
resource "aws_cloudfront_function" "resume_redirect" {
  name    = "resume-to-portfolio-redirect"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOF
    function handler(event) {
      return {
        statusCode: 301,
        statusDescription: "Moved Permanently",
        headers: {
          location: { value: "https://portfolio.${var.domain_name}" + event.request.uri }
        }
      };
    }
  EOF
}

# Redirect distribution: resume.sharmaabhineet.com → portfolio.sharmaabhineet.com
resource "aws_cloudfront_distribution" "resume_redirect" {
  enabled         = true
  http_version    = "http2"
  is_ipv6_enabled = true
  price_class     = "PriceClass_All"
  aliases         = ["resume.${var.domain_name}"]

  origin {
    origin_id   = aws_s3_bucket_website_configuration.website.website_endpoint
    domain_name = aws_s3_bucket_website_configuration.website.website_endpoint

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = aws_s3_bucket_website_configuration.website.website_endpoint
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    # AWS managed CachingOptimized policy
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.resume_redirect.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.website.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_acm_certificate_validation.website]
}

resource "aws_cloudfront_distribution" "website" {
  enabled         = true
  http_version    = "http2"
  is_ipv6_enabled = true
  price_class     = "PriceClass_All"
  aliases         = ["${var.subdomain}.${var.domain_name}"]

  origin {
    origin_id   = aws_s3_bucket_website_configuration.website.website_endpoint
    domain_name = aws_s3_bucket_website_configuration.website.website_endpoint

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = aws_s3_bucket_website_configuration.website.website_endpoint
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    # AWS managed CachingOptimized policy
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.website.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_acm_certificate_validation.website]
}
