output "detector_id" {
  value = aws_guardduty_detector.cloudmart.id
}

output "detector_arn" {
  value = aws_guardduty_detector.cloudmart.arn
}

output "alerts_topic_arn" {
  value = aws_sns_topic.guardduty_alerts.arn
}

output "email_subscription_arn" {
  value = aws_sns_topic_subscription.email.arn
}
