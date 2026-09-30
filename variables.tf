variable "project_name" {
  description = "Project name used as prefix for all resources."
  type        = string
  default     = "floci-semantic-search"
}

variable "aws_region" {
  description = "AWS region (simulated by floci)."
  type        = string
  default     = "us-east-1"
}

variable "enterprise_documents_bucket_name" {
  description = "Name of the S3 bucket holding enterprise documents (semantic search source)."
  type        = string
  default     = "enterprise-documents"
}

variable "embedding_model_id" {
  description = "Bedrock foundation model id used to embed documents for the vector database."
  type        = string
  default     = "amazon.titan-embed-text-v1"
}

variable "generation_model_id" {
  description = "Bedrock foundation model id used to generate grounded answers."
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "vector_index_name" {
  description = "Name of the vector index inside the OpenSearch Serverless collection."
  type        = string
  default     = "assistant-index"
}

variable "cognito_user_pool_name" {
  description = "Name of the Cognito User Pool used to authenticate assistant users."
  type        = string
  default     = "assistant-users"
}

variable "api_name" {
  description = "Name of the REST API Gateway that fronts the assistant."
  type        = string
  default     = "semantic-search-api"
}

variable "api_stage_name" {
  description = "Deployment stage name for the API Gateway."
  type        = string
  default     = "v1"
}
