#!/usr/bin/env bash
# Install the central observability stack into a single-node k3s cluster.
# Idempotent: safe to re-run.
#
# Prereqs (preflight will check):
#   - kubectl reaches the cluster
#   - helm 3.12+
#   - These secret files exist on the server (gitignored, you create them by copying *.example):
#       k8s/grafana/values.secrets.local.yaml
#       k8s/loki/values.secrets.local.yaml
#       k8s/minio/values.secrets.local.yaml
#       k8s/harbor/values.secrets.local.yaml
#       k8s/alertmanager/secrets.local.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ──────────────────────────────────────────────────────────────────
# Preflight
# ──────────────────────────────────────────────────────────────────
echo "==> Preflight"
command -v kubectl >/dev/null || { echo "kubectl not found"; exit 1; }
command -v helm    >/dev/null || { echo "helm not found"; exit 1; }
command -v yq      >/dev/null || { echo "yq not found (install: snap install yq)"; exit 1; }

required_secret_files=(
  grafana/values.secrets.local.yaml
  loki/values.secrets.local.yaml
  minio/values.secrets.local.yaml
  harbor/values.secrets.local.yaml
  alertmanager/secrets.local.yaml
)
missing=0
for f in "${required_secret_files[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "  MISSING: $f  (copy from ${f%.local.yaml}.example.yaml and fill in real values)"
    missing=1
  fi
done
[[ $missing -eq 0 ]] || { echo "Create the missing secret files above and re-run."; exit 1; }

# ──────────────────────────────────────────────────────────────────
# Namespaces
# ──────────────────────────────────────────────────────────────────
echo "==> Namespaces"
kubectl apply -f namespaces.yaml

# ──────────────────────────────────────────────────────────────────
# Helm repos
# ──────────────────────────────────────────────────────────────────
echo "==> Helm repos"
helm repo add minio https://charts.min.io/                                   >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts                  >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add harbor https://helm.goharbor.io                                >/dev/null 2>&1 || true
helm repo update >/dev/null

# ──────────────────────────────────────────────────────────────────
# Bootstrap K8s Secrets from values.secrets.local.yaml files
# (the Helm charts reference these by name via existingSecret/envFrom)
# ──────────────────────────────────────────────────────────────────
echo "==> K8s Secrets"

apply_secret () {  # name, namespace, key=value pairs from positional args
  local name=$1 ns=$2; shift 2
  kubectl create secret generic "$name" -n "$ns" "$@" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# minio-root  ← minio/values.secrets.local.yaml :: minioRoot
MINIO_ROOT_USER=$(yq -r '.minioRoot.user' minio/values.secrets.local.yaml)
MINIO_ROOT_PASSWORD=$(yq -r '.minioRoot.password' minio/values.secrets.local.yaml)
apply_secret minio-root obs-storage \
  "--from-literal=rootUser=${MINIO_ROOT_USER}" \
  "--from-literal=rootPassword=${MINIO_ROOT_PASSWORD}"

# grafana-admin  ← grafana/values.secrets.local.yaml :: grafanaAdmin
GF_USER=$(yq -r '.grafanaAdmin.user' grafana/values.secrets.local.yaml)
GF_PASS=$(yq -r '.grafanaAdmin.password' grafana/values.secrets.local.yaml)
apply_secret grafana-admin obs-metrics \
  "--from-literal=admin-user=${GF_USER}" \
  "--from-literal=admin-password=${GF_PASS}"

# grafana-oidc  ← Keycloak client secret (env GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET)
GF_OIDC=$(yq -r '.grafanaOidc.clientSecret' grafana/values.secrets.local.yaml)
apply_secret grafana-oidc obs-metrics \
  "--from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${GF_OIDC}"

# Loki S3 creds: no Secret needed — values.secrets.local.yaml is passed to Helm directly
# as a -f overlay (see "Loki" install step below).

# harbor-admin + harbor-database
HARBOR_ADMIN=$(yq -r '.harborAdmin.password' harbor/values.secrets.local.yaml)
HARBOR_DB=$(yq -r '.harborDatabase.password' harbor/values.secrets.local.yaml)
apply_secret harbor-admin obs-registry \
  "--from-literal=HARBOR_ADMIN_PASSWORD=${HARBOR_ADMIN}"
apply_secret harbor-database obs-registry \
  "--from-literal=POSTGRES_PASSWORD=${HARBOR_DB}"

# alertmanager-webhooks  ← raw K8s manifest
kubectl apply -f alertmanager/secrets.local.yaml

# ──────────────────────────────────────────────────────────────────
# additional-scrape-configs (Prometheus extra scrape jobs for non-K8s hosts)
# Edit prometheus/additional-scrape-configs.example.yaml first if you have hosts to add.
# ──────────────────────────────────────────────────────────────────
SCRAPE_FILE=prometheus/additional-scrape-configs.local.yaml
[[ -f $SCRAPE_FILE ]] || SCRAPE_FILE=prometheus/additional-scrape-configs.example.yaml
echo "==> additional-scrape-configs (using ${SCRAPE_FILE})"
kubectl create secret generic additional-scrape-configs \
  -n obs-metrics \
  --from-file=prometheus-additional.yaml="${SCRAPE_FILE}" \
  --dry-run=client -o yaml | kubectl apply -f -

# ──────────────────────────────────────────────────────────────────
# loki-rules ConfigMap (log-based alerts)
# ──────────────────────────────────────────────────────────────────
echo "==> loki-rules"
kubectl create configmap loki-rules \
  -n obs-logs \
  --from-file=../alerting/log-based.yml \
  --dry-run=client -o yaml | kubectl apply -f -

# ──────────────────────────────────────────────────────────────────
# Helm releases
# ──────────────────────────────────────────────────────────────────
echo "==> MinIO"
helm upgrade --install minio minio/minio \
  -n obs-storage \
  -f minio/values.yaml \
  --wait

# Bootstrap MinIO users + buckets via `mc` inside the pod.
# We do this explicitly because the chart's `users:` / `buckets:` blocks rely on a
# post-install Job that is flaky (silently fails / runs before MinIO is reachable).
# Idempotent: re-runs ignore "already exists" errors.
echo "==> MinIO users + buckets (mc exec)"
MINIO_LOKI_SK=$(yq -r '.minioUsers.loki.secretKey' minio/values.secrets.local.yaml)
MINIO_HARBOR_SK=$(yq -r '.minioUsers.harbor.secretKey' minio/values.secrets.local.yaml)

kubectl -n obs-storage wait --for=condition=ready pod -l release=minio --timeout=180s

MINIO_POD=$(kubectl -n obs-storage get pod -l release=minio -o jsonpath='{.items[0].metadata.name}')
kubectl -n obs-storage exec -i "${MINIO_POD}" -- env \
  ROOT_USER="${MINIO_ROOT_USER}" \
  ROOT_PASS="${MINIO_ROOT_PASSWORD}" \
  LOKI_SK="${MINIO_LOKI_SK}" \
  HARBOR_SK="${MINIO_HARBOR_SK}" \
  bash -e <<'EOF'
mc alias set local http://localhost:9000 "$ROOT_USER" "$ROOT_PASS"
mc admin user add    local loki   "$LOKI_SK"   2>/dev/null || true
mc admin user add    local harbor "$HARBOR_SK" 2>/dev/null || true
mc admin policy attach local readwrite --user loki   2>/dev/null || true
mc admin policy attach local readwrite --user harbor 2>/dev/null || true
for b in loki-chunks loki-ruler loki-admin harbor-blobs; do
  mc mb -p "local/$b" 2>/dev/null || true
done
echo "--- MinIO users ---"
mc admin user ls local
echo "--- MinIO buckets ---"
mc ls local
EOF

echo "==> Loki"
helm upgrade --install loki grafana/loki \
  -n obs-logs \
  -f loki/values.yaml \
  -f loki/values.secrets.local.yaml \
  --timeout 10m --wait

echo "==> kube-prometheus-stack"
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n obs-metrics \
  -f prometheus/values.yaml \
  --set-file alertmanager.config=alertmanager/config.yaml \
  --wait

echo "==> Grafana"
helm upgrade --install grafana grafana/grafana \
  -n obs-metrics -f grafana/values.yaml --wait

echo "==> Harbor"
HARBOR_S3_SK=$(yq -r '.harborS3.secretKey' harbor/values.secrets.local.yaml)
helm upgrade --install harbor harbor/harbor \
  -n obs-registry \
  -f harbor/values.yaml \
  --set "persistence.imageChartStorage.s3.secretkey=${HARBOR_S3_SK}" \
  --wait

# ──────────────────────────────────────────────────────────────────
# Prometheus alert rules ConfigMap
# ──────────────────────────────────────────────────────────────────
echo "==> Prometheus alert rules"
kubectl create configmap prometheus-rules \
  -n obs-metrics \
  --from-file=../alerting/ \
  --dry-run=client -o yaml | \
  kubectl label --local --overwrite -f - prometheus=kube-prometheus -o yaml | \
  kubectl apply -f -

echo "==> Done. Verify NodePorts (see ../docs/network-topology.md)."
