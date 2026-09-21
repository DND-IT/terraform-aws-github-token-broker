locals {
  create_alarm = var.cloudtrail_log_group_name != null

  signer_exclusions = join(" && ", [
    for arn in local.signer_role_arns : "($.userIdentity.sessionContext.sessionIssuer.arn != \"${arn}\")"
  ])
}

resource "aws_cloudwatch_log_metric_filter" "unexpected_signer" {
  count = local.create_alarm ? length(local.key_arns) : 0

  name           = "${var.name}-unexpected-signer-${count.index}"
  log_group_name = var.cloudtrail_log_group_name
  pattern        = "{ ($.eventSource = \"kms.amazonaws.com\") && ($.eventName = \"Sign\") && ($.resources[0].ARN = \"${local.key_arns[count.index]}\") && (($.userIdentity.sessionContext.sessionIssuer.arn NOT EXISTS) || (${local.signer_exclusions})) }"

  metric_transformation {
    name      = "${var.name}-unexpected-signer"
    namespace = "GitHubAppBroker"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "unexpected_signer" {
  count = local.create_alarm ? 1 : 0

  alarm_name          = "${var.name}-unexpected-signer"
  alarm_description   = "A principal other than the broker roles called kms:Sign on the ${var.name} GitHub App key."
  namespace           = "GitHubAppBroker"
  metric_name         = "${var.name}-unexpected-signer"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags

  depends_on = [aws_cloudwatch_log_metric_filter.unexpected_signer]
}
