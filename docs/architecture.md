# Architecture

## Goals (and what we're explicitly avoiding)

**Goals:** centralized observability, centralized image management, project-level access control, operational simplicity, easy debugging.

**Avoiding:** service mesh, ingress controllers in front of monitoring, cluster-internal-only services, multi-cluster federation.

> Services are exposed on **NodePort** so any operator can `curl localhost:<port>` on the node and see the same thing the platform sees. External access is fronted by **cloudflared tunnel** (no public ports). No magic.

## Component layout

```
                        ┌──────────────────────────────────────────────┐
                        │         Single-node k3s (7.7Gi, 116Gi)       │
                        │                                              │
   Cloud VMs ───┐       │  ┌──────────────┐   ┌──────────────────┐    │
   VPS hosts ───┼──────►│  │  Prometheus  │◄──┤ kube-state-      │    │
   Docker hosts ┘       │  │  (15d hot)   │   │ metrics, cAdvisor│    │
        │               │  └──────┬───────┘   └──────────────────┘    │
        │ node_exporter │         │                                    │
        │ cadvisor      │         ▼                                    │
        │ promtail      │  ┌──────────────┐   ┌──────────────────┐    │
        │               │  │ Alertmanager │──►│ Email/Slack/     │    │
        ▼ (push)        │  └──────────────┘   │ Discord/Telegram │    │
   ┌─────────────┐      │         ▲           └──────────────────┘    │
   │   Loki      │◄─────┼─── Promtail (push, via cloudflared)         │
   │   (7d)      │──────┼──► MinIO (S3) ◄──── Harbor (registry blobs) │
   └─────────────┘      │                                              │
        ▲               │  ┌──────────────┐                            │
        │               │  │   Grafana    │ ── reads Prom + Loki      │
        │               │  └──────────────┘                            │
        │               │                                              │
   K8s workloads ───────┼──► Promtail DaemonSet ──► Loki              │
                        │                                              │
                        │   ┌──────────────┐                           │
                        │   │ cloudflared  │ ── outbound tunnel        │
                        │   └──────────────┘                           │
                        └──────────────────────────────────────────────┘
                                                ▲
                                                │ HTTPS
                                                │
                                          Operators / Developers
                                          (browser, docker CLI, CI/CD)
```

## Data flow

### Metrics
1. `node_exporter` runs on every monitored host (systemd or container).
2. `cadvisor` runs on every Docker host.
3. The k3s node exposes kubelet/cAdvisor metrics natively; `kube-state-metrics` runs in-cluster.
4. Prometheus scrapes everything via `static_configs` (VMs/VPS) + `kubernetes_sd_configs` (in-cluster).
5. Application metrics: apps expose `/metrics`, Prometheus scrapes them via the same configs (label `project=` is the multi-tenant key).
6. Retention: **15 days**.

### Logs
1. Promtail runs on every host (systemd binary, Docker container, or K8s DaemonSet).
2. Promtail tails `/var/log/*`, Docker `json-file` logs, and K8s pod logs.
3. **Required labels** on every stream: `project`, `environment`, `team`. Optional: `service`, `severity`.
4. Promtail pushes to Loki via the cloudflared tunnel (`https://loki-push.example.com`) or directly to NodePort `:30100` from inside the network.
5. Loki stores chunks in MinIO (S3 API). Retention: **7 days**.

### Alerts
1. Prometheus evaluates rules in `alerting/*.yml`; firing alerts go to Alertmanager.
2. Loki ruler evaluates `alerting/log-based.yml`; firing alerts go to the same Alertmanager.
3. Alertmanager routes by `project` / `environment` / `severity` / `team` labels (see [alerting.md](alerting.md)).

### Images
1. Developers `docker login harbor.example.com` (cloudflared tunnel) and push to `harbor.example.com/<project>/<image>:<tag>`.
2. Harbor scans on push (Trivy), enforces project RBAC, applies retention.
3. K8s + Docker hosts pull via the same URL.

## Storage assumptions

Storage class everywhere is **`local-path`** (k3s default).

| Component   | PVC size | Notes                                              |
|-------------|----------|----------------------------------------------------|
| Prometheus  | 30 GiB   | 15d retention, ~1.5 GiB/day at expected volume     |
| Loki        | 5 GiB    | Cache only; chunks live in MinIO                   |
| MinIO       | 50 GiB   | Loki chunks + Harbor blobs combined                |
| Harbor DB   | 10 GiB   | Internal Postgres                                  |
| Harbor Redis| 5 GiB    |                                                    |
| Grafana     | 5 GiB    | Dashboards + sqlite users; back up dashboards via git |

**Total disk**: ~105 GiB requested. Available: 96 GiB. **Tight** — see [README.md](../README.md#resource-fit) for what to drop if you run out.

## No-backup policy

Per design decision: this stack is **monitoring-only**. We accept full data loss on rebuild:
- MinIO buckets (logs, image blobs): lost = re-push images, re-collect logs going forward.
- Prometheus TSDB: lost = recent metrics gone, no historical impact.
- Grafana dashboards: keep them in git under [dashboards/](../dashboards/), restore by re-applying the ConfigMaps.
- Harbor DB: lost = re-create projects + members (or rebuild from a recent `pg_dump` if you choose to).

The single piece worth backing up is the **dashboards JSON**, which is in this repo already.

## Multi-tenancy model

We do **not** run a Grafana per project. We run **one Grafana** with:
- One folder per project (`payment-api`, `auth-service`, …)
- Grafana teams scoped to folders (Viewer)
- A single admin team with full Editor/Admin
- Loki/Prometheus datasources with `org-wide` access; project isolation is enforced by **dashboard variables fixed to `project=<name>`** + folder permissions, not by per-tenant datasources.

This is a deliberate trade-off: Grafana folder RBAC is easy to operate; full multi-tenant Loki (X-Scope-OrgID) is rejected as too complex for 15 projects. See [access-control.md](access-control.md) for the threat model that justifies this.

## What an operator sees on day 1

1. SSH to the node → `curl localhost:30090/-/healthy` (Prometheus), `curl localhost:30100/ready` (Loki).
2. Open `https://grafana.example.com` (cloudflared) → log in via Keycloak.
3. Navigate to "Infrastructure / Overview" dashboard → see every host green/red.
4. Open "Alerts" → see firing alerts grouped by project.
5. `docker pull harbor.example.com/library/hello-world` works.
