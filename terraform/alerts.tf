# SNS topic for backup and infrastructure alerts

resource "aws_sns_topic" "alerts" {
  name = "infosec-mgr-alerts"

  tags = {
    Name = "infosec-mgr-alerts"
  }
}

# Email subscription for admin alerts
resource "aws_sns_topic_subscription" "admin_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

output "sns_topic_arn" {
  description = "ARN of the SNS alerts topic"
  value       = aws_sns_topic.alerts.arn
}
