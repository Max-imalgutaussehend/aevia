---
name: handover-back
description: Take a task back from the Aevia server agent (Herdr) after a handover. Use when the user says "handover back", "hol das zurück", "was hat der Server gemacht" or comes back to a task that was handed over. Fetches the handover branch, reads the agent's RESULT.md, brings the work into the local checkout and walks through the steps that need the laptop.
---

# Handover back: server agent to laptop

## 1. Find the handover
- `git fetch origin 'refs/heads/handover/*:refs/remotes/origin/handover/*'` and list `git branch -r --list 'origin/handover/*'`. If the user gave a slug, use it; if there is exactly one recent branch, use it; otherwise ask.
- Check the state on the server (needs kubectl as in the handover skill): `kubectl -n agents exec herdr-0 -- aevia-handover status <slug>`.
  - **running**: tell the user how long it has been running and what its newest commits are. Offer to wait, or to stop it (`... stop <slug>`; what it did so far is already pushed) and take it back now.
  - **done / partial / blocked**: continue.
  - no server access: the branch itself is enough if it contains `.handover/<slug>/RESULT.md`.

## 2. Read the result before touching code
`git show origin/handover/<slug>:.handover/<slug>/RESULT.md`. Summarise for the user in a few lines: status, what was done, decisions the agent made (call out any that change behaviour or security), what is left, and the "Needs the laptop" checklist. Show `git diff --stat <your-branch>...origin/handover/<slug>`.

## 3. Bring the work in
Ask which way: (a) `git switch handover/<slug>` and review there, (b) merge into the working branch (`git merge --no-ff origin/handover/<slug>`), (c) cherry-pick selected commits. Default to (a) so nothing lands unreviewed. Then run the "How to verify" commands from RESULT.md and report the real output. Do not trust the agent's claim that tests pass.

## 4. Do the laptop steps
Go through "Needs the laptop" one item at a time with the user: logins, secrets, hardware, visual checks. These are the things the server agent could not do. Check each one off in `.handover/<slug>/RESULT.md` (add a short "Back on the laptop" note with the date).

## 5. Close the loop
When the work is merged or abandoned: delete the remote branch only if the user agrees (`git push origin --delete handover/<slug>`), and offer to clean the server workspace (`kubectl -n agents exec herdr-0 -- rm -rf /home/agent/handover/<slug>`). If more work remains for the server, offer a new **handover** with an updated note.
