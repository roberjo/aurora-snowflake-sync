# ---------------------------------------------------------------------------------------------------------------------
# LAMBDA MODULE: EVENTBRIDGE SCHEDULED TRIGGERS
# ---------------------------------------------------------------------------------------------------------------------
# Creates EventBridge rules to trigger Lambda functions on schedule.

resource "aws_cloudwatch_event_rule" "cdc_schedule" {
  for_each = var.table_definitions

  name                = "${var.project_name}-cdc-${lower(replace(each.key, "_", "-"))}"
  description         = "Trigger CDC export for ${each.key}"
  schedule_expression = each.value.schedule_expression

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "cdc_lambda" {
  for_each = var.table_definitions

  rule      = aws_cloudwatch_event_rule.cdc_schedule[each.key].name
  target_id = "cdc-lambda-${each.key}"
  arn       = aws_lambda_function.cdc[each.key].arn

  input = jsonencode({
    table_name = each.key
  })

  retry_policy {
    maximum_event_age_in_seconds = 3600  # 1 hour
    maximum_retry_attempts       = 2
  }
}

resource "aws_lambda_permission" "eventbridge" {
  for_each = var.table_definitions

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cdc[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cdc_schedule[each.key].arn
}
