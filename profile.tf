variable "aws_region" {
  default = "us-east-1"
}

variable "distribution" {
  type = string
  default = "Szakallas"
}

variable "bucket" {
  type = string
  default = "szakallas.eu"
}

variable "domain" {
  type = string
  default = "szakallas.eu"
}

locals {
  distribution_origin_id = "${var.distribution}Origin"
}

provider "aws" {
  region = var.aws_region
}

data "aws_s3_bucket" "storage" {
  bucket = var.bucket
}

resource "aws_s3_bucket_policy" "storage" {
  bucket = data.aws_s3_bucket.storage.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Id": "${var.distribution}CloudFrontAccessPolicy",
  "Statement": [
    {
      "Sid": "2",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_cloudfront_origin_access_identity.distribution.iam_arn}"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${data.aws_s3_bucket.storage.bucket}/*"
    }
  ]
}
EOF
}

data "aws_route53_zone" "zone" {
  name         = "${var.domain}."
  private_zone = false
}

resource "aws_route53_record" "distribution" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.distribution.domain_name
    zone_id                = aws_cloudfront_distribution.distribution.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}

resource "aws_route53_record" "cert_validation" {
  name    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_type
  zone_id = data.aws_route53_zone.zone.id
  records = [aws_acm_certificate.cert.domain_validation_options.0.resource_record_value]
  ttl     = 60
}

resource "aws_cloudfront_distribution" "distribution" {
  origin {
    domain_name = data.aws_s3_bucket.storage.bucket_regional_domain_name
    origin_id   = local.distribution_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.distribution.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = ["${var.domain}"]

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cert.arn
    minimum_protocol_version = "TLSv1.1_2016"
    ssl_support_method = "sni-only"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.distribution_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 259200
    max_ttl                = 31536000
    compress               = true

    lambda_function_association {
      event_type = "origin-request"
      lambda_arn = "${aws_lambda_function.url_rewrite.arn}:2" # FIXME https://github.com/terraform-providers/terraform-provider-aws/issues/8081
      include_body = false
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  price_class = "PriceClass_200"
}

resource "aws_cloudfront_origin_access_identity" "distribution" {}

resource "aws_iam_role" "url_rewrite" {
  name = "${var.distribution}UrlRewriteRole"

  assume_role_policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
      {
         "Effect": "Allow",
         "Principal": {
            "Service": [
               "lambda.amazonaws.com",
               "edgelambda.amazonaws.com"
            ]
         },
         "Action": "sts:AssumeRole"
      }
   ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "url_rewrite_basic" {
  role       = aws_iam_role.url_rewrite.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "url_rewrite" {
  function_name = "${var.distribution}UrlRewrite"
  role          = aws_iam_role.url_rewrite.arn
  handler       = "index.handler"

  filename         = data.archive_file.url_rewrite.output_path
  source_code_hash = data.archive_file.url_rewrite.output_base64sha256

  runtime = "nodejs12.x"
  publish = true
}

data "local_file" "url_rewrite" {
  filename = "${path.module}/url_rewrite/index.js"
}

resource "local_file" "url_rewrite" {
  content  = data.local_file.url_rewrite.content
  filename = "${path.module}/build/url_rewrite/index.js"
}

data "archive_file" "url_rewrite" {
  depends_on = [
    local_file.url_rewrite
  ]

  type        = "zip"
  output_path = "${path.module}/build/url_rewrite.zip"
  source_dir  = "${path.module}/build/url_rewrite"
}
