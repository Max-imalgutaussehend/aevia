# agents/herdr — agent profiles

Agents are plain Kubernetes workloads in namespace `agents` (ADR-0028). The scaffold
(ServiceAccount, egress policy) is `gitops/base/agents/agents.yaml`; the quota and PSS
`restricted` come from `gitops/base/namespaces`.

A profile must:
- use `serviceAccountName: agent`, `automountServiceAccountToken: false`
- run on the agent node: `nodeSelector: {workload: agent}` and toleration `workload=agent:NoSchedule`
- set `runAsNonRoot`, drop ALL capabilities, a memory limit

`tests/isolation/run.sh` proves agents cannot reach `data`. Real profiles are added when the
first agent is chosen; none exists yet.
