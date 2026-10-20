# ADR-0036: Herdr workspace and object store consumers

Status: accepted (2026-10-20); the agent node is created only after explicit approval (billable).

## Object store
SeaweedFS (S3 API, `data/s3`) replaces MinIO. It now has two buckets with one identity each, plus the admin:
- `artifacts`: identity `apps` (Read/Write/List/Tagging on this bucket only)
- `agent-workspace`: identity `agents` (same, this bucket only)
Verified: each identity is refused on the other bucket. Credentials live only in the SOPS secret `s3-auth` (and
`herdr-s3` for the agents identity). Apps get no network path to the store until one is named; the agents path is added
together with the Herdr profile (`s3-from-agents` policy).

## Herdr
Herdr (Apache-2.0) is a terminal multiplexer that keeps coding agents running in a background server. It runs as one
StatefulSet pod `herdr-0` in `agents` on a dedicated node (taint `workload=agent:NoSchedule`), image built by CI from
`agents/herdr/image` (binary pinned by sha256), 10 GiB home volume. Agent CLIs are installed into that home by the user.
Access is `kubectl -n agents exec -it herdr-0 -- herdr`; there is no public hostname.
Network: DNS, public HTTPS, `freellmapi:3001` and `s3:8333` (bucket `agent-workspace`). Not Postgres, Redis, NATS, n8n or the
Kubernetes API (`tests/isolation` still proves agents cannot reach Postgres).

## Cost
Agent node cx23 (2 vCPU, 4 GB): about 6.53 EUR per month at Hetzner (gross, hel1, 2026-10).
