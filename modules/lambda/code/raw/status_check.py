import json
import os
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["TABLE_NAME"]
table = dynamodb.Table(TABLE_NAME)


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def lambda_handler(event, context):


    query_params = event.get("queryStringParameters") or {}
    imageId = query_params.get("imageId")

    if not imageId:
        return _response(400, {"error": "Missing imageId query parameter"})

    try:
        result = table.get_item(
            Key={"imageId": imageId},
            ProjectionExpression="#s",
            ExpressionAttributeNames={"#s": "status"},
        )
    except ClientError as e:
        return _response(500, {"error": e.response["Error"]["Message"]})

    item = result.get("Item")
    if not item:
        return _response(404, {"error": "No item found for imageId: " + imageId})

    return _response(200, {"imageId": imageId, "status": item.get("status")})