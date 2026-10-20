#!/usr/bin/env bash
# Backup/restore rehearsal on a throwaway kind cluster (phase 12/27/28 verification).
# Applies the real data layer with random test secrets, writes a row, runs the real pg-backup
# CronJob, destroys the database volume, restores from the dump, and checks the row came back.
# Needs docker, kind, kubectl. Creates and deletes cluster aevia-restore. Never touches a server.
set -euo pipefail
cd "$(dirname "$0")/../.."
CL=aevia-restore
trap 'kind delete cluster --name $CL >/dev/null 2>&1 || true' EXIT
kind create cluster --name $CL --wait 120s
rnd() { head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24; }
PW=$(rnd)
kubectl create ns data
kubectl -n data create secret generic postgres-auth --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD="$PW" --from-literal=POSTGRES_N8N_PASSWORD="$(rnd)" \
  --from-literal=POSTGRES_AUTHENTIK_PASSWORD="$(rnd)"
kubectl -n data create secret generic pg-backup-auth --from-literal=PGUSER=postgres --from-literal=PGPASSWORD="$PW"
kubectl -n data create secret generic redis-auth --from-literal=REDIS_PASSWORD="$(rnd)"
AK=$(rnd); SK=$(rnd)
kubectl -n data create secret generic s3-auth --from-literal=s3.json="{\"identities\":[{\"name\":\"admin\",\"credentials\":[{\"accessKey\":\"$AK\",\"secretKey\":\"$SK\"}],\"actions\":[\"Admin\",\"Read\",\"Write\",\"List\",\"Tagging\"]}]}"
# Only postgres + backup + s3: the other data components are covered by kubeconform.
kubectl -n data apply -f <(kubectl kustomize gitops/base/data | python3 -c '
import sys, yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d["metadata"]["name"].startswith(("postgres","s3")) and d["kind"] != "NetworkPolicy":
        print("---"); print(yaml.safe_dump(d))
')
kubectl -n data rollout status statefulset/postgres --timeout=240s
psql() { kubectl -n data exec postgres-0 -- psql -U postgres -tA "$@"; }
psql -d n8n -c "create table restore_probe(v text); insert into restore_probe values ('survives');"
kubectl apply -f gitops/base/backup/pg-backup.yaml
kubectl -n data create job --from=cronjob/pg-backup manual-backup
kubectl -n data wait --for=condition=complete job/manual-backup --timeout=180s
kubectl -n data logs job/manual-backup | tail -1
echo "-- destroy"
psql -d postgres -c "drop database n8n;"
[[ -z $(psql -d postgres -c "select 1 from pg_database where datname='n8n'") ]]
echo "-- restore"
kubectl -n data run restore --rm -i --restart=Never --image=postgres:17.7-alpine \
  --overrides='{"spec":{"securityContext":{"runAsUser":70,"runAsGroup":70},"containers":[{"name":"restore","image":"postgres:17.7-alpine","stdin":true,"command":["sh","-c","f=$(ls /backup/aevia-*.sql.gz | tail -1); gunzip -c $f | psql -h postgres -U postgres -d postgres -v ON_ERROR_STOP=0 >/dev/null"],"env":[{"name":"PGPASSWORD","value":"'"$PW"'"}],"volumeMounts":[{"name":"b","mountPath":"/backup"}]}],"volumes":[{"name":"b","persistentVolumeClaim":{"claimName":"pg-backup"}}]}}' >/dev/null 2>&1 || true
got=$(psql -d n8n -c "select v from restore_probe")
echo "restored value: ${got:-none}"
[[ $got == survives ]] || { echo "FAIL"; exit 1; }
echo "-- s3 auth"
kubectl -n data rollout status statefulset/s3 --timeout=240s
s3() { kubectl -n data run "s3-$1" --rm -i --restart=Never --image=amazon/aws-cli:2.17.0 --env=AWS_ACCESS_KEY_ID="$2" --env=AWS_SECRET_ACCESS_KEY="$3" -- --endpoint-url http://s3:8333 s3 mb "s3://probe-$1" 2>&1 || true; }
ok=0
for i in 1 2 3 4 5 6; do
  out=$(s3 "good$i" "$AK" "$SK")
  grep -q "make_bucket" <<<"$out" && { ok=1; break; }
  sleep 10
done
[[ $ok == 1 ]] || { echo "last s3 output: $out"; kubectl -n data logs s3-0 --tail=20 || true; echo "FAIL: valid key rejected"; exit 1; }
s3 bad wrong wrong | grep -q "InvalidAccessKeyId" || { echo "FAIL: invalid key accepted"; exit 1; }
echo PASS
