# Aevia R2 migration plan

R1 is frozen at `release-1`. R2 is built on branch `r2` against a parallel VPS.
Each phase needs: ADR, test, rollback. Status: `todo` unless noted.

| # | Phase | Needs credentials |
|---|---|---|
| 01 | R1 audit + freeze (tag pushed; generator check verified locally; CI status and restore rehearsal open) | no |
| 02 | Aevia rebrand (docs/text first; GitHub repo rename last) | no |
| 03 | Service inventory → `catalog/services.yml` (drafted) | no |
| 04 | Remove agent stack (Paperclip, Hermes, OpenClaw, CLIProxy) | no |
| 05 | R2 repo design + OpenTofu modules | no |
| 06 | Provision parallel R2 VPS (ADR-0029, drafted) | Hetzner, tofu state |
| 07 | k3s bootstrap (ADR-0030, drafted) | server SSH |
| 08 | Cilium (ADR-0030; isolation test `tests/isolation/run.sh` passes on kind) (default-deny per namespace) | — |
| 09 | Argo CD (ADR-0031, drafted) | — |
| 10 | Secrets (SOPS + age) (ADR-0032; repo side done: rules, templates, ksops values; in-cluster key open) | age key |
| 11 | Ingress / Cloudflare (repo side done: Traefik, cloudflared; apply open) | Cloudflare |
| 12 | PostgreSQL (manifests done; restore runbook written, restore not run) | — |
| 13 | Redis (manifests done) | — |
| 14 | Authentik | — |
| 15 | MinIO | — |
| 16 | NATS (manifests done) | — |
| 17–20 | n8n, Uptime Kuma, ntfy, earnings-alpha, regime-lens (generated manifests done; portfolio held: no image; longevity held: exam) | — |
| 21 | CI/CD (k8s validation + isolation workflow done; image build/push open) | GitHub |
| 22 | Herdr runtime | — |
| 23 | Dedicated agent node (taint `workload=agent`) | Hetzner |
| 24 | AI gateway | provider keys |
| 25 | Observability (OTel, Prometheus, Loki, Tempo, Grafana, Hubble) | — |
| 26 | Security hardening | — |
| 27 | Backup (pg-backup CronJob done; off-cluster copy open) | — |
| 28 | Disaster-recovery test (destroy → tofu → k3s → Argo → restore) | all |
| 29 | Traffic cutover | Cloudflare |
| 30 | R1 decommission | Hetzner |

Phases 01–05 are repo-only. Phase 06 onward touches billable infrastructure.

Phases 14, 15, 22-26 and 28-30 are not started. `longevity` is held (exam review): no R2 manifests, R1 untouched. See ADR-0033.
