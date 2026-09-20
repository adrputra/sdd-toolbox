# Spec Kit Driver — Artifacts & Feature Resolution

Where Spec Kit stores everything and how the driver finds the active feature.
Loaded from [`navigation.md`](navigation.md).

## On-disk layout

```
<project>/
├── .specify/                       # Spec Kit-owned
│   ├── memory/constitution.md      # project constitution (once)
│   ├── templates/                  # artifact templates
│   ├── scripts/                    # Spec Kit helper scripts
│   ├── extensions/                 # installed extensions (e.g. bug)
│   └── feature.json                # active feature pointer
├── specs/
│   └── <###-feature-name>/         # one directory per feature
│       ├── spec.md                 # requirements  (Spec Kit-authored)
│       ├── plan.md                 # design/plan   (Spec Kit-authored)
│       ├── tasks.md                # task list     (Spec Kit-authored)
│       ├── research.md             # optional
│       ├── data-model.md           # optional
│       └── contracts/              # optional
└── .sdd-toolbox/                   # toolbox-owned (never Spec Kit)
    ├── config.json
    ├── manifest.json
    └── waves/<feature>.json
```

## Ownership rules

| Path | Owner | Driver may |
|---|---|---|
| `.specify/**` | Spec Kit | only invoke Spec Kit commands |
| `specs/**` | Spec Kit | only invoke Spec Kit commands |
| `specs/**/tasks.md` | Spec Kit | tick checkboxes during execution |
| `.sdd-toolbox/**` | Toolbox | read config; read/write wave sidecars |

**Never create, edit, or delete `.specify/` or `specs/` files directly.** Author
them exclusively through the discovered Spec Kit capabilities. The single
sanctioned direct write is flipping `- [ ]` to `- [x]` in `tasks.md` as tasks
complete.

## Feature-directory resolution

Resolve the active feature before doing anything else. Precedence:

1. **Explicit argument** — a feature name/dir passed to `/sdd`.
2. **Environment** — `SPECIFY_FEATURE_DIRECTORY` when set.
3. **Pointer file** — `.specify/feature.json` (e.g. `{"feature_directory":
   "specs/001-photo-albums"}` or a `feature`/`path` key).
4. **Filesystem** — when exactly one directory exists under `specs/`, use it.
5. **Ambiguous** — list `specs/*` and ask the owner to choose via the `question`
   tool. Never guess.

Once resolved, keep the feature directory fixed for the run and pass it to every
delegated worker.

### Reading `.specify/feature.json` safely

Use `jq`; never `eval` its content. The key name varies by Spec Kit version, so
check the common keys:

```sh
jq -r '.feature_directory // .feature // .path // empty' .specify/feature.json
```

If the resolved path does not exist under `specs/`, fall back to filesystem
discovery and report the mismatch.

## Artifact responsibilities

| Artifact | Authored by | Driver's role |
|---|---|---|
| `constitution.md` | constitution capability | run once; skip when present + approved |
| `spec.md` | specify capability | present at the Specify gate; analyse pre-plan |
| `plan.md` | plan capability | present at the Plan gate |
| `tasks.md` | tasks capability | parse, compute waves, tick live |
| `research.md`, `data-model.md`, `contracts/` | plan/tasks capabilities | reference only |

## Task file is execution state

`tasks.md` is the single source of truth for execution. Its checkbox state is
live: `[ ]` pending, `[x]` done. Parsing rules, the DAG, and the wave sidecar
live in [`wave-execution.md`](wave-execution.md).

## Never touch

- `.git/**`
- `**/*.env*`, `**/*.key`, `**/*.secret`
- Anything outside the project root
