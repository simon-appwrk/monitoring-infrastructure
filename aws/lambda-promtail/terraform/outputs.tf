output "lambda_arn" {
  value = aws_lambda_function.promtail.arn
}

output "subscribed_log_groups" {
  value = var.log_group_names
}
