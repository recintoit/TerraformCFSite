provider "aws" {
  # profile = "assumed profile"
  # region  = "us-east-2"
}

# terraform {
#   backend "s3" {
#     bucket         = "BUCKETNAME"
#     key            = "tf/iamtfinfra.tfstate"
#     region         = "us-east-2"
#     dynamodb_table = "iam-terraform-locks"
#     encrypt        = true
#   }
# }

resource "aws_s3_bucket" "terraform_state" {
  bucket = "BUCKETNAME HER"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}
resource "aws_dynamodb_table" "terraform_locks" {
  name           = "PUT DBNAME NAME HERE"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  lifecycle {
    ignore_changes = [read_capacity, write_capacity]
  }
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.terraform_state.arn
  description = "The ARN of the S3 bucket"
}
output "dynamodb_table_name" {
  value       = aws_dynamodb_table.terraform_locks.name
  description = "The name of the DynamoDB table"
}
