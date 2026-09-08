import json
import os
import uuid
import urllib.parse
import boto3

sfn = boto3.client('stepfunctions')
STATE_MACHINE_ARN = os.environ['STATE_MACHINE_ARN']

def lambda_handler(event, context):
    batch_item_failures = []

    for record in event['Records']:
        message_id = record['messageId']
        try:
            body = json.loads(record['body'])

            # body is a native S3 event notification (S3 -> SQS)
            s3_record = body['Records'][0]['s3']
            bucket = s3_record['bucket']['name']
            key = urllib.parse.unquote_plus(s3_record['object']['key'])
            image_id = key.split("/")[-1]

            print(f"Starting execution for message {message_id}: s3://{bucket}/{key}")

            sfn_input = {
                "bucket": bucket,
                "key": key,
                "imageId": image_id,
            }

            execution_name = message_id

            sfn.start_execution(
                stateMachineArn=STATE_MACHINE_ARN,
                name=execution_name,
                input=json.dumps(sfn_input)
            )

        except sfn.exceptions.ExecutionAlreadyExists:
            continue
        except Exception as e:
            print(f"Failed to start execution for message {message_id}: {e}")
            batch_item_failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": batch_item_failures}