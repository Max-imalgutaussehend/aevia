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
| 14 | Authentik (Helm app + policies done; bootstrap after cluster) | — |
| 15 | Object store (SeaweedFS replaces MinIO; manifest done, auth verified locally; no consumer yet) | — |
| 16 | NATS (manifests done) | — |
| 17–20 | n8n, Uptime Kuma, ntfy, earnings-alpha, regime-lens (generated manifests done; portfolio held: no image; longevity held: exam) | — |
| 21 | CI/CD (k8s validation, isolation, restore and portfolio-image workflows done; portfolio digest pin open until the workflow runs) | GitHub |
| 22 | Herdr runtime (agents zone scaffold done; no profile yet) | — |
| 23 | Dedicated agent node (taint `workload=agent`) (tofu `nodes` supports it; apply open) | Hetzner |
| 24 | AI gateway (FreeLLMAPI manifest, seed mechanism and runbook done; key adoption and egress allow-list by provider host open) | provider keys |
| 25 | Observability (Prometheus, Grafana, Loki, Tempo, OTel collector values + Argo apps done; Hubble was already on in the Cilium values) | — |
| 26 | Security hardening (quotas, PSS, CI policy check done) | — |
| 27 | Backup (pg-backup CronJob done; off-cluster copy open) | — |
| 28 | Disaster-recovery test (Postgres dump/destroy/restore rehearsal on kind done; full drill needs server) | all |
| 29 | Traffic cutover | Cloudflare |
| 30 | R1 decommission | Hetzner |

Phases 01–05 are repo-only. Phase 06 onward touches billable infrastructure.

Phases 29-30 are not started; 24 is blocked on operator input. `longevity` is held (exam review): no R2 manifests, R1 untouched. See ADR-0033.
