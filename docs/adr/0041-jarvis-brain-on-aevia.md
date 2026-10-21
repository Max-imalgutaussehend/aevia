# 0041 Jarvis: brain on Aevia, voice on the laptop

Date: 2026-10-21. Status: accepted.

## Context
Jarvis is a voice assistant for Claude Code (own repo, private). Its client/server split lives on the branch `spike/deployment`: the voice node
(wake word, speech to text, text to speech) needs a microphone and stays on the laptop; the brain (UI, sessions, `claude -p`) needs no audio and can run anywhere.

## Decision
- The brain runs as a catalog service `jarvis` in the `agents` namespace: same isolation as the Herdr workspace (default-deny, gateway reachable, no databases). Claude Code runs with edit rights, so it must not sit next to the data.
- Sign-in: Cloudflare Access with Authentik (like every private host). The brain checks the Access JWT itself (`JARVIS_CF_TEAM`, `JARVIS_CF_AUD`), so a bypass of the edge would not open it.
- Model access: through the AI gateway (`ANTHROPIC_BASE_URL`, key from the existing secret `herdr-gateway`), no Claude login in the pod and no extra cost.
- State: one 10 Gi volume (`/data`: sessions, Claude's own session files via `HOME`, workspaces).
- Image: built from the jarvis repo by CI, published as a public GHCR package (the repo stays private, the brain code is visible in the image, there are no secrets in it), digest pinned in the catalog.
- Traefik may now reach the `agents` namespace; Herdr stays unreachable because `agents` denies ingress by default.

## Update: laptop panel, MCP, harness
- Settings of the page show whether the voice node on the laptop is connected and current; update, restart and a setup download (launchd agent) are buttons there.
- The brain reaches the platform MCP server with a shared internal token (secrets `mcp-internal` in apps and `jarvis-mcp` in agents). The MCP server accepts that token only for calls that did not come through Cloudflare; a NetworkPolicy allows exactly Jarvis to reach it.
- Claude Code runs with an explicit allowlist: read and web by default, edit rights and extra tools per workspace, `--max-turns` and a turn timeout, the whole process group is killed on stop. `main` of the jarvis repo is this mode.

## Consequences
- Memory: limit 768 Mi in `agents` (quota 4 Gi); the node is at about 70 % memory.
- Anyone who passes Access can make Claude edit files in the Jarvis volume: keep the Access policy to the operator.
- Gotcha found on the way: a Service named `jarvis` makes Kubernetes inject `JARVIS_PORT=tcp://...`; the catalog sets `JARVIS_PORT` explicitly.
