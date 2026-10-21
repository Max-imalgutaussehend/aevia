# 0043 n8n workflow builder through the Aevia MCP server

Date: 2026-10-21. Status: accepted.

## Context
n8n 2.13 and later has an instance-level MCP server (`/mcp-server/http`) with 34 tools: search nodes and read their types, validate and create workflows from SDK code,
update, publish, run and test them, data tables. It was already switched on in the restored database (`settings`: `mcp.access.enabled = true`). What was missing was an access token
and a way for Max's clients (claude.ai, Jarvis) to reach it: n8n itself sits behind Cloudflare Access.

## Decision
- The Aevia MCP server (apps namespace) bridges n8n's tools: each appears as `n8n_<name>` with n8n's original input schema, forwarded with a bearer token. The tool list is re-read every
  5 minutes, so a newer n8n brings its new tools by itself. `aevia_overview` shows the bridge status. Clients keep one MCP connection with the existing Authentik sign-in (claude.ai) or internal token (Jarvis).
- The token is made by `scripts/n8n-mcp-token.py`: n8n signs MCP tokens as JWTs (HS256, audience `mcp-server-api`) with `signing.jwt` from the table `deployment_key` and lists them in `user_api_keys`.
  The script does what the UI button does, without a browser login, and writes the SOPS secret `mcp-n8n`. Repeat it after a restore (`--rotate` replaces the token).
- Network: the MCP pod may reach n8n on 5678 (policy `n8n-from-mcp`); nothing else in the namespace may.
- Built-in guardrails stay: n8n validates every workflow (`validate_workflow` before `create_workflow_from_code`), tools that run workflows only see workflows that were exposed to MCP, and tokens act as the owner.

## Consequences
- Whoever can call this MCP server (Max through claude.ai, Jarvis) can create, change, publish and run n8n workflows as the owner. Archiving is a tool; permanently deleting is not.
- Verified end to end on 2026-10-21: validate, create, read and archive of a two-node test workflow through the bridge (the archived workflow is still listed under archived workflows in n8n).
- The bridge depends on the pinned `mcp` library internals (the tool registry); its tests (`tests/test_n8n.py`, including a real SSE transport) fail loudly if an upgrade breaks it.
