# 0042 Memory diet

Date: 2026-10-21. Status: accepted.

## Context
The node has 8 GB and no swap. The dashboard said 74 % used, but that mixes in file cache. What counts is `MemAvailable`: 1.9 GB, with 5.2 GB of resident
program memory (3.7 GB in containers, 1.4 GB k3s and the container runtime). Everything below was measured on the node before it was changed
(`scripts/mem-report.sh` repeats the measurements).

## Decision
Three methods, applied together.

1. **Remove what nothing uses.** The in-cluster S3 (SeaweedFS, 147 MiB, one 8-byte object, 20 GiB volume with preallocated files; backups live in R2), the Loki rules sidecar
   (68 MiB, no rules exist), the Argo CD ApplicationSet and notifications controllers (46 MiB, no ApplicationSets, no subscriptions) and the Grafana datasource sidecar
   (73 MiB, one datasource, now provisioned as a file). Removed from git, secrets and the restore test; the live objects were deleted by hand because Argo CD does not prune.
2. **A soft Go memory limit.** Go collects garbage when the heap has doubled, so resident memory is about twice the live data. A soft `GOMEMLIMIT` just above the live heap
   keeps it there without extra CPU: Argo CD application controller 409 to 240 MiB (limit 260 MiB), Prometheus 450 MiB, k3s 800 MiB (live heap 419 MiB, heap goal 556 MiB, process
   1185 to about 900 MiB). k3s: `cluster/bootstrap/k3s/k3s.service.env`. A soft limit never kills a process; above it the GC works harder.
3. **A series diet for Prometheus.** 87 000 of 101 000 series came from the `kubelet` and `apiserver` jobs, 58 800 of them histogram buckets. k3s serves the apiserver registry through the kubelet endpoint
   as well, so those families existed twice. Dropped: `apiserver_*`, `etcd_*`, `scheduler_*` from the kubelet job, and seven large bucket families no dashboard or rule reads from the
   apiserver job. Kept: `apiserver_request_duration_seconds_bucket` and `apiserver_request_sli_duration_seconds_bucket` (kube-prometheus dashboards and error-budget rules). Series scraped from the two jobs: 88 700 to 34 000.

## Tried and rejected
- `MALLOC_ARENA_MAX=2` for the Authentik worker (glibc arenas): 291 to 313 MiB, no effect.
- zram swap: the Python and Node memory compresses 3.2 to 3.7 times, but pods may not swap by default; it needs a kubelet setting and a k3s restart for a gain the three methods already give. Revisit if memory gets tight again.
- Lowering k3s below 800 MiB: the heap goal would approach the live heap (419 MiB) and the GC would run constantly.

## Consequences
- The API server and kubelet latency histograms (except the two above) are gone from Prometheus; nothing in the stack reads them.
- Agents have no in-cluster object store any more (it held nothing). If a workload needs one, use R2 (ADR 0039) rather than running a store in the cluster.
- A soft limit that is set too low makes the GC spin. If k3s or Prometheus CPU rises, raise the limit before anything else.
- Disk: 75 % to 45 % because the SeaweedFS volume files were preallocated.
