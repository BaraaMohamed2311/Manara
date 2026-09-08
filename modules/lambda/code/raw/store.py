import boto3
import io
from PIL import Image
import os

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("ImageMetadata")

FORMAT_TO_MIME = {"JPEG": "image/jpeg", "PNG": "image/png", "WEBP": "image/webp"}


def store(image: Image.Image, output_path: str, quality=85) -> str:
    """Save the final image to disk."""
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    fmt = image.format or "JPEG"  # PIL can't infer format from an extension-less/unknown path
    image.save(output_path, format=fmt, quality=quality, optimize=True)
    return output_path


def lambda_handler(event, context):
    """Load the watermarked image, save it to /tmp, then upload it to the final/ location in S3."""
    payload = event["Payload"]
    bucket, key = payload["bucket"], payload["key"]
    image_id = payload["imageId"]

    print(f"Storing final image {image_id} from s3://{bucket}/{key}")

    obj = s3.get_object(Bucket=bucket, Key=key)
    img = Image.open(io.BytesIO(obj["Body"].read()))

    # Ensure tmp_path has an extension even if the S3 key doesn't
    base = os.path.basename(key)
    name, ext = os.path.splitext(base)
    if not ext:
        ext = "." + (img.format or "JPEG").lower().replace("jpeg", "jpg")
    tmp_path = "/tmp/" + name + ext

    store(img, tmp_path)

    new_key = key.replace("watermarked/", "final/", 1)
    s3.upload_file(
        tmp_path,
        bucket,
        new_key,
        ExtraArgs={"ContentType": FORMAT_TO_MIME.get(img.format, "application/octet-stream")},
    )

    payload["key"] = new_key
    payload["final_key"] = new_key
    payload.setdefault("steps", {})["store"] = {"status": "ok", "key": new_key}

    table.update_item(
        Key={"imageId": image_id},
        UpdateExpression="SET #s = :s, finalKey = :k",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": "done", ":k": new_key},
    )

    return payload