variable "generate_presigned_url_lambda_arn" {
  description = "The ARN of the Lambda function that generates presigned URLs for S3 object upload"
  type        = string
}

variable "check_status_lambda_arn" {
  description = "The ARN of the Lambda function that checks the status of the uploaded image"
    type        = string
}