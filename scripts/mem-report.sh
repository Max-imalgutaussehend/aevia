#!/usr/bin/env bash
# Where does the node's memory go? Run from the laptop (SSH to the node, tunnel not needed for the first two parts).
#   1. host: what is really used (anonymous program memory) and what the kernel can drop (cache); MemAvailable is the number that matters
#   2. every container split into anonymous memory and file cache, from the cgroups
#   3. k3s: live heap versus what the Go GC holds back (needs KUBECONFIG and the tunnel)
set -euo pipefail
NODE=${NODE:-root@2.31.1.35}
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/aevia.yaml}
ssh -o ConnectTimeout=15 "$NODE" 'free -m | sed -n 1,2p; grep -E "MemAvailable|AnonPages|^Cached" /proc/meminfo; df -h / | tail -1
python3 - <<"PY"
import glob, json, re, subprocess
names = {}
for c in json.loads(subprocess.run(["crictl", "ps", "-a", "-o", "json"], capture_output=True, text=True).stdout)["containers"]:
    names[c["id"]] = c["labels"].get("io.kubernetes.pod.namespace", "?") + "/" + c["labels"].get("io.kubernetes.pod.name", "?")[:34] + ":" + c["metadata"]["name"]
rows = []
for d in glob.glob("/sys/fs/cgroup/kubepods.slice/**/cri-containerd-*.scope", recursive=True):
    cid = re.search(r"cri-containerd-([0-9a-f]{64})", d).group(1)
    try: st = dict(l.split() for l in open(d + "/memory.stat").read().splitlines())
    except Exception: continue
    rows.append((int(st.get("anon", 0)), int(st.get("file", 0)), names.get(cid, cid[:12])))
rows.sort(reverse=True)
print("containers: %d  anon %d MiB  file cache %d MiB" % (len(rows), sum(r[0] for r in rows) // 2**20, sum(r[1] for r in rows) // 2**20))
print("  anon   file  container")
for a, f, n in rows[:15]: print("%6d %6d  %s" % (a // 2**20, f // 2**20, n))
PY'
echo "--- k3s Go heap (MiB):"
kubectl get --raw /metrics 2>/dev/null | grep -E '^(go_gc_heap_live_bytes|go_gc_heap_goal_bytes|go_gc_gomemlimit_bytes|go_memstats_heap_idle_bytes|go_memstats_heap_released_bytes|process_resident_memory_bytes) ' \
  | awk '{printf "  %-34s %8.0f\n", $1, $2/1048576}' || echo "  (no cluster access)"
