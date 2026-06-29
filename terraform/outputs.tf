output "aws_region" {
  value = var.aws_region
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnet_ids" {
  value = [for subnet in aws_subnet.private : subnet.id]
}

output "public_subnet_ids" {
  value = [for subnet in aws_subnet.public : subnet.id]
}

output "security_group_ids" {
  value = {
    public_alb    = aws_security_group.public_alb.id
    app_workload  = aws_security_group.app_workload.id
    aiops_worker  = aws_security_group.aiops_worker.id
    ai_engine     = aws_security_group.ai_engine.id
    integration   = aws_security_group.integration.id
    observability = aws_security_group.observability.id
    vpc_endpoints = aws_security_group.vpc_endpoints.id
  }
}

output "eks_cluster_name" {
  value = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "eks_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "incident_queue_url" {
  value = aws_sqs_queue.incident.url
}

output "incident_queue_arn" {
  value = aws_sqs_queue.incident.arn
}

output "incident_dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "incident_state_table_name" {
  value = aws_dynamodb_table.incident_state.name
}

output "audit_bucket_name" {
  value = aws_s3_bucket.audit.bucket
}

output "ingest_lambda_name" {
  value = aws_lambda_function.ingest_alert.function_name
}

output "ingest_lambda_function_url" {
  value = var.enable_ingest_lambda_function_url ? aws_lambda_function_url.ingest_alert[0].function_url : null
}

output "correlator_worker_role_arn" {
  value = aws_iam_role.correlator_worker.arn
}

output "ai_engine_role_arn" {
  value = aws_iam_role.ai_engine.arn
}

output "aws_load_balancer_controller_role_arn" {
  value = aws_iam_role.aws_load_balancer_controller.arn
}

output "runtime_secret_arns" {
  value = {
    for key, secret in aws_secretsmanager_secret.runtime : key => secret.arn
  }
}

output "ecr_repository_urls" {
  value = {
    for key, repo in aws_ecr_repository.repos : key => repo.repository_url
  }
}

output "cloudwatch_dashboard_name" {
  value = aws_cloudwatch_dashboard.pipeline.dashboard_name
}

output "alarms_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "kubectl_config_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}
