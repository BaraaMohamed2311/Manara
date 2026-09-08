import boto3
import io
from PIL import Image
import os

MAX_SIZE_MB = 10
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}
MAX_DIMENSION = 8000

FORMAT_TO_MIME = {"JPEG": "image/jpeg", "PNG": "image/png", "WEBP": "image/webp"}

s3 = boto3.client("s3")  # NEW: needed to read the resized image, the watermark file, and write the result
dynamodb = boto3.resource("dynamodb")  # NEW: needed to update the status-tracking record
table = dynamodb.Table("ImageMetadata")  # NEW: adjust table name to match your actual DynamoDB table

WATERMARK_KEY = os.environ.get("WATERMARK_KEY", "assets/watermark.png")  # fixed S3 location of your watermark image

# Cache the downloaded watermark PNG at module scope: it's a shared, unchanging
# asset (not per-image data), so on a warm Lambda invocation we can reuse the
# already-downloaded file instead of hitting S3 again every single time.
_wm_tmp_path = "/tmp/watermark.png"
_wm_downloaded = False


def watermark(image: Image.Image, watermark_path: str, opacity=0.5, margin=20) -> Image.Image:
    """Overlay a watermark image in the bottom-right corner."""
    base = image.convert("RGBA")
    wm = Image.open(watermark_path).convert("RGBA")

    # Scale watermark to ~20% of base width
    wm_width = int(base.width * 0.2)
    wm_ratio = wm_width / wm.width
    wm = wm.resize((wm_width, int(wm.height * wm_ratio)), Image.LANCZOS)

    # Apply opacity
    alpha = wm.split()[3].point(lambda p: int(p * opacity))
    wm.putalpha(alpha)

    position = (base.width - wm.width - margin, base.height - wm.height - margin)
    base.paste(wm, position, wm)

    return base.convert("RGB")


# NEW: this whole function is added — it's the part AWS Lambda actually calls.
def lambda_handler(event, context):
    """Load the resized image and the watermark PNG, stamp it, save under watermarked/, pass the event on."""
    payload = event["Payload"]  # NEW: unwrap once; all reads/writes happen on this, not on `event`
    bucket, key = payload["bucket"], payload["key"]
    image_id = payload["imageId"]

    print(f"Watermarking image {image_id} from s3://{bucket}/{key}")

    obj = s3.get_object(Bucket=bucket, Key=key)
    img = Image.open(io.BytesIO(obj["Body"].read()))
    img_format = img.format or "JPEG"

    # NEW: watermark() needs a local file path — download the watermark asset to
    # /tmp only if this container hasn't already fetched it (warm-start caching)
    global _wm_downloaded
    if not _wm_downloaded:
        s3.download_file(bucket, WATERMARK_KEY, _wm_tmp_path)
        _wm_downloaded = True

    watermarked = watermark(img, _wm_tmp_path)  # unchanged — same pure PIL logic as before

    new_key = key.replace("resized/", "watermarked/", 1)
    buf = io.BytesIO()
    watermarked.save(buf, format=img_format)
    s3.put_object(
        Bucket=bucket,
        Key=new_key,
        Body=buf.getvalue(),
        ContentType=FORMAT_TO_MIME.get(img_format, "application/octet-stream"),
    )

    # NEW: same reasoning as resize.py — write to `payload` so the new key actually
    # propagates to the next state's event["Payload"]["key"], not just this state's output.
    payload["key"] = new_key
    payload.setdefault("steps", {})["watermark"] = {"status": "ok", "key": new_key}

    # NEW: bump the tracking record's status
    table.update_item(
        Key={"imageId": image_id},
        UpdateExpression="SET #s = :s",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": "watermarked"},
    )

    return payload  # NEW: return the flat payload, not the outer `event` wrapper