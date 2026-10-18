# Site Design Brief

**Status**: TEMPLATE — fill in the sections this project depends on, replace
every `[bracketed]` placeholder, then change the status to `LOCKED v1` with
the owner and date. Delete this file if the project has no UI surfaces.

**Scope**: `[which app(s), routes, or surfaces this brief governs]`

**Authority**: for UI work in the SDD flow this brief outranks taste and
component-library defaults. It never overrides accessibility, performance
budgets, security, or platform/content policy.

## How this brief is used

- Every UI task loads this brief and the `impeccable` skill before editing.
- Locked sections are hard constraints for every UI change; a task that cannot
  satisfy one is a blocker, not a reason to improvise.
- Bracketed placeholders are **unlocked**: a feature that depends on one raises
  an Open Question instead of guessing.
- `VisualQA` verifies the rendered result against the locked sections and the
  impeccable craft floor.
- Theme tokens are the implementation mechanism: appearance changes flow
  through tokens, never hardcoded values scattered through components.

## Visual direction

[Personality in a sentence. Three adjectives, and three anti-patterns to avoid.
What should a visitor feel in the first five seconds?]

## Typography

[Font families and loading strategy; heading scale; body size/line-height;
measure; weights; fallback stack. State what is banned.]

## Color system

[Semantic roles (surface, text, muted, border, accent, success, warning,
danger), contrast targets, light/dark behavior. Name the token source.]

## Surfaces and elevation

[Cards, panels, overlays, borders, radii, shadows. What elevation means and
when it is used. What must never float.]

## Layout

[Grid, container widths, breakpoints, spacing scale, density. How the layout
responds below the smallest desktop breakpoint.]

## Shape

[Radius scale, iconography style, illustration style, decorative rules.]

## Motion

[Duration/easing ranges, which interactions may animate, reduced-motion
behavior. What must not animate.]

## Component rules

[Buttons (variants, sizes, states), inputs, selects, tables, navigation, tabs,
badges, dialogs, alerts, tooltips, pagination, empty/loading/error states.
State conventions and banned patterns.]

## Voice and tone

[Microcopy conventions, capitalization, error-message shape, empty-state
shape, button labels. Terminology that must stay consistent.]

## Icons

[Icon set, stroke/fill rules, sizes, alignment, accessible labeling.]

## Verification checklist

- [ ] Every bracketed placeholder this project depends on is resolved.
- [ ] Tokens exist for every color, spacing, radius, and type decision.
- [ ] Desktop (1440×900) and mobile (390×844) are explicitly in scope.
- [ ] Accessibility and performance budgets are unchanged.
- [ ] The owner approved this brief and recorded the date above.
