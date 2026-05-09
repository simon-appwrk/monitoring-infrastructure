# Dashboards

Grafana picks up dashboards from ConfigMaps labelled `grafana_dashboard=1` (see [../k8s/grafana/values.yaml](../k8s/grafana/values.yaml)).

## Layout convention

```
Infrastructure/         (admin folder)
├── Overview            — every host, every cluster, one screen
├── Nodes               — drill-down on node_exporter
└── Kubernetes          — kube-prometheus-stack default set

Projects/<project>/     (one folder per project, ACL'd to that team)
├── Overview            — service-level summary
├── Logs                — Loki Explore-style panels, $project pinned
├── Errors              — error rate + log error spike panels
└── Latency             — RED / USE for the project's services
```

## Starter dashboards to import (by ID, from grafana.com)

These give you a working baseline on day 1. Replace with bespoke dashboards as you learn what your projects actually need.

| Folder         | Dashboard                            | grafana.com ID |
|----------------|--------------------------------------|----------------|
| Infrastructure | Node Exporter Full                   | 1860           |
| Infrastructure | Kubernetes / Compute Resources / Cluster | 7249       |
| Infrastructure | Loki / Operational                   | 17781          |
| Infrastructure | Harbor                               | 14515          |
| Infrastructure | MinIO                                | 13502          |
| Projects/*     | Logs / Loki Logs Explorer (template) | 13639          |

Import once, modify, export JSON, drop into a ConfigMap:

```bash
kubectl create configmap dash-node-exporter \
  -n obs-metrics \
  --from-file=node-exporter.json=./infrastructure-overview.json
kubectl label configmap dash-node-exporter \
  -n obs-metrics grafana_dashboard=1
kubectl annotate configmap dash-node-exporter \
  -n obs-metrics grafana_folder=Infrastructure
```

## Per-project dashboard template

Every project dashboard MUST:

1. Set a constant variable `project` to the project name (no dropdown):
   ```
   Settings → Variables → New
     Type: Constant
     Name: project
     Value: payment-api
     Hide: variable
   ```
2. Use `$project` in every query: `{project="$project"}` for Loki, `up{project="$project"}` for Prometheus.
3. Live in the project's folder (Grafana ACL enforces visibility).

Place project dashboard JSONs under `dashboards/projects/<project>/`. Keep them in git so a project owner edits via PR, not via Grafana UI.
