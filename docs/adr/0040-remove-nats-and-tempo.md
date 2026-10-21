# 0040 Remove NATS and Tempo

Date: 2026-10-21. Status: accepted.

## Context
NATS (JetStream) was installed ahead of need: no service uses it and the namespace policy allows no ingress to it. Tempo stores traces, but
no service sends any. The node has 8 GB and runs at about 72 % memory, so unused components cost headroom and attention (updates, policies, dashboards).

## Decision
Remove both from the platform: the NATS manifests, the Tempo Argo app and its values, the trace pipeline of the OTel collector (it keeps shipping logs
to Loki) and the `tempo` chart from `scripts/k8s-validate.sh`. Git history keeps the manifests. When a service really needs a message bus or traces,
add the component back together with that service (new ADR) instead of running it speculatively.
Argo CD runs without prune, so the live objects were deleted by hand after the commit.

## Consequences
Less memory used and two fewer things to patch. Applications that want to send traces have nowhere to send them until Tempo returns.
