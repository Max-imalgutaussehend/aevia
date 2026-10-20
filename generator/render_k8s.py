#!/usr/bin/env python3
"""Generate Kubernetes manifests from catalog/services.yml (ADR-0033).

One file per service in gitops/base/services/, plus a kustomization.yaml.
Held services (`hold:` set) get nothing.

    python3 generator/render_k8s.py          # write
    python3 generator/render_k8s.py --check  # exit 1 if output would change
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog" / "services.yml"
OUT = REPO / "gitops" / "base" / "services"

DATA_BACKENDS = {"postgres": ("data", 5432), "redis": ("data", 6379)}
DOMAIN = "maxrommel.de"
NS_BY_TYPE = {"application": "apps", "platform": "platform"}


def load() -> list[dict]:
    doc = yaml.safe_load(CATALOG.read_text())
    d = doc["defaults"]
    out = []
    for s in doc["services"]:
        if s.get("hold") or s.get("managed_by"):
            continue
        if "image" not in s:
            sys.exit(f"error: {s['name']} has no image and is not held")
        if ":latest" in s["image"]:
            sys.exit(f"error: {s['name']} uses :latest")
        for k, v in d.items():
            s.setdefault(k, v)
        s.setdefault("namespace", NS_BY_TYPE[s["type"]])
        for n in s["needs"]:
            if n not in DATA_BACKENDS and n not in {x["name"] for x in doc["services"]}:
                sys.exit(f"error: {s['name']} needs unknown service {n}")
        out.append((s, {x["name"]: x for x in doc["services"]}))
    return out


def render(s: dict, by_name: dict) -> str:
    n, ns, port = s["name"], s["namespace"], s["port"]
    labels = {"app.kubernetes.io/name": n, "app.kubernetes.io/part-of": "aevia"}
    sel = {"app.kubernetes.io/name": n}
    persist = s["persistence"] != "none"
    # nginx-based static builds need writable scratch dirs; stateful apps need a PVC.
    vols = [{"name": "tmp", "emptyDir": {}}]
    mounts = [{"name": "tmp", "mountPath": "/tmp"}]
    if persist:
        vols.append({"name": "data", "persistentVolumeClaim": {"claimName": f"{n}-data"}})
        mounts.append({"name": "data", "mountPath": s.get("data_path", "/data")})
    cport = s.get("container_port", port)
    container = {
        "name": n,
        "image": s["image"],
        "ports": [{"name": "http", "containerPort": cport}],
        "resources": {
            "requests": {"cpu": s["resources"]["cpu"], "memory": s["resources"]["memory"]},
            "limits": {"memory": s["resources"]["memory"]},
        },
        "securityContext": {
            "allowPrivilegeEscalation": False,
            "capabilities": {"drop": ["ALL"]},
            "seccompProfile": {"type": "RuntimeDefault"},
        },
        "volumeMounts": mounts,
    }
    for i, sp in enumerate(s.get("scratch_paths", [])):
        vols.append({"name": f"scratch-{i}", "emptyDir": {}})
        mounts.append({"name": f"scratch-{i}", "mountPath": sp})
    if s.get("add_caps"):
        container["securityContext"]["capabilities"]["add"] = s["add_caps"]
    if s.get("args"):
        container["args"] = s["args"]
    if s.get("env"):
        container["env"] = [{"name": k, "value": str(v)} for k, v in s["env"].items()]
    if s.get("secret_env"):
        refs = s["secret_env"] if isinstance(s["secret_env"], list) else [s["secret_env"]]
        container["envFrom"] = [{"secretRef": ({"name": r} if isinstance(r, str) else dict(r))} for r in refs]
    cfg = s.get("config_file")
    extra_docs = []
    if cfg:
        vols.append({"name": "config", "configMap": {"name": cfg["configmap"]}})
        mounts.append({"name": "config", "mountPath": cfg["mount"],
                       "subPath": Path(cfg["source"]).name, "readOnly": True})
        extra_docs.append({
            "apiVersion": "v1", "kind": "ConfigMap",
            "metadata": {"name": cfg["configmap"], "namespace": ns, "labels": labels},
            "data": {Path(cfg["source"]).name: (REPO / cfg["source"]).read_text()},
        })
    if s.get("healthcheck"):
        probe = {"httpGet": {"path": s["healthcheck"], "port": "http"}}
        container["readinessProbe"] = dict(probe, periodSeconds=15)
        container["livenessProbe"] = dict(probe, periodSeconds=30, initialDelaySeconds=30)
    if s["type"] == "application" and not persist:
        container["securityContext"]["readOnlyRootFilesystem"] = True
        for p in ("/var/cache/nginx", "/var/run"):
            nm = p.strip("/").replace("/", "-")
            vols.append({"name": nm, "emptyDir": {}})
            mounts.append({"name": nm, "mountPath": p})
    pod_sc = {"seccompProfile": {"type": "RuntimeDefault"}}
    if s.get("uid"):  # only where the image is verified to run as that uid
        pod_sc.update(runAsNonRoot=True, runAsUser=s["uid"], runAsGroup=s["uid"], fsGroup=s["uid"])
    dep = {
        "apiVersion": "apps/v1",
        "kind": "Deployment",
        "metadata": {"name": n, "namespace": ns, "labels": labels},
        "spec": {
            "replicas": s["replicas"],
            "strategy": {"type": "Recreate"} if persist else {"type": "RollingUpdate"},
            "selector": {"matchLabels": sel},
            "template": {
                "metadata": {"labels": labels},
                "spec": {
                    # service_account: the pod gets its own account and its token (RBAC lives next to the manifests)
                    "automountServiceAccountToken": bool(s.get("service_account")),
                    **({"serviceAccountName": s["service_account"]} if s.get("service_account") else {}),
                    "securityContext": pod_sc,
                    "containers": [container],
                    "volumes": vols,
                },
            },
        },
    }
    svc = {
        "apiVersion": "v1",
        "kind": "Service",
        "metadata": {"name": n, "namespace": ns, "labels": labels},
        "spec": {"selector": sel, "ports": [{"name": "http", "port": port, "targetPort": "http"}]},
    }
    egress = [{"to": [{"namespaceSelector": {}, "podSelector": {"matchLabels": {"k8s-app": "kube-dns"}}}],
               "ports": [{"port": 53, "protocol": "UDP"}, {"port": 53, "protocol": "TCP"}]}]
    for need in s["needs"]:
        if need in DATA_BACKENDS:
            nns, nport = DATA_BACKENDS[need]
            egress.append({"to": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": nns}},
                                   "podSelector": {"matchLabels": {"app.kubernetes.io/name": need}}}],
                           "ports": [{"port": nport}]})
        else:
            dep_s = by_name[need]
            dns = dep_s.get("namespace", NS_BY_TYPE[dep_s["type"]])
            egress.append({"to": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": dns}},
                                   "podSelector": {"matchLabels": {"app.kubernetes.io/name": need}}}],
                           "ports": [{"port": dep_s.get("container_port", dep_s["port"])}]})
    if s.get("internet"):
        egress.append({"to": [{"ipBlock": {"cidr": "0.0.0.0/0", "except": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]}}],
                       "ports": [{"port": 443}, {"port": 80}]})
    np_ingress = {
        "apiVersion": "networking.k8s.io/v1",
        "kind": "NetworkPolicy",
        "metadata": {"name": f"{n}-ingress", "namespace": ns},
        "spec": {
            "podSelector": {"matchLabels": sel},
            "policyTypes": ["Ingress"],
            "ingress": [{"from": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "ingress"}}}]
                         + [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "platform"}},
                             "podSelector": {"matchLabels": {"app.kubernetes.io/name": "status"}}}],
                         "ports": [{"port": cport}]}],
        },
    }
    np_egress = {
        "apiVersion": "networking.k8s.io/v1",
        "kind": "NetworkPolicy",
        "metadata": {"name": f"{n}-egress", "namespace": ns},
        "spec": {"podSelector": {"matchLabels": sel}, "policyTypes": ["Egress"], "egress": egress},
    }
    docs = [dep, svc] + extra_docs
    if persist:
        docs.append({
            "apiVersion": "v1",
            "kind": "PersistentVolumeClaim",
            "metadata": {"name": f"{n}-data", "namespace": ns, "labels": labels},
            "spec": {"accessModes": ["ReadWriteOnce"], "resources": {"requests": {"storage": s["persistence"]}}},
        })
    host = DOMAIN if s.get("apex") else f"{n}.{DOMAIN}"
    docs.append({
        "apiVersion": "networking.k8s.io/v1", "kind": "Ingress",
        "metadata": {"name": n, "namespace": ns, "labels": labels},
        "spec": {"ingressClassName": "traefik", "rules": [{"host": h, "http": {"paths": [
            {"path": "/", "pathType": "Prefix", "backend": {"service": {"name": n, "port": {"name": "http"}}}}]}}
            for h in [host] + [f"{a}.{DOMAIN}" for a in s.get("aliases", [])]]},
    })
    docs += [np_ingress, np_egress]
    header = f"# GENERATED by generator/render_k8s.py from catalog/services.yml. Do not edit.\n"
    return header + "---\n".join(yaml.safe_dump(d, sort_keys=False) for d in docs)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    check = ap.parse_args().check
    files: dict[Path, str] = {}
    names = []
    for s, by_name in load():
        files[OUT / f"{s['name']}.yaml"] = render(s, by_name)
        names.append(f"{s['name']}.yaml")
    kust = {"apiVersion": "kustomize.config.k8s.io/v1beta1", "kind": "Kustomization", "resources": sorted(names)}
    files[OUT / "kustomization.yaml"] = (
        "# GENERATED by generator/render_k8s.py. Do not edit.\n" + yaml.safe_dump(kust, sort_keys=False)
    )
    stale = [p for p in OUT.glob("*.yaml") if p not in files] if OUT.exists() else []
    if check:
        bad = [str(p.relative_to(REPO)) for p, t in files.items() if not p.exists() or p.read_text() != t]
        bad += [str(p.relative_to(REPO)) for p in stale]
        if bad:
            print("k8s manifests out of date:", *bad, sep="\n  ")
            return 1
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    for p in stale:
        p.unlink()
    for p, t in files.items():
        p.write_text(t)
    print(f"wrote {len(files)} files to {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
