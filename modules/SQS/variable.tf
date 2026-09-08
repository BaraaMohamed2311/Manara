variable "src_bucket_arn" {
  description = "source bucket arn"
  type = string
}

variable "sfn_trigger_lambda_arn" {
  description = "arn of the lambda function that triggers the state machine"
  type = string
}