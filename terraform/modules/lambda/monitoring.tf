# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA MODULE: CLOUDWATCH ALARMS
# ---------------------------------------------------------------------------------------------------------------------
# Creates CloudWatch alarms for Lambda function monitoring.

# Lambda Error Alarm (per function)
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = var.table_definitions

  alarm_name          = "${var.project_name}-cdc-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.cdc[each.key].function_name
  }

  alarm_description = "Lambda errors for CDC table ${each.key}"
  alarm_actions     = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions        = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

# Lambda Duration Alarm (per function) - warn if approaching timeout
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = var.table_definitions

  alarm_name          = "${var.project_name}-cdc-${each.key}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Maximum"
  threshold           = each.value.timeout_seconds * 800 # 80% of timeout in milliseconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.cdc[each.key].function_name
  }

  alarm_description = "Lambda duration approaching timeout for CDC table ${each.key}"
  alarm_actions     = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

# DLQ Messages Alarm
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.project_name}-cdc-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_description = "Messages in CDC DLQ indicate failed Lambda invocations"
  alarm_actions     = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

# Invocations alarm - detect if Lambda stopped being invoked
resource "aws_cloudwatch_metric_alarm" "lambda_invocations" {
  for_each = var.table_definitions

  alarm_name          = "${var.project_name}-cdc-${each.key}-no-invocations"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Invocations"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    FunctionName = aws_lambda_function.cdc[each.key].function_name
  }

  alarm_description = "No Lambda invocations for CDC table ${each.key} in 15 minutes"
  alarm_actions     = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}
