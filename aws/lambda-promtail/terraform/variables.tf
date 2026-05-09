variable "aws_access_key" {
  description = "AWS access key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret access key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "AWS region the log groups live in"
  type        = string
  default     = "us-east-1"
}

variable "loki_push_url" {
  description = "Public Loki push URL (cloudflared hostname), e.g. https://loki-push.example.com/loki/api/v1/push"
  type        = string
}

variable "log_group_names" {
  description = "CloudWatch Log Groups to ship to Loki. One subscription filter is created per group."
  type        = list(string)
  default     = []
}
