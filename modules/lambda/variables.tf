variable "sns_topic_arn" {
  description = "The ARN of the SNS topic to publish messages to"
  type        = string
  
}

variable "cloudfront_distribution_domain_name" {
  description = "The domain name of the CloudFront distribution"
  type        = string
  
}

variable "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table"
  type        = string
}

variable "src_bucket_arn" {
  description = "The ARN of the source S3 bucket"
  type        = string
}

variable "src_bucket_name" {
  description = "The name of the source S3 bucket"
  type        = string
}

variable "destination_bucket_arn" {
  description = "The ARN of the destination S3 bucket"
  type        = string
}

variable "main_sqs_queue_arn" {
  description = "The ARN of the main SQS queue"
  type        = string
}

variable "state_machine_arn" {
  description = "The ARN of the Step Functions state machine"
  type        = string
}

variable "sender" {
    description = "The email address to use as the sender for SES notifications"
    type        = string
  }

variable "recipient" {
    description = "The email address to use as the recipient for SES notifications"
    type        = string
  }

  variable "smtp_user" {
    description = "The SMTP username for sending emails"
    type        = string
    sensitive = true
  }

  variable "smtp_password" {
    description = "The SMTP password for sending emails"
    type        = string
    sensitive = true
  }