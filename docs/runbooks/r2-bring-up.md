# Runbook: R2 bring-up order (everything here needs the server)

Everything below is prepared in git; nothing has been executed. Stop before step 1 until the
exam review of `longevity` is over and the server is released.

1. Phase 06-07: `tofu apply`, k3s per ADR-0030 (`docs/runbooks/tofu-bootstrap.md` first).
2. Phase 08: Cilium (`gitops/platform/cilium/values.yaml`), then `tests/isolation/run.sh`.
3. Phase 09: `helm install argocd argo/argo-cd --version 10.10.1 -n argocd -f gitops/platform/argocd-values.yaml`.
4. Phase 10: `age-keygen`, `kubectl -n argocd create secret generic sops-age --from-file=keys.txt`,
   add the public key to `.sops.yaml`, `sops updatekeys`, create `gitops/secrets/*.enc.yaml` from the templates.
5. `kubectl apply -f gitops/bootstrap/root-app.yaml`; sync waves: namespaces, data, ingress, edge+services, backup.
6. Phase 12: `docs/runbooks/restore.md`.
7. Phase 29/30 (cutover, decommission) are separate, explicit go-aheads.
