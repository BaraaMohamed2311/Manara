import os
import uuid

import boto3
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException
from mangum import Mangum
from pydantic import BaseModel

app = FastAPI()

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
BUCKET_NAME = os.getenv("S3_BUCKET_NAME", "my-src-bucket-tf")
IMAGE_METADATA_TABLE = os.getenv("IMAGE_METADATA_TABLE", "ImageMetadata")

MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # matches validate.py's MAX_SIZE_MB = 10

s3_client = boto3.client("s3", region_name=AWS_REGION)

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table = dynamodb.Table(IMAGE_METADATA_TABLE)


# ------------------------------------------------------------------
# 1. GET /uploads/presigned-url — presigned POST for uploads
# ------------------------------------------------------------------
class PresignedUploadResponse(BaseModel):
    url: str
    fields: dict
    key: str
    image_id: str


@app.get("/uploads/presigned-url", response_model=PresignedUploadResponse)
def create_upload_url():
    image_id = str(uuid.uuid4())
    unique_key = f"fresh/{image_id}"

    try:
        response = s3_client.generate_presigned_post(
            Bucket=BUCKET_NAME,
            Key=unique_key,
            Conditions=[["content-length-range", 1, MAX_UPLOAD_BYTES]],
            ExpiresIn=300,  # 5 minutes
        )
    except ClientError as e:
        raise HTTPException(status_code=500, detail=f"Error generating upload URL: {e}")

    return {
        "url": response["url"],
        "fields": response["fields"],
        "key": unique_key,
        "image_id": image_id,
    }


# ------------------------------------------------------------------
# 2. GET /images/{image_id}/download-url — presigned GET for downloads
# ------------------------------------------------------------------
class PresignedDownloadResponse(BaseModel):
    url: str
    key: str


MIME_TO_EXT = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}


@app.get("/images/{image_id}/download-url", response_model=PresignedDownloadResponse)
def create_download_url(image_id: str):
    # Look the image up in DynamoDB rather than trusting a client-supplied key directly to look up s3 objects
    # This prevents a malicious user from guessing keys and downloading arbitrary files from the bucket.
    # presign a GET for arbitrary keys in the bucket.
    try:
        item = table.get_item(Key={"imageId": image_id}).get("Item")
    except ClientError as e:
        raise HTTPException(status_code=500, detail=f"Error looking up image: {e}")

    if not item:
        raise HTTPException(status_code=404, detail=f"No image found with id '{image_id}'")

    if item.get("status") != "done":
        raise HTTPException(
            status_code=409,
            detail=f"Image '{image_id}' is not ready yet (status: {item.get('status', 'unknown')})",
        )

    key = item.get("finalKey")
    if not key:
        raise HTTPException(status_code=500, detail=f"Image '{image_id}' has no finalKey recorded")

    # NEW: read the object's real Content-Type so we can force it (and a real
    # filename/extension) on the presigned URL — this fixes downloads even for
    # objects uploaded before ContentType was set correctly at write time.
    try:
        head = s3_client.head_object(Bucket=BUCKET_NAME, Key=key)
    except ClientError as e:
        raise HTTPException(status_code=500, detail=f"Error reading image metadata: {e}")

    content_type = head.get("ContentType") or "image/jpeg"
    ext = MIME_TO_EXT.get(content_type, ".jpg")

    try:
        url = s3_client.generate_presigned_url(
            ClientMethod="get_object",
            Params={
                "Bucket": BUCKET_NAME,
                "Key": key,
                "ResponseContentType": content_type,
                "ResponseContentDisposition": f'inline; filename="{image_id}{ext}"',
            },
            ExpiresIn=300,  # 5 minutes
        )
    except ClientError as e:
        raise HTTPException(status_code=500, detail=f"Error generating download URL: {e}")

    return {"url": url, "key": key}


# ------------------------------------------------------------------
# 3. Lambda entrypoint
# ------------------------------------------------------------------
lambda_handler = Mangum(app)