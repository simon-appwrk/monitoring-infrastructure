# Central stack — k3s install

Deploys the central observability + registry stack into a single-node k3s cluster, exposed via NodePort and fronted by cloudflared.

## Prereqs

- k3s running (`kubectl get nodes` shows `Ready`)
- Default storage class is `local-path` (`kubectl get sc` should show `local-path (default)`)
- `helm` 3.12+
- `yq` (the [mikefarah Go version](https://github.com/mikefarah/yq) — install: `snap install yq`)
- cloudflared tunnel configured (or you'll only access services from the node itself)
- DNS set up for the public hostnames (Cloudflare DNS, pointing at the tunnel)

## Secrets — the important part

**Real secrets never enter git.** Each component has a `values.secrets.example.yaml` (committed, dummy) and a `values.secrets.local.yaml` (gitignored, real). Same pattern for the alertmanager K8s Secret manifest.

```bash
# On the server, one-time setup:
cd k8s
for d in grafana loki minio harbor; do
  cp $d/values.secrets.example.yaml $d/values.secrets.local.yaml
done
cp alertmanager/secrets.example.yaml alertmanager/secrets.local.yaml

# Edit each *.local.yaml — fill in real passwords, webhook URLs, Keycloak client secret.
# Tip: use `pwgen -s 32 1` or `openssl rand -base64 32` for passwords.
```

`install.sh` won't run until all five `*.local.yaml` files exist (it preflights this).

### Cross-file consistency you must maintain

These three values **must match** or Loki/Harbor will fail to authenticate to MinIO:

| Value           | Set in                                           |
|-----------------|--------------------------------------------------|
| Loki secret key | `minio/values.secrets.local.yaml :: minioUsers.loki.secretKey` |
|                 | `loki/values.secrets.local.yaml :: lokiMinio.secretKey` |
| Harbor secret key | `minio/values.secrets.local.yaml :: minioUsers.harbor.secretKey` |
|                 | `harbor/values.secrets.local.yaml :: harborS3.secretKey` |

## Install

```bash
bash install.sh
```

The script is idempotent. It:

1. Preflights — kubectl, helm, yq, all five `*.local.yaml` files present
2. Creates namespaces
3. Adds Helm repos
4. Reads each `values.secrets.local.yaml` and creates the corresponding K8s Secrets
5. Applies `alertmanager/secrets.local.yaml` (raw manifest)
6. Creates the `additional-scrape-configs` Secret + `loki-rules` ConfigMap
7. `helm upgrade --install` for MinIO → Loki → kube-prometheus-stack → Grafana → Harbor
8. Loads Prometheus rule ConfigMap from `../alerting/`

## Verify

```bash
# All pods Running
kubectl get pods -A | grep -E 'obs-(storage|logs|metrics|registry)'

# NodePorts open (run on the node)
for n in 30030 30090 30093 30100 30101 30900 30901 30002; do
  printf "%5d  " "$n"; curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:$n/" || true
done
```

## Post-install (manual one-time)

1. **Grafana**: log in once via Keycloak → confirm `obs-admins` group → `Admin` mapping works.
2. **Harbor**: Administration → Configuration → Authentication → set OIDC (provider URL, client ID, client secret, scope `openid profile email groups`, group claim `groups`).
3. **MinIO console** (`localhost:30901`): log in with root creds, browse buckets, confirm `loki-chunks` and `harbor-blobs` exist.
4. **cloudflared**: route `grafana.<domain>` → `http://localhost:30030`, `harbor.<domain>` → `http://localhost:30002`, `loki-push.<domain>` → `http://localhost:30100`.

## What this does NOT install

- An ingress controller (we use NodePort by design — cloudflared handles external).
- A service mesh (rejected by design).
- cert-manager (TLS handled by cloudflared at the edge).
- Keycloak itself (assumed to exist; install separately if you don't have one).
