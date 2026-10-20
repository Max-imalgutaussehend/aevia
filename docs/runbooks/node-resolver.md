# Runbook: fixed resolver file for the node (silences "Nameserver limits exceeded")

Symptom: hundreds of Warning events "Nameserver limits exceeded" on Cilium, CoreDNS and the node exporter. Harmless, but noisy.
Cause: the node's `/etc/resolv.conf` lists more than three nameservers and Kubernetes only uses three.

On `aevia-control-01` (SSH as root through the allowed address):
```sh
printf 'nameserver 185.12.64.1\nnameserver 185.12.64.2\n' > /etc/rancher/k3s/resolv.conf
# add to /etc/rancher/k3s/config.yaml (it is already in cluster/bootstrap/k3s/config.yaml):
#   kubelet-arg: ["resolv-conf=/etc/rancher/k3s/resolv.conf"]
systemctl restart k3s        # the API is unavailable for about a minute; running pods keep running
```
Check: `kubectl get events -A | grep -c "Nameserver limits"` stops growing; pods resolve names (`kubectl -n apps exec deploy/mcp -- getent hosts argocd-server.argocd`).
Rollback: remove the `kubelet-arg` line and restart k3s.
