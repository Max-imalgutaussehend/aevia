#!/usr/bin/env bash
# Offline validation of everything under gitops/ (no cluster, no server access).
# Needs: python3 + pyyaml, kubectl, kubeconform, helm.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 generator/render_k8s.py --check
for d in namespaces data edge backup services platform agents ai-gateway; do
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
helm repo add goauthentik https://charts.goauthentik.io >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null
helm repo update >/dev/null
chart() { helm template "$1" "$2" -n "$3" --version "$4" -f "$5" 2>/dev/null | kubeconform -strict -ignore-missing-schemas -summary; }
chart authentik goauthentik/authentik platform 2026.8.3 gitops/platform/authentik/values.yaml
chart kps prometheus-community/kube-prometheus-stack observability 92.2.0 gitops/platform/observability/kube-prometheus-stack.yaml
chart loki grafana/loki observability 7.3.0 gitops/platform/observability/loki.yaml
chart tempo grafana/tempo observability 1.24.4 gitops/platform/observability/tempo.yaml
chart otel open-telemetry/opentelemetry-collector observability 0.175.1 gitops/platform/observability/otel-collector.yaml
helm template argocd argo/argo-cd --version 10.10.1 -n argocd -f gitops/platform/argocd-values.yaml \
  | kubeconform -strict -ignore-missing-schemas -summary
echo "== workload hardening policy"
python3 tests/policy/check_workloads.py
echo "== no plaintext secrets / :latest"
if grep -rEn 'image: .*:latest' gitops; then echo "FAIL: :latest"; exit 1; fi
if ls gitops/secrets/*.yaml 2>/dev/null | grep -v -E "\.(example|enc)\.yaml$|secret-generator\.yaml$|kustomization\.yaml$"; then echo "FAIL: unencrypted secret"; exit 1; fi
for f in gitops/secrets/*.enc.yaml; do
  [[ -e $f ]] || continue
  grep -q '^sops:' "$f" || { echo "FAIL: $f has no sops block"; exit 1; }
  grep -q 'ENC\[' "$f" || { echo "FAIL: $f is not encrypted"; exit 1; }
done
echo OK
