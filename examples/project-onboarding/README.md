# Project onboarding — checklist

Use this when adding project number 16 (or 17, 18, …). Should take a few hours after the platform is live.

## Inputs to collect from the project owner

- Project name (lowercase, hyphenated): e.g. `payment-api`
- Owning team name: e.g. `backend`
- Environments: `production`, `staging`, `dev` (subset)
- Hosts: which VMs/VPS/Docker hosts run this project
- Endpoints to probe (URLs for blackbox)
- Slack/Discord/Telegram channel for alerts
- Whether they need a Harbor project for images

## Step-by-step

### 1. Identity (Keycloak)

```
Create groups in Keycloak:
  proj-<name>-dev      (developers)
  proj-<name>-lead     (project lead — gets Editor in Grafana, Maintainer in Harbor)
Add users.
```

### 2. Grafana folder

In Grafana UI (Admin only):

1. Dashboards → New folder → name = `<name>` (matches project name exactly).
2. Folder → Permissions → remove default `Viewer Everyone`.
3. Add team `proj-<name>-dev` as `Viewer`, `proj-<name>-lead` as `Editor`.
4. Import the project dashboard template (see [dashboards/README.md](../../dashboards/README.md)) and pin `$project` to the project name.

### 3. Harbor project (if needed)

In Harbor UI (SysAdmin only):

1. Projects → New → name = `<name>`, access = Private.
2. Members → Add: `proj-<name>-dev` as Developer, `proj-<name>-lead` as Maintainer.
3. Configuration → Vulnerability scanning: enable "Prevent vulnerable images from running" if appropriate.
4. Retention policy → keep last 10 by tag pattern, or align with project owner's wish.

### 4. Promtail labels

For each host running the project:

- If it's a Linux VM/VPS managed by Ansible, edit [agents/ansible/inventory.example](../../agents/ansible/inventory.example) to add the host under the right group with `project=<name>`.
- If it's a Docker host running this project's containers, ensure the containers are deployed with Docker labels:

  See [promtail-labels-snippet.yml](promtail-labels-snippet.yml).

- If it's a K8s pod, add Pod labels: `app.kubernetes.io/part-of=<name>`, `environment=`, `team=`. The DaemonSet relabel rules pick these up.

### 5. Prometheus scrape (if the project exposes app metrics)

Edit [k8s/prometheus/additional-scrape-configs.example.yaml](../../k8s/prometheus/additional-scrape-configs.example.yaml). Add a job:

```yaml
- job_name: 'app-<name>'
  metrics_path: /metrics
  static_configs:
    - targets: ['<name>-1.internal:8080']
      labels:
        project: <name>
        environment: production
        team: <team>
```

Re-create the Secret + roll Prometheus.

### 6. Alerts

1. Copy [alerting/application.template.yml](../../alerting/application.template.yml) to `alerting/projects/<name>.yml`.
2. Replace `payment-api` and `backend` with this project's values.
3. Tune thresholds with the project owner.
4. PR → CI validates → merge → ConfigMap reload.

### 7. Alertmanager receiver

The default routing tree (`docs/alerting.md`) assumes channels named `#alerts-<team>`. If this project's team needs a custom Slack/Discord/Telegram, add a child route in [k8s/alertmanager/config.yaml](../../k8s/alertmanager/config.yaml) keyed on `project=<name>`.

### 8. Verify end-to-end

```bash
# Grafana — does the project's "Logs" panel show recent lines?
# Prometheus — http://<node>:30090/targets has app-<name> as 'up'
# Alertmanager — fire a synthetic alert by stopping a target → confirm Slack message
```

### 9. Document

Add the project to a simple onboarded-projects table in this repo (or in your wiki), with: owner, team, hosts, Slack channel, status.

That's it.
