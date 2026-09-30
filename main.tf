# ─── S3: enterprise documents (semantic search source) ──────────────────────

resource "aws_s3_bucket" "enterprise_documents" {
  bucket = "${local.name_prefix}-${var.enterprise_documents_bucket_name}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.enterprise_documents_bucket_name}"
  })
}

resource "aws_s3_bucket_public_access_block" "enterprise_documents" {
  bucket = aws_s3_bucket.enterprise_documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── OpenSearch Serverless: vector database backing the knowledge base ──────

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${local.name_prefix}-kb-encryption"
  type = "encryption"

  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${local.name_prefix}-kb"]
    }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name = "${local.name_prefix}-kb-network"
  type = "network"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.name_prefix}-kb"]
      },
      {
        ResourceType = "dashboard"
        Resource     = ["collection/${local.name_prefix}-kb"]
      },
    ]
    AllowFromPublic = true
  }])
}

resource "aws_opensearchserverless_access_policy" "data" {
  name = "${local.name_prefix}-kb-access"
  type = "data"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.name_prefix}-kb"]
        Permission   = ["aoss:*"]
      },
      {
        ResourceType = "index"
        Resource     = ["index/${local.name_prefix}-kb/*"]
        Permission   = ["aoss:*"]
      },
    ]
    Principal = [aws_iam_role.bedrock_kb.arn]
  }])

  depends_on = [aws_iam_role.bedrock_kb]
}

resource "aws_opensearchserverless_collection" "kb" {
  name = "${local.name_prefix}-kb"
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]

  tags = local.common_tags
}

# ─── IAM: role assumed by the Bedrock knowledge base ─────────────────────────

resource "aws_iam_role" "bedrock_kb" {
  name = "${local.name_prefix}-bedrock-kb"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "bedrock.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "bedrock_kb_s3" {
  name = "${local.name_prefix}-bedrock-kb-s3"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.enterprise_documents.arn, "${aws_s3_bucket.enterprise_documents.arn}/*"]
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_kb_embed" {
  name = "${local.name_prefix}-bedrock-kb-embed"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_kb_aoss" {
  name = "${local.name_prefix}-bedrock-kb-aoss"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aoss:APIAccessAll"]
      Resource = aws_opensearchserverless_collection.kb.arn
    }]
  })
}

# ─── Bedrock: knowledge base over the enterprise documents (semantic search) ─

resource "aws_bedrockagent_knowledge_base" "assistant" {
  name     = "${local.name_prefix}-kb"
  role_arn = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"

    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = var.vector_index_name

      field_mapping {
        vector_field   = "embedding"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }

  depends_on = [
    aws_opensearchserverless_access_policy.data,
    aws_iam_role_policy.bedrock_kb_s3,
    aws_iam_role_policy.bedrock_kb_embed,
    aws_iam_role_policy.bedrock_kb_aoss,
  ]

  tags = local.common_tags
}

resource "aws_bedrockagent_data_source" "enterprise_documents" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.assistant.id
  name              = "${local.name_prefix}-enterprise-documents"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn = aws_s3_bucket.enterprise_documents.arn
    }
  }
}

# ─── Cognito User Pool (authentication) ──────────────────────────────────────

resource "aws_cognito_user_pool" "main" {
  name = "${local.name_prefix}-${var.cognito_user_pool_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
  }

  tags = local.common_tags
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.name_prefix}-web-client"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

# ─── IAM role shared by the assistant's Lambda functions ─────────────────────

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_bedrock" {
  name = "${local.name_prefix}-lambda-bedrock"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:Retrieve"]
        Resource = aws_bedrockagent_knowledge_base.assistant.arn
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.generation_model_id}"
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_invoke_access_models" {
  name = "${local.name_prefix}-lambda-invoke-access-models"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.access_models.arn
    }]
  })
}

# ─── Lambda: access-models (semantic search + AI model) ──────────────────────

resource "null_resource" "access_models_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/access_models/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} access_models"
  }
}

data "archive_file" "access_models_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/access_models/handler.py"
  output_path = "${path.module}/.build/access_models.zip"

  depends_on = [null_resource.access_models_package]
}

resource "aws_lambda_function" "access_models" {
  function_name = "${local.name_prefix}-access-models"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.access_models_zip.output_path
  source_code_hash = data.archive_file.access_models_zip.output_base64sha256

  environment {
    variables = {
      REGION              = var.aws_region
      KNOWLEDGE_BASE_ID   = aws_bedrockagent_knowledge_base.assistant.id
      GENERATION_MODEL_ID = var.generation_model_id
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-access-models"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_bedrock,
  ]
}

# ─── Lambda: api-call (REST API integration) ─────────────────────────────────

resource "null_resource" "api_call_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/api_call/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} api_call"
  }
}

data "archive_file" "api_call_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/api_call/handler.py"
  output_path = "${path.module}/.build/api_call.zip"

  depends_on = [null_resource.api_call_package]
}

resource "aws_lambda_function" "api_call" {
  function_name = "${local.name_prefix}-api-call"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.api_call_zip.output_path
  source_code_hash = data.archive_file.api_call_zip.output_base64sha256

  environment {
    variables = {
      REGION                       = var.aws_region
      ACCESS_MODELS_FUNCTION_NAME  = aws_lambda_function.access_models.function_name
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-call"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_invoke_access_models,
  ]
}

# ─── API Gateway: REST API + Cognito authorizer ──────────────────────────────

resource "aws_api_gateway_rest_api" "assistant" {
  name        = "${local.name_prefix}-${var.api_name}"
  description = "REST API that lets the assistant's web app submit domain-specific questions for RAG-grounded answers."

  tags = local.common_tags
}

resource "aws_api_gateway_resource" "search" {
  rest_api_id = aws_api_gateway_rest_api.assistant.id
  parent_id   = aws_api_gateway_rest_api.assistant.root_resource_id
  path_part   = "search"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "${local.name_prefix}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.assistant.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn]
}

resource "aws_api_gateway_method" "post_search" {
  rest_api_id   = aws_api_gateway_rest_api.assistant.id
  resource_id   = aws_api_gateway_resource.search.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "post_search" {
  rest_api_id             = aws_api_gateway_rest_api.assistant.id
  resource_id             = aws_api_gateway_resource.search.id
  http_method             = aws_api_gateway_method.post_search.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_call.invoke_arn
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke-api-call"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_call.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.assistant.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.assistant.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_integration.post_search,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.post_search,
  ]
}

resource "aws_api_gateway_stage" "v1" {
  rest_api_id   = aws_api_gateway_rest_api.assistant.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = var.api_stage_name

  tags = local.common_tags
}

# ─── Lambda: web-app (Assistant UI, Function URL) ───────────────────────────

resource "null_resource" "web_app_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/web_app/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} web_app"
  }
}

data "archive_file" "web_app_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/web_app/handler.py"
  output_path = "${path.module}/.build/web_app.zip"

  depends_on = [null_resource.web_app_package]
}

resource "aws_lambda_function" "web_app" {
  function_name = "${local.name_prefix}-web-app"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.web_app_zip.output_path
  source_code_hash = data.archive_file.web_app_zip.output_base64sha256

  environment {
    variables = {
      API_ENDPOINT         = "http://localhost:4566/restapis/${aws_api_gateway_rest_api.assistant.id}/${var.api_stage_name}/_user_request_"
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.web.id
      PROJECT_NAME         = var.project_name
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web-app"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
  ]
}

resource "aws_lambda_function_url" "web_app" {
  function_name      = aws_lambda_function.web_app.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["GET"]
  }
}
