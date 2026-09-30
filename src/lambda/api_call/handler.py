"""api_call: REST API integration Lambda. Validates the authenticated user's
request, then invokes the access-models Lambda that performs semantic search
and generates the grounded answer (Retrieval Augmented Generation).
"""
import json
import os

import boto3

REGION = os.environ.get("REGION", "us-east-1")
ACCESS_MODELS_FUNCTION_NAME = os.environ["ACCESS_MODELS_FUNCTION_NAME"]

lambda_client = boto3.client(
    "lambda",
    region_name=REGION,
    endpoint_url="http://localhost:4566",
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Request body must be valid JSON."})

    prompt = body.get("prompt")
    if not prompt:
        return _response(400, {"error": "'prompt' is required."})

    invocation = lambda_client.invoke(
        FunctionName=ACCESS_MODELS_FUNCTION_NAME,
        InvocationType="RequestResponse",
        Payload=json.dumps({"prompt": prompt}).encode("utf-8"),
    )

    result = json.loads(invocation["Payload"].read())
    if "error" in result:
        return _response(400, result)

    return _response(200, result)


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(payload),
    }
