# Access control

Two principals: **Admin** (infrastructure owner) and **Developer** (project contributor). RBAC is enforced in three places: Grafana, Harbor, and Alertmanager routing.

## Roles

### Admin
- Grafana: `Admin` org role; access to all folders.
- Prometheus / Alertmanager / Loki: direct UI access (NodePort).
- Harbor: `SysAdmin`.
- Cluster: full kubectl.

### Developer
- Grafana: `Viewer` on **only their project's folder** (`payment-api`, `auth-service`, …).
- Prometheus / Alertmanager / Loki UIs: **no direct access**. They consume these only through Grafana panels with `project=<their-project>` baked into dashboard variables.
- Harbor: `Developer` (push/pull) or `Guest` (pull) on their project, no others.
- Cluster: no kubectl. If pod logs are needed, they read them via Grafana → Loki.

## Identity

TODO(decide): pick one and stick with it.

- **Recommended:** Keycloak (self-hosted, OIDC). Single source of truth for Grafana + Harbor.
- Alternative: GitHub OAuth (lower lift, but couples access to GitHub org membership).
- Fallback: local Grafana users + local Harbor users. Acceptable for bootstrap; migrate within 90 days.

## Group → access mapping (Keycloak example)

| Keycloak group         | Grafana role            | Harbor role           |
|------------------------|-------------------------|-----------------------|
| `obs-admins`           | Org Admin               | SysAdmin              |
| `proj-payment-api-dev` | Viewer on folder `payment-api` | Developer on project `payment-api` |
| `proj-payment-api-lead`| Editor on folder `payment-api` | Maintainer on project `payment-api` |
| `proj-<name>-dev`      | …                       | …                     |

Grafana team-sync (via OIDC `groups` claim) handles folder permissions automatically. Harbor has the same pattern (`Configuration → OIDC → Group claim`).

## How developer scoping is actually enforced

The honest answer: **Grafana folder permissions + dashboard variable defaults**, not Loki tenant isolation.

A Viewer in folder `payment-api` can only:
- Open dashboards in that folder
- Those dashboards have `$project = payment-api` as a **constant** variable (no dropdown)
- Every panel query is `{project="$project", ...}` for Loki, `{project="$project"}` for Prometheus

A determined Viewer **cannot** craft an arbitrary Loki query in the Explore tab — Explore is disabled for Viewers (`[users] viewers_can_edit = false` and `[explore] enabled = false` in `grafana.ini`, scoped to non-admin orgs).

If you need *cryptographic* tenant isolation (regulated data, untrusted developers), switch Loki to multi-tenant mode and put a per-tenant proxy in front. That is **not** in scope for this design — flagged here so the trade-off is explicit.

## Audit

- Grafana: `[log] mode = console file` + ship `/var/log/grafana/grafana.log` to Loki (label `project=infra`).
- Harbor: built-in audit log, exposed at `/api/v2.0/audit-logs`. Scrape into Loki via Promtail with label `project=infra, component=harbor`.
- Alertmanager: silences/inhibitions are logged; ship those too.
