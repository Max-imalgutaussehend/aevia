# ADR-0038: Handover between the laptop and the server agent

Status: accepted (2026-10-20)

## Context
Long tasks should keep running when the laptop is closed, and the result must come back with an honest list of what only the operator can do.
The server has a Herdr pod (ADR-0036) with Claude Code and the AI gateway, but no shared state with the laptop session.

## Decision
- **Transport is git.** The laptop pushes `handover/<slug>` with `.handover/<slug>/HANDOVER.md`; the server pushes to the same branch with `RESULT.md`.
  No new service, full history, reviewable diffs, works for any repository the server can read.
- **Two skills** for Claude Code on the laptop: `handover` (prepare, write the note, push, start) and `handover-back` (read the result, review, merge, do the laptop steps).
  Versioned in `agents/herdr/skills`, installed with `install.sh`.
- **One runner** in the image, `aevia-handover` (start, status, logs, result, stop, list). It clones the branch, runs Claude Code headless against the gateway with a tool
  allow-list and turn and time limits, guarantees a RESULT.md (a stub with status `blocked` if the agent wrote none), commits, pushes and sends an ntfy message.
- **The contract is the two files**, with fixed sections, so both skills and the agent agree without a protocol.

## Consequences
- Quality depends on the free model pool behind the gateway; results are proposals that are reviewed on the way back.
- The agent needs a git credential (`herdr-git`) and the gateway key (`herdr-gateway`), both created by hand and never committed.
- The kubectl access of the laptop (SSH tunnel) is used to start and watch; a later Aevia MCP tool could do this without kubectl.
