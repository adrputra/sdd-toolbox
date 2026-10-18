---
name: visual-qa
description: Use when verifying the rendered UI of this project — pages, tool surfaces, or admin screens — after a frontend change, before claiming UI work complete, or when asked to screenshot/review a page. Captures desktop/tablet/mobile screenshots with Playwright, runs the Impeccable detector, and inspects layout, typography, color, components, hierarchy, responsive behavior, interaction states, accessibility, and content realism against PRODUCT.md and DESIGN.md. Produces an evidence-based report with CRITICAL/HIGH/MEDIUM/LOW findings.
---

# Visual QA

Browser-based visual verification for this project. Source code, DOM
assertions, unit tests, and accessibility trees are useful but **insufficient**:
a page is not verified until its rendered pixels have been inspected.

## Prerequisites

- Playwright is installed in the app package (`@playwright/test`, browsers
  provisioned). Nothing else is needed for capture.
- The Impeccable skill (`.opencode/skills/impeccable/`) is used for design
  guidance and the mechanical detector. If the detector is unavailable, report
  that; capture and review still proceed.
- Context to read before judging: `PRODUCT.md`, `DESIGN.md`, and — when the
  project has one — the owner constraints in
  `.opencode/context/design/site-design-brief.md` (locked sections bind;
  bracketed placeholders are `unlocked`, never failures).

## Quick start

Use the project's capture runner. Discover it from `package.json` scripts and
`.sdd-toolbox/config.json` (`visual_qa` block, when present); do not invent a
command.

```bash
<package-manager> visual:qa            # build + serve + full viewport matrix + detector
<package-manager> visual:qa:desktop    # desktop viewport only
<package-manager> visual:qa:mobile     # mobile viewport only
<package-manager> visual:qa:report     # print the latest capture summary (no re-run)
```

A typical runner accepts `--routes=...`, `--viewports=...`, `--out=...`,
`--site=...`, `--port=...`, `--full-page`, `--base-url=...` (skip build/serve),
`--no-build`, and `--report`. Check the project's runner before using a flag.

For a dev server already running, use `--base-url` and `--routes`, e.g.:

```bash
<package-manager> --filter <app-package> exec node scripts/visual-qa.mjs \
  --base-url=http://localhost:5173 --routes=/ --viewports=desktop,mobile --no-build
```

If the project has no runner, capture with Playwright directly and report
`UNABLE` for the missing automation rather than pretending a pass.

## Output structure

```
.visual-qa/
  screenshots/
    desktop/   home-desktop.png, ...-desktop.png
    tablet/
    mobile/
  reports/     <timestamp>-capture.md, <timestamp>-capture.json, detect-*.json
  baselines/   future visual-regression baselines (empty until adopted)
```

Generated screenshots and reports are gitignored; never commit large
screenshot sets.

## Standard viewport matrix

| Class   | Size      | When |
|---------|-----------|------|
| Desktop | 1440×900  | Always |
| Mobile  | 390×844   | Always |
| Desktop | 1280×800  | Optional (compact desktop) |
| Tablet  | 768×1024  | Optional (tablet breakpoint) |
| Mobile  | 393×873   | Optional (tall phone) |

Use the matrix the runner exposes: `desktop`, `mobile`, `tablet`, or `all`.
Do not add arbitrary viewports for quantity; match the layout's real
breakpoints.

## Procedure (bounded passes)

1. **Understand** — read the change, `PRODUCT.md`, `DESIGN.md`, the design
   brief when present, and the feature's acceptance criteria.
2. **Capture** — run the project runner (or `<package-manager> visual:qa` for
   the full matrix).
3. **Inspect** the screenshots plus detector output against the checklist
   below. Inspect desktop and mobile before concluding anything.
4. **Report** findings with severity, evidence, and a recommended fix
   (format below).
5. **Fix** — the implementing agent fixes all significant findings in one
   batch; the verifier never edits product code.
6. **Re-capture and confirm** — one confirmation pass over the original
   findings plus a fresh sweep. Then stop: do not keep polishing variations
   that are not defects.

Open-ended polishing is failure. Two passes (fix batch + confirmation) is the
ceiling unless a new significant regression appears.

## What to inspect

### Layout
Alignment, spacing, vertical/horizontal rhythm, container width, density,
section relationships, grid, unexpected wrapping, overflow, clipping,
whitespace imbalance, inconsistent margins/padding.

### Typography
Font family and loading, hierarchy, heading scale, line-height, letter
spacing, paragraph width, density, truncation, wrapping.

### Color
Primary/secondary/semantic roles, contrast, surface hierarchy, muted text,
borders, state colors, accidental color noise.

### Components
Buttons, inputs, selects, cards, tables, navigation, tabs, badges, dropdowns,
dialogs, alerts, tooltips, pagination, empty/loading/error states.

### Visual hierarchy
What should the visitor notice first? Is the primary action obvious? Are
secondary elements competing with primary content? Is important information
buried? Are decorative elements stealing attention?

### Responsive behavior
Mobile navigation, wrapping, stacking, horizontal scrolling, table behavior,
button width, form layout, image scaling, typography scaling, sticky
elements, dialogs, overflow.

### Interaction states
Hover, focus, active, selected, disabled, loading, validation error, success,
empty, expanded, collapsed — where relevant to the surface.

### Accessibility
Contrast, visible focus, touch-target size (≥ 44px), text size, semantic
structure, keyboard usability, form labeling, error visibility. The project's
axe e2e gates must stay green.

### Content realism
Never judge with short placeholder text only. Test long titles, long names,
large numbers, long labels, multi-line descriptions, empty values, missing
images, long button labels. Apply real-world length pressure even when the
current locale is short.

## Impeccable detector (mechanical second layer)

The runner should invoke it automatically. Manual equivalent:

```bash
.opencode/skills/impeccable/scripts/impeccable detect --json \
  --viewport 1440x900 http://localhost:4321/ http://localhost:4321/example/
```

Rules: exit `2` means primary findings — they block unless an owner-approved
ignore (`.impeccable/config.json`) waives them; exit `0` is clean; exit `1` is
a scan error. JSON goes to stdout, the readable finding list to stderr. A clean
detector run is **one signal, not proof** — screenshot inspection remains
mandatory.

## Report format

```
Page:
Viewport:
Screenshot:
Severity:
Problem:
Evidence:
Recommended Fix:
Status:
```

Severity levels:

- **CRITICAL** — blocks normal usage or seriously breaks layout.
- **HIGH** — major visual/UX defect; the interface feels broken or
  substantially worse.
- **MEDIUM** — noticeable inconsistency or usability/design issue.
- **LOW** — minor polish.

Every finding needs rendered evidence and a concrete reference: page, viewport,
screenshot path, and the observed effect. No subjective criticism without
visual evidence.

Bad: "Header feels bad."

Good: "At 390×844 the header consumes about a third of the initial viewport
because the navigation wraps to a second row, pushing primary content below
the fold (`screenshots/mobile/home-mobile.png`). Recommend a compact mobile nav
or a single-row collapse."

## Evidence rules

- Fresh output only: capture and read the screenshots from this run.
- Both desktop and mobile, or it is not a pass.
- Failed capture/build is a defect or a blocker — never "should be fine".
- Do not mark findings acceptable or waived; only the owner approves ignores.

## Preserve functionality

Visual QA never encourages breaking behavior. Before/after a UI change verify
routing, navigation, forms, API interaction, loading, validation, error
handling, state management, and responsive interactions — a beautiful but
broken page fails.

## Integration with the SDD workflow

- `FeatureRunner` dispatches the `VisualQA` agent for UI-touching features
  after the last converge round. Verdicts: `PASS` → complete; `FAIL` → one
  batch fix plus one re-check, then block; `UNABLE` → block.
- In harnesses without subagents, follow this skill directly and report the
  same PASS/FAIL/UNABLE verdict with findings.
- This skill is also usable standalone on any route of any app via
  `--base-url`.

## Adding a page to visual QA

Add the route to the runner invocation (`--routes=/new/page/`) or to the
runner's `DEFAULT_ROUTES` list if it is a permanent representative surface.
Then capture desktop and mobile at minimum and run the checklist above.
