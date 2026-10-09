# gitops/

Desired state for the R2 cluster, reconciled by Argo CD (ADR-0031, ADR-0033).

- `bootstrap/root-app.yaml`: applied once; points Argo CD at `apps/` on branch `r2`.
- `apps/`: one Application per component, ordered by sync wave.
- `platform/`: Helm values (Cilium, Argo CD, Traefik).
- `base/namespaces`, `base/data`, `base/edge`, `base/backup`: hand-written.
- `base/services`: GENERATED from `catalog/services.yml` (`make k8s-gen`). Do not edit.
- `secrets/`: SOPS templates; see its README.

Validate offline with `make k8s-check`. The isolation fixture lives in `tests/isolation/`, not here.
Held services (`hold:` in the catalog, currently longevity and portfolio) have no manifests.
