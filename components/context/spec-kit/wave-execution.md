# Spec Kit Driver — Wave Execution Engine

How the driver turns `tasks.md` into dependency-ordered waves, dispatches them,
and validates each one. Loaded from [`navigation.md`](navigation.md) when the
implement phase starts.

## 1. Task parsing

Parse `tasks.md` line by line. A task line matches:

```
^- \[[ x]\] (T[0-9]{3,})
```

Per task, extract:

| Field | Source | Regex / rule |
|---|---|---|
| ID | checkbox line | `(T[0-9]{3,})` |
| State | checkbox | `[ ]` pending, `[x]` done |
| Parallel-safe | `[P]` marker | `\[P\]` |
| Story | `[USn]` marker | `\[US[0-9]+\]` |
| Dependencies | prose refs | `\(depends on ([^)]*)\)`, then `T[0-9]{3,}` inside |
| Phase | nearest heading above | see below |
| Order | file position | index among parsed tasks |

Phase headings are Markdown headings whose text matches, case-insensitively:
`Setup`, `Foundational`, `User Story <n>`, `Polish`. Any other heading is not a
phase boundary. Tasks before the first phase heading belong to an implicit
first phase.

A line that starts with `- [ ]` but has no `T###` ID is not a task — ignore it.

## 2. Wave computation

Build a DAG over task IDs. Edge sources, strongest first:

1. **Explicit** — every ID in `(depends on ...)` → `depends on` edge.
2. **Phase order** (fallback) — earlier phase → later phase.
3. **Story order** (fallback) — within a phase, same story, earlier task →
   later task, **unless** the later task is `[P]`.

Compute waves as topological levels, preserving file order within each level:

```
Wave 1 = tasks with no unmet dependencies
Wave N = tasks whose dependencies all completed in waves < N
```

`wave_strategy: "order"` in config skips the DAG: waves are sequential chunks
following file order.

## 3. Sidecar (toolbox-owned)

Write the plan to `.sdd-toolbox/waves/<feature-dir-name>.json` — never inside
`specs/`:

```json
{
  "schema": 1,
  "feature": "001-photo-albums",
  "source_tasks_sha256": "<sha256 of tasks.md when the plan was computed>",
  "strategy": "auto",
  "waves": [
    { "n": 1, "tasks": ["T001", "T003"] },
    { "n": 2, "tasks": ["T002"] }
  ],
  "generated_at": "<ISO-8601 timestamp>"
}
```

`source_tasks_sha256` lets the driver detect that `tasks.md` changed (e.g.
converge appended tasks). On mismatch, recompute the plan before executing.

The plan is **data, not prompt magic**: the owner may edit the sidecar to
reorder/adjust waves and the driver honours the edited file.

## 4. Plan presentation

Before executing, present the plan for approval (unless just approved at the
tasks gate):

```
Wave 1: T001, T003   (parallel)
Wave 2: T002         (depends on T001)
Wave 3: T004, T005   (parallel)
```

Include the sidecar path so the owner can adjust it. Ask for approval via the
`question` tool (options: Approve / Adjust sidecar / Stop), then wait.

## 5. Dispatch

| Wave size | Dispatch |
|---|---|
| 1–4 tasks (below `parallel_threshold`) | one `task(CoderAgent)` per task, launched together |
| `>= parallel_threshold` (default 5) | delegate the whole wave to `BatchExecutor` |
| task includes tests | also/primarily `TestEngineer` |

Every worker prompt carries:
- task ID and full task text,
- the `tasks.md` path,
- the feature directory,
- the project's required context files (discover with `ContextScout` when
  unclear).

**UI tasks** additionally carry the UI worker protocol — the prompt must state:
"This task is UI. Load the `impeccable` skill and follow its Setup for the
target app; read `reference/craft-floor.md` before editing; honor
`.opencode/context/design/site-design-brief.md` when present (locked sections
are hard constraints, placeholders unresolved); run `impeccable detect` on the
changed UI before handoff."

Independent tasks within a wave run concurrently. A task whose dependencies are
not yet `[x]` must not be dispatched.

## 6. Live ticking

The moment a task completes, flip its checkbox in `tasks.md`: `- [ ] T00x` →
`- [x] T00x`. This is the only direct write to a Spec Kit file, and it keeps the
artifact the single source of truth. Do not batch ticks to the end of a wave.

## 7. Validation — per wave vs. checkpoint

Two levels, deliberately: cheap while iterating, complete before `COMPLETE`.

**Per wave (scoped, after each wave):** run only the checks that cover the
changed files — the feature's per-story "Independent Test" commands,
changed-file test runs (`vitest run --changed` / `--related <file>`, or the
project's equivalent), and the package-scoped `lint`/`typecheck` for the
packages you touched. Build/test cache hits are fine here; do **not** force a
cold run while iterating. Do **not** run the whole-repo suite, the whole
browser matrix, or the visual QA capture per wave.

**At the feature checkpoint (once, fresh, before `COMPLETE`):** run the full
configured `validation.commands` (`.sdd-toolbox/config.json` →
`validation.commands` array; empty → profile default) in a single pass from the
repo root (or the configured `scope`), plus the project's quality/coverage
gates and the affected e2e suite once. Capture fresh output — see
[`evidence.md`](evidence.md).

A fixed failure re-runs only the affected scope, then the full checkpoint pass
again before reporting. This is a **redundancy** rule, not a coverage
reduction: no gate is dropped, no test is weakened, and any failing command
still stops the run. Machine validation is necessary but not sufficient for UI
waves: the rendered result is verified by the single Visual QA pass in §8.

## 8. Visual QA for UI work

A wave/feature is **UI-touching** when the tasks or changed files include
presentation surfaces: UI app code (HTML, Astro/TSX/JSX, Vue/Svelte), CSS/SCSS,
theme tokens, layouts, shared components, public pages, or admin screens.
API-only, data, infra, and docs-only work is not UI. When the project has a
design brief, its app/surface paths are authoritative.

- **Mandatory pass**: after the last converge round that changed UI, dispatch
  `VisualQA` once for the feature's affected surfaces before the feature can be
  reported `COMPLETE`. Use the project's capture command (typically
  `<package-manager> visual:qa`; desktop 1440×900 + mobile 390×844 minimum,
  plus tablet when justified); the full procedure is the `visual-qa` skill.
- **Exactly once per feature.** One full capture after the last UI-changing
  round, plus at most one bounded focus pass per completed surface. Do **not**
  re-run the full matrix after unrelated wave/fix churn — re-run only the
  surfaces a fix touched. Scope the capture to the changed surfaces plus the
  standard representative matrix; run the full route matrix only when the change
  touches global chrome, tokens, layout, or shared components.
- **Optional focus pass**: a wave that completes a whole surface may get a
  focused `VisualQA` before the next wave — bounded, one pass.
- **Payload to `VisualQA`**: feature id, spec dir, target app/surface,
  affected routes, changed UI files (`git diff --name-only`), prior findings,
  attempt number.
- **Verdict handling**: `PASS` -> include it in the feature report; `FAIL` ->
  dispatch one batch fix to `CoderAgent` with the findings verbatim and re-run
  `VisualQA` once; still `FAIL` or `UNABLE` -> STOP and report as a blocker
  (`visual QA failure` / `missing capability`) with the evidence paths.
- **Evidence**: screenshots (`.visual-qa/screenshots/<viewport>/`) and capture
  reports + detector output (`.visual-qa/reports/`); the `VISUAL_QA` line in
  the feature report cites those paths.
- `VisualQA` never edits product code; fixing stays with the implementing
  worker, verification stays independent.

## 9. Stop rules

On any validation failure or task failure:

1. **STOP** — do not start the next wave.
2. Report: task ID, exact command, output excerpt (the failing lines).
3. Ask for the recovery decision via the `question` tool (options: fix-forward,
   revise spec, re-scope, abort).
4. Wait for an explicit selection before continuing. Never auto-fix, never skip
   ahead.

## 10. Converge and re-plan

After all waves are green, run the converge capability. If converge appends
tasks:

1. Re-read `tasks.md` and recompute its sha256.
2. The sha will differ from `source_tasks_sha256` → recompute the DAG and waves.
3. Present the updated plan, then loop back to dispatch.

Repeat until converge reports converged or the owner stops. Respect
`converge_loop: false` in config (single pass, then stop).

## 11. Interruption

If the owner stops a run, state exactly which tasks are `[x]` and which remain.
Resuming continues from the first unticked task; recompute waves from the
current file state.
