# Runbook: R2 bring-up (executed 2026-10-20)

Node: `aevia-control-01` (Hetzner cx33, Helsinki). Tofu state is in the Cloudflare R2 bucket `aevia-tofu-state` (see ADR 0039).
Credentials come from `~/.config/aevia/secrets.env` (TF_VAR_hcloud_token, object-storage keys); nothing is in git.

1. **Server (06):** already applied via `tofu`. The Hetzner firewall only admits `ssh_allowed_cidrs`; add your current
   IP to `production.tfvars` and `tofu apply -target=module.hetzner.hcloud_firewall.node` if SSH times out.
2. **k3s (07):** `cluster/bootstrap/k3s/config.yaml` to `/etc/rancher/k3s/config.yaml` and `cluster/bootstrap/k3s/k3s.service.env` to `/etc/systemd/system/k3s.service.env` (Go memory limit, ADR 0042), then the k3s installer.
3. **Cilium (08):** `helm upgrade --install cilium cilium/cilium --version 1.20.2 -n kube-system -f gitops/platform/cilium/values.yaml --set k8sServiceHost=10.42.1.1 --set k8sServicePort=6443`.
   Needs `10.42.1.1` in the API certificate SANs (config above), otherwise the agent loops on "Establishing connection to apiserver".
4. **Age key (10):** `age-keygen`, public key into `.sops.yaml`, private key as Secret `sops-age` in `argocd` (and a copy at `~/.config/sops/age/aevia-cluster-key.txt`).
5. **Argo CD (09):** `helm upgrade --install argocd argo/argo-cd --version 10.10.1 -n argocd -f gitops/platform/argocd-values.yaml`.
6. **Secrets:** `python3 scripts/gen-k8s-secrets.py --verify-r1` (random values; `N8N_ENCRYPTION_KEY` from R1, verified by hash). Login values land in `~/.config/aevia/r2-generated.env`.
7. **Root app:** `kubectl apply -f gitops/bootstrap/root-app.yaml`. All apps sync automatically (selfHeal, no prune).
   To change a workload by hand, pause `root` first (`syncPolicy.automated: null`) or Argo reverts it.
8. **Data (12):** n8n database from R1, database `n8n` only: `pg_dump --no-owner --no-privileges` on R1, restore into R2 with `PGOPTIONS='-c role=n8n'`.
   Do not restore `hermes`, `paperclip` (agent stack removed) or longevity (separate container `prod-longevity-db`).

## Not done (needs Cloudflare)
- Secret `cloudflared-token`, DNS records, tunnel config and Access applications (tofu `cloudflare` module needs
  `TF_VAR_cloudflare_api_token`, account id, zone id and a tunnel secret). Until then `edge` stays Degraded and nothing is reachable from the internet.
- Verify routing without Cloudflare: `kubectl -n ingress port-forward svc/ingress 18080:80` and `curl -H 'Host: n8n.maxrommel.de' localhost:18080/`.

## Cutover (29) and R1 decommission (30)
After Cloudflare is wired: switch DNS per host, watch, then retire R1. R1 also runs things outside the catalog that need a decision first:
`prod-longevity*` (own DB container), `prod-daviddiehm`, `claude-rc-container`. R1's disk is at 93%.
