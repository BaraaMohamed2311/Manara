resource "aws_cloudfront_origin_access_control" "cdn" {
  name                              = "cdn-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = var.source_bucket_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.cdn.id
    origin_id                = var.s3_bucket_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.html"


  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.s3_bucket_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }



  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


## Allow cloudfront to access the S3 bucket ##

data "aws_iam_policy_document" "origin_bucket_policy_document" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      "${var.src_bucket_arn}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "origin_bucket_policy" {
  bucket = var.src_bucket_name
  policy = data.aws_iam_policy_document.origin_bucket_policy_document.json
}

########### Outputs ###########
output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}