# CloudWatch Logs → Loki

Deploys [Grafana's lambda-promtail](https://github.com/grafana/loki/tree/main/tools/lambda-promtail) into your AWS account. CloudWatch Log Groups → subscription filter → Lambda → POST to your Loki push URL via cloudflared.

## Use

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — paste AWS keys, set Loki URL, list Log Groups

terraform init
terraform apply
```

## What you set in `terraform.tfvars`

| Variable          | What                                        |
|-------------------|---------------------------------------------|
| `aws_access_key`  | Access key for an IAM user with Lambda + IAM + CloudWatch Logs permissions |
| `aws_secret_key`  | Matching secret                             |
| `region`          | Region the Log Groups live in               |
| `loki_push_url`   | `https://loki-push.<your-domain>/loki/api/v1/push` |
| `log_group_names` | List of Log Groups to ship                  |

To add more log groups later: edit `log_group_names` in `terraform.tfvars` and re-run `terraform apply`.

## IAM user

Create an IAM user (in AWS Console → IAM → Users) with this minimal inline policy, then put its access key + secret in `terraform.tfvars`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole", "iam:GetRole", "iam:DeleteRole",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PassRole",
        "lambda:*",
        "logs:PutSubscriptionFilter", "logs:DescribeSubscriptionFilters",
        "logs:DeleteSubscriptionFilter", "logs:DescribeLogGroups"
      ],
      "Resource": "*"
    }
  ]
}
```

## Removing

```bash
terraform destroy
```

The original CloudWatch Logs are unaffected.

## Notes

- `terraform.tfvars` is gitignored — your AWS keys never enter git.
- The Lambda runs in **your AWS account**, not in your k3s cluster.
- For multi-region: copy this directory per region, set `region` differently in each.
