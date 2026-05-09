# Rollout plan

Phased rollout. Each phase has an exit criterion — don't move on until it's met.

## Phase 0 — Server prep (1 day)

- [ ] k3s installed (already done — v1.35.4+k3s1)
- [ ] `local-path` storage class is default (k3s default — verify with `kubectl get sc`)
- [ ] cloudflared installed and a tunnel created for the domain
- [ ] DNS records in Cloudflare for `grafana.<domain>`, `harbor.<domain>`, `loki-push.<domain>`
- [ ] Keycloak instance reachable (self-hosted on this node or external)
- [ ] Keycloak realm + clients created: `grafana`, `harbor`
- [ ] SMTP credentials available (for email alerts)
- [ ] Slack/Discord/Telegram webhooks per team

**Exit:** all of the above checked. Resolve remaining `TODO(decide):` markers in repo.

## Phase 1 — Central stack on cluster (1 week)

1. Clone repo to the server: `git clone <repo> /opt/logger-agent`
2. For each component with secrets:
   ```bash
   cp k8s/<comp>/values.secrets.example.yaml k8s/<comp>/values.secrets.local.yaml
   # edit values.secrets.local.yaml — fill in real passwords
   ```
3. Create the alertmanager webhook secret:
   ```bash
   cp k8s/alertmanager/secrets.example.yaml k8s/alertmanager/secrets.local.yaml
   # edit, then:
   kubectl apply -f k8s/alertmanager/secrets.local.yaml
   ```
4. Run `bash k8s/install.sh` (idempotent — install in dependency order: namespaces → MinIO → Loki → Prometheus → Grafana → Harbor)

**Exit:**
- All NodePorts respond on health endpoints (see [runbook.md](runbook.md)).
- Grafana shows the k3s node's own metrics in "Kubernetes / Compute Resources / Cluster" dashboard.
- `docker push harbor.<domain>/library/test:1` and `docker pull` round-trip successfully via cloudflared.

## Phase 2 — Onboard the platform team (1–2 days)

- Configure OIDC on Grafana + Harbor (point at Keycloak realm).
- Create `obs-admins` group in Keycloak; add the platform team.
- Verify admin can see infrastructure dashboards + all logs.
- Verify a non-admin user (test account) sees nothing.

**Exit:** Admins can do their job; unprivileged accounts are correctly empty.

## Phase 3 — Onboard 1 pilot project (1 week)

Pick the project with the most engaged owner. Walk through [examples/project-onboarding/](../examples/project-onboarding/) live with them.

- Deploy Promtail to their hosts.
- Verify logs appear under `{project="<name>"}` in Loki.
- Create their Grafana folder + 1 dashboard.
- Wire one alert end-to-end → Slack channel.
- Onboard them to Harbor; migrate one image.

**Exit:**
- Pilot project owner says "I can debug from this." (Get it in writing.)
- One alert has fired in production and routed correctly.

## Phase 4 — Onboard remaining 14 projects (3–4 weeks)

Two projects per week, sequentially. Each onboarding is now templated; should take a few hours per project.

**Exit:** All 15 projects onboarded.

## Phase 5 — Decommission legacy (variable)

Whatever was monitoring/storing-images before this — turn it off:

1. Old log aggregation (after 7 days of dual-write to confirm parity — matches Loki retention).
2. Old metrics store (after 15 days, once Grafana parity is confirmed — matches Prometheus retention).
3. Old image registry (after all CI pipelines have switched).

**Exit:** Legacy systems are off; their machines are reclaimed.

## What can derail this

- **k3s instability under load** — at 7.7Gi RAM the box is not generously provisioned. Watch `kubectl top pods` and OOMKill events. If Harbor + Trivy together push you over, drop Trivy.
- **No clear project owners** → can't proceed past Phase 3 without an owner per project.
- **Trying to migrate images and metrics simultaneously** → don't. Image migration is its own track; let it run in parallel but track separately.
