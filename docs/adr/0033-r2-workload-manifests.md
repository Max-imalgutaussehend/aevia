# ADR-0033: Workload manifests are generated from the catalog

- **Status:** Proposed
- **Date:** 2026-10-09
- **Milestone:** R2 phases 10-21, 27

## Context

R2 needs Deployments, Services, Ingresses and NetworkPolicies for every service. Writing them
by hand repeats the R1 drift problem (ADR-0014). The server is not touched and `longevity` is
under exam review, so everything here must be buildable and verifiable without a cluster.

## Decision

- `generator/render_k8s.py` renders `gitops/base/services/` from `catalog/services.yml`; `--check` fails on drift.
- Default per workload: no service-account token, seccomp RuntimeDefault, all capabilities dropped,
  no privilege escalation, memory limit, ingress only from namespace `ingress`, egress only to DNS and `needs`.
- `uid` is set only where the image is known to run unprivileged; no guessing.
- Services with `hold:` in the catalog get no manifests. `longevity` is held until the exam is released;
  `portfolio` is held until CI publishes an image.
- Stateful backends (Postgres, Redis, NATS) are hand-written in `gitops/base/data` and reuse the R1 configs.
- Ingress is Traefik in namespace `ingress`, Service named `ingress` (what the tofu cloudflare module targets);
  cloudflared lives alone in `edge`.
- Secrets are SOPS-encrypted `gitops/secrets/*.enc.yaml`; only templates are committed.
- Validation is offline: `make k8s-check` (kubeconform, helm template) plus the kind/Cilium isolation test in CI.

## Verification

`make k8s-check` passes; CI job `k8s` green; `tests/isolation/run.sh` passes.

## Rollback

Delete the Argo CD Applications in `gitops/apps`; nothing here changes R1.
