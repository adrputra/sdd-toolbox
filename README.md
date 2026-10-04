# SDD Toolbox

SDD Toolbox bootstraps opencode-based SDD tooling into new or existing projects — a pinned GitHub Spec Kit integration, a vendored OpenAgents Control component subset, a custom `spec-kit-driver` agent that enforces review gates and dependency-ordered wave execution, and an optional `roadmap-driver` outer loop that walks a roadmap document feature by feature with per-feature checkpoints and git commits.

One command installs the toolchain, records every file it owns, and can safely refresh an existing install without destroying your customizations.

---

## Overview

The toolbox installs four layers into a target project (the roadmap loop is opt-in via a roadmap profile):

| Layer | What it is | Where it lands |
|---|---|---|
| **Pinned Spec Kit integration** | The official `specify` CLI at the release tag in `versions.env`, initialised for opencode | `.specify/`, `specs/` (Spec Kit-owned) |
| **Vendored OAC subset** | A pinned OpenAgents Control component subset bundled inside the toolbox and installed offline | `.opencode/…` |
| **`spec-kit-driver` agent** | The driver agent, its `/sdd` entry command, and `context/spec-kit/` files — review gates plus wave execution on top of Spec Kit | `.opencode/agent/core/`, `.opencode/command/sdd.md`, `.opencode/context/spec-kit/` |
| **Roadmap loop** (optional) | The `roadmap-driver` agent, the `FeatureRunner` subagent, the `/roadmap` command, the loop protocol, and the headless `scripts/loop.sh` runner | `.opencode/…`, `.opencode/context/roadmap/`, `scripts/loop.sh`, `.sdd-toolbox/roadmap.json` |

Ownership is explicit: every file the toolbox writes is tracked in `.sdd-toolbox/manifest.json` with a sha256 hash. Unmanaged files are never touched. Updates refresh unmodified files and preserve your edits (see [Updating](#updating)).

The vendored snapshot is produced by `scripts/vendor-sync.sh` (see [Vendoring OAC](#vendoring-oac)).

---

## Requirements

| Requirement | Why | Notes |
|---|---|---|
| `bash` 3.2+ | runs the toolbox | macOS system bash and Linux bash both work. Linux/macOS only. |
| `jq` | parses `registry.json`, profiles, and the manifest | Required; JSON is never `eval`-ed. |
| `uv` | installs the pinned Spec Kit CLI | Spec Kit's Python 3.11+ requirement is satisfied by `uv`. |
| `curl` | Spec Kit bootstrap / network reachability | Required. |
| `sha256sum` or `shasum -a 256` | file hashes in the manifest | coreutils on Linux, built-in `shasum` on macOS. |
| `gum` or `fzf` | enhanced wizard menus | **Optional.** Numbered prompts are the always-available fallback. |
| `git` | one-line installer, Spec Kit install | Required by the one-line installer; also used by `uv` to install Spec Kit from its git tag. Not enforced by the prereq check. |

If a required tool is missing, bootstrap prints a one-line cause and an OS-aware install hint, then exits **3** without writing anything.

```sh
brew install jq uv                 # macOS
sudo apt-get install -y jq curl    # Debian/Ubuntu
curl -LsSf https://astral.sh/uv/install.sh | sh   # uv
```

---

## Quick Start

Interactive (TTY, no flags — walks every option):

```sh
./bootstrap.sh
```

Non-interactive (CI, scripts, or when you already know the plan):

```sh
./bootstrap.sh <target> --profile minimal --yes
```

From anywhere — one line, no clone (fetches a managed checkout to `~/.sdd-toolbox`):

```sh
curl -fsSL https://raw.githubusercontent.com/adrputra/sdd-toolbox/main/install.sh | bash -s -- <target> --profile minimal --yes
```

Interactive wizard via the same one-liner (bash process substitution keeps your terminal on stdin):

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/adrputra/sdd-toolbox/main/install.sh)
```

Pin a version or relocate the managed checkout with `SDD_TOOLBOX_REF` / `SDD_TOOLBOX_HOME`.

Interactive mode always asks for the profile. Defaults (`target=.`, `profile=minimal`) apply only to non-interactive runs.

### What gets installed

| Path | Contents |
|---|---|
| `.opencode/…` | driver agent, `/sdd` command, `context/spec-kit/` files, and the vendored OAC subset |
| `.opencode/…` (roadmap profiles) | `roadmap-driver`, `FeatureRunner`, `/roadmap` command, and `context/roadmap/` files |
| `scripts/loop.sh` (roadmap profiles) | headless roadmap runner (`--feature`, `--approve`, `--auto-checkpoint`) |
| `.sdd-toolbox/roadmap.json` (roadmap profiles) | roadmap state scaffold — created empty when missing, agent/owner-owned, never overwritten or manifest-managed |
| `.specify/` | Spec Kit integration (templates, scripts, constitution, extension config) — Spec Kit-owned |
| `specs/` | feature artifacts, created by Spec Kit as features are specified — Spec Kit-owned |
| `.sdd-toolbox/manifest.json` | ownership record: toolbox/OAC/Spec Kit pins, profile, extensions, per-file hashes |
| `.sdd-toolbox/config.json` | runtime settings the driver reads (see [Driver Agent](#driver-agent)) |
| `opencode.json` | project-local opencode config with the [context7](https://context7.com) MCP server (created, or merged into an existing file; an existing `context7` entry is never overwritten) |

The generated `opencode.json` works keyless. For higher context7 rate limits, add `"headers": {"CONTEXT7_API_KEY": "{env:CONTEXT7_API_KEY}"}` (or a literal key) to its `context7` entry — the toolbox never rewrites an existing entry.

### Next steps

```sh
cd <target>
# launch opencode
/sdd <request>
# roadmap profiles only — build the feature queue from your roadmap document
/roadmap init ROADMAP.md
```

### Bootstrap flags

| Flag | Meaning |
|---|---|
| `<target-dir>` | Directory to install into (default: current directory). |
| `--profile <name>` | Non-interactive profile selection (`minimal`, `go-backend`, `node-typescript`, `roadmap`, `roadmap-node-typescript`). |
| `--yes` | Assume yes for all prompts (implies non-interactive). |
| `--update` | Update mode; requires an existing toolbox manifest. |
| `--force` | With `--update`: reinstall mode (overwrite modified files). |
| `--dry-run` | Print planned actions without writing anything. |
| `--no-spec-kit` | Skip the Spec Kit stages (install the toolbox overlay only). |
| `-h`, `--help` | Show usage and exit. |

`--force` is only valid together with `--update` (otherwise exit **2**).

---

## Profiles

A profile is a declarative JSON bundle of components plus runtime settings. Menus are generated dynamically from `profiles/` — adding a profile requires no script changes. A profile may declare `"extends": "<other-profile>"`; components resolve parent-first (duplicates dropped) and settings deep-merge, parent under child.

| Profile | Description | Wave validation |
|---|---|---|
| `minimal` (default) | Spec Kit integration + driver agent + `/sdd` + spec-kit context + the delegation subagents. No stack-specific tooling. | none (`converge` still runs) |
| `go-backend` | Everything in `minimal`, plus the review/build subagents and test-coverage context. | `go vet ./...` then `go test -race -count=1 ./...` |
| `node-typescript` | Everything in `minimal`, plus the review/build subagents, test-coverage and TypeScript standards contexts. | `npx tsc --noEmit` then `npm test` |
| `roadmap` | Extends `minimal`, plus the roadmap outer loop: `roadmap-driver`, `FeatureRunner`, `/roadmap`, `context/roadmap/`, and `scripts/loop.sh`. | inherited from `minimal` |
| `roadmap-node-typescript` | Extends `node-typescript`, plus the same roadmap outer loop. | inherited from `node-typescript` |

Selecting an unknown profile exits **2** and lists the available profiles.

---

## Updating

Re-running bootstrap against a target that already has a manifest behaves as an update. `--update` is the explicit form; `--update --force` is the reinstall form (the interactive equivalent of the wizard's **Reinstall** action).

Every managed file is classified before anything is written:

| Classification | Meaning | `--update` | `--update --force` |
|---|---|---|---|
| `identical` | target already equals the toolbox version | skip | skip |
| `unmodified` | target matches the manifest; toolbox moved on | refresh | refresh |
| `missing` | file was deleted | restore | restore |
| `modified` | you edited it | preserve + report as skipped | back up + overwrite |
| `conflict` | unmanaged file already exists at a managed path | **abort** | **abort** |
| `stale` | recorded in the manifest but no longer shipped | report, leave in place, retain in manifest | report, leave in place, retain in manifest |

- `--dry-run` prints the classification table and writes nothing.
- `--update` without an existing manifest exits **6** with the manifest path in the message.
- Backups from `--update --force` land in `.sdd-toolbox/backup/<UTC-timestamp>/<relpath>`.
- The manifest is written **last**, so a partial install is always detectable and safely re-runnable.
- `opencode.json` is ensured on every run (create or merge); an existing `context7` entry is never overwritten and the file is not manifest-managed.
- No operation ever deletes unmanaged files; `stale` entries are reported, left on disk, and retained in the manifest — never removed.
- User-modified `.sdd-toolbox/config.json` is preserved by the same policy.

---

## Driver Agent

`/sdd <request>` is the entry point (the `sdd` command routes to the `spec-kit-driver` agent). `/sdd bug <description>` runs the bug-fix flow when the Spec Kit `bug` extension is installed.

### Gated flow

```
constitution (once) → specify → [clarify/checklist] → plan → tasks → [analyze]
  → implement (waves) → converge → (append tasks) → implement → … → done
```

Hard gates at **Specify**, **Plan**, and **Tasks** (plus the bug-flow gates). Between phases the driver presents a summary and waits for explicit approval — it never proceeds unapproved. Before planning it runs a mandatory requirements-analysis pass (ambiguities, gaps, conflicts with the repo) and surfaces **Open Questions**; it never invents answers.

### Interactive gates

Every clarification, option choice, and approval gate is asked through opencode's built-in **`question` tool**: the owner picks from 2–4 concrete options (recommended first) with one-line descriptions, or types a custom answer. The driver advances only on an explicit approval selection; a custom answer counts as revision feedback, not approval. When the tool is unavailable (older opencode, headless runs) the driver falls back to a numbered text list and still stops at the gate.

### Wave execution

On implement, the driver parses `tasks.md` (IDs `T###`, `[P]` parallel markers, `[USn]` story tags, `(depends on T0xx)` refs), computes a dependency-ordered DAG, and presents the wave plan for approval. The plan is written to `.sdd-toolbox/waves/<feature>.json` (toolbox-owned; Spec Kit's `specs/` is never touched).

- 1–4 tasks (below `parallel_threshold`): one `CoderAgent` per task, launched together.
- `>= parallel_threshold` (default 5): the whole wave goes to `BatchExecutor`.
- Tasks that include tests use `TestEngineer`.
- Checkboxes tick `[ ] → [x]` in `tasks.md` immediately as tasks complete.
- The profile's validation commands run after each wave. On failure the driver **stops**, reports the task ID + command + output excerpt, and asks for the recovery decision via the `question` tool — never auto-fixes or advances.
- After all waves are green it runs `converge`; appended tasks are re-planned and the loop repeats until converged.

### Runtime configuration

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

| Field | Meaning |
|---|---|
| `wave_strategy` | `auto` (DAG from `tasks.md` hints) or `order` (strict file order, no DAG). |
| `parallel_threshold` | Waves at or above this size go to `BatchExecutor`. |
| `validation.commands` | Commands run after each wave; `[]` means the profile default. |
| `validation.scope` | Working directory scope for validation. |
| `converge_loop` | `false` stops after a single converge pass. |

### Evidence rules

No phase or task is reported complete without fresh command output captured at that moment (command + result). The bug flow ends with a verdict of `verified`, `partial`, or `failed`, backed by test evidence.

---

## Roadmap Loop

Installed only by the `roadmap` and `roadmap-node-typescript` profiles. `/roadmap <request>` is the entry point (the `roadmap` command routes to the `roadmap-driver` agent); it wraps the same Spec Kit inner loop in an outer queue with one human checkpoint per feature, git commits, and a journal.

### Initialize

Bootstrap creates an empty `.sdd-toolbox/roadmap.json` when a roadmap profile is installed (create-if-missing only; the state is agent/owner-owned and never touched again). `/roadmap init <roadmap-file>` reads the document, proposes the full feature queue (ids, titles, milestones, `kind`, dependencies, acceptance criteria, roadmap sections) and the constitution bootstrap if the document defines one, and writes the state file only after explicit owner approval via the `question` tool. Gaps become questions, never invented criteria. Extending a roadmap appends new `pending` features without renumbering existing ones.

### Run

```
/roadmap            # state table, next eligible feature, ask how to proceed
/roadmap next       # next eligible feature -> validation -> checkpoint
/roadmap F00x       # run or resume a named feature
/roadmap status     # read-only state table, blockers, pending checkpoints
/roadmap approve F00x   # approve the checkpoint: commit + advance one feature
/roadmap resume F00x    # resume a blocked/in-progress feature after a decision
/roadmap milestone Mx   # switch the active milestone (explicit confirmation)
```

Each feature is dispatched to the `FeatureRunner` subagent, which runs specify → requirements analysis → plan → tasks → wave implement → converge under the protocol's gate policy: specify/plan/tasks auto-approve only when the analysis is clean; any ambiguity blocks with questions; feature completion always waits for the owner. On approval the driver commits `<commit_prefix>(F00x): <title>` (default prefix `feat`) — that commit is the rollback boundary — and records the sha, evidence, and journal entry.

### Headless

`scripts/loop.sh` drives `opencode run --agent roadmap-driver` iteration by iteration, resuming between sessions from the state file:

```sh
scripts/loop.sh                       # run until checkpoint (exit 2) or blocker (exit 3)
scripts/loop.sh --feature F007        # run or resume one feature
scripts/loop.sh --approve F007        # commit an approved checkpoint and continue
scripts/loop.sh --auto-checkpoint     # unattended: pre-approve every checkpoint
scripts/loop.sh --max-iterations 20 --model provider/model --dry-run
```

Exit codes: `0` milestone complete, `2` checkpoint pending, `3` blocked, `1` error/stall. `--auto-checkpoint` is the owner's explicit pre-approval for the run; without it the runner stops at every checkpoint and never simulates an answer.

### State and protocol

`.sdd-toolbox/roadmap.json` is the single source of truth (queue, policy, active milestone, owner decisions, last run). The canonical protocol — state schema, initialization, eligibility, payload, report schema, evidence rules, headless behavior, boundaries — lives in `.opencode/context/roadmap/loop-protocol.md`.

---

## Maintainer Guide

### Validation

Run the standard checks from the toolbox root:

```sh
scripts/validate.sh      # repo self-check: syntax, schemas, reference integrity
scripts/smoke-test.sh    # end-to-end bootstrap scenarios into temp dirs
```

- `scripts/validate.sh` — offline self-check with per-check output: `bash -n` on every shell file (including `bootstrap.sh`), `shellcheck` on those files when installed (**skipped visibly** — a `[SKIP]` line — when absent), `jq` schema checks for `registry.json`, every `profiles/*.json` (including `extends` targets), `vendor/oac/bundle.json` and `versions.env`, and reference integrity (every profile extends chain resolves; every profile component ID resolves via `catalog_resolve`; every spec-kit-driver subagent exists in the vendored subset and every roadmap-driver subagent resolves in the catalog; every registry path exists on disk; every bundle hash matches). Currently **185 checks**; exits **7** if any check fails and **0** otherwise.
- `scripts/smoke-test.sh` — thirteen hermetic scenarios: fresh install, idempotency, update-preserve, force+backup, dry-run, unknown profile, `--no-spec-kit`, a stripped-`PATH` prereq failure, three `opencode.json` handling cases, and two roadmap-profile cases (component/script/scaffold install; modified state preserved by `--update`). `uv`/`specify` are stubbed on `PATH` (no network, no global installs), each scenario runs in its own directory under a scratch root that is removed on exit, and the suite exits **1** if any scenario fails.

Tests override the data root with the **`TOOLBOX_ROOT`** environment variable: the code always loads from the script's own directory, but `TOOLBOX_ROOT` points `registry.json`, `profiles/`, `components/`, and `vendor/` at an alternate root (e.g. a fixture tree).

### Vendoring OAC

`scripts/vendor-sync.sh` is a maintainer-only tool that refreshes the vendored OAC subset. It copies selected `.opencode/**` files from a local OAC checkout into `vendor/oac/` and writes `vendor/oac/bundle.json`. It makes **no network calls**.

```sh
scripts/vendor-sync.sh --source <oac-checkout> --version <ver> \
  --provenance "github.com/…@<tag> (MIT)" --selection vendor/selection.txt --dry-run
```

| Flag | Meaning |
|---|---|
| `--source <dir>` | Local OAC checkout containing `.opencode/` (required). |
| `--version <ver>` | Version label for the snapshot (required). |
| `--provenance <str>` | Provenance note (default: `unknown`). |
| `--selection <file>` | Selection list (default: `vendor/selection.txt`). |
| `--dry-run` | Print the plan and bundle JSON; write nothing. |
| `-h`, `--help` | Show usage. |

- `vendor/selection.txt` lists the driver-needed subset — the primary agents, the subagents the driver delegates to, and the referenced context files. Each non-comment line is relative to the source `.opencode/` directory.
- `vendor/oac/bundle.json` records `version`, `provenance`, `generated_by`, and a `files[]` array of `{path, id, type, sha256}` entries.
- `VENDOR_ROOT` overrides the destination (default: `<toolbox>/vendor/oac`).
- Exit codes: **0** ok; **2** usage; **3** missing source `.opencode/` or selection file; **1** selected files missing from the source.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `prereq: missing required tool: jq` (or `uv`/`curl`) | A required tool is missing. Bootstrap exits **3** and prints the OS-aware install hint; install it and re-run. |
| `target is not empty; 'specify init --force' will merge…` | The target already has files. Spec Kit merges and may replace conflicting *managed* paths; review the warning before continuing. |
| `--update requires an existing manifest at …` | `--update` was run against a directory with no `.sdd-toolbox/manifest.json`. Run without `--update` for a fresh install, or point at the correct target. Exit **6**. |
| `unmanaged file(s) already exist at planned path(s)` | A file at a toolbox-managed path is not owned by the toolbox. Bootstrap aborts before writing (exit **6**); move or remove the listed files, then retry. |
| Wizard cancelled | `q` / Ctrl-C at any screen prints `no changes made` and exits **0**. Nothing is written. |
| `--force is only valid together with --update` | Add `--update`, or drop `--force`. Exit **2**. |
| `unknown profile: <name>` | The profile does not exist. Exit **2**; the available profiles are listed. |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success, or wizard cancelled ("no changes made"). |
| `1` | Generic error. |
| `2` | Usage error: unknown flag, missing value, extra argument, `--force` without `--update`, or unknown profile. |
| `3` | Prerequisite missing (bash, `jq`, `uv`, `curl`, sha256 tool). |
| `5` | Spec Kit stage failed (CLI install, `specify init`, or extension add). |
| `6` | Overlay stage failed (`--update` without a manifest, unmanaged-file conflict, or a write failure). |
| `7` | Validation / self-check failure (maintainer scripts). |
