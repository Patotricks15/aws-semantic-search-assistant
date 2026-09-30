output "web_app_url" {
  description = "Public URL of the Assistant UI (Web app)."
  value       = aws_lambda_function_url.web_app.function_url
}

output "api_endpoint" {
  description = "Base URL of the semantic search REST API."
  value       = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.assistant.id}/${var.api_stage_name}/_user_request_"
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool used for authentication."
  value       = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  description = "ID of the Cognito app client."
  value       = aws_cognito_user_pool_client.web.id
}

output "knowledge_base_id" {
  description = "ID of the Bedrock knowledge base backing semantic search."
  value       = aws_bedrockagent_knowledge_base.assistant.id
}

output "enterprise_documents_bucket" {
  description = "Name of the S3 bucket holding enterprise documents."
  value       = aws_s3_bucket.enterprise_documents.bucket
}
