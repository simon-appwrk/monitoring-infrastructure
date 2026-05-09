# CloudWatch metrics → Prometheus

Pulls AWS CloudWatch metrics into your Prometheus via [YACE](https://github.com/nerdswords/yet-another-cloudwatch-exporter) (Yet Another CloudWatch Exporter). Tag-based discovery: new AWS resources with the right tags get scraped automatically.

**When to enable:** when you have AWS workloads and want their RDS / ALB / SQS / EBS / Lambda / etc. metrics in Grafana alongside everything else. Skip if you have no AWS.

## Prereqs

1. An AWS IAM user (or role) with the policy in [iam-policy.json](iam-policy.json).
2. Tag your AWS resources with at least:
   - `project=<name>` (matches your Grafana folder)
   - `environment=production|staging|dev`
   - `team=<owning-team>`
3. The k3s node has outbound HTTPS to AWS (it does — same path cloudflared uses).

## Install

```bash
# 1. Create the AWS creds secret
cp values.secrets.example.yaml values.secrets.local.yaml
# edit: paste real AWS access key + secret
kubectl -n obs-metrics create secret generic yace-aws-creds \
  --from-literal=AWS_ACCESS_KEY_ID="$(yq -r '.aws.accessKeyId' values.secrets.local.yaml)" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$(yq -r '.aws.secretAccessKey' values.secrets.local.yaml)" \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Create the YACE config ConfigMap
cp yace-config.example.yaml yace-config.local.yaml
# edit: pick which AWS services + regions to scrape
kubectl -n obs-metrics create configmap yace-config \
  --from-file=config.yml=yace-config.local.yaml \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Install the chart
helm repo add nerdswords https://nerdswords.github.io/helm-charts
helm upgrade --install yace nerdswords/yet-another-cloudwatch-exporter \
  -n obs-metrics -f values.yaml --wait
```

## Wire Prometheus to scrape it

Add this job to [../prometheus/additional-scrape-configs.example.yaml](../prometheus/additional-scrape-configs.example.yaml) (or your `.local.yaml` copy), then re-create the secret and roll Prometheus:

```yaml
- job_name: 'cloudwatch-yace'
  static_configs:
    - targets: ['yace-yet-another-cloudwatch-exporter.obs-metrics.svc:5000']
      labels:
        # YACE injects per-resource labels (project, environment, team) from AWS tags
        host_class: aws
```

The metric labels (`project`, `environment`, `team`) come straight from AWS tags via YACE's tag-based discovery — same labels as everything else in the stack.

## Verify

```bash
# YACE itself reports metrics it has scraped
kubectl -n obs-metrics port-forward svc/yace-yet-another-cloudwatch-exporter 5000:5000
curl http://localhost:5000/metrics | head -50

# In Prometheus UI: query aws_rds_cpuutilization_average{project="<your-project>"}
```

## Cost

CloudWatch GetMetricData calls cost ~$0.01 per 1000 calls. YACE batches; default scrape interval (5 min) over ~50 metrics × 10 instances = ~30 calls/scrape = $0.0003/scrape × 288 scrapes/day = ~$0.10/day. Tune scrape interval up if you have a lot of resources.

## Removing

```bash
helm uninstall yace -n obs-metrics
kubectl -n obs-metrics delete configmap yace-config
kubectl -n obs-metrics delete secret yace-aws-creds
```

Then remove the `cloudwatch-yace` job from `additional-scrape-configs`.
