# Host agents — onboard a monitored host

A monitored host runs:
- `node_exporter` (always) — host metrics
- `cadvisor` (only on Docker hosts) — container metrics
- `promtail` (always) — log shipping

Three deployment styles are provided. Pick the one that matches the host:

| Host type            | Use                                          |
|----------------------|----------------------------------------------|
| Linux VM / VPS       | [systemd/](systemd/) — native binaries       |
| Docker host          | [docker-compose/](docker-compose/) — agents as containers |
| K8s cluster (worker) | [k8s-promtail/](k8s-promtail/) — DaemonSet  |
| Many hosts at once   | [ansible/](ansible/) — one playbook         |

## Prereqs (every host)

- Reachable from cluster nodes on port `9100` (node_exporter scrape)
- Can reach the cluster on `:30100` (Loki push) and `:30090` if scraping over reverse direction (we use pull, so usually not needed)

## Required labels on every Promtail config

```yaml
# In static_configs.labels OR in pipeline_stages with stage_labels
project: <project-name>      # one of the 15 projects, or 'infra'
environment: production|staging|dev
team: <owning-team>
host: ${HOSTNAME}            # auto-populated by Promtail
host_class: cloud-vm|vps|docker-host|k8s-node
```

A host with the wrong labels will still ship logs, but they will land in the
unrouted bucket and developers won't see them in their dashboards. CI for the
ansible roles validates these labels before deploy.

## After onboarding — verify

```bash
# On the central K8s cluster
curl -s http://<node>:30090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.instance | contains("<new-host>"))'

# Or in Grafana → Explore → Loki:
{host="<new-host>"}
```

If both return data within 60s, the host is onboarded.

## Removing a host

1. Stop services: `systemctl disable --now node_exporter promtail` (or `docker compose down`).
2. Remove from `prometheus/additional-scrape-configs.example.yaml` and re-create the Secret.
3. Loki retention will age out old logs naturally.
