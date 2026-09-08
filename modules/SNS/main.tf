resource "aws_sns_topic" "image-processing-topic" {
  name = "image-processing-topic"
}

resource "aws_sns_topic_subscription" "email_formatter_target" {
  topic_arn = aws_sns_topic.image-processing-topic.arn
  protocol  = "lambda"
  endpoint  = var.email_formatter_lambda_arn
}


##### Outputs #####

output "sns_topic_arn" {
  value = aws_sns_topic.image-processing-topic.arn
}