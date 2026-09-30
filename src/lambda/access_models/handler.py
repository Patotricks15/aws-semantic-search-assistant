"""access_models: performs semantic search over the enterprise knowledge base
(Amazon Bedrock knowledge base backed by an OpenSearch Serverless vector
database), then augments the user's prompt with the retrieved context and
generates a grounded answer with a Bedrock foundation model.
"""
import json
import os

import boto3

REGION = os.environ.get("REGION", "us-east-1")
KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
GENERATION_MODEL_ID = os.environ["GENERATION_MODEL_ID"]

_ENDPOINT_KWARGS = {
    "endpoint_url": "http://localhost:4566",
    "aws_access_key_id": "test",
    "aws_secret_access_key": "test",
}

bedrock_agent_runtime = boto3.client("bedrock-agent-runtime", region_name=REGION, **_ENDPOINT_KWARGS)
bedrock_runtime = boto3.client("bedrock-runtime", region_name=REGION, **_ENDPOINT_KWARGS)


def lambda_handler(event, context):
    prompt = (event or {}).get("prompt")
    if not prompt:
        return {"error": "'prompt' is required."}

    retrieved_chunks = _semantic_search(prompt)
    answer = _generate_answer(prompt, retrieved_chunks)

    return {"answer": answer, "retrieved_chunks": retrieved_chunks}


def _semantic_search(prompt):
    """Query the vector database for the passages most relevant to the prompt."""
    response = bedrock_agent_runtime.retrieve(
        knowledgeBaseId=KNOWLEDGE_BASE_ID,
        retrievalQuery={"text": prompt},
        retrievalConfiguration={
            "vectorSearchConfiguration": {"numberOfResults": 5},
        },
    )
    return [
        result.get("content", {}).get("text", "")
        for result in response.get("retrievalResults", [])
    ]


def _generate_answer(prompt, retrieved_chunks):
    """Call the AI model with the prompt plus retrieved data (RAG)."""
    context = "\n\n".join(retrieved_chunks) or "No relevant enterprise documents were found."

    augmented_prompt = (
        "Answer the question using only the context below. "
        "If the answer isn't in the context, say you don't know.\n\n"
        f"Context:\n{context}\n\nQuestion: {prompt}"
    )

    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 512,
        "messages": [{"role": "user", "content": augmented_prompt}],
    })

    response = bedrock_runtime.invoke_model(
        modelId=GENERATION_MODEL_ID,
        body=body,
        contentType="application/json",
        accept="application/json",
    )

    payload = json.loads(response["body"].read())
    content = payload.get("content", [])
    return content[0]["text"] if content else ""
