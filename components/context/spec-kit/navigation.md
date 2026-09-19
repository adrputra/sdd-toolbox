# Spec Kit Driver — Navigation

Map of the driver context and the runtime state it operates on. Load this file
first on every `/sdd` run; it tells you which other file to read for the task
at hand.

## Context files

| File | Load when | Covers |
|---|---|---|
| [`workflow.md`](workflow.md) | Planning or executing the phase sequence | Full command order, approval gates, requirements analysis, bug flow |
| [`artifacts.md`](artifacts.md) | Resolving the feature directory or reading/writing Spec Kit files | `.specify/` layout, `specs/<###-feature>/`, feature resolution |
| [`wave-execution.md`](wave-execution.md) | Parsing `tasks.md` or dispatching waves | Task regexes, DAG/wave computation, sidecar schema, dispatch, validation, stop rules |
| [`evidence.md`](evidence.md) | Before reporting any phase/task complete | Fresh-output rule, report/verdict format |

Read order for a fresh run: **navigation → workflow → artifacts**, then load
`wave-execution.md` when you reach the tasks/implement phases and `evidence.md`
before any completion claim.

## Runtime state

| Path | Owner | Purpose |
|---|---|---|
| `.sdd-toolbox/config.json` | Toolbox | Runtime settings the driver reads before implement |
| `.sdd-toolbox/waves/<feature>.json` | Toolbox | Wave sidecar (computed plan + source hash) |
| `.sdd-toolbox/manifest.json` | Toolbox | Ownership manifest (installed files + pins) |
| `.specify/` | Spec Kit | Templates, scripts, constitution, extension config |
| `specs/<###-feature>/` | Spec Kit | Feature artifacts (`spec.md`, `plan.md`, `tasks.md`, …) |

## Config quick reference

`.sdd-toolbox/config.json` (missing file → built-in defaults):

```json
{
  "schema": 1,
  "wave_strategy": "auto",
  "parallel_threshold": 5,
  "validation": { "commands": [], "scope": "repo" },
  "converge_loop": true
}
```

- `wave_strategy` — `auto` (DAG) or `order` (sequential by file order).
- `parallel_threshold` — waves of at least this size go to `BatchExecutor`.
- `validation.commands` — commands run after each wave (`[]` = profile default).

## Driver entry points

- `/sdd <request>` — start or continue the gated flow.
- `/sdd bug <description>` — bug-fix flow (bug extension required).

## Boundaries (do not cross)

- Never write `.specify/` or `specs/` directly — only through Spec Kit commands.
- The only direct edit to a Spec Kit file is ticking `tasks.md` checkboxes during
  execution (the documented live-status mechanism).
- Never edit `.git/`, `.env*`, `*.key`, or `*.secret`.
- Never hardcode `/speckit.*` command names — discover the installed surface at
  runtime (see [`workflow.md`](workflow.md)).
