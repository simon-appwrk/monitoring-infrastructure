#!/usr/bin/env bash
# Install ArgoCD into a fresh k3s cluster.
# Idempotent — safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v kubectl >/dev/null || { echo "kubectl not found"; exit 1; }
command -v helm    >/dev/null || { echo "helm not found";    exit 1; }

echo "==> argocd namespace"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "==> Helm repo"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "==> ArgoCD"
helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  -f "${SCRIPT_DIR}/argocd-values.yaml" \
  --wait --timeout 10m

echo
echo "==> Done."
echo
echo "Initial admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d ; echo"
echo
echo "UI: http://<node-ip>:30040"
echo
echo "Next: kubectl apply -f bootstrap/root-app.yaml"
