# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA MODULE: OUTPUTS
# ---------------------------------------------------------------------------------------------------------------------

output "lambda_function_arns" {
  description = "ARNs of the Lambda functions."
  value       = { for k, v in aws_lambda_function.cdc : k => v.arn }
}

output "lambda_function_names" {
  description = "Names of the Lambda functions."
  value       = { for k, v in aws_lambda_function.cdc : k => v.function_name }
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role."
  value       = aws_iam_role.lambda.arn
}

output "dlq_arn" {
  description = "ARN of the dead letter queue."
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  description = "URL of the dead letter queue."
  value       = aws_sqs_queue.dlq.url
}

output "eventbridge_rule_arns" {
  description = "ARNs of the EventBridge rules."
  value       = { for k, v in aws_cloudwatch_event_rule.cdc_schedule : k => v.arn }
}

output "layer_arn" {
  description = "ARN of the Lambda layer."
  value       = aws_lambda_layer_version.dependencies.arn
}
