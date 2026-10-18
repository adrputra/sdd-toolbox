---
description: Advance the roadmap to the next milestone headlessly in the background and report the result
agent: build
---

Start the roadmap loop to advance milestones, detached so it does not block this
session (the session turn must return promptly).

1. Guard against concurrent runs. If another loop is active, stop and report it
   instead of starting a second one:
   `pgrep -af 'loop\.sh|roadmap-driver'`
   A second loop would corrupt `.sdd-toolbox/roadmap.json`.
2. From the repository root, launch it detached:
   `nohup scripts/loop.sh --auto-checkpoint --advance-milestone >>/tmp/roadmap-advance.log 2>&1 & echo $!`
3. Report the PID, the log path, and the active milestone, then stop this turn.
   Do not wait for the loop to finish.
4. On later requests (for example "roadmap status"), tail the last 20 lines of
   `/tmp/roadmap-advance.log` and check the PID with `kill -0`. Report any
   `LOOP:` line: `LOOP: MILESTONE Mxx DONE`, `LOOP: CHECKPOINT <id>`,
   `LOOP: BLOCKED <id>`, or `LOOP: ALL MILESTONES DONE`, and its exit code
   (0 done, 2 checkpoint pending, 3 blocked, 1 error).

Never run the loop in the foreground.
