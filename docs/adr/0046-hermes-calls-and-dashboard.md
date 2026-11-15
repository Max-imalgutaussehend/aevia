# 0046 Hermes can phone Max, and keeps a personal dashboard

Date: 2026-11-15. Status: dashboard live (2026-11-15). callme is built and tested but held: the Twilio trial account has 0.00 USD credit and no free route exists, so there is no phone line.

## Context
Hermes (ADR 0045) reaches Max over Signal and ntfy. When he does not answer, it has no stronger channel. Max also wants one page (iPhone, Mac, Framework) that Hermes keeps up to date:
reminders, todos, trackers, financials.

## Decision
- **callme**: Aevia fork (repo `callme`) of ZeframLou/call-me (MIT, upstream 4e0aa20). Changes: no ngrok (fixed Cloudflare host `callme.maxrommel.de`), MCP over HTTP on `/mcp`
  with a bearer token instead of stdio, a mandatory Telnyx signature key for the upstream mode, and a new default **native mode**: the call uses Twilio's own `<Say>` and `<Gather input="speech">`
  (de-DE), so there is no OpenAI key, no Whisper and no TTS container. Max has no paid speech API, the AI gateway only serves chat models, and Kokoro cannot speak German; the node has no memory for
  local Whisper plus Piper. The upstream media-stream pipeline stays available as `CALLME_MODE=media`.
  Spend guard: 3 calls per 24 h, 5 minutes each, 30 minutes in total, one at a time (persisted on a 1 Gi volume), plus the live Twilio balance (refuses below 2 USD; tool `call_budget`).
  Runs in `apps`, not `agents`: it holds the phone and OpenAI credentials and needs no agent rights, and the `agents` memory quota is nearly used up.
  Hermes only receives the MCP token (`callme-mcp`), never the phone or OpenAI credentials. The host is public because the phone provider must reach `/twiml` and `/media-stream`;
  Twilio webhooks are signature-checked (constant-time compare, the expected value is never logged), `/mcp` needs the token.
- Escalation policy lives in the Hermes skill `call-escalation`: Signal, then ntfy, then a call, with quiet hours and no calls during lectures.
- **dashboard**: repo `dashboard`, Node without dependencies, state as JSON on a 1 Gi volume (last 50 versions kept). The page renders a closed set of widgets (callout, stat, todo,
  reminders, tracker, chart, budget, accounts, progress, agenda, list, text) from that state; Hermes changes only data through a validated API (bearer token, in-cluster only),
  so a bad edit cannot break the page or run code. Max can tick todos and reminders off on the page. Access is Cloudflare Access with Authentik; the app verifies the Access JWT itself
  and fails closed. The session lasts 30 days (`access_session: 720h`, new catalog field) so there is about one login a month per device.
- Both services are `hold`ed in `catalog/services.yml`: the generator emits nothing and tofu publishes nothing until the image digest and the SOPS secrets exist.

## Consequences
- Finding 2026-11-15: the Twilio console shows "Trial balance: $0.00" and "Days left in trial: 30"; the billing and verified-numbers pages redirect to "Upgrade". Without funds no call can be placed, so callme stays held and Hermes escalates with Signal and ntfy (priority 5) only.
- Original goal: pay nothing. A Twilio trial account runs on free credit and, as far as I know, cannot be charged as long as no card is added or the account upgraded: calls then simply stop when the credit is gone. Native-mode speech (Gather, Say) is billed from that credit. The trial announcement plays before each call and Max has to press a key; calls go only to verified numbers.
- The Twilio speech quality (voice `alice`, recognition default model) is plainer than OpenAI's; `CALLME_VOICE` can be changed.
- The Hermes seed config is only copied once; an init step merges the `callme` MCP server into an existing `config.yaml`, and the two new skills are copied if missing.
- Financial data on the dashboard is only what Max or his notes provide; Hermes does not read bank accounts.
