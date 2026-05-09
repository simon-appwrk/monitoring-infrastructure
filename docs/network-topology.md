# Network topology & NodePort assignments

All central-stack services are exposed via **NodePort** on the single k3s node. External access goes through a **cloudflared tunnel** running on the same node — Cloudflare terminates TLS, the tunnel forwards plain HTTP to the local NodePort.

```
   Internet
      │  HTTPS (TLS terminated by Cloudflare)
      ▼
  ┌────────────────────┐
  │  cloudflared       │  (runs on the k3s node, outbound-only tunnel)
  └────────┬───────────┘
           │  HTTP localhost:<NodePort>
           ▼
  ┌────────────────────┐
  │  k3s node          │
  │  Services exposed  │
  │  on NodePort       │
  └────────────────────┘
```

## Port assignments

| Service           | NodePort | Protocol | Tunnel publicly? |
|-------------------|----------|----------|------------------|
| Grafana           | 30030    | HTTP     | Yes — main UI    |
| Prometheus        | 30090    | HTTP     | Admin-only or skip |
| Alertmanager      | 30093    | HTTP     | Admin-only or skip |
| Loki push         | 30100    | HTTP     | Yes — agents push from outside |
| Loki query        | 30101    | HTTP     | No — Grafana proxies |
| MinIO S3 API      | 30900    | HTTP     | No — internal only |
| MinIO console     | 30901    | HTTP     | Admin-only       |
| Harbor portal/registry | 30002 | HTTP   | Yes — main registry URL |

These are pinned in each component's `Service` manifest under [k8s/](../k8s/) — do not let K8s auto-assign.

## Cloudflared config sketch

Run `cloudflared` as a systemd service on the same node. `~/.cloudflared/config.yml` looks roughly like:

```yaml
tunnel: <tunnel-id>
credentials-file: /etc/cloudflared/<tunnel-id>.json

ingress:
  - hostname: grafana.example.com
    service: http://localhost:30030
  - hostname: harbor.example.com
    service: http://localhost:30002
  - hostname: loki-push.example.com
    service: http://localhost:30100
  - service: http_status:404
```

Cloudflare DNS routes `grafana.example.com` → tunnel → NodePort 30030. Harbor's `externalURL` must match the public hostname so the registry advertises the right URL to docker clients.

## Why HTTP behind the tunnel (not HTTPS)

Cloudflared expects plain HTTP from the origin and re-encrypts to the client. Running TLS twice (Cloudflare → cloudflared → in-cluster TLS) buys nothing here. So:

- Harbor: `expose.tls.enabled: false`, `externalURL: https://harbor.example.com`.
- Grafana / Prometheus / Loki: HTTP NodePorts as-is.

## Firewall (single-node k3s)

Inbound to the public IP:
- `22` SSH (your IP only)
- Everything else: blocked at the cloud firewall

Cloudflared is **outbound-only** — no public ports needed for it. That's the whole point of the tunnel.

For agents (cloud VMs / VPS / Docker hosts) shipping logs to `loki-push.example.com`: they hit Cloudflare, which tunnels to the local NodePort. No public port on the k3s node is required.

If an agent is on the same private network as the node, you can also have it push directly to `http://<node-private-ip>:30100` and skip the tunnel.

## Why NodePort over Ingress

- Direct: `curl localhost:30090` works on the node; no controller logs to triage.
- No SNI / virtualhost layer between you and the service.
- TLS handled by cloudflared — already the user's external front door.
- Trade-off: must coordinate ports manually (this file is the source of truth).

## k3s note: traefik

k3s ships with traefik enabled by default. We don't use it. Either:
- Leave it running (harmless, ~50Mi RAM), or
- Install k3s with `--disable traefik` to save the resources.
