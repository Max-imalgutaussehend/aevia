#!/usr/bin/env bash
# Opens the SSH tunnel to the k3s API and port-forwards the internal UIs to localhost.
# Needs: ~/.kube/aevia.yaml (or KUBECONFIG) pointing at https://127.0.0.1:16443, SSH access to the node.
#   argocd https://localhost:8080   grafana http://localhost:3000   prometheus http://localhost:9090
#   hubble http://localhost:12000   freellmapi http://localhost:13001
# Stop everything with Ctrl-C.
set -euo pipefail
NODE=${AEVIA_NODE:-root@2.31.1.35}
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/aevia.yaml}
kubectl get nodes >/dev/null 2>&1 || ssh -f -N -L 16443:127.0.0.1:6443 "$NODE"
pids=()
pf() { kubectl -n "$1" port-forward "$2" "$3" >/dev/null 2>&1 & pids+=($!); }
trap 'kill "${pids[@]}" 2>/dev/null' EXIT
pf argocd svc/argocd-server 8080:443
pf observability svc/kube-prometheus-stack-grafana 3000:80
pf observability svc/kps-prometheus 9090:9090
pf kube-system svc/hubble-relay 12000:80
pf platform svc/freellmapi 13001:3001
echo "argocd   https://localhost:8080  (user admin; password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo "grafana  http://localhost:3000   (user admin; password: Bitwarden item "Aevia R2 - Grafana")"
echo "prometheus http://localhost:9090 | hubble relay localhost:12000 | freellmapi http://localhost:13001"
wait
