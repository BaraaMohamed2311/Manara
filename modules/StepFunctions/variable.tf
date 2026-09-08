variable "validate_lambda_arn" {
  description = "ARN of the Lambda function for validation"
  type        = string
}

variable "resize_lambda_arn" {
  description = "ARN of the Lambda function for resizing"
  type        = string
}

variable "watermark_lambda_arn" {
  description = "ARN of the Lambda function for watermarking"
  type        = string
}

variable "store_lambda_arn" {
  description = "ARN of the Lambda function for storing"
  type        = string
}



variable "sns_topic_arn" {
  description = "ARN of the SNS topic"
  type        = string
}
