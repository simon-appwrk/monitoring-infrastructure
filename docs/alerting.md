# Alerting

## Alert categories

| Category       | Source           | Examples                                  |
|----------------|------------------|-------------------------------------------|
| Infrastructure | Prometheus       | Node down, disk >85%, RAM >90%, NTP drift |
| Container      | Prometheus       | Container restart loop, OOMKilled, image pull error |
| Application    | Prometheus       | App `up == 0`, error rate >1%, latency p99 |
| Availability   | Prometheus blackbox | HTTP 5xx, TCP unreachable, TLS expiring |
| Log-based      | Loki ruler       | "panic:" / "FATAL" lines, error-rate spike |

Rule files: [alerting/](../alerting/).

## Required labels on every rule

Every alert **must** carry these labels (used by Alertmanager routing):

```yaml
labels:
  project: payment-api      # or "infra" for platform-wide
  environment: production   # production | staging | dev
  severity: critical        # critical | warning | info
  team: backend             # owning team
```

Rules without these labels will fall to a `team=unrouted` catch-all that pages the platform team. That is intentional — unrouted alerts are bugs in the rule, not incidents in the system.

## Routing tree (Alertmanager)

```
root
├── severity=info     → suppressed (visible in UI only)
├── team=unrouted     → #obs-platform Slack (always)
├── project=infra
│   ├── severity=critical → PagerDuty + #infra-oncall Slack + email
│   └── severity=warning  → #infra-oncall Slack
└── project=<any>
    ├── environment=production
    │   ├── severity=critical → team Slack + Telegram + email to <team>@org
    │   └── severity=warning  → team Slack
    ├── environment=staging
    │   └── severity=critical → team Slack
    └── environment=dev
        └── (suppressed unless severity=critical)
```

Concrete config: [k8s/alertmanager/config.yaml](../k8s/alertmanager/config.yaml).

## Notification channels

| Channel  | Setup                                                 |
|----------|-------------------------------------------------------|
| Email    | SMTP relay (TODO(decide): SES / Postmark / internal)  |
| Slack    | Per-team incoming webhook URL                         |
| Discord  | Per-team webhook URL                                  |
| Telegram | Bot token + per-team chat_id                          |

Webhooks live in K8s `Secret/alertmanager-webhooks` — never in git.

## Inhibition rules

- A `NodeDown` for a host inhibits all `ContainerDown` / `AppDown` alerts whose `instance` lives on that host (avoid alert storms).
- A `LokiDown` inhibits all log-based alerts (they would be false negatives anyway).

## Silences

Silences are created via Alertmanager UI (`<node>:30093`). Audit log of silences ships to Loki under `project=infra, component=alertmanager`.

## Adding a new alert (developer self-service)

A project owner adds rules under `alerting/projects/<project>.yml`, opens a PR. CI:
1. `promtool check rules` validates syntax.
2. Verifies `project` label matches the file's project.
3. Verifies `team` label is non-empty.

Merge → ConfigMap reload → Prometheus picks it up within 30s.
