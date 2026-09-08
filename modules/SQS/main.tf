############ SQS #############
resource "aws_sqs_queue" "main-queue-tf" {
  name                      = "main-queue-tf"
  delay_seconds             = 90
  max_message_size          = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10


  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead-letter-queue-tf.arn
    maxReceiveCount     = 4
  })

  tags = {
    Name = "main-queue-tf"
  }
}

resource "aws_sqs_queue_policy" "main_queue_policy" {
  queue_url = aws_sqs_queue.main-queue-tf.id
  policy    = data.aws_iam_policy_document.allow_s3_to_send_messages.json
}

data "aws_iam_policy_document" "allow_s3_to_send_messages" {
  statement {
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.main-queue-tf.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.src_bucket_arn]
    }
  }
}


#### Lambda Event Source Mapping for SQS Trigger
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.main-queue-tf.arn
  function_name    = var.sfn_trigger_lambda_arn
  enabled          = true
  batch_size       = 5
}



############ DLQ #############


resource "aws_sqs_queue" "dead-letter-queue-tf" {
  name = "dead-letter-queue-tf"
}

resource "aws_sqs_queue_redrive_allow_policy" "terraform_queue_redrive_allow_policy" {
  queue_url = aws_sqs_queue.dead-letter-queue-tf.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.main-queue-tf.arn]
  })
}



######## Outputs ########

output "main_queue_arn" {
  value = aws_sqs_queue.main-queue-tf.arn
}

output "dead_letter_queue_arn" {
  value = aws_sqs_queue.dead-letter-queue-tf.arn
}