# variable "stage" {}
# variable "dnsname" {
#   default = "NAME"
# }


data "aws_canonical_user_id" "current_user" {}

variable "dnszone" {
  default = "ZONE NAME HERE"
}

variable "cert_arn" {
  default = "CERT HERE"
}

variable "vanityname" {
  default = "selfserv"
}

provider "aws" {
  version = "~> 2.68"
  region = "us-east-2"
}

provider "aws" {
  version = "~> 2.68"
  alias  = "useast1"
  region = "us-east-1"
}



terraform {
  backend "s3" {
    bucket         = "BUCKETNAME"
    key            = "REMOVED"
    region         = "us-east-2"
    dynamodb_table = "Name-terraform-locks"
    encrypt        = true
  }
}

locals {
  cf_origin_id = "NAME"
}

resource "aws_s3_bucket" "selfserv_bucket" {
  bucket = "${var.vanityname}.${var.dnszone}"
  # acl    = "public-read"

  website {
    index_document = "index.html"
    error_document = "index.html"
  }
  grant {
    type        = "Group"
    permissions = ["READ"]
    uri         = "http://acs.amazonaws.com/groups/global/AllUsers"
  }
  grant {
    id          = data.aws_canonical_user_id.current_user.id
    type        = "CanonicalUser"
    permissions = ["FULL_CONTROL"]
  }

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_cloudfront_origin_access_identity" "CloudfrontOriginAccessId" {
  comment = "Cloudfront access Identity"
}

#Create Cloud Distribution


resource "aws_cloudfront_distribution" "selfserv_bucket_distribution" {
  origin {
    domain_name = aws_s3_bucket.selfserv_bucket.bucket_domain_name
    origin_id   = local.cf_origin_id

    s3_origin_config {
      # http_port              = 80
      # https_port             = 443
      # origin_protocol_policy = "match-viewer"
      origin_access_identity = "origin-access-identity/cloudfront/${aws_cloudfront_origin_access_identity.CloudfrontOriginAccessId.id}"
    }
  }

  enabled = true
  # is_ipv6_enabled     = true
  comment             = "dev"
  default_root_object = "index.html"
  aliases             = ["${var.vanityname}.${var.dnszone}"]
  #   logging_config {
  #     include_cookies = false
  #     bucket          = "mylogs.s3.amazonaws.com"
  #     prefix          = "myprefix"
  #   }

  #   aliases = ["mysite.example.com", "yoursite.example.com"]

  # If there is a 404, return index.html with a HTTP 200 Response
  custom_error_response {
    error_caching_min_ttl = 3000
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.cf_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"


    lambda_function_association {
      event_type = "viewer-response"
      lambda_arn = aws_lambda_function.edge_lambda.qualified_arn
      # lambda_arn = "arn:aws:lambda:us-east-1:754159388236:function:SelfservLamba:$LATEST"
    }
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
      # locations        = ["US", "CA", "GB", "DE"]
    }
  }

  tags = {
    Environment = "dev"
  }

  viewer_certificate {
    acm_certificate_arn            = var.cert_arn
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2018"
    ssl_support_method             = "sni-only"
  }
}


resource "aws_s3_bucket_public_access_block" "selfserv_bucket" {
  bucket              = aws_s3_bucket.selfserv_bucket.id
  block_public_acls   = false
  block_public_policy = false
}
# Here we specify the bucket

resource "aws_s3_bucket_policy" "selfserv_bucket" {
  bucket = aws_s3_bucket.selfserv_bucket.id

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Allow Public Access to All Objects",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
      "Resource": ["arn:aws:s3:::sitename/*"]
    } 
  ]
}
POLICY
}

#Create Lambda Edge function, deploy, create IAM Policy

resource "aws_iam_role" "lambda_edge_role" {
  name               = "lambda-edge-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
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

resource "aws_iam_role_policy" "edgerole_policy" {
  name   = "HttpSecurityHeadersLambdaPolicy"
  role   = aws_iam_role.lambda_edge_role.id
  policy = <<-EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:*:*:*"
            ]
        },
        {
            "Action": [
                "iam:CreateServiceLinkedRole",
                "lambda:GetFunction",
                "lambda:EnableReplication",
                "cloudfront:UpdateDistribution",
                "cloudfront:CreateDistribution",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_lambda_function" "edge_lambda" {
  provider         = aws.useast1
  version          = "~> 2.68"
  function_name    = "lambdatedge"
  filename         = "function.zip"
  handler          = "index.handler"
  runtime          = "nodejs12.x" // This should match the version in AWS
  publish          = "true"       // Important!
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.lambda_edge_role.arn
}

# creates a zip file with the code that can be fed into Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "index.js"
  output_path = "function.zip"
}

#Route 53

resource "aws_route53_zone" "primary_dns_zone" {
  name          = var.dnszone
  comment       = "DNS for dev resources."
  force_destroy = null
}

resource "aws_route53_record" "appURL" {
  zone_id = aws_route53_zone.primary_dns_zone.zone_id
  name    = var.vanityname
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.selfserv_bucket_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.selfserv_bucket_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
