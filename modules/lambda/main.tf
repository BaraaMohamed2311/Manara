
######## Shared Assume Role Policy (used by all Lambda roles) ########

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}


######## The sfn trigger Function ########

# Package the Lambda function code
data "archive_file" "sfn_trigger_zip" {
  type        = "zip"
  source_file = "${path.module}/code/raw/sfn_trigger.py"
  output_path = "${path.module}/code/zipped/sfn_trigger.zip"
}


resource "aws_lambda_function" "sfn_trigger" {
  filename      = data.archive_file.sfn_trigger_zip.output_path
  function_name = "sfn_trigger"
  role          = aws_iam_role.sfn_trigger.arn
  handler       = "sfn_trigger.lambda_handler"
  code_sha256   = data.archive_file.sfn_trigger_zip.output_base64sha256
  runtime       = "python3.12"
  timeout       = 30

  environment {
    variables = {
      STATE_MACHINE_ARN = var.state_machine_arn
    }
  }
}

# IAM role
resource "aws_iam_role" "sfn_trigger" {
  name               = "sfn_trigger_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Attach permissions to role
resource "aws_iam_role_policy" "sfn_trigger" {
  name   = "sfn_trigger_permissions"
  role   = aws_iam_role.sfn_trigger.id
  policy = data.aws_iam_policy_document.sfn_trigger_permissions.json
}

# Permissions document
data "aws_iam_policy_document" "sfn_trigger_permissions" {
  statement {
    sid    = "AllowSQSAccess"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [var.main_sqs_queue_arn]
  }

  statement {
    sid       = "AllowSFNStartExecution"
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [var.state_machine_arn]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}


######## The Validate Image Function ########

# Package the Lambda function code
data "archive_file" "validate_image_zip" {
  type        = "zip"
  source_file = "${path.module}/code/raw/validate.py"
  output_path = "${path.module}/code/zipped/validate.zip"
}

# Lambda function
resource "aws_lambda_function" "validate_image" {
  filename      = data.archive_file.validate_image_zip.output_path
  function_name = "validate_image"
  role          = aws_iam_role.validate_image.arn
  handler       = "validate.lambda_handler"
  code_sha256   = data.archive_file.validate_image_zip.output_base64sha256
  runtime       = "python3.12"

  layers = [aws_lambda_layer_version.pillow_deps.arn]

}

# IAM role
resource "aws_iam_role" "validate_image" {
  name               = "validate_image_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Attach permissions to role
resource "aws_iam_role_policy" "validate_image" {
  name   = "validate_image_permissions"
  role   = aws_iam_role.validate_image.id
  policy = data.aws_iam_policy_document.validate_image_permissions.json
}

# Permissions document
data "aws_iam_policy_document" "validate_image_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.src_bucket_arn}/*"]
  }

  # NEW: validate.py is the first step in the pipeline, so it creates the DynamoDB tracking record
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [var.dynamodb_table_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}




######## The Resize Image Function ########

# Package the Lambda function code
data "archive_file" "resize_image_zip" {
  type        = "zip"
  source_file = "${path.module}/code/raw/resize.py"
  output_path = "${path.module}/code/zipped/resize.zip"
}

# Lambda function
resource "aws_lambda_function" "resize_image" {
  filename      = data.archive_file.resize_image_zip.output_path
  function_name = "resize_image"
  role          = aws_iam_role.resize_image.arn
  handler       = "resize.lambda_handler"
  code_sha256   = data.archive_file.resize_image_zip.output_base64sha256
  runtime       = "python3.12"
  layers = [aws_lambda_layer_version.pillow_deps.arn]
  timeout     = 30    # seconds — was implicitly 3
  memory_size = 512   # MB — was implicitly 128; more memory also means more CPU

}

# IAM role
resource "aws_iam_role" "resize_image" {
  name               = "resize_image_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Attach permissions to role
resource "aws_iam_role_policy" "resize_image" {
  name   = "resize_image_permissions"
  role   = aws_iam_role.resize_image.id
  policy = data.aws_iam_policy_document.resize_image_permissions.json
}


# Permissions document
data "aws_iam_policy_document" "resize_image_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.src_bucket_arn}/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.src_bucket_arn}/*"]
  }

  # NEW: resize.py only updates the existing record's status, it doesn't create it
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:UpdateItem"]
    resources = [var.dynamodb_table_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}



######## The Watermark Image Function ########

# Package the Lambda function code
data "archive_file" "watermark_image_zip" {
  type        = "zip"
  source_file = "${path.module}/code/raw/watermark.py"
  output_path = "${path.module}/code/zipped/watermark.zip"
}

# Lambda function
resource "aws_lambda_function" "watermark_image" {
  filename      = data.archive_file.watermark_image_zip.output_path
  function_name = "watermark_image"
  role          = aws_iam_role.watermark_image.arn
  handler       = "watermark.lambda_handler"
  code_sha256   = data.archive_file.watermark_image_zip.output_base64sha256
  runtime       = "python3.12"
  layers = [aws_lambda_layer_version.pillow_deps.arn]
  timeout     = 30    
  memory_size = 512 
}

# IAM role
resource "aws_iam_role" "watermark_image" {
  name               = "watermark_image_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Attach permissions to role
resource "aws_iam_role_policy" "watermark_image" {
  name   = "watermark_image_permissions"
  role   = aws_iam_role.watermark_image.id
  policy = data.aws_iam_policy_document.watermark_image_permissions.json
}

# Permissions document
data "aws_iam_policy_document" "watermark_image_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.src_bucket_arn}/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.src_bucket_arn}/*"]
  }

  # NEW: watermark.py only updates the existing record's status, same as resize.py
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:UpdateItem"]
    resources = [var.dynamodb_table_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}




######## The Store Image Function ########

# Package the Lambda function code
data "archive_file" "store_image_zip" {
  type        = "zip"
  source_file = "${path.module}/code/raw/store.py"
  output_path = "${path.module}/code/zipped/store.zip"
}

# Lambda function
resource "aws_lambda_function" "store_image" {
  filename      = data.archive_file.store_image_zip.output_path
  function_name = "store_image"
  role          = aws_iam_role.store_image.arn
  handler       = "store.lambda_handler"
  code_sha256   = data.archive_file.store_image_zip.output_base64sha256
  runtime       = "python3.12"
  layers = [aws_lambda_layer_version.pillow_deps.arn]
  timeout     = 60    
  memory_size = 1024 
}

# IAM role
resource "aws_iam_role" "store_image" {
  name               = "store_image_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Attach permissions to role
resource "aws_iam_role_policy" "store_image" {
  name   = "store_image_permissions"
  role   = aws_iam_role.store_image.id
  policy = data.aws_iam_policy_document.store_image_permissions.json
}


# Permissions document
data "aws_iam_policy_document" "store_image_permissions" {

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.src_bucket_arn}/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.src_bucket_arn}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:UpdateItem"
    ]
    resources = [var.dynamodb_table_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}


######## The email Formatter Function ########

# Package the Lambda function code
data "archive_file" "email_formatter_zip" {
  type        = "zip"
  source_file = "${path.module}/code/raw/email_formatter.py"
  output_path = "${path.module}/code/zipped/email_formatter.zip"
}


# Lambda function
resource "aws_lambda_function" "email_formatter" {
  filename      = data.archive_file.email_formatter_zip.output_path
  function_name = "email_formatter"
  role          = aws_iam_role.email_formatter.arn # atttach the role to the lambda function
  handler       = "email_formatter.lambda_handler"
  code_sha256   = data.archive_file.email_formatter_zip.output_base64sha256

  runtime = "python3.12"

  environment {
    variables = {
      SENDER    = var.sender
      RECIPIENT = var.recipient
      SMTP_HOST="smtp.gmail.com"
      SMTP_PORT="587"
      SMTP_USER=var.smtp_user
      SMTP_PASSWORD=var.smtp_password
    }
  }
}

resource "aws_iam_role" "email_formatter" {
  name               = "email_formatter_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}


resource "aws_iam_role_policy" "email_formatter" {
  name   = "email_formatter_permissions"
  role   = aws_iam_role.email_formatter.id
  policy = data.aws_iam_policy_document.email_formatter_permissions.json
}

# Allow SNS to invoke this Lambda (topic subscription protocol = "lambda")
resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_formatter.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topic_arn
}


## lambda is now triggered BY the SNS topic, unwraps the message, and sends
## the formatted email itself via SES — it no longer publishes to SNS

data "aws_iam_policy_document" "email_formatter_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = ["*"] # scope to a specific SES identity ARN if you want tighter permissions
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

######## The Generate PreSigned URL Function ########

# Package the Lambda function code
data "archive_file" "generate_presigned_url_zip" {
  type        = "zip"
  source_file = "${path.module}/code/raw/generatePreSignedURL.py"
  output_path = "${path.module}/code/zipped/generatePreSignedURL.zip"
}

# Lambda function
resource "aws_lambda_function" "generate_presigned_url" {
  filename      = data.archive_file.generate_presigned_url_zip.output_path
  function_name = "generate_presigned_url"
  role          = aws_iam_role.generate_presigned_url.arn
  handler       = "generatePreSignedURL.lambda_handler"
  code_sha256   = data.archive_file.generate_presigned_url_zip.output_base64sha256
  runtime       = "python3.12"

  layers = [aws_lambda_layer_version.presigned_url_deps.arn]

  environment {
    variables = {
      SRC_BUCKET_NAME = var.src_bucket_name
    }
  }
}

# IAM role
resource "aws_iam_role" "generate_presigned_url" {
  name               = "generate_presigned_url_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Attach permissions to role
resource "aws_iam_role_policy" "generate_presigned_url" {
  name   = "generate_presigned_url_permissions"
  role   = aws_iam_role.generate_presigned_url.id
  policy = data.aws_iam_policy_document.generate_presigned_url_permissions.json
}

# Permissions document
data "aws_iam_policy_document" "generate_presigned_url_permissions" {
  ## for the generate download link
  statement {
    effect    = "Allow"
    actions   = ["s3:getObject"]
    resources = ["${var.src_bucket_arn}/*"]
  }

  ## for the generate upload link
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.src_bucket_arn}/*"]
  }

  ## for get metadata of the object
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:GetItem"]
    resources = ["${var.dynamodb_table_arn}"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}


######## The Status Check Function ########


# Package the Lambda function code
data "archive_file" "status_check_zip" {
  type        = "zip"
  source_file = "${path.module}/code/raw/status_check.py"
  output_path = "${path.module}/code/zipped/status_check.zip"
}

# Lambda function
resource "aws_lambda_function" "status_check" {
  filename      = data.archive_file.status_check_zip.output_path
  function_name = "status_check"
  role          = aws_iam_role.status_check.arn
  handler       = "status_check.lambda_handler"
  code_sha256   = data.archive_file.status_check_zip.output_base64sha256

  runtime = "python3.12"

  environment {
    variables = {
      TABLE_NAME = var.dynamodb_table_name
    }
  }
}

# IAM role
resource "aws_iam_role" "status_check" {
  name               = "status_check_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Attach permissions to role
resource "aws_iam_role_policy" "status_check" {
  name   = "status_check_permissions"
  role   = aws_iam_role.status_check.id
  policy = data.aws_iam_policy_document.status_check_permissions.json
}

# Permissions document
data "aws_iam_policy_document" "status_check_permissions" {
  # NEW: read-only — this function never writes to the table
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:GetItem"]
    resources = [var.dynamodb_table_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}


#####################################################################
########################### Layers ##################################
#####################################################################

##################### Layers (shared build logic) #####################

locals {
  is_windows = can(regex("^[A-Za-z]:", abspath(path.module)))

  win_cmd_tpl  = "Set-Location '%s'; if (Test-Path package) { Remove-Item -Recurse -Force package }; New-Item -ItemType Directory -Force -Path package/python | Out-Null; python -m pip install -r requirements.txt -t package/python --platform manylinux2014_x86_64 --implementation cp --python-version 3.12 --only-binary=:all:; New-Item -ItemType File -Force -Path package/.build_complete | Out-Null"
  bash_cmd_tpl = "cd '%s' && rm -rf package && mkdir -p package/python && python3.12 -m pip install -r requirements.txt -t package/python --platform manylinux2014_x86_64 --implementation cp --python-version 3.12 --only-binary=:all: && touch package/.build_complete"

  pillow_dir        = "${path.module}/layers/pillow"
  presigned_url_dir = "${path.module}/layers/presigned_url"
}

##################### Pillow Layer (shared) #####################

resource "terraform_data" "pillow_layer_deps" {
  triggers_replace = {
    requirements  = filesha256("${local.pillow_dir}/requirements.txt")
    build_cmd     = local.is_windows ? local.win_cmd_tpl : local.bash_cmd_tpl
    output_exists = fileexists("${local.pillow_dir}/package/.build_complete")
  }

  provisioner "local-exec" {
    interpreter = local.is_windows ? ["PowerShell", "-Command"] : ["bash", "-c"]
    command     = local.is_windows ? format(local.win_cmd_tpl, local.pillow_dir) : format(local.bash_cmd_tpl, local.pillow_dir)
  }
}

# Create the ZIP file
data "archive_file" "pillow_layer" {
  depends_on  = [terraform_data.pillow_layer_deps]
  type        = "zip"
  source_dir  = "${local.pillow_dir}/package"
  output_path = "${local.pillow_dir}/layer.zip"
}

# Create the Lambda layer
resource "aws_lambda_layer_version" "pillow_deps" {
  layer_name          = "pillow-deps"
  description         = "Pillow (PIL) for image-processing Lambdas"
  filename            = data.archive_file.pillow_layer.output_path
  source_code_hash    = data.archive_file.pillow_layer.output_base64sha256
  compatible_runtimes = ["python3.12"]

  compatible_architectures = ["x86_64"]
}



##################### generatePresignedUrl Layer #####################

resource "terraform_data" "presigned_url_layer_deps" {
  triggers_replace = {
    requirements  = filesha256("${local.presigned_url_dir}/requirements.txt")
    build_cmd     = local.is_windows ? local.win_cmd_tpl : local.bash_cmd_tpl
    output_exists = fileexists("${local.presigned_url_dir}/package/.build_complete")
  }

  provisioner "local-exec" {
    interpreter = local.is_windows ? ["PowerShell", "-Command"] : ["bash", "-c"]
    command     = local.is_windows ? format(local.win_cmd_tpl, local.presigned_url_dir) : format(local.bash_cmd_tpl, local.presigned_url_dir)
  }
}

# Create the ZIP file
data "archive_file" "presigned_url_layer" {
  depends_on  = [terraform_data.presigned_url_layer_deps]
  type        = "zip"
  source_dir  = "${local.presigned_url_dir}/package"
  output_path = "${local.presigned_url_dir}/layer.zip"
}

# Create the Lambda layer
resource "aws_lambda_layer_version" "presigned_url_deps" {
  layer_name          = "presigned-url-deps"
  description         = "FastAPI, Mangum, Pydantic for generate_presigned_url function"
  filename            = data.archive_file.presigned_url_layer.output_path
  source_code_hash    = data.archive_file.presigned_url_layer.output_base64sha256
  compatible_runtimes = ["python3.12"]

  compatible_architectures = ["x86_64"]
}

######### Outputs #########

output "validate_image_lambda_arn" {
  value = aws_lambda_function.validate_image.arn
}

output "resize_image_lambda_arn" {
  value = aws_lambda_function.resize_image.arn
}

output "watermark_image_lambda_arn" {
  value = aws_lambda_function.watermark_image.arn
}

output "store_image_lambda_arn" {
  value = aws_lambda_function.store_image.arn
}

output "email_formatter_lambda_arn" {
  value = aws_lambda_function.email_formatter.arn
}


output "generate_presigned_url_lambda_arn" {
  value = aws_lambda_function.generate_presigned_url.arn
}

output "check_status_lambda_arn" {
  value = aws_lambda_function.status_check.arn
}

output "sfn_trigger_lambda_arn" {
  value = aws_lambda_function.sfn_trigger.arn
}

