import boto3
import io
from PIL import Image
import os

MAX_SIZE_MB = 10
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}
MAX_DIMENSION = 8000

# NEW: PIL format -> MIME type, so every object we write to S3 carries a
# correct Content-Type. Without this, S3 defaults to application/octet-stream
# and downloads show up as a generic "file" instead of an image.
FORMAT_TO_MIME = {"JPEG": "image/jpeg", "PNG": "image/png", "WEBP": "image/webp"}

s3 = boto3.client("s3")  # NEW: needed to read the fresh image and write the resized one back to S3
dynamodb = boto3.resource("dynamodb")  # NEW: needed to update the status-tracking record
table = dynamodb.Table("ImageMetadata")  # NEW: adjust table name to match your actual DynamoDB table


def resize(image: Image.Image, max_width=1920, max_height=1080) -> Image.Image:
    """Resize image in-place proportionally to fit within bounds."""
    img = image.copy()
    img.thumbnail((max_width, max_height), Image.LANCZOS)
    return img


# NEW: this whole function is added — it's the part AWS Lambda actually calls.
def lambda_handler(event, context):
    """Load the image this step is supposed to work on, resize it, save it under resized/, pass the event on."""
    payload = event["Payload"]  # NEW: unwrap once; all reads/writes happen on this, not on `event`
    bucket, key = payload["bucket"], payload["key"]  # "key" always points to whatever the previous step produced
    image_id = payload["imageId"]

    print(f"Resizing image {image_id} from s3://{bucket}/{key}")

    obj = s3.get_object(Bucket=bucket, Key=key)
    img = Image.open(io.BytesIO(obj["Body"].read()))
    img_format = img.format or "JPEG"

    resized = resize(img)  # unchanged — same pure PIL logic as before

    # NEW: build the output path in its own "folder" (prefix) instead of overwriting the original
    new_key = key.replace("fresh/", "resized/", 1)
    buf = io.BytesIO()
    resized.save(buf, format=img_format)
    s3.put_object(
        Bucket=bucket,
        Key=new_key,
        Body=buf.getvalue(),
        ContentType=FORMAT_TO_MIME.get(img_format, "application/octet-stream"),
    )

    # NEW: point the pipeline at the new file and leave a note about what happened here.
    # This must land on `payload`, not the outer `event` — otherwise the new key never
    # reaches the next state's event["Payload"]["key"] and downstream steps keep
    # reprocessing the original file.
    payload["key"] = new_key
    payload.setdefault("steps", {})["resize"] = {
        "status": "ok",
        "key": new_key,
        "width": resized.width,
        "height": resized.height,
    }

    # NEW: bump the tracking record's status — item already exists from validate.py, so update_item
    table.update_item(
        Key={"imageId": image_id},
        UpdateExpression="SET #s = :s",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": "resized"},
    )

    return payload  # NEW: return the flat payload, not the outer `event` wrapper