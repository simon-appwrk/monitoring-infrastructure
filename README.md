# Observability & Container Platform

Centralized monitoring, logging, alerting, and container registry for ~15 projects across cloud VMs, VPS servers, Docker hosts, and Kubernetes workloads.

Designed for a **single-node k3s** server, exposed via **NodePort**, fronted by **cloudflared tunnel** for external access. Identity via **Keycloak**.

## Stack

| Layer        | Component       | Purpose                                       |
|--------------|-----------------|-----------------------------------------------|
| Metrics      | Prometheus      | Scrape + store metrics (15d retention)        |
| Visualization| Grafana         | Dashboards, per-project access                |
| Alerting     | Alertmanager    | Route alerts to Email/Slack/Discord/Telegram  |
| Logs         | Loki            | Centralized log store (7d retention)          |
| Log shipping | Promtail        | Agent on VMs / Docker hosts / K8s             |
| Object store | MinIO           | Loki chunks + Harbor blobs (no backup — acceptable loss) |
| Registry     | Harbor          | Private images, scanning, RBAC, retention     |

## Layout

```
docs/        Architecture, RBAC, alerting, runbook, rollout
k8s/         Central stack (Helm values + manifests, NodePort)
  <comp>/values.yaml                  ← committed, public
  <comp>/values.secrets.example.yaml  ← committed, dummy values
  <comp>/values.secrets.local.yaml    ← GITIGNORED, real secrets (you create on the server)
agents/      Per-host bundles: docker-compose, systemd, ansible, k8s daemonset
alerting/    Prometheus + Loki rules
dashboards/  Grafana JSON dashboards
examples/    Project onboarding template
```

## Secrets workflow

Real secrets never enter git. The pattern, applied to every component that needs them:

1. Each component ships `values.secrets.example.yaml` with placeholder `CHANGEME` values — committed.
2. On the server, you copy that to `values.secrets.local.yaml` and fill in real values.
3. `install.sh` passes both files to Helm: `-f values.yaml -f values.secrets.local.yaml`.
4. `*.secrets.local.yaml` is in `.gitignore` and will never be committed.

The same pattern applies to raw K8s Secret manifests under `k8s/alertmanager/` (webhook URLs).

## Read in this order

1. [docs/architecture.md](docs/architecture.md) — what runs where, data flow
2. [docs/network-topology.md](docs/network-topology.md) — NodePort assignments + cloudflared layout
3. [docs/access-control.md](docs/access-control.md) — admin vs. developer RBAC model
4. [docs/rollout-plan.md](docs/rollout-plan.md) — phased rollout
5. [k8s/README.md](k8s/README.md) — install central stack (with secrets workflow)
6. [agents/README.md](agents/README.md) — onboard a host
7. [examples/project-onboarding/README.md](examples/project-onboarding/README.md) — onboard project #N

## Resource fit

The single-node target is **7.7Gi RAM / 116Gi disk**. With current sizing the stack uses ~6–7Gi RAM at steady state. If you hit OOM:

- Disable Harbor Trivy scanner (saves ~512Mi): `trivy.enabled: false` in [k8s/harbor/values.yaml](k8s/harbor/values.yaml).
- Drop Loki retention to 3d.
- Drop Prometheus retention to 7d.

If you outgrow the box, scale Harbor off first — it's the heaviest component and the most independent.
