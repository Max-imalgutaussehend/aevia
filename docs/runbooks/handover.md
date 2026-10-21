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

## Verified (2026-10-21)
End to end on the cluster: a note `.handover/hello/HANDOVER.md` on branch `handover/hello` of `akadmin/handover-test` (Forgejo), started with
`aevia-handover start`, Claude Code 2.1.304 headless through the AI gateway wrote `greet.js`, `greet.test.js` and `package.json`, committed, wrote `RESULT.md`
(status done) and pushed the branch; the diff and `npm test` (3 of 3 passing) were checked independently in the pod. The `finished:` line in that RESULT.md carried an
invented timestamp: the runner's own `finished` file is the reliable time. Fixed since: the runner now writes the real finish time into `RESULT.md`.

Second run through the `handover` and `handover-back` skills on a GitHub repository (this one): a docs change (restore runbook) and a check task (`python3 generator/render_k8s.py --check`,
13 services, 7 generated files; the numbers were re-checked on the laptop). The first run showed that the agent image had no Python, so it could not run the repository checks;
the image now has python3 and PyYAML. `herdr-git` holds one line per host: `git.maxrommel.de` (Forgejo) and `github.com` (fine-grained token, Contents read/write on `aevia`, `aevia-mcp`,
`site-aevia`, `site-maxrommel`, 90 days: renew it before it expires on 2027-01-19; the file is `~/.config/aevia/github-token` on the laptop).

## From Jarvis (voice or text)
Jarvis (ADR 0041) can hand a task over without a laptop: "Übergib das an den Server" makes Claude in the Jarvis pod call the tool `handover_start`
(repository, slug, the complete note). That is an HTTP call to the handover API in the Herdr pod (`aevia-handover-api`, port 8099, bearer token from the
secret `handover-api`, reachable from Jarvis only). The API clones the repository, creates `handover/<slug>` with `.handover/<slug>/HANDOVER.md`, pushes it
and starts the runner; only repositories of the allowed owners (`github.com/Max-imalgutaussehend`, `git.maxrommel.de/akadmin`) are accepted.
Jarvis lists the handover in its task list, announces when it finishes and answers "wie ist es ausgegangen" with `handover_status` and `handover_result`.
Taking the work back (merge, laptop steps) stays with the `handover-back` skill. Tried 2026-10-21: a docs change in this repository, 1 min 42 s from the spoken request to the pushed commit;
the note Jarvis wrote had all sections but one wrong statement (it said the file did not exist), which the agent resolved itself: read the note before you trust it.
