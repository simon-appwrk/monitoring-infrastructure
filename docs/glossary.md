# Glossary

Terms used across this repo, in alphabetical order.

> [!TIP]
> If a term you're looking for isn't here, [concepts.md](concepts.md) probably explains it in context.

---

## A

**Alertmanager** — the part of the Prometheus stack that takes firing alerts and routes them to humans (Slack, email, etc.). Has its own routing tree config — see [helm-values/kube-prometheus-stack.yaml](../helm-values/kube-prometheus-stack.yaml).

**ArgoCD** — a GitOps controller that runs in Kubernetes, watches a Git repo, and reconciles cluster state with what's in Git. The deployment engine for everything in this repo. See [concepts.md → ArgoCD](concepts.md#what-is-argocd).

**Application** (capital A) — an ArgoCD object that says "deploy this Helm chart with these values" or "apply these manifests from this Git path." We have one per workload — see [apps/](../apps/).

**App-of-apps** — a pattern where one ArgoCD Application is responsible for creating other Applications. Our [bootstrap/root-app.yaml](../bootstrap/root-app.yaml) does this.

**`apps/`** — the directory containing one ArgoCD Application per workload (MinIO, Loki, Prometheus, Grafana, Harbor, alert rules).

---

## C

**cAdvisor** — a metrics exporter for Docker container resource usage. Built into the kubelet, so K8s nodes expose container metrics natively. We also run it standalone on non-K8s Docker hosts.

**ConfigMap** — a Kubernetes object holding non-sensitive config (rule files, JSON dashboards, etc.). Mounted into Pods as files or env vars. See [manifests/loki-rules-configmap.yaml](../manifests/loki-rules-configmap.yaml).

**cloudflared** — Cloudflare's tunnel client. Runs on your server, makes outbound connections to Cloudflare, and proxies inbound HTTPS traffic from Cloudflare to your local NodePorts. Eliminates the need to expose public ports on your server.

**CRD** (Custom Resource Definition) — a way to teach Kubernetes new object types. `PrometheusRule`, `Application`, `ServiceMonitor` are all CRDs. Once installed, `kubectl get prometheusrule` works.

---

## D

**DaemonSet** — a Kubernetes workload that runs one Pod per node. Used for things that need to be on every machine: `node-exporter`, Promtail, the local-path provisioner.

**Deployment** — a Kubernetes workload spec saying "I want N copies of this Pod running, always." Most stateless workloads (Grafana, Harbor portal) are Deployments.

---

## G

**Gateway** (Loki) — an nginx Pod fronting the Loki SingleBinary, providing a single HTTP entry point on port 3100 (and exposed via NodePort 30100). Promtail and Grafana talk to the gateway, not Loki directly.

**GitOps** — a deployment philosophy: desired state lives in Git, a controller in the cluster reconciles reality with Git. Our controller is ArgoCD. See [concepts.md → GitOps](concepts.md#what-is-gitops).

**Grafana** — the visualization layer. Reads from Prometheus + Loki. Folder-per-project ACL is how we enforce "developers can only see their project."

---

## H

**Harbor** — an open-source private container registry. Where you `docker push` your images. Includes vulnerability scanning (Trivy) and project-based RBAC.

**Helm** — the package manager for Kubernetes. A "chart" is a parameterized bundle of K8s YAML; you tune it via `values.yaml`. ArgoCD renders charts on our behalf. See [concepts.md → Helm](concepts.md#what-is-helm).

**`helm-values/`** — the directory in this repo containing one `values.yaml` per Helm chart we use.

---

## I

**Ingress** — a Kubernetes object for HTTP routing. We don't use it (we use NodePort + cloudflared instead — simpler).

---

## K

**k3s** — a lightweight Kubernetes distribution. Single binary, sensible defaults, runs on small servers. Built by Rancher. Our entire stack runs on a one-node k3s cluster.

**kube-prometheus-stack** — a Helm chart that bundles Prometheus + Alertmanager + node-exporter + kube-state-metrics + the Prometheus Operator. The most common way to install Prometheus on K8s.

**kubelet** — the K8s agent that runs on every node, manages Pods, and reports back to the API server. Exposes container metrics via cAdvisor.

**kube-state-metrics** — exporter that exposes K8s object state (Deployments, Pods, PVCs, etc.) as Prometheus metrics. So you can alert on "this Deployment has 0 ready replicas".

**Keycloak** — an open-source identity provider. We plan to use it for SSO into Grafana + Harbor (OIDC). Currently optional / not deployed in this repo.

---

## L

**`local-path`** — k3s's default StorageClass. When a Pod claims a PVC, k3s creates a directory under `/var/lib/rancher/k3s/storage/` on the node and mounts it. No external storage system needed.

**Loki** — Grafana Labs' log aggregation system. Indexes only labels (not log content), making it cheap to run. Stores log chunks in object storage (we use MinIO).

**Loki ruler** — Loki's built-in alert evaluator. Reads rules from a ConfigMap, evaluates them against logs, fires alerts to Alertmanager. See [manifests/loki-rules-configmap.yaml](../manifests/loki-rules-configmap.yaml).

---

## M

**MinIO** — an open-source S3-compatible object store. Loki stores its log chunks here. Standalone mode (single-node) for our deployment.

---

## N

**Namespace** — a Kubernetes concept for grouping objects. Like folders. We have `obs-metrics`, `obs-logs`, `obs-storage`, `obs-registry`, `argocd`.

**node-exporter** — a Prometheus exporter for host-level metrics (CPU, memory, disk, network). Runs as a DaemonSet in K8s; runs as a systemd service on non-K8s hosts.

**NodePort** — a Service flavor that opens a port on the host machine itself (not just in-cluster). All our user-facing services use NodePort, then cloudflared tunnels to them.

---

## O

**OIDC** (OpenID Connect) — an identity protocol. Keycloak speaks OIDC; Grafana + Harbor consume OIDC. Lets users log in once and reach both.

---

## P

**Pod** — the smallest schedulable unit in Kubernetes. Usually one container; sometimes a few helper containers grouped together. When a Pod dies, K8s starts a new one.

**Promtail** — Loki's log shipper. Tails files / Docker logs / K8s logs and pushes them to Loki with labels.

**Prometheus** — the metrics collection + storage system. Scrapes targets, stores time-series in its TSDB, evaluates alert rules.

**PrometheusRule** — a CRD provided by the Prometheus Operator. Each one wraps a list of alert rules + recording rules. We have one per file in [alerting/](../alerting/).

**Prometheus Operator** — a controller that turns CRDs (Prometheus, Alertmanager, ServiceMonitor, PrometheusRule) into actual K8s resources. Bundled with kube-prometheus-stack.

**PVC** (PersistentVolumeClaim) — a Pod's request for storage. The provisioner (local-path in our case) creates an actual disk directory and mounts it. PVCs survive Pod restarts.

---

## R

**RBAC** (Role-Based Access Control) — who can do what. K8s has its own RBAC; Grafana has folder-based RBAC; Harbor has project-based RBAC.

**Reconciliation** — the GitOps loop: ArgoCD reads Git, compares with cluster, applies any difference. Happens every 3 minutes by default.

---

## S

**Secret** — a Kubernetes object holding sensitive data (passwords, API keys). Stored base64-encoded in etcd. We create them manually with `kubectl apply` from templates in [secrets/](../secrets/) — they're NOT in Git.

**Service** — a stable network endpoint for a set of Pods. Pods come and go (different IPs each time); the Service IP is stable. Flavors include `ClusterIP` (in-cluster only), `NodePort` (also opens port on each node), `LoadBalancer` (cloud LB).

**SingleBinary** (Loki) — Loki's mode where one Pod does everything (ingest, index, query). Simpler than the scaled "read/write/backend" mode. Right choice for a single-node cluster.

**StatefulSet** — like a Deployment but for stateful workloads (databases, etc.). Each Pod gets a stable name (`foo-0`, `foo-1`) and its own PVC. Loki SingleBinary is a StatefulSet under the hood.

**Sync wave** — an ArgoCD annotation (`argocd.argoproj.io/sync-wave: "10"`) that controls deploy ordering. Lower numbers go first.

**Sync policy** — how aggressively ArgoCD reconciles. We use `automated.prune: true` (delete things removed from Git) and `automated.selfHeal: true` (revert manual cluster changes).

---

## T

**TSDB** (Time-Series Database) — Prometheus's on-disk format for storing metrics. Optimized for write-heavy time-series data. Lives on Prometheus's PVC.

**Trivy** — a vulnerability scanner. Bundled with Harbor. Scans images on push, reports CVEs. Optional — disable to save ~512 Mi RAM.

---

## Y

**YACE** (Yet Another CloudWatch Exporter) — a Prometheus exporter that pulls AWS CloudWatch metrics into Prometheus. Not currently deployed in this repo (we removed it for simplicity).
