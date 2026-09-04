output "ses_identity_arn" {
  value = aws_ses_email_identity.notification_sender.arn
}

output "from_email" {
  value = aws_ses_email_identity.notification_sender.email
}
