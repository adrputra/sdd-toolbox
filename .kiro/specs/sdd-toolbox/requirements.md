# Requirements: SDD Toolbox

**Phase**: 1 — Requirements
**Status**: DRAFT — awaiting owner review (Phase 1 checkpoint)
**Spec**: `.kiro/specs/sdd-toolbox`

---

## 1. Introduction

`sdd-toolbox` is a standalone, reusable toolchain repository that bootstraps new
software projects with opencode-based spec-driven-development tooling:

- **OpenAgents Control (OAC)** base components, bundled at a pinned version
- **GitHub Spec Kit** integration, installed via the official `specify` CLI at a
  pinned version
- A custom **Spec Kit driver agent** that orchestrates Spec Kit's workflow with
  mandatory review gates and wave-based parallel execution
- Declarative **profiles** per project type, with safe update semantics
- An **interactive bootstrap wizard** that surfaces every available option —
  profiles, components, extensions, actions, advanced settings — so the user
  decides at install time

### Why this exists

- Built SDD tools (Spec Kit, OpenSpec) stop at planning artifacts: no hard
  review gates, no execution orchestration.
- The gates + parallel-wave execution pattern is already proven by the custom
  SpecDriver agent in `shipgo-backend-go` (20+ shipped specs).
- New projects currently require manual tooling setup that drifts between repos.

### Glossary

| Term | Meaning |
|---|---|
| Toolbox | This repository (`sdd-toolbox`) |
| Target project | A repository being bootstrapped by the toolbox |
| Driver agent | The custom opencode agent (`spec-kit-driver`) shipped by the toolbox |
| Profile | A named, declarative bundle of components + validation commands for a project type (`minimal`, `go-backend`) |
| Managed file | A file installed into a target project by bootstrap and tracked in the target manifest |
| Wave | A group of tasks whose dependencies are all satisfied, executed in parallel |

---

## 2. User Stories

### US-1 — Interactive, guided project bootstrap

As a solo developer, I want to run one command and choose what gets installed
from an interactive terminal menu, so that setup is guided and I always know
what is about to be written into my project.

**Acceptance criteria**

- [ ] Running `./bootstrap.sh` with no arguments in an interactive terminal
      (TTY) starts a wizard that lets me choose: the target directory
      (default: current directory), the profile (menu of all available
      profiles, with descriptions), component groups (multi-select of
      everything in the registry, pre-selected from the chosen profile),
      optional Spec Kit extensions (e.g. bug-fix), and an advanced options
      section for runtime-configurable settings.
- [ ] All menus are populated dynamically from the toolbox contents
      (`profiles/`, `registry.json`) — nothing is hardcoded; adding a profile
      or component makes it appear in the wizard with no script changes.
- [ ] Interactive mode always asks for the profile; defaults are applied only
      in non-interactive mode — the user always decides.
- [ ] The wizard shows a confirmation summary (target, profile, components,
      pinned versions) before anything is written; nothing is written until
      confirmed.
- [ ] The wizard is cancellable at any point, exiting cleanly with a
      "no changes made" message.
- [ ] Invalid input re-prompts instead of failing.
- [ ] When flags are supplied (`--profile <name>`, `--yes`) or stdout is not a
      TTY, the installer runs non-interactively — required for scripted smoke
      tests and automation.
- [ ] `./bootstrap.sh <target-dir> [--profile <name>]` exits 0 on (a) a new or
      empty directory and (b) an existing project directory.
- [ ] Installs: Spec Kit opencode integration (official CLI, pinned version),
      bundled OAC base, driver agent + context + commands, and the target
      manifest.
- [ ] Never modifies files not owned by the toolbox (no unmanaged file is
      created, changed, or deleted in the target).
- [ ] If the target already contains a toolbox manifest, the wizard detects it
      and offers Update / Reinstall / Cancel instead of overwriting silently.
- [ ] Prints a next-steps summary (how to launch opencode and invoke the driver).
- [ ] Fails fast with actionable messages when prerequisites are missing
      (bash, git, network for the pinned Spec Kit CLI install).
- [ ] Is verifiable end-to-end by a scripted smoke test that bootstraps a
      temporary directory non-interactively and asserts the expected files and
      manifest exist.

### US-2 — Pinned, bundled toolchain

As a solo developer, I want all components and external versions pinned and
recorded, so every bootstrapped project uses a known-good toolchain and nothing
drifts silently.

**Acceptance criteria**

- [ ] OAC base components are vendored inside the toolbox at a recorded
      version; bootstrap installs them from the local bundle (no network fetch
      to OAC).
- [ ] The Spec Kit CLI version is pinned, and bootstrap installs that exact
      version.
- [ ] The target manifest records: toolbox version, OAC version, Spec Kit CLI
      version, profile name, and per-file content hashes.
- [ ] The toolbox collects no telemetry and makes no network calls beyond the
      pinned Spec Kit CLI install.

### US-3 — Safe updates

As a solo developer, I want `--update` to refresh managed files without
destroying my customizations.

**Acceptance criteria**

- [ ] `./bootstrap.sh <target> --update` refreshes managed files that are
      unmodified since install to the toolbox's current versions.
- [ ] Update is reachable both via `--update` and from the interactive wizard
      when an existing install is detected.
- [ ] The wizard's Reinstall action is the interactive equivalent of
      `--update --force` (explicit confirmation required).
- [ ] Managed files modified by the user are preserved untouched and reported
      as skipped.
- [ ] `--force` explicitly overwrites modified managed files (opt-in only).
- [ ] `--dry-run` prints planned writes/skips without modifying the target.
- [ ] Running bootstrap or update repeatedly is idempotent (no duplicates, no
      data loss).

### US-4 — Profiles per project type

As a solo developer, I want selectable profiles, so a Go backend project gets
Go-specific validation and context while a minimal project stays lean.

**Acceptance criteria**

- [ ] `minimal` (default for non-interactive runs): Spec Kit integration +
      driver agent + the bundled subagents/context required for execution; no
      stack-specific tooling.
- [ ] `go-backend`: everything in `minimal`, plus Go validation commands
      (`go vet ./...`, `go test -race -count=1 ./...`) wired into wave
      validation, plus Go-relevant context/skills from the OAC base.
- [ ] Profiles are declarative files under `profiles/`; adding or changing a
      profile requires no changes to bootstrap-script logic.
- [ ] Each profile declares a name, description, and component list that the
      interactive wizard can render as a menu.
- [ ] Selecting an unknown profile fails with the list of available profiles.

### US-5 — Driver agent: gated Spec Kit flow

As a solo developer, I want the driver agent to walk Spec Kit's workflow with
mandatory review checkpoints, so no code is written before I approve the
artifacts.

**Acceptance criteria**

- [ ] Driver supports Spec Kit's full SDD command set: constitution (once per
      project; skipped when already present and approved), specify, clarify,
      checklist, plan, tasks, analyze, implement, and converge — plus the
      bug-fix flow (assess → fix → test) when the Spec Kit bug-fix extension
      is installed (offered as a bootstrap option). `taskstoissues` is out of
      scope (GitHub-specific; this toolbox targets GitLab).
- [ ] Between phases, the driver presents a summary and waits for explicit
      approval; it never proceeds unapproved.
- [ ] Before planning, the driver runs a requirements-analysis pass
      (ambiguities, gaps, conflicts with the existing codebase) and surfaces
      Open Questions; it never invents answers.
- [ ] The driver uses Spec Kit's own `/speckit-*` commands for artifact
      authoring rather than reimplementing them.
- [ ] Any phase failure stops the flow with a report; no silent workarounds.

### US-6 — Driver agent: wave execution on implement

As a solo developer, I want implementation orchestrated in dependency-ordered
waves with parallel workers, so independent tasks run concurrently and each
wave is validated.

**Acceptance criteria**

- [ ] On implement, the driver derives a dependency-ordered wave plan and
      presents it for approval before executing anything.
- [ ] Independent tasks within a wave are dispatched to parallel execution
      subagents.
- [ ] Task status is updated live as tasks complete (task checkboxes ticked in
      the tasks artifact).
- [ ] After each wave, the profile's validation commands run; on failure the
      driver stops, reports, proposes, and requests approval before continuing.
- [ ] The implement → converge loop repeats until Spec Kit reports converged.
- [ ] The wave-metadata mechanism does not alter Spec Kit-owned artifacts in a
      way that breaks Spec Kit tooling (mechanism defined in design).
- [ ] Wave-derivation strategy is a runtime-configurable setting (default:
      toolbox sidecar metadata) offered in the wizard's advanced options and
      editable after bootstrap.

### US-7 — Evidence-based reporting

As a solo developer, I want the driver to never claim success without fresh
verification, so its reports are trustworthy.

**Acceptance criteria**

- [ ] The driver never claims a phase complete, fixed, or passing without fresh
      verification output (command + result) captured at that moment.
- [ ] The bug-fix flow ends with a verdict (verified / partial / failed) backed
      by test evidence.

### US-8 — Registry and self-validation

As the toolbox maintainer, I want custom components cataloged in an
OAC-compatible registry and validated automatically, so the toolbox stays
installable and internally consistent.

**Acceptance criteria**

- [ ] All custom components (agent, context, commands) are cataloged in an
      OAC-compatible `registry.json` with a valid schema.
- [ ] A validation script checks: registry schema, agent frontmatter validity,
      and that every subagent/component referenced by the driver and profiles
      exists in the bundle.
- [ ] The validation script passes on a clean checkout and is documented in
      the README.

---

## 3. Out of Scope (v1)

- OpenSpec support — the driver targets Spec Kit only (OpenSpec remains a
  future profile option)
- Spec Kit's assessment extension (`/speckit-assess-*`)
- Windows support — Linux/macOS only
- Tool integrations other than opencode
- Publishing the toolbox or components to public registries
- Team/multi-repo features (shared spec stores, cross-repo planning)
- CI/CD pipeline generation for target projects
- Global opencode configuration (`~/.config/opencode`) — project-local only
- Migrating existing repositories (e.g. `shipgo-backend-go`) to the toolbox
- Dogfooding (the toolbox developing itself with the driver) — planned after v1

---

## 4. Constraints

- POSIX-friendly bash; Linux + macOS
- The interactive wizard must run on plain bash + coreutils — no mandatory
  external TUI dependency; optional TUI tools may be used only when detected,
  never required
- No secrets in the repository; no telemetry
- Toolbox components are the source of truth; target copies are managed
  artifacts (changes flow toolbox → target, not the reverse)
- Standalone: no dependency on any private or personal repository
- The driver writes into `.specify/` only through Spec Kit commands

---

## 5. Decisions & Design Verification

**Owner directive: options are decided at runtime.** Every option the toolbox
supports is surfaced to the user when the installer asks (the wizard), not
hardcoded into requirements. Defaults apply only to non-interactive runs.
The former open questions are resolved as follows:

1. **Wave dependency metadata** → runtime-configurable setting (default:
   toolbox-owned sidecar emitted at the tasks phase; Spec Kit artifacts
   untouched). Exposed in the wizard's advanced options and editable in the
   target config. Mechanism verified in design.
2. **OAC bundling breadth** → the toolbox vendors the superset of components
   needed by all profiles; the wizard's component multi-select decides what is
   installed per project. The curated set is validated by the US-8 script.
3. **Per-project customization** → toolbox remains the source of truth; the
   wizard offers Update (preserve modified) / Reinstall (overwrite all) /
   Cancel; `--force` is the non-interactive equivalent of Reinstall.
4. **Default profile** → interactive mode always asks; `minimal` is the
   default only for non-interactive runs without `--profile`.
5. **Wizard interactivity style** → best available UX: enhanced menus
   (arrow-key) when optional tools (e.g. `gum`, `fzf`) are detected; numbered
   prompts always available as the zero-dependency fallback.

**Design verification items (no owner decision needed):**

- Spec Kit tasks artifact format and whether dependency edges exist (drives
  the wave-strategy implementation).
- Exact pinned versions and install commands for the Spec Kit CLI
  (`uv`/`specify`) and its opencode integration.
- OAC registry schema compatibility for custom components.
- Enhanced-terminal detection mechanics and fallback behavior.

---

## 6. Phase Gate

- [ ] Owner approves these requirements (runtime-choice approach included)
- [ ] Proceed to Phase 2 (design)
