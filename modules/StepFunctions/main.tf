# ...

resource "aws_cloudwatch_log_group" "sfn_log_group" {
  name              = "/aws/vendedlogs/states/my-state-machine"
  retention_in_days = 14
}

resource "aws_sfn_state_machine" "sfn_state_machine" {
  name     = "my-state-machine"
  role_arn = aws_iam_role.iam_for_sfn.arn
  type     = "EXPRESS"


  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_log_group.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  definition = <<EOF
        {
        "Comment": "Serverless Image Processing Pipeline Workflow",
        "QueryLanguage": "JSONata",
        "StartAt": "Validate Lambda",
        "States": {
            "Validate Lambda": {
            "Type": "Task",
            "Resource": "${var.validate_lambda_arn}",
            "Output": "{% $states.result %}",
            "Arguments": {
                "Payload": "{% $states.input %}"
            },
            "Retry": [
                {
                "ErrorEquals": [
                    "Lambda.ServiceException",
                    "Lambda.AWSLambdaException",
                    "Lambda.SdkClientException",
                    "Lambda.TooManyRequestsException"
                ],
                "IntervalSeconds": 1,
                "MaxAttempts": 3,
                "BackoffRate": 2,
                "JitterStrategy": "FULL"
                }
            ],
            "Catch": [
                {
                "ErrorEquals": ["States.ALL"],
                "Next": "Publish Failure SNS"
                }
            ],
            "Next": "Resize Lambda"
            },
            "Resize Lambda": {
            "Type": "Task",
            "Resource": "${var.resize_lambda_arn}",
            "Output": "{% $states.result %}",
            "Arguments": {
                "Payload": "{% $states.input %}"
            },
            "Retry": [
                {
                "ErrorEquals": [
                    "Lambda.ServiceException",
                    "Lambda.AWSLambdaException",
                    "Lambda.SdkClientException",
                    "Lambda.TooManyRequestsException"
                ],
                "IntervalSeconds": 1,
                "MaxAttempts": 3,
                "BackoffRate": 2,
                "JitterStrategy": "FULL"
                }
            ],
            "Catch": [
                {
                "ErrorEquals": ["States.ALL"],
                "Next": "Publish Failure SNS"
                }
            ],
            "Next": "Watermark Lambda"
            },
            "Watermark Lambda": {
            "Type": "Task",
            "Resource": "${var.watermark_lambda_arn}",
            "Output": "{% $states.result %}",
            "Arguments": {
                "Payload": "{% $states.input %}"
            },
            "Retry": [
                {
                "ErrorEquals": [
                    "Lambda.ServiceException",
                    "Lambda.AWSLambdaException",
                    "Lambda.SdkClientException",
                    "Lambda.TooManyRequestsException"
                ],
                "IntervalSeconds": 1,
                "MaxAttempts": 3,
                "BackoffRate": 2,
                "JitterStrategy": "FULL"
                }
            ],
            "Catch": [
                {
                "ErrorEquals": ["States.ALL"],
                "Next": "Publish Failure SNS"
                }
            ],
            "Next": "Store Lambda"
            },
            "Store Lambda": {
            "Type": "Task",
            "Resource": "${var.store_lambda_arn}",
            "Output": "{% $states.result %}",
            "Arguments": {
                "Payload": "{% $states.input %}"
            },
            "Retry": [
                {
                "ErrorEquals": [
                    "Lambda.ServiceException",
                    "Lambda.AWSLambdaException",
                    "Lambda.SdkClientException",
                    "Lambda.TooManyRequestsException"
                ],
                "IntervalSeconds": 1,
                "MaxAttempts": 3,
                "BackoffRate": 2,
                "JitterStrategy": "FULL"
                }
            ],
            "Catch": [
                {
                "ErrorEquals": ["States.ALL"],
                "Next": "Publish Failure SNS"
                }
            ],
            "Next": "Publish Success SNS"
            },
           "Publish Success SNS": {
              "Type": "Task",
              "Resource": "arn:aws:states:::sns:publish",
              "Arguments": {
                "TopicArn": "${var.sns_topic_arn}",
                "Message": {
                  "status": "success",
                  "bucket": "{% $states.input.bucket %}",
                  "key": "{% $states.input.key %}",
                  "final_key": "{% $states.input.final_key %}",
                  "imageId": "{% $states.input.imageId %}",
                  "metadata": "{% $exists($states.input.metadata) ? $states.input.metadata : {} %}",
                  "steps": "{% $states.input.steps %}"
                }
              },
              "End": true
            },
            "Publish Failure SNS": {
              "Type": "Task",
              "Resource": "arn:aws:states:::sns:publish",
              "Arguments": {
                "TopicArn": "${var.sns_topic_arn}",
                "Message": {
                  "status": "failure",
                  "bucket": "{% $states.input.bucket %}",
                  "key": "{% $states.input.key %}",
                  "imageId": "{% $states.input.imageId %}",
                  "error": "{% $states.input.error %}",
                  "steps": "{% $states.input.steps %}",
                  "execution_arn": "{% $states.context.Execution.Id %}"
                }
              },
              "End": true
            }
        }
    }
    EOF
}


######## Step Functions Execution Role ########

data "aws_iam_policy_document" "sfn_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "iam_for_sfn" {
  name               = "step_functions_execution_role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume_role.json
}

resource "aws_iam_role_policy" "sfn_permissions" {
  name   = "step_functions_permissions"
  role   = aws_iam_role.iam_for_sfn.id
  policy = data.aws_iam_policy_document.sfn_permissions.json
}

data "aws_iam_policy_document" "sfn_permissions" {
  statement {
    effect  = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [
      var.validate_lambda_arn,
      var.resize_lambda_arn,
      var.watermark_lambda_arn,
      var.store_lambda_arn
    ]
  }


  statement {
    effect  = "Allow"
    actions = ["sns:Publish"]
    resources = [
      var.sns_topic_arn
    ]
  }

  # Express workflows log to CloudWatch Logs, unlike Standard which uses the SFN console/history natively
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups"
    ]
    resources = ["*"]
  }
}


####  Outputs ####

output "state_machine_arn" {
  value = aws_sfn_state_machine.sfn_state_machine.arn
}