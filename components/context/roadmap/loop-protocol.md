# Roadmap Loop Protocol

The outer loop that walks the roadmap document named by
`.sdd-toolbox/roadmap.json` (`source`) feature by feature on top of the
existing Spec Kit machinery. Read this before every roadmap run; it defines the
only sanctioned way to initialize, advance, stop, or report.

## Two nested loops

| Loop | Owner | Scope |
|---|---|---|
| Outer (roadmap) | `roadmap-driver` | Queue, state, checkpoints, git commits, journal |
| Inner (feature) | `FeatureRunner` subagent | One feature: specify -> analysis -> plan -> tasks -> implement -> converge |

The inner loop reuses the existing spec-kit context. `FeatureRunner` MUST read
`.opencode/context/spec-kit/navigation.md` first and follow its `workflow.md`,
`artifacts.md`, `wave-execution.md`, and `evidence.md`.

## State file — `.sdd-toolbox/roadmap.json`

Single source of truth for the outer loop. Only `roadmap-driver` writes it.
`FeatureRunner` reports back; it never edits the state file.

Top-level fields:

| Field | Meaning |
|---|---|
| `schema` | State schema version (currently `1`) |
| `project` | Project name (informational) |
| `source` | Roadmap document path, relative to the project root |
| `active_milestone` | Milestone currently being executed |
| `journal_dir` | Journal directory (default `.sdd-toolbox/journal`) |
| `policy` | Loop policy (see *Gate policy*) |
| `bootstrap` | Optional initialization record (`constitution`, amendments) |
| `owner_decisions` | Append-only owner decisions with timestamp, feature, decision, detail |
| `features` | The feature queue (below) |
| `last_run` | `{ "feature", "event", "at", "detail" }` for the most recent event |
| `created_at` / `updated_at` | ISO-8601 timestamps |

Feature statuses:

```
pending -> in_progress -> awaiting_approval -> done
                        \-> blocked -----------^  (resume after decision)
```

| Feature field | Meaning |
|---|---|
| `id` | Stable id (`F001`, `F002`, …) |
| `title` | Short title used in commit messages |
| `phase` | Optional phase number for grouping |
| `milestone` | Milestone id (`M1`, `M2`, …) |
| `kind` | `constitution` or `feature` |
| `deps` | Feature ids that must be `done` before dispatch |
| `roadmap_section` | Literal heading/quote in the `source` document for this feature |
| `acceptance` | Acceptance criteria (strings) |
| `status` | One of the statuses above |
| `attempts` | Incremented each time `FeatureRunner` is dispatched |
| `spec_dir` | Actual Spec Kit directory (`specs/NNN-...`) once created |
| `commit` | Checkpoint commit sha once approved |
| `evidence` | Paths to evidence artifacts for this feature |
| `blocker` | `{ "reason", "questions": [{ "question", "options": [] }] }` when blocked |
| `started_at` / `completed_at` | ISO-8601 timestamps |

Default `policy`:

```json
{
  "gates": "checkpoint-per-feature",
  "auto_approve_phases": ["specify", "plan", "tasks"],
  "require_clean_analysis": true,
  "feature_checkpoint": "human",
  "stop_on_validation_failure": true,
  "max_attempts_per_feature": 2,
  "commit_per_feature": true,
  "commit_prefix": "feat"
}
```

## Initialization — `/roadmap init <roadmap-file>`

The bootstrap installer creates an empty scaffold (no features) when the
roadmap components are selected. `/roadmap init` fills it:

1. Read the named roadmap document end to end. If it is missing or unreadable,
   stop and ask for the correct path — never proceed from memory.
2. Derive the feature queue from the document's own structure: feature
   headings/sections, ids it already uses, stated dependencies, milestones or
   phases, and explicit acceptance criteria. For each feature set `id`,
   `title`, `phase`, `milestone`, `kind`, `deps`, `roadmap_section`, and
   `acceptance`.
   - Use the document's ids when present; otherwise assign sequential `F001`,
     `F002`, … in document order.
   - `kind` is `constitution` only for a feature that authors
     `.specify/memory/constitution.md`; everything else is `feature`.
   - Acceptance criteria must be traceable to the document. Missing or
     ambiguous criteria become questions, never invented text.
3. If the document defines governance rules for a constitution, record the
   constitution bootstrap (`bootstrap.constitution`: feature id, capability
   `constitution`, inputs, output `.specify/memory/constitution.md`).
4. Resolve `source` to the document's project-relative path; set
   `active_milestone` to the first milestone containing a `pending` feature.
5. Present the complete proposed queue (ids, titles, milestones, deps,
   acceptance, constitution bootstrap) to the owner via the `question` tool:
   Approve / Request changes / Stop. Summarize counts and flag every feature
   whose extraction was uncertain.
6. Only on explicit approval: write `.sdd-toolbox/roadmap.json` (preserving the
   scaffold's `created_at`, setting `updated_at`) and append an
   initialization journal entry listing the approved queue.
7. On request-changes, revise the proposal and re-present. Never write the
   state file without approval.

If the state file already has features, `init` must refuse and offer to extend
the queue instead (below) — it never silently replaces a queue with history.

### Extending the roadmap

When the owner adds features to the roadmap document later: derive the new
entries from the document using the same rules, append them as `pending` to
`features` (never renumber existing ids), record the owner approval in
`owner_decisions`, journal the extension, and update `updated_at`. Existing
feature statuses, commits, and evidence are never modified by an extension.

## Outer loop algorithm

1. Read `.sdd-toolbox/roadmap.json` and the policy block.
2. If a feature is `awaiting_approval`, **stop** and present the checkpoint
   (never start new work while a checkpoint is pending).
3. If a feature is `blocked`, **stop** and surface the blocker with options.
4. Select the next eligible feature: `status == "pending"`, all `deps` are
   `done`, and `milestone == active_milestone` (unless the owner named one).
5. Mark it `in_progress`, `attempts += 1`, set `started_at`, and append a
   journal entry.
6. Dispatch `FeatureRunner` (Task tool) with the feature payload (below).
7. On `COMPLETE`:
   - Re-run the validation commands from `.sdd-toolbox/config.json` fresh
     yourself — never trust a report without fresh output.
   - Verify the acceptance criteria against the report and the artifacts.
   - Set status `awaiting_approval`, write the summary to the journal, and ask
     the owner at the checkpoint via the `question` tool.
8. On owner approval: `git add -A && git commit` using
   `<commit_prefix>(F00x): <lowercased title>`, record the sha, set status
   `done`, `completed_at`, then continue the loop.
   On request-changes: resume `FeatureRunner` with the feedback; status stays
   `in_progress`.
9. On `BLOCKED`: store the blocker on the feature, set status `blocked`, ask
   the owner via the `question` tool, then resume or stop per the decision.
10. When no eligible feature remains in the active milestone: write a
    milestone journal entry, report the final state table, and stop.

Never skip a dependency. Never run two features concurrently. Never advance
past an unresolved `awaiting_approval` or `blocked` feature.

## FeatureRunner payload (outer -> inner)

Every dispatch carries:

```
FEATURE: F00x — <title>
ROADMAP_SOURCE: <state.source>
ROADMAP_SECTION: "<literal heading>" in <state.source> (quote only the section + directly referenced material)
DEPENDENCIES: <ids, all done>
ACCEPTANCE:
  - <criterion>
POLICY: gates=checkpoint-per-feature; auto-approve specify/plan/tasks only if
        requirements analysis is clean; stop on any validation failure
VALIDATION: commands from .sdd-toolbox/config.json (may be empty => none)
ATTEMPT: <n> of <max>
PRIOR_FEEDBACK: <feedback or blocker decision on resume, else none>
```

The feature kind decides the entry phase:

- `kind: "constitution"` — run the constitution capability with the roadmap's
  rule set as input; produce `.specify/memory/constitution.md`; no code tasks.
  Honor `bootstrap.constitution` in the state file.
- `kind: "feature"` — the full inner flow, starting with the specify capability.

## Gate policy (checkpoint per feature)

The inner loop does not stop for every gate. It applies:

| Phase gate | Policy |
|---|---|
| Specify | Auto-approve **iff** requirements analysis finds zero open questions and no conflicts with the existing codebase |
| Plan | Auto-approve under the same condition |
| Tasks | Auto-approve under the same condition |
| Feature completion | **Always human** — the orchestrator checkpoints with the owner |

- An ambiguity, gap, or conflict is never guessed. Return `BLOCKED` with the
  exact open questions and proposed options.
- Any validation command failure (inner wave validation or outer re-run) is a
  hard stop. Never auto-fix, never re-scope, never mark done.
- `max_attempts_per_feature` exhausted -> set `blocked` and escalate.

## Report schema (inner -> outer)

`FeatureRunner` ends every run with exactly one of:

```
STATUS: COMPLETE
FEATURE: F00x
SPEC_DIR: specs/NNN-name
PHASES: specify=done analysis=clean plan=done tasks=done implement=waves:<n> converge=<converged|appended>
VALIDATION:
  - cmd: <exact command> | result: PASS|FAIL (exit N) | excerpt: <failing lines when FAIL>
ACCEPTANCE:
  - <criterion> | met|unmet | evidence: <path or command output ref>
ARTIFACTS: <paths created/changed>
UNRESOLVED: <items or none>
```

```
STATUS: BLOCKED
FEATURE: F00x
PHASE: <specify|analysis|plan|tasks|implement|converge>
REASON: <validation failure | open questions | missing capability | repeated failure>
DETAIL: <failing command + excerpt, or the ambiguity text>
QUESTIONS:
  - question: <text>
    options: [<option 1>, <option 2>, ...]
```

No other terminal states. Partial work is reported with exact task checkbox
state so a resume can continue from the first unticked task.

## Evidence rules

`FeatureRunner` inherits `.opencode/context/spec-kit/evidence.md` unchanged:
fresh command output only, no "should work", one of
`verified | partial | failed`. The outer loop adds its own fresh validation run
at the feature checkpoint — the checkpoint summary must cite the commands and
their actual output.

## Journal and commits

- Journal: `.sdd-toolbox/journal/<YYYYMMDD-HHMMSS>-<F00x>.md`, appended per
  event (initialization, dispatch, gate, validation, blocker, decision,
  completion, extension). Keep it short: timestamp, event, artifact paths,
  commands, verdict.
- Commits: one per approved feature, message
  `<commit_prefix>(F00x): <lowercased title>`. This is the rollback boundary.
- Evidence artifacts live with the feature (spec dir, `.sdd-toolbox/journal/`)
  and are listed in the state file.

## Headless mode

When invoked by `scripts/loop.sh`:

- There is no owner. Apply the policy table mechanically.
- On a feature checkpoint: set `awaiting_approval`, write the checkpoint summary
  to the journal, print `LOOP: CHECKPOINT F00x`, and exit 0.
- On a blocker: set `blocked`, print `LOOP: BLOCKED F00x <reason>`, exit 0.
- On milestone completion: print `LOOP: MILESTONE <id> DONE`, exit 0.
- Never simulate an owner answer. Never auto-approve a checkpoint, with one
  exception: an invocation that explicitly carries the `AUTO_CHECKPOINT` marker
  (the owner launched `scripts/loop.sh --auto-checkpoint`) is pre-approval for
  every feature checkpoint in that run. Treat each completed feature as
  approved: commit, record the sha, set
  `done`, journal it, and continue. Without the marker, stop at checkpoints.

`/roadmap init` is never run headless; a queue must be initialized and approved
interactively first.

## Boundaries

- Never write `.specify/**` or `specs/**` directly (checkbox ticks in
  `tasks.md` remain the only exception, done by the inner loop).
- Never edit `.git/**`, `.env*`, `*.key`, `*.secret`, or anything outside the
  project root.
- Never hardcode Spec Kit command names; discover the installed surface at
  runtime as `workflow.md` requires.
- New files not owned by a Spec Kit capability (scripts, docs) may be created
  only when the feature's own spec/tasks call for them.
