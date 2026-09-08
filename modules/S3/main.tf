################## Source Bucket #########################
resource "aws_s3_bucket" "source-bucket-tf" {
  bucket = "my-src-bucket-tf"
  provider = aws.source
  
  tags = {
    Name        = "My Source bucket"
  }

}
## Required to be enabled for Cross-Region Replication (CRR)
resource "aws_s3_bucket_versioning" "source-versioning-enabled" {
  bucket = aws_s3_bucket.source-bucket-tf.id
  provider = aws.source
  versioning_configuration {
    status = "Enabled"
  }
}

## CORS configuration for the source bucket to allow cross-origin requests from the CloudFront distribution
resource "aws_s3_bucket_cors_configuration" "cors_configuration" {
  bucket = aws_s3_bucket.source-bucket-tf.bucket

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST","GET"]
    allowed_origins = ["*"]

  }

  
}


## SRC IAM Role  ###
resource "aws_iam_role" "src-role" {
  name = "src-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "s3.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    tag-key = "src-role"
  }
}


# policy for the src bucket **role**  read from source and replicate to destination

resource "aws_iam_role_policy" "src-role-policy" {
  name = "src-role-policy"
  role = aws_iam_role.src-role.id
  policy = data.aws_iam_policy_document.src_role_policy_document.json
  provider = aws.source
}

data "aws_iam_policy_document" "src_role_policy_document" {
  statement {
    
    actions = [
        "s3:GetBucketVersioning",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket"
    ]

    resources = [
        aws_s3_bucket.source-bucket-tf.arn,
        "${aws_s3_bucket.source-bucket-tf.arn}/*"
    ]
  }

  statement {
    
    actions = [
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags"
    ]

    resources = [
      aws_s3_bucket.destination-bucket-tf.arn,
      "${aws_s3_bucket.destination-bucket-tf.arn}/*"
    ]
  }
}







## Lifecycle Configuration  ###
resource "aws_s3_bucket_lifecycle_configuration" "src-versioning-bucket-config" {
  # Must have bucket versioning enabled first
  depends_on = [aws_s3_bucket_versioning.source-versioning-enabled]
  provider = aws.source
  bucket = aws_s3_bucket.source-bucket-tf.bucket

  rule {
    id = "config"
    
    ## Retrieval in milliseconds
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    ### Retrieval in hours
    noncurrent_version_transition {
      noncurrent_days = 60
      storage_class   = "GLACIER"
    }
    ### Delete the object after 90 days of creation
    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    status = "Enabled"
  }
}



## Trigger SQS Queue for S3 Bucket Notification  ###
## notify on fresh images upload only
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.source-bucket-tf.id
  provider = aws.source
  queue {
    queue_arn     = var.main_queue_arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "fresh/"
  }
}


################## Destination Bucket #########################
resource "aws_s3_bucket" "destination-bucket-tf" {
  bucket = "my-dst-bucket-tf"
  provider = aws.destination
  tags = {
    Name        = "My Destination bucket"
  }
}


## Required to be enabled for Cross-Region Replication (CRR)
resource "aws_s3_bucket_versioning" "destination-versioning-enabled" {
  bucket = aws_s3_bucket.destination-bucket-tf.id
  provider = aws.destination
  versioning_configuration {
    status = "Enabled"
  }
}


# Replication config (new objects)
resource "aws_s3_bucket_replication_configuration" "replication" {
  provider = aws.source
    depends_on = [
    aws_s3_bucket_versioning.source-versioning-enabled,
    aws_s3_bucket_versioning.destination-versioning-enabled
  ]

  bucket   = aws_s3_bucket.source-bucket-tf.id
  role     = aws_iam_role.src-role.arn

  

  rule {
    id     = "replication-rule"
    status = "Enabled"


    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.destination-bucket-tf.arn
      storage_class = "STANDARD_IA"
    }
  }
  
}


## Lifecycle Configuration  ###
resource "aws_s3_bucket_lifecycle_configuration" "dst-versioning-bucket-config" {
  # Must have bucket versioning enabled first
  provider = aws.destination
  depends_on = [aws_s3_bucket_versioning.destination-versioning-enabled]

  bucket = aws_s3_bucket.destination-bucket-tf.bucket

  rule {
    id = "config"

    
    ### Retrieval in hours
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }
    status = "Enabled"
  }
}

## Policy configuration  ###

resource "aws_s3_bucket_policy" "destination-bucket-policy" {
  bucket = aws_s3_bucket.destination-bucket-tf.id
  policy = data.aws_iam_policy_document.destination_policy_document.json
  provider = aws.destination
}

# resource policy to allow replication interactions from source bucket to destination bucket
data "aws_iam_policy_document" "destination_policy_document" {
  statement {
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.src-role.arn]
    }

    actions = [
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags"
    ]

    resources = [
      aws_s3_bucket.destination-bucket-tf.arn,
      "${aws_s3_bucket.destination-bucket-tf.arn}/*"
    ]
  }
}


######### Outputs #########

output "source_bucket_arn" {
  value = aws_s3_bucket.source-bucket-tf.arn
}


output "source_bucket_id" {
  value = aws_s3_bucket.source-bucket-tf.id
}

output "source_bucket_name" {
  value = aws_s3_bucket.source-bucket-tf.bucket
}

output "source_bucket_domain_name" {
  value = aws_s3_bucket.source-bucket-tf.bucket_domain_name
}

output "destination_bucket_arn" {
  value = aws_s3_bucket.destination-bucket-tf.arn
}

