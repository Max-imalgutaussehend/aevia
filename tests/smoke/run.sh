#!/usr/bin/env bash
# Smoke test: the real generated manifests, real namespaces (PSS + quotas enforced) and data layer on
# a throwaway kind cluster with random test secrets. Fails if any workload does not become Ready.
# kindnet enforces NetworkPolicy, so the real default-deny and allow-rules are exercised too.
# regime-lens is amd64-only and is skipped on arm hosts. Never touches a server.
set -euo pipefail
cd "$(dirname "$0")/../.."
CL=aevia-smoke
trap 'kind delete cluster --name $CL >/dev/null 2>&1 || true' EXIT
kind create cluster --name $CL --wait 120s
rnd() { head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24; }
PW=$(rnd); NPW=$(rnd)
kubectl apply -f <(kubectl kustomize gitops/base/namespaces | grep -v '^$') >/dev/null
kubectl -n data create secret generic postgres-auth --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD="$PW" --from-literal=POSTGRES_N8N_PASSWORD="$NPW" \
  --from-literal=POSTGRES_AUTHENTIK_PASSWORD="$(rnd)"
kubectl -n data create secret generic redis-auth --from-literal=REDIS_PASSWORD="$(rnd)"
kubectl -n apps create secret generic n8n-env --from-literal=N8N_ENCRYPTION_KEY="$(rnd)" \
  --from-literal=DB_POSTGRESDB_PASSWORD="$NPW"
kubectl kustomize gitops/base/data | python3 -c '
import sys, yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d["metadata"]["name"].startswith(("postgres","redis")):
        d["metadata"]["namespace"] = "data"; print("---"); print(yaml.safe_dump(d))
' | kubectl apply -f -
kubectl -n data rollout status statefulset/postgres --timeout=300s
kubectl -n data rollout status statefulset/redis --timeout=300s
kubectl -n platform create secret generic freellmapi-env --from-literal=ENCRYPTION_KEY="$(openssl rand -hex 32)"
echo "seed-probe" > /tmp/aevia-seed-probe.txt
kubectl -n platform create secret generic freellmapi-seed --from-file=probe.txt=/tmp/aevia-seed-probe.txt
kubectl kustomize gitops/base/ai-gateway | kubectl apply -f -
skip=""
[[ $(uname -m) == arm64 || $(uname -m) == aarch64 ]] && skip="regime-lens"
kubectl kustomize gitops/base/services | python3 -c '
import sys, yaml
skip = sys.argv[1]
for d in yaml.safe_load_all(sys.stdin):
    if d and d["metadata"]["name"] not in (skip, skip + "-ingress", skip + "-egress"):
        print("---"); print(yaml.safe_dump(d))
' "$skip" | kubectl apply -f - 2>&1 | grep -v "no matches for kind" || true
fail=0
for d in $(kubectl get deploy -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {end}'); do
  ns=${d%/*}; n=${d#*/}
  [[ $ns == kube-system || $ns == local-path-storage ]] && continue
  if kubectl -n "$ns" rollout status "deploy/$n" --timeout=240s >/dev/null 2>&1; then echo "ready  $d"; else
    echo "NOT READY $d"; kubectl -n "$ns" describe pod -l app.kubernetes.io/name="$n" | tail -15
    kubectl -n "$ns" logs -l app.kubernetes.io/name="$n" --tail=15 2>&1 || true; fail=1; fi
done
seeded=$(kubectl -n platform exec deploy/freellmapi -c freellmapi -- cat /app/server/data/probe.txt 2>/dev/null || true)
[[ $seeded == seed-probe ]] && echo "ready  seed copied into freellmapi data volume" || { echo "NOT READY seed not copied: $seeded"; fail=1; }
[[ $fail == 0 ]] || { echo FAIL; exit 1; }
echo PASS
