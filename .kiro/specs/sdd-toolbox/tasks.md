# Tasks: SDD Toolbox

**Phase**: 3 — Tasks
**Status**: DRAFT — awaiting owner review (Phase 3 checkpoint)
**Spec**: `.kiro/specs/sdd-toolbox`
**Design**: `design.md` (approved, with 3 consistency adjustments: flat `vendor/oac/`, `lib/wizard.sh` module, catalog split)

---

## Task Format

```
- [ ] Tnn: <deliverable> — depends_on: <ids|none> — layer: <area> — verify: <check>
```

Execution notes:
- Tasks run in dependency-ordered waves; checkboxes tick live.
- Per-wave validation: `bash -n` + `shellcheck` (when available) on changed
  scripts; `scripts/validate.sh` and `scripts/smoke-test.sh` once they exist.
- On failure: STOP the wave, report, propose, request approval.
- Repo-specifics: bash 3.2+ compatible, `jq` for JSON, no `sudo`.

---

## Tasks

### Wave 2 — Core modules and components

- [x] T01: Scaffold repo layout (`lib/`, `components/{agent,command,context}`, `vendor/oac/`, `profiles/`, `scripts/`), `.gitignore`, `versions.env` (OAC_VERSION, SPEC_KIT_VERSION placeholders), README skeleton — depends_on: none — layer: repo/scaffold — verify: tree matches design §3
- [x] T02: `lib/args.sh` — flag parsing (`<target>`, `--profile`, `--yes`, `--update`, `--force`, `--dry-run`, `--no-spec-kit`, `--help`), usage text, exit 2 on invalid usage — depends_on: T01 — layer: lib/args — verify: piped-arg cases behave per design §5.1
- [x] T03: `lib/ui.sh` — logging helpers, `confirm`, `choose`, `multiselect` with numbered-prompt fallback + `gum`/`fzf` detection, cancel semantics (q/Ctrl-C → exit 0 "no changes") — depends_on: T01 — layer: lib/ui — verify: functions exercised with piped input (enhanced + fallback paths)
- [x] T04: `lib/prereqs.sh` — checks for bash version, `jq`, `uv`, `curl`; actionable install hints; exit 3; test hook for PATH simulation — depends_on: T01 — layer: lib/prereqs — verify: stripped-PATH case produces hint + exit 3
- [x] T05: `lib/manifest.sh` — sha256 wrapper (`sha256sum`/`shasum -a 256`), manifest + config read/write via `jq`, file classification helpers (identical/unmodified/modified/missing/conflict) — depends_on: T01 — layer: lib/manifest — verify: hash parity both binaries; classification table on fixture files
- [x] T06: `lib/registry.sh` — load `registry.json` + `vendor/oac/bundle.json` + `profiles/*.json`, merge catalog, resolve `type:id` → source path, profile defaults; pure `jq`, no `eval` — depends_on: T01 — layer: lib/registry — verify: fixtures resolve; unknown ID errors cleanly
- [x] T07: Driver agent + entry command — `components/agent/core/spec-kit-driver.md` (frontmatter + permission guards; phase state machine §9.2; gates; full command routing with runtime-discovered invocation; requirements-analysis pass; delegation table; evidence rules) + `components/command/sdd.md` routing `/sdd` — depends_on: T01 — layer: components/agent — verify: frontmatter parses; checklist against design §9
- [x] T08: Driver context files — `components/context/spec-kit/{navigation,workflow,artifacts,wave-execution,evidence}.md` (task parsing incl. `[P]` + `(depends on …)` regex, sidecar schema §10.3, wave loop + stop rules, artifact/feature resolution, evidence protocol) — depends_on: T01 — layer: components/context — verify: matches design §9.6/§10; cross-references valid
- [x] T09: `scripts/vendor-sync.sh` — maintainer tool: `--source <dir> [--components <file>]` copies selected `.opencode/**` into `vendor/oac/`, writes `bundle.json` (version, component entries, hashes, provenance/license note); selection file `vendor/selection.txt`; never network — depends_on: T01 — layer: scripts/vendor — verify: dry-run against a fixture source produces expected bundle.json
- [x] T10: `registry.json` — OAC-compatible schema (`schema_version`, `components` with custom entries: driver agent, sdd command, context files; `extensions` catalog with `bug`); unique IDs — depends_on: T01 — layer: catalog/registry — verify: `jq` schema check; no duplicate IDs
- [x] T11: `lib/spec_kit.sh` — ensure pinned `specify-cli` via `uv tool install` (resolve latest stable release tag, record in `versions.env`), `specify version` parse + mismatch policy, init invocation matrix (empty vs non-empty `--force`, `--non-interactive --integration opencode --script sh`), `specify extension add` wrapper; exit 5 — depends_on: T01 — layer: lib/spec-kit — verify: version-parse fixtures; init/extension commands dry-checked against docs

### Wave 3 — Data, profiles, engine, wizard

- [x] T12: Vendored OAC snapshot — run `vendor-sync.sh` against the OAC source (path required at execution time) at a pinned version; commit `vendor/oac/**` + `bundle.json`; set `OAC_VERSION` — depends_on: T09 — layer: vendor/bundle — verify: `bundle.json` hashes match files; every profile-needed component present
- [x] T13: Profiles — `profiles/minimal.json` + `profiles/go-backend.json` (name, description, components by ID, validation commands, wave defaults) — depends_on: T10 — layer: profiles — verify: schema check; IDs resolve against merged catalog
- [x] T14: Installer engine — `lib/installer.sh` + `lib/update.sh`: install/update/reinstall classification per design §7.2, backups on force, dry-run plan table, config generation §11, manifest assembly (written last); exit 6 — depends_on: T05, T06 — layer: lib/installer — verify: fixture-driven classification; dry-run writes nothing
- [x] T15: `lib/wizard.sh` — 7 screens per design §6 (target, action, profile, components, extensions, advanced, confirm); dynamic from registry/profiles; cancel semantics — depends_on: T03, T05, T06 — layer: lib/wizard — verify: scripted input runs (fallback path); cancel exits 0 with no writes

### Wave 4 — Entry point and self-validation

- [x] T16: `bootstrap.sh` — entry orchestration per design §5.2 (args → prereqs → wizard or non-interactive plan → Spec Kit stage → overlay install → config → manifest → summary); traps + exit codes; `--no-spec-kit`, `--dry-run`, `--update` paths — depends_on: T02, T04, T11, T14, T15 — layer: bootstrap/entry — verify: `--help`, bad usage, `--dry-run` on temp dir
- [x] T17: `scripts/validate.sh` — `bash -n` on all scripts, `shellcheck` when present, `jq` schema checks (registry, profiles, bundle, versions), reference integrity (profile IDs → catalog → files; driver subagent refs → vendor) — depends_on: T07, T08, T10, T12, T13 — layer: scripts/validate — verify: passes on repo; fails when a reference is removed (negative test)

### Wave 5 — Smoke tests and docs

- [x] T18: `scripts/smoke-test.sh` — 8 scenarios per design §14.2 (fresh install, idempotency, update preserve, force+backup, dry-run, unknown profile, `--no-spec-kit`, missing prereq) into temp dirs — depends_on: T12, T16 — layer: scripts/smoke — verify: suite runs end-to-end with non-interactive flags
- [x] T19: `README.md` — usage, wizard flow, update/reinstall semantics, driver usage (gates, waves, config), maintainer notes (vendor-sync, validate), troubleshooting — depends_on: T16, T07 — layer: docs/readme — verify: commands in README copy-paste-correct

### Wave 6 — End-to-end hardening

- [x] T20: Full-suite hardening — run `scripts/validate.sh` + `scripts/smoke-test.sh` end-to-end; fix until green; capture evidence output; update artifacts if spec/design proves wrong (with owner approval) — depends_on: T17, T18 — layer: verification/e2e — verify: both suites green with fresh output

---

## Wave Plan (computed)

```
Wave 1: T01
Wave 2: T02 T03 T04 T05 T06 T07 T08 T09 T10 T11   (10 parallel)
Wave 3: T12 T13 T14 T15                            (4 parallel)
Wave 4: T16 T17                                    (2 parallel)
Wave 5: T18 T19                                    (2 parallel)
Wave 6: T20
```

Notes:
- Wave 2 has 10 parallel tasks → BatchExecutor handles the wave (5+ rule).
- T12 (vendor snapshot) needs the OAC source path at execution time — see
  open items below.
- T20 may surface follow-up fixes; per execution rules, failures stop the
  wave and require approval before remediation.

---

## Open Items (resolved)

1. **OAC vendor source** — **Resolved (option 1):** snapshot from
   `shipgo-backend-go/.opencode`, vendored 2026-09-19 at version `0.5.2`
   (contamination scan clean; all 15 selection paths present). Provenance is
   recorded in `vendor/oac/bundle.json`.
2. **Spec Kit pin** — **Resolved:** T11 resolved and recorded the latest
   stable release tag, `v1.0.8`, in `versions.env` (independently confirmed
   against live tags).

---

## Phase Gate

- [x] Owner approves the task list and wave plan
- [x] Open Items 1–2 answered (T12 can proceed without #1; all other waves unaffected)
- [x] Approve execution (scope: all, or a subset)
