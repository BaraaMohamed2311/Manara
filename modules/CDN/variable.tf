variable "source_bucket_domain_name" {
  description = "The domain name of the source S3 bucket for the CloudFront distribution"
  type        = string
  
}

variable "src_bucket_arn" {
  description = "The ARN of the source S3 bucket for the CloudFront distribution"
  type        = string
  
}

variable "s3_bucket_id" {
  description = "The ID of the source S3 bucket for the CloudFront distribution"
  type        = string

}

variable "src_bucket_name" {
  description = "The name of the source S3 bucket for the CloudFront distribution"
  type        = string
}