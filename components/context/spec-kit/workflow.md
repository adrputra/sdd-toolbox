# Spec Kit Driver — Workflow & Gates

The exact command sequence the driver runs, where it must stop for approval, and
how the bug flow differs. Loaded from [`navigation.md`](navigation.md).

## Runtime discovery (do this first)

Spec Kit's invocation surface depends on the installed integration: it may be
commands (`/speckit.specify`) or skills (`/speckit-specify`). At the start of a
run, enumerate the installed surface and build a capability map. Route by
capability, never by a hardcoded literal.

| Capability | Used in phase |
|---|---|
| `constitution` | Constitution |
| `specify` | Specify |
| `clarify`, `checklist` | Quality (optional, before plan) |
| `plan` | Plan |
| `tasks` | Tasks |
| `analyze` | Quality (optional, before implement) |
| `implement` semantics | Implement (per task) |
| `converge` | Converge |
| `bug.assess`, `bug.fix`, `bug.test` | Bug flow (if extension installed) |

If a required capability is absent, STOP and report it. Never substitute a
homemade equivalent. `taskstoissues` is out of scope (GitHub-only; target is
GitLab).

## Feature flow

```
Intake
  -> Constitution        (once; skip if present + approved)
  -> Specify             -> GATE
  -> [Clarify | Checklist]   (optional)
  -> Requirements Analysis   (MANDATORY before plan)
  -> Plan                -> GATE
  -> Tasks               -> GATE
  -> [Analyze]               (optional)
  -> Implement (waves)   -> per-wave validation
  -> Converge            -> (tasks appended?) -> Implement -> ...
```

### Intake
Classify the request (feature / bug / continuation), resolve the active feature
directory (see [`artifacts.md`](artifacts.md)), and ask clarifying questions via
the `question` tool. Write nothing until intake is answered.

### Constitution
Run the constitution capability once per project when the constitution is
missing or unapproved. Skip when present and approved. Never re-run silently.

### Specify
Author `spec.md` through the specify capability. Present a summary + the file.

**GATE — Specify.** Wait for approval or revision comments; revise until
approved. Do not plan unapproved.

### Quality (optional)
Offer `clarify` when ambiguities exist and `checklist` when a review checklist
would help. These are optional; the owner decides.

### Requirements Analysis (MANDATORY before plan)
Scan `spec.md` for:
- **Ambiguities** — terms with more than one meaning.
- **Gaps** — missing triggers/events, edge cases, data migrations.
- **Conflicts** — with other criteria or with the existing codebase.

Output an **Open Questions** list. For each, ask via the `question` tool with
your proposed options (recommended first), but never fabricate a decision.
Resolve through the clarify capability when the owner approves. Unresolved
questions block planning for the affected area only.

### Plan
Author `plan.md` through the plan capability. Present it.

**GATE — Plan.** Wait for approval or revision.

### Tasks
Author `tasks.md` through the tasks capability. Parse it and compute the wave
plan (see [`wave-execution.md`](wave-execution.md)). Present the task list and
the wave plan together.

**GATE — Tasks.** Wait for approval; accept scoping ("implement T001–T004" or
"all").

### Quality (optional)
Run `analyze` to cross-check artifacts for consistency before execution.

### Implement
Run the wave engine in [`wave-execution.md`](wave-execution.md). Validation
runs after every wave.

### Converge
Run the converge capability. If it appends tasks, recompute waves from the fresh
`tasks.md` and loop back to Implement. Repeat until converged or the owner
stops.

## Gate protocol

A gate is a hard stop:

1. Present a concise summary: what changed, the artifact path, and open items.
2. Ask for explicit approval via the `question` tool (options: Approve / Request
   changes / Stop; recommended option first). Do not interpret silence or an
   unrelated message as approval.
3. On revision comments, apply them and re-present the same gate.
4. On an explicit approval selection, advance exactly one phase.
5. If the spec proves wrong at any point, STOP and update it with approval —
   never drift silently.

Gates: **Specify**, **Plan**, **Tasks**, plus the bug-flow gates below. The
option shape is defined in the driver's *Asking the Owner* section: 2–4 concrete
options with one-line descriptions, no "Other" option (custom answers are built
in), and a numbered text list as fallback when the tool is unavailable.

## Bug flow (bug extension required)

```
assess -> GATE -> fix -> test -> verdict
```

1. **assess** — reproduce and characterise; capture current vs expected.
2. **GATE** — owner approves the assessment via the `question` tool before any
   fix.
3. **fix** — apply the minimal change.
4. **test** — run fresh tests.
5. **verdict** — `verified | partial | failed`, backed by test evidence (see
   [`evidence.md`](evidence.md)).

If the extension is not installed, report that and offer to install it via the
toolbox; do not improvise a substitute flow.

## Stop rules

- Any command failure, missing capability, or failed validation STOPS the flow.
- Report the failure and ask for the recovery decision via the `question` tool.
- Never auto-fix, never skip a gate, never advance a wave on red.
