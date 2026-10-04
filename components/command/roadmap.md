---
description: Drive the roadmap feature queue — init/next/status/approve/resume — with per-feature checkpoints, evidence, and git commits
agent: roadmap-driver
---

/roadmap <request> — Arguments: $ARGUMENTS

Route the request to the **roadmap-driver** agent and follow the roadmap loop
protocol. `$ARGUMENTS` is one of:

- *(empty)* — show the state table, the next eligible feature, and ask how to
  proceed.
- `init <roadmap-file>` — bootstrap the queue from a roadmap document: draft
  the feature queue, present it for approval, then write the state file.
- `next` — run the next eligible feature through dispatch, validation, and the
  checkpoint.
- `F00x` — run or resume the named feature.
- `status` — read-only state table: statuses, active milestone, blockers,
  pending checkpoints, last journal entries.
- `approve F00x` — approve an `awaiting_approval` checkpoint: commit and
  advance exactly one feature.
- `resume F00x` — resume a `blocked` or `in_progress` feature after a decision.
- `milestone Mx` — switch the active milestone after explicit confirmation.

Procedure:

1. **Load** `.opencode/context/roadmap/loop-protocol.md` first, then
   `.sdd-toolbox/roadmap.json` and `.sdd-toolbox/config.json`.
2. **On `init`** — follow the *Initialization* section of the protocol: read
   the roadmap document, propose the queue and constitution bootstrap, get
   explicit owner approval via the `question` tool, then write the state file.
   Never invent acceptance criteria the document does not support.
3. **Resolve blockers before work.** If any feature is `awaiting_approval` or
   `blocked`, surface it first; never start new work over an unresolved feature.
4. **Eligibility** — a feature runs only when `status == "pending"`, all deps
   are `done`, and its milestone matches the active one (unless named
   explicitly).
5. **Dispatch** `FeatureRunner` via the Task tool with the exact payload from
   the protocol; mark `in_progress`, increment `attempts`, append the journal.
6. **On `BLOCKED`** — store the blocker, set `blocked`, ask the owner via the
   `question` tool with the reported options (recommended first), then resume
   the same task with the decision.
7. **On `COMPLETE`** — re-run every configured validation command fresh,
   verify each acceptance criterion, then set `awaiting_approval` and ask the
   owner at the checkpoint: Approve / Request changes / Stop.
8. **On approval** — commit `feat(F00x): <lowercased title>`, record the sha,
   set `done`, and continue the loop.
9. **Report with evidence** — every summary cites the exact commands run and
   their observed output. Never claim completion without fresh output.
