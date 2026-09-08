resource "aws_apigatewayv2_api" "app_api_gateway_tf" {
  name          = "app_api_gateway_tf"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]                
    allow_methods = ["GET", "POST","PUT", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 300
  }
}

## Stage - required for routes to actually be reachable
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.app_api_gateway_tf.id
  name        = "$default"
  auto_deploy = true
}

## GET /uploads/presigned-url route to generate a presigned URL for S3 object upload.
resource "aws_apigatewayv2_integration" "presigned_url_integration" {
  api_id                 = aws_apigatewayv2_api.app_api_gateway_tf.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = var.generate_presigned_url_lambda_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "generate_presigned_url_route" {
  api_id    = aws_apigatewayv2_api.app_api_gateway_tf.id
  route_key = "GET /uploads/presigned-url"
  target    = "integrations/${aws_apigatewayv2_integration.presigned_url_integration.id}"
}

resource "aws_lambda_permission" "presigned_url_permission" {
  statement_id  = "AllowAPIGatewayInvokePresignedUrl"
  action        = "lambda:InvokeFunction"
  function_name = var.generate_presigned_url_lambda_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.app_api_gateway_tf.execution_arn}/*/*"
}

## GET /images/{image_id}/download-url route to generate a presigned URL for S3 object download.
## reuses the integration above rather than creating a second identical one —
resource "aws_apigatewayv2_route" "download_url_route" {
  api_id    = aws_apigatewayv2_api.app_api_gateway_tf.id
  route_key = "GET /images/{image_id}/download-url"
  target    = "integrations/${aws_apigatewayv2_integration.presigned_url_integration.id}"
}

## check status of the uploaded image
resource "aws_apigatewayv2_integration" "check_status_integration" {
  api_id                 = aws_apigatewayv2_api.app_api_gateway_tf.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = var.check_status_lambda_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "check_status_route" {
  api_id    = aws_apigatewayv2_api.app_api_gateway_tf.id
  route_key = "GET /check-status"
  target    = "integrations/${aws_apigatewayv2_integration.check_status_integration.id}"
}

resource "aws_lambda_permission" "check_status_permission" {
  statement_id  = "AllowAPIGatewayInvokeCheckStatus"
  action        = "lambda:InvokeFunction"
  function_name = var.check_status_lambda_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.app_api_gateway_tf.execution_arn}/*/*"
}
