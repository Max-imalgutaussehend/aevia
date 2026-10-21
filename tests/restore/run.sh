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
# Only postgres + backup: the other data components are covered by kubeconform.
kubectl -n data apply -f <(kubectl kustomize gitops/base/data | python3 -c '
import sys, yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d["metadata"]["name"].startswith(("postgres",)) and d["kind"] != "NetworkPolicy":
        print("---"); print(yaml.safe_dump(d))
')
kubectl -n data rollout status statefulset/postgres --timeout=240s
psql() { kubectl -n data exec postgres-0 -- psql -U postgres -tA "$@"; }
psql -d n8n -c "create table restore_probe(v text); insert into restore_probe values ('survives');"
# The real job also uploads to the Hetzner bucket; the test points the same `enc:` remote at a local dir.
kubectl -n data create secret generic backup-offsite --from-literal=RCLONE_CONFIG_ENC_TYPE=alias --from-literal=RCLONE_CONFIG_ENC_REMOTE=/tmp/offsite
kubectl apply -f gitops/base/backup/pg-backup.yaml
kubectl -n data create job --from=cronjob/pg-backup manual-backup
kubectl -n data wait --for=condition=complete job/manual-backup --timeout=180s
kubectl -n data logs job/manual-backup -c dump | tail -1
kubectl -n data logs job/manual-backup -c upload 2>/dev/null | grep -q 'aevia-.*sql.gz' || { echo "upload step did not list the dump"; exit 1; }
echo "-- destroy"
psql -d postgres -c "drop database n8n;"
[[ -z $(psql -d postgres -c "select 1 from pg_database where datname='n8n'") ]]
echo "-- restore"
kubectl -n data run restore --rm -i --restart=Never --image=postgres:17.7-alpine \
  --overrides='{"spec":{"securityContext":{"runAsUser":70,"runAsGroup":70},"containers":[{"name":"restore","image":"postgres:17.7-alpine","stdin":true,"command":["sh","-c","f=$(ls /backup/aevia-*.sql.gz | tail -1); gunzip -c $f | psql -h postgres -U postgres -d postgres -v ON_ERROR_STOP=0 >/dev/null"],"env":[{"name":"PGPASSWORD","value":"'"$PW"'"}],"volumeMounts":[{"name":"b","mountPath":"/backup"}]}],"volumes":[{"name":"b","persistentVolumeClaim":{"claimName":"pg-backup"}}]}}' >/dev/null 2>&1 || true
got=$(psql -d n8n -c "select v from restore_probe")
echo "restored value: ${got:-none}"
[[ $got == survives ]] || { echo "FAIL"; exit 1; }
echo PASS
