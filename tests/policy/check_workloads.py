#!/usr/bin/env python3
"""Fail if any hand-written or generated workload under gitops/base breaks the baseline:
memory limit, allowPrivilegeEscalation=false, no privileged/hostNetwork/hostPath, no :latest."""
import subprocess, sys
import yaml

DIRS = ["namespaces", "data", "edge", "backup", "services", "platform", "agents"]
bad = []
for d in DIRS:
    out = subprocess.run(["kubectl", "kustomize", f"gitops/base/{d}"], check=True, capture_output=True, text=True).stdout
    for doc in yaml.safe_load_all(out):
        if not doc or doc.get("kind") not in ("Deployment", "StatefulSet", "CronJob", "DaemonSet"):
            continue
        spec = doc["spec"]
        if doc["kind"] == "CronJob":
            spec = spec["jobTemplate"]["spec"]
        pod = spec["template"]["spec"]
        name = f'{doc["kind"]}/{doc["metadata"]["name"]}'
        if pod.get("hostNetwork") or pod.get("hostPID"):
            bad.append(f"{name}: host namespaces")
        if any("hostPath" in v for v in pod.get("volumes", [])):
            bad.append(f"{name}: hostPath volume")
        for c in pod["containers"]:
            sc = c.get("securityContext", {})
            if sc.get("privileged"):
                bad.append(f"{name}/{c['name']}: privileged")
            if sc.get("allowPrivilegeEscalation") is not False:
                bad.append(f"{name}/{c['name']}: allowPrivilegeEscalation not false")
            if "memory" not in c.get("resources", {}).get("limits", {}):
                bad.append(f"{name}/{c['name']}: no memory limit")
            if c["image"].endswith(":latest") or (":" not in c["image"].split("/")[-1] and "@" not in c["image"]):
                bad.append(f"{name}/{c['name']}: unpinned image {c['image']}")
if bad:
    print("\n".join(bad))
    sys.exit(1)
print("workload policy OK")
