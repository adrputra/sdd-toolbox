# Spec Kit Driver — Evidence Protocol

Rules for proving work happened. Loaded from [`navigation.md`](navigation.md)
before any phase/task completion claim.

## The one rule

**No completion claim without fresh command output captured at that moment.**

"Fresh" means: you ran the command during this session, after the last change,
and you are reading its actual output — not remembering a previous run and not
predicting what it would say.

Forbidden phrases without evidence:
- "should work", "should pass", "probably fine", "looks correct"
- "tests pass" (without the run output)
- "the file is updated" (without showing the write/read)

If you did not verify it, say so explicitly.

## What counts as evidence

| Claim | Required evidence |
|---|---|
| Task implemented | the file(s) changed + a read/diff showing the change |
| Build/typecheck passes | the exact command + its exit-0 output |
| Tests pass | the exact command + the summary line (pass/fail counts) |
| Phase artifact authored | the artifact path + a read of the relevant section |
| Bug fixed | the failing-before evidence + passing-after test output |

Evidence is captured at the moment of the claim, not reconstructed later.

## Report format

For each completed unit:

```
Task:    T003 — add migration for new states
Ran:     go test -race -count=1 ./internal/... 
Result:  ok  github.com/.../internal/...  1.234s   (exit 0)
Verdict: verified
```

For a wave:

```
Wave 2: T003, T004, T005 — all ticked
Validation: go vet ./... && go test -race -count=1 ./... 
Result: PASS (exit 0)
```

## Verdicts

Use exactly one of:

- **verified** — the command ran now and passed; evidence included.
- **partial** — some checks passed, others did not run or failed; state which.
- **failed** — the command ran now and failed; include the failing output.

Never report `verified` when any required check is missing or stale.

## On failure

A failure is reported, not hidden:

1. The exact command that failed.
2. The relevant output excerpt (failing lines, not the whole log).
3. The task/wave it belongs to.
4. Proposed next options asked via the `question` tool, then **STOP** and wait
   for the owner's selection.

Do not retry silently, do not weaken the check, do not proceed to the next wave.

## Evidence and gates

At every gate, the summary states what was verified and with which command. If a
gate's artifact was authored through a Spec Kit command, cite the command and
the resulting file path. An unverifiable gate is not ready to approve.

## Bug-flow verdicts

The bug flow ends with `verified | partial | failed` backed by test evidence:

```
Bug:     <slug>
Before:  <test/command> -> FAIL (output excerpt)
After:   <test/command> -> PASS (output excerpt)
Verdict: verified
```

`partial` means the fix works for some cases but coverage is incomplete — say
which cases remain. `failed` means the test still fails; report and stop.
