# Runbook (Day-2 ops)

## Health checks (paste into a monitoring bookmark)

```
http://localhost:30090/-/healthy        Prometheus
http://localhost:30090/-/ready          Prometheus
http://localhost:30093/-/healthy        Alertmanager
http://localhost:30030/api/health       Grafana
http://localhost:30100/ready            Loki (push)
http://localhost:30101/ready            Loki (query)
http://localhost:30900/minio/health/ready  MinIO
http://localhost:30002/api/v2.0/health     Harbor (multi-component JSON)
```

Run from the k3s node itself. Externally, replace `localhost:<port>` with the Cloudflare hostname.

## "Nothing is showing in Grafana"

1. Is the data source healthy? Grafana → Connections → Data sources → Test.
2. Is Prometheus scraping? `http://localhost:30090/targets` → search the host.
3. If the host is missing: did Promtail/node_exporter actually start? SSH → `systemctl status node_exporter` / `docker ps | grep promtail`.
4. If targets are `up=0`: firewall? `nc -zv <node> 9100` from the Prometheus pod.
5. If logs are missing: `curl http://localhost:30100/ready` from the source host (or via cloudflared URL). If unreachable → tunnel routing or firewall.

## "Loki is slow / OOMing"

1. Check chunk store latency: Grafana → Explore → Loki → `{job="loki"} |= "level=error"`.
2. Cardinality: Loki dashboard → "Active series per tenant". If a label has unbounded values (`request_id`, `trace_id` as a label), find the offending Promtail config and move the field into the log line, not the label.
3. MinIO healthy? `mc admin info minio` from a maintenance pod.
4. Single-binary Loki not scaling? Drop retention from 7d to 3d in [k8s/loki/values.yaml](../k8s/loki/values.yaml).

## "Harbor push fails with 'unauthorized'"

1. `docker logout harbor.<domain> && docker login harbor.<domain>` — refreshes token.
2. Check Harbor → Projects → `<project>` → Members. User must be at least `Developer`.
3. If using OIDC: Keycloak group must match Harbor's group claim mapping.

## "Out of memory / pod evicted"

The node has 7.7Gi total. Steady-state we expect ~6–7Gi used. Mitigations in order:

1. `trivy.enabled: false` in [k8s/harbor/values.yaml](../k8s/harbor/values.yaml) → saves ~512Mi.
2. Drop Loki retention to 3d in [k8s/loki/values.yaml](../k8s/loki/values.yaml).
3. Drop Prometheus retention to 7d in [k8s/prometheus/values.yaml](../k8s/prometheus/values.yaml).
4. Move Harbor to a separate node.

## "Out of disk"

The node has 116Gi total, ~96Gi free at start. We allocate ~105Gi across PVCs. Mitigations:

1. Shrink Loki retention (chunks dominate).
2. Shrink Harbor MinIO bucket (delete unused image tags).
3. Add Harbor retention rules: Projects → `<project>` → Policy → Tag retention.

## Restarting components safely

| Component    | Safe to restart?                 | Notes                                    |
|--------------|----------------------------------|------------------------------------------|
| Grafana      | Yes, anytime                     | Sessions drop                            |
| Prometheus   | Yes, drains in-flight scrape     | TSDB compaction may pause; scrape gap ~30s |
| Alertmanager | Yes                              | Inflight notifications may dupe          |
| Loki         | Yes (single replica — ~30s gap)  | Brief log-write gap                      |
| MinIO        | Yes (standalone — ~30s gap)      | Loki + Harbor pause briefly              |
| Harbor       | Yes; brief registry downtime     |                                          |

## Backup policy

**There is none, by design.** This stack is monitoring-only and we accept full data loss on rebuild:

- Logs / metrics: lost = re-collect going forward.
- Image blobs: lost = re-push from CI / dev workstations.
- Dashboards: kept in git under [dashboards/](../dashboards/) — restore by re-applying ConfigMaps.
- Harbor projects + members: kept in git as desired-state config (TODO: terraform-harbor-provider or a small script).

If you ever decide you do need image-blob backup, set up MinIO bucket replication to S3-compatible offsite storage. Out of scope for the current design.

## Capacity rules of thumb

- Prometheus: ~1.5 GiB / 1M active series / day. At 15d retention + ~1M series, plan ~25 GiB.
- Loki: ~0.1–0.3 GiB / 1M log lines compressed. At 7d retention + moderate volume, plan ~30 GiB in MinIO.
- Harbor: image blobs dominate. Budget 10× the size of the largest image × tagged versions retained.

## Common tickets

- "Add a new project" → see [examples/project-onboarding/](../examples/project-onboarding/).
- "Add a new monitored host" → see [agents/README.md](../agents/README.md).
- "Add an alert" → see "Adding a new alert" in [alerting.md](alerting.md).
- "Onboard a new developer" → Keycloak group `proj-<name>-dev`. Grafana + Harbor pick it up via OIDC sync within 5 minutes.
