# ADR-0034: Identity, object storage, observability, agent zone, AI gateway

- **Status:** Proposed
- **Date:** 2026-10-09
- **Milestone:** R2 phases 14, 15, 22-26, 28

## Decision

- **Authentik (14):** official Helm chart via Argo CD, external Postgres in `data`, secrets from SOPS. Listed in the catalog as `managed_by: helm` so tofu publishes its host and the generator emits nothing.
- **Object store (15):** SeaweedFS StatefulSet in `data` (S3 API). The official MinIO images and chart repo are no longer reachable. Auth requires the identities file in Secret `s3-auth`; env-var credentials were tested and do NOT enforce auth. No consumer allowed until one is named.
- **Agent zone (22/23):** namespace `agents` is PSS `restricted`, default-deny, egress only DNS + public HTTPS. The agent node and its taint already exist in the tofu `nodes` variable (role `agent`). No agent profile exists yet.
- **AI gateway (24):** NOT built. It needs provider keys and a choice of gateway product; both are the operator's. The agents zone is ready to be given one allow-rule when it exists.
- **Observability (25):** kube-prometheus-stack (no Alertmanager, ntfy covers alerting), Loki single binary, Tempo. Namespace `observability` is `privileged` only because node-exporter needs host access; everything else is denied by default. Scraping other namespaces is NOT yet allowed (their default-deny blocks it); add per-namespace allow-rules from `observability` when ServiceMonitors are enabled.
- **Hardening (26):** ResourceQuota + LimitRange per namespace, PSS labels, and `tests/policy/check_workloads.py` fails CI on missing memory limits, privilege escalation, host access or unpinned images.
- **DR (28):** `tests/restore/run.sh` rehearses dump, destroy and restore of Postgres on kind. The full destroy-tofu-k3s-Argo drill needs the server and is in `docs/runbooks/r2-bring-up.md`.

## Held

`longevity` (exam review): no manifests, no DNS record (tofu skips catalog entries with `hold`), no database role.

## Rollback

Delete the corresponding Argo CD Applications; R1 is unaffected.
