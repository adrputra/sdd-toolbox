---
description: Drive a request through the gated GitHub Spec Kit flow — specify, plan, tasks, then dependency-ordered parallel wave execution with evidence
agent: spec-kit-driver
---

/sdd <request> — Arguments: $ARGUMENTS

Route the request to the **spec-kit-driver** agent and follow its gated phase
workflow. `$ARGUMENTS` is the raw request: a feature description, a bug report
(prefix `bug`), or a continuation instruction for the active feature.

Procedure:

1. **Load context** — read `.opencode/context/spec-kit/navigation.md` first, then
   the context files it points to. Read `.sdd-toolbox/config.json` for runtime
   settings.
2. **Discover Spec Kit** — at runtime, enumerate the installed `/speckit.*`
   surface (command vs skill naming differs per integration). Never hardcode
   invocation names.
3. **Intake** — classify the request (feature / bug / continuation), resolve the
   active feature directory via `.specify/feature.json` /
   `SPECIFY_FEATURE_DIRECTORY`, and ask clarifying questions via the `question`
   tool. Write nothing yet.
4. **Run the gated flow** — constitution (once) → specify → [clarify/checklist]
   → **GATE** → requirements analysis → plan → **GATE** → tasks → [analyze] →
   **GATE** → implement waves → converge loop.
5. **Stop at every gate** and ask for explicit owner approval via the `question`
   tool (numbered text fallback when it is unavailable). Never proceed
   unapproved.
6. **On implement** — compute and present the wave plan, dispatch 1–4 tasks to
   parallel `CoderAgent`s (5+ to `BatchExecutor`), tick checkboxes live, run the
   configured validation after each wave, and STOP on failure.
7. **Bug requests** — use the bug-fix flow (assess → fix → test) when the bug
   extension is installed, ending with a `verified | partial | failed` verdict.
8. **Report with evidence** — never claim completion without fresh command
   output captured at that moment.

If `$ARGUMENTS` is empty, ask the owner what they want to build or fix and run
intake.
