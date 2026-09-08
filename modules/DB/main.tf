## DynamoDB is Non-Relational Schemeless Database so we only define the primary key and its type. The rest of the attributes can be added dynamically when we insert items into the table.
resource "aws_dynamodb_table" "image_metadata" {
  name         = "ImageMetadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "imageId"

  attribute {
    name = "imageId"
    type = "S"
  }

  tags = {
    Name        = "image-metadata-table"
  }
}


##### Outpiuts #####
output "dynamodb_table_name" {
  value = aws_dynamodb_table.image_metadata.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.image_metadata.arn
}