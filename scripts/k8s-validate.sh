#!/usr/bin/env bash
# Offline validation of everything under gitops/ (no cluster, no server access).
# Needs: python3 + pyyaml, kubectl, kubeconform, helm.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 generator/render_k8s.py --check
for d in namespaces data edge backup services; do
  echo "== kustomize gitops/base/$d"
  kubectl kustomize "gitops/base/$d" | kubeconform -strict -summary
done
echo "== argo applications"
kubeconform -strict -ignore-missing-schemas -summary gitops/apps gitops/bootstrap
echo "== helm: traefik, argo-cd"
helm repo add traefik https://traefik.github.io/charts >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null
helm template ingress traefik/traefik --version 41.7.0 -n ingress -f gitops/platform/traefik/values.yaml \
  | kubeconform -strict -ignore-missing-schemas -summary
helm template argocd argo/argo-cd --version 10.10.1 -n argocd -f gitops/platform/argocd-values.yaml \
  | kubeconform -strict -ignore-missing-schemas -summary
echo "== no plaintext secrets / :latest"
if grep -rEn 'image: .*:latest' gitops; then echo "FAIL: :latest"; exit 1; fi
if ls gitops/secrets/*.yaml 2>/dev/null | grep -v -E '\.(example|enc)\.yaml$'; then echo "FAIL: unencrypted secret"; exit 1; fi
if grep -L '^sops:' gitops/secrets/*.enc.yaml 2>/dev/null; then echo "FAIL: .enc.yaml without sops block"; exit 1; fi
echo OK
