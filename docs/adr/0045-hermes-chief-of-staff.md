# 0045 Hermes Agent as the always-on chief of staff (beta)

Date: 2026-11-11. Status: accepted as a beta; the subscription login is untested (see below).

## Context
Hermes (Nous Research, MIT, v0.23.1) can use a Claude subscription through its own Anthropic OAuth (`hermes model`), without a proxy. Its docs say this works only on Claude Max with
purchased extra usage and not on Pro; Max has Pro. The goal is one central agent with access to everything around Aevia that runs 24/7, and a way to track how much of the
subscription idle work (heartbeats, scheduled jobs) uses over time.

## Decision
- StatefulSet `hermes` in `agents` (same isolation as Herdr and Jarvis: default-deny, no databases), image `nousresearch/hermes-agent` pinned by digest, 5 Gi volume `/vol/h (the volume is mounted at /vol)`, 1.5 Gi limit.
- The image's s6-overlay needs root, so the gateway (`hermes gateway run`: cron scheduler and an OpenAI-compatible API server on 8642) is started directly as PID 1 (behind tini the CLI re-enters the s6 entrypoint); Kubernetes restarts it. Zombie processes are not reaped, which the CLI warns about.
- Config is seeded once from a ConfigMap (model `anthropic`, Aevia MCP server with the internal bearer token, local terminal backend), plus `SOUL.md` (chief of staff, German, never merges or deploys) and a skill `aevia-handover` that calls the handover API of the Herdr pod. Hermes may edit its own config afterwards.
- Building on the server is the existing handover path (Herdr + Claude Code through the AI gateway), not a Docker sandbox: there is no Docker daemon in the cluster, and E2B is not a Hermes backend. `terminal.backend: local` runs inside the isolated pod.
- Jarvis reaches Hermes only through the API server (NetworkPolicy, bearer key in the secret `hermes-api`). The wiring on the Jarvis side lives in the jarvis repository.
- Tracking: the sidecar `usage-track` appends `hermes usage --json` (subscription windows) to `/vol/h (the volume is mounted at /vol)/usage/usage.jsonl` every 30 minutes; `hermes insights` gives per-session tokens and cost; one-shot runs can write `--usage-file`.

## Consequences
- The login is done by hand: `kubectl -n agents exec -it hermes-0 -- hermes model`. Two programs sharing one Claude login can invalidate each other's refresh tokens: do not copy `~/.claude` credentials into the pod.
- If Anthropic refuses Pro on this path, fall back to the AI gateway (OpenAI wire format) or an API key; the rest stays.
- Memory: about 210 MiB idle, up to 1.5 Gi under load on a node with little headroom; the pod has the lowest priority and yields first.

## Measured 2026-11-11
The subscription login works (Claude Pro, Anthropic OAuth token, one-shot answered). A trivial one-shot costs about 20,000 input tokens. This is not the MCP server: Hermes loads
MCP tools on demand (`tool_search`), the weight is its own default toolsets (21 tools, about 40 KB of schemas) plus the system prompt (10 KB). The `lazy` option of an MCP
server only defers the connection, it does not remove schemas from the context.
Heartbeat: job `heartbeat` (every 60 minutes, prompt "answer only ok", delivery `local`), toolsets browser, vision, image_gen, tts, computer_use, connections, delegation and
code_execution disabled for the platform `cron` (`hermes tools disable <name> --platform cron`; this state lives in the volume, not in git). One run: 13,972 tokens, about 335,000 tokens a day,
mostly cache reads. The tracker shows it as source `cron`. Further cuts: fewer toolsets, a longer interval, or `--no-agent` jobs (no model call at all, but then no real heartbeat).
