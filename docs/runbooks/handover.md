# Runbook: handover between the laptop and the server agent

One workflow for long tasks: start on the laptop, hand over, let the Herdr agent on the cluster continue, take it back.

```
laptop (Claude Code)                              cluster (Herdr pod, Claude Code via the AI gateway)
  skill: handover  ── branch handover/<slug> ──>   aevia-handover start  ── works, commits, writes RESULT.md
                    <── pushes, ntfy message ───   status: done | partial | blocked
  skill: handover-back  (reads RESULT.md, merges, does the laptop steps)
```

The transport is a git branch. The note `.handover/<slug>/HANDOVER.md` is written by the laptop session and must stand on its own (the agent has no
chat history); the agent answers with `.handover/<slug>/RESULT.md` (what was done, decisions, what remains, what needs the laptop, how to verify).

## One-time setup
1. **Skills on every laptop:** `agents/herdr/skills/install.sh` (copies `handover` and `handover-back` to `~/.claude/skills`).
2. **Gateway key for the agent:** the FreeLLMAPI unified key (dashboard → Keys → Unified API key) as a secret in the cluster, so Claude Code in the pod can call the gateway:
   ```sh
   kubectl -n agents create secret generic herdr-gateway --from-literal=ANTHROPIC_AUTH_TOKEN='<unified key>'
   kubectl -n agents rollout restart statefulset/herdr
   ```
3. **Git access for the agent** (private repos and pushing the handover branch): a file of lines `https://user:token@host` in the secret `herdr-git`
   (GitHub: a fine-grained token with contents read/write on the repos you hand over; `git.maxrommel.de`: a Forgejo token):
   ```sh
   kubectl -n agents create secret generic herdr-git --from-file=credentials=./credentials   # then delete ./credentials
   ```
4. **Notification user:** `scripts/ntfy-user.sh herdr herdr-ntfy` (write-only on topic `aevia`; subscribe to that topic in the ntfy app).

## Daily use
- On the laptop, in the project: "handover" (the skill checks access, asks once, writes the note, pushes `handover/<slug>`, starts the agent).
- Watch: `kubectl -n agents exec herdr-0 -- aevia-handover status <slug>` · `logs <slug> -f` · `stop <slug>` · `list`
- Back: "handover back" (the skill fetches the branch, summarises RESULT.md, brings the work in after review, goes through "Needs the laptop").

## What the agent can and cannot do
- It runs Claude Code headless (`claude -p`, permission mode `acceptEdits`, an allow-list of tools: file edits, git, python, node, npm, make, pytest) through the AI gateway, so model quality is that of the free pool.
- It can read and write the repository it was given and reach the gateway, one S3 bucket and ntfy. It has no cluster access and no databases (network policies).
- It cannot log in anywhere, use laptop secrets or do interactive and visual checks; those go to "Needs the laptop".
- Limits: 60 turns and 90 minutes per run (`HANDOVER_MAX_TURNS`, `HANDOVER_TIMEOUT`). It pushes only to the handover branch.

## Safety notes
- `acceptEdits` plus a shell allow-list is code execution inside the pod for whoever controls the repository content: hand over only your own repositories.
- Never put secrets into `HANDOVER.md`; list where they live instead.
- The agent's work is a proposal. Review the diff and run the verification yourself (the skill does this on the way back).
