####################### Storage #######################


module "S3" {
    source = "./modules/S3"

    providers = {
    aws.source      = aws.source
    aws.destination = aws.destination
  }
    main_queue_arn = module.SQS.main_queue_arn
}

module "DB" {
    source = "./modules/DB"
    

}

####################### Functions #######################

module "lambda" {
    source = "./modules/lambda"

    sns_topic_arn = module.SNS.sns_topic_arn
    cloudfront_distribution_domain_name = module.CDN.cloudfront_distribution_domain_name
    dynamodb_table_name = module.DB.dynamodb_table_name
    src_bucket_arn = module.S3.source_bucket_arn
    destination_bucket_arn = module.S3.destination_bucket_arn
    dynamodb_table_arn = module.DB.dynamodb_table_arn
    src_bucket_name = module.S3.source_bucket_name
    state_machine_arn = module.StepFunctions.state_machine_arn
    main_sqs_queue_arn = module.SQS.main_queue_arn
    sender    = "baraamohamed2311@gmail.com"
    recipient = "baraamohamed2311@gmail.com"
    smtp_password = var.smtp_password
    smtp_user     = var.smtp_user

}

module "StepFunctions" {
    source = "./modules/StepFunctions"

    validate_lambda_arn = module.lambda.validate_image_lambda_arn
    resize_lambda_arn   = module.lambda.resize_image_lambda_arn
    watermark_lambda_arn = module.lambda.watermark_image_lambda_arn
    store_lambda_arn = module.lambda.store_image_lambda_arn
    sns_topic_arn = module.SNS.sns_topic_arn
}

####################### Events #######################

module "SQS" {
    source = "./modules/SQS"

    src_bucket_arn = module.S3.source_bucket_arn
    sfn_trigger_lambda_arn = module.lambda.sfn_trigger_lambda_arn

}

module "SNS" {
    source = "./modules/SNS"

    email_formatter_lambda_arn = module.lambda.email_formatter_lambda_arn

}



####################### Forwarding #######################

module "Gateway" {
    source = "./modules/Gateway"

    generate_presigned_url_lambda_arn = module.lambda.generate_presigned_url_lambda_arn
    check_status_lambda_arn = module.lambda.check_status_lambda_arn
}

module "CDN" {
    source = "./modules/CDN"

    s3_bucket_id = module.S3.source_bucket_id
    src_bucket_arn = module.S3.source_bucket_arn
    src_bucket_name =  module.S3.source_bucket_name
    source_bucket_domain_name = module.S3.source_bucket_domain_name
}