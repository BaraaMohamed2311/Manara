import boto3
import io
from PIL import Image
import os
import time

MAX_SIZE_MB = 10
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}
MAX_DIMENSION = 8000

s3 = boto3.client("s3")  
dynamodb = boto3.resource("dynamodb")  
table = dynamodb.Table("ImageMetadata")  


def validate(filepath):
    """Check file size, format, and dimensions. Raises ValueError if invalid."""
    size_mb = os.path.getsize(filepath) / (1024 * 1024)
    if size_mb > MAX_SIZE_MB:
        raise ValueError(f"File too large: {size_mb:.1f}MB (max {MAX_SIZE_MB}MB)")

    with Image.open(filepath) as img:
        if img.format not in ALLOWED_FORMATS:
            raise ValueError(f"Unsupported format: {img.format}")
        if img.width > MAX_DIMENSION or img.height > MAX_DIMENSION:
            raise ValueError(f"Image too large: {img.width}x{img.height}")

    return True


# this whole function is added — it's the part AWS Lambda actually calls.
def lambda_handler(event, context):
    """Download the image from S3, run validate(), record status, and hand the event to the next step."""
    payload = event["Payload"]  
    bucket, key = payload["bucket"], payload["key"]
    image_id = payload["imageId"]

    print(f"Validating image {image_id} from s3://{bucket}/{key}")

    # pull the file down from S3 to a temp path so validate() can open it like a normal file
    tmp_path = "/tmp/" + os.path.basename(key)
    s3.download_file(bucket, key, tmp_path)

    with Image.open(tmp_path) as img:
        size_mb = os.path.getsize(tmp_path) / (1024 * 1024)
        width, height = img.width, img.height

    validate(tmp_path)  # unchanged logic — raises ValueError if something's wrong, Step Functions Catch handles it

    # record what we found, so later steps (or a human debugging) don't need to re-open the file
    payload.setdefault("steps", {})["validate"] = {
        "status": "ok",
        "size_mb": round(size_mb, 2),
        "width": width,
        "height": height,
    }

    # upsert image record to table — this is the first step, so put_item is fine (no existing record yet)
    table.put_item(Item={
        "imageId": image_id,
        "status": "validating",
        "bucket": bucket,
        "key": key,
        "uploadTime": int(time.time()),
    })

    return payload  