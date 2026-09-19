#!/usr/bin/env bash
# =============================================================================
# scripts/smoke-test.sh — end-to-end bootstrap scenarios (design §14.2, T18).
#
# Hermetic: every scenario runs in its own temp directory under a scratch root;
# `uv` and `specify` are stubbed on PATH (no network, no global installs). The
# scratch root is removed on exit, so nothing is left behind.
#
# Scenarios:
#   1 fresh install of an empty dir (--profile minimal --yes)
#   2 re-run -> idempotent (tree hash unchanged)
#   3 modify a managed file + delete another -> --update preserves + restores
#   4 modify -> --update --force -> backup created + overwritten + listed
#   5 --dry-run -> zero writes
#   6 unknown --profile -> exit 2 + available profiles listed
#   7 --no-spec-kit -> overlay installs; no .specify/
#   8 restricted PATH -> prereq failure exit 3 + actionable hint
#
# Runnable standalone from anywhere. Exit codes: 0 all scenarios passed;
# 1 one or more scenarios failed.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$CODE_ROOT}"
BOOTSTRAP="$TOOLBOX_ROOT/bootstrap.sh"

# shellcheck source=../lib/manifest.sh
. "${CODE_ROOT}/lib/manifest.sh"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/sdd-toolbox-smoke.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

STUB="$SCRATCH/stub"
STUB_LOG="$SCRATCH/stub.log"
LAST_OUT="$SCRATCH/last.out"
mkdir -p "$STUB"

# Pinned Spec Kit version, read from versions.env so the stub matches it.
# shellcheck source=/dev/null
. "$TOOLBOX_ROOT/versions.env"
stub_version="${SPEC_KIT_VERSION#v}"

cat > "$STUB/specify" <<EOF
#!/usr/bin/env bash
printf 'SPECIFY: %s\n' "\$*" >> "\${STUB_LOG:-/dev/null}"
if [[ "\${1:-}" == "version" ]]; then echo "specify $stub_version"; fi
exit 0
EOF
cat > "$STUB/uv" <<'EOF'
#!/usr/bin/env bash
printf 'UV: %s\n' "$*" >> "${STUB_LOG:-/dev/null}"
exit 0
EOF
chmod +x "$STUB/specify" "$STUB/uv"

PASS=0
FAIL=0
SCEN_FAILS=0

ok()  { printf '  [PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); SCEN_FAILS=$((SCEN_FAILS + 1)); }
scenario_begin() { SCEN_NAME="$1"; SCEN_FAILS=0; printf '\n--- %s ---\n' "$1"; }
scenario_end() {
    if [[ "$SCEN_FAILS" -eq 0 ]]; then
        printf '  => %s: PASS\n' "$SCEN_NAME"
    else
        printf '  => %s: FAIL\n' "$SCEN_NAME"
    fi
}

# run_bootstrap <args...> — run bootstrap.sh with the stubs on PATH.
# Call as: rc=0; run_bootstrap ... || rc=$?
run_bootstrap() {
    : > "$STUB_LOG"
    PATH="$STUB:$PATH" STUB_LOG="$STUB_LOG" "$BOOTSTRAP" "$@" >"$LAST_OUT" 2>&1
}

# tree_hash <dir> — content hash of every file under <dir>.
tree_hash() {
    local dir="$1"
    ( cd "$dir" 2>/dev/null && find . -type f | sort | while IFS= read -r f; do
        printf '%s ' "$f"; hash_file "$f"
      done | sha256sum | awk '{print $1}' )
}

# ===========================================================================
# Scenario 1 — fresh install
scenario_begin "Scenario 1: fresh install (--profile minimal --yes)"
T1="$SCRATCH/s1"; mkdir -p "$T1"
rc=0; run_bootstrap "$T1" --profile minimal --yes || rc=$?
[[ $rc -eq 0 ]] && ok "exit 0" || bad "exit 0 (got $rc; $(tail -n 2 "$LAST_OUT" | tr '\n' ' '))"
for f in .sdd-toolbox/manifest.json .sdd-toolbox/config.json \
         .opencode/agent/core/spec-kit-driver.md \
         .opencode/command/sdd.md \
         .opencode/context/spec-kit/navigation.md \
         .opencode/agent/subagents/code/coder-agent.md \
         .opencode/agent/subagents/core/contextscout.md \
         .opencode/context/core/standards/code-quality.md; do
    [[ -f "$T1/$f" ]] && ok "present $f" || bad "present $f"
done
jq -e '.profile == "minimal" and .pins.oac == "0.5.2"' "$T1/.sdd-toolbox/manifest.json" >/dev/null 2>&1 \
    && ok "manifest profile + OAC pin" || bad "manifest profile + OAC pin"
grep -q '^UV:' "$STUB_LOG" && bad "no global install (uv was invoked)" || ok "no global install (uv not invoked)"
scenario_end

# ===========================================================================
# Scenario 2 — idempotent re-run
scenario_begin "Scenario 2: re-run -> idempotent"
before="$(tree_hash "$T1")"
rc=0; run_bootstrap "$T1" --profile minimal --yes || rc=$?
after="$(tree_hash "$T1")"
[[ $rc -eq 0 ]] && ok "exit 0" || bad "exit 0 (got $rc)"
[[ "$before" == "$after" ]] && ok "tree hash unchanged" || bad "tree hash unchanged"
scenario_end

# ===========================================================================
# Scenario 3 — update preserves modified, refreshes others
scenario_begin "Scenario 3: --update preserves modified + restores deleted"
T3="$SCRATCH/s3"; mkdir -p "$T3"
run_bootstrap "$T3" --profile minimal --yes || true
printf '\nuser edit\n' >> "$T3/.opencode/agent/core/spec-kit-driver.md"
rm -f "$T3/.opencode/command/sdd.md"
rc=0; run_bootstrap "$T3" --profile minimal --yes --update || rc=$?
[[ $rc -eq 0 ]] && ok "exit 0" || bad "exit 0 (got $rc)"
grep -q 'user edit' "$T3/.opencode/agent/core/spec-kit-driver.md" \
    && ok "modified file preserved" || bad "modified file preserved"
grep -q 'preserve' "$LAST_OUT" && ok "preserve reported" || bad "preserve reported"
[[ -f "$T3/.opencode/command/sdd.md" ]] \
    && ok "deleted file restored (others refreshed)" || bad "deleted file restored"
scenario_end

# ===========================================================================
# Scenario 4 — --update --force backs up + overwrites
scenario_begin "Scenario 4: --update --force -> backup + overwrite + listed"
T4="$SCRATCH/s4"; mkdir -p "$T4"
run_bootstrap "$T4" --profile minimal --yes || true
printf '\nuser edit force\n' >> "$T4/.opencode/agent/core/spec-kit-driver.md"
rc=0; run_bootstrap "$T4" --profile minimal --yes --update --force || rc=$?
[[ $rc -eq 0 ]] && ok "exit 0" || bad "exit 0 (got $rc)"
grep -q 'user edit force' "$T4/.opencode/agent/core/spec-kit-driver.md" \
    && bad "modified file overwritten" || ok "modified file overwritten"
bcount="$(find "$T4/.sdd-toolbox/backup" -type f 2>/dev/null | wc -l | tr -d ' ')"
[[ "$bcount" -ge 1 ]] && ok "backup created ($bcount file)" || bad "backup created"
grep -q 'backup:' "$LAST_OUT" && ok "backup listed" || bad "backup listed"
scenario_end

# ===========================================================================
# Scenario 5 — --dry-run writes nothing
scenario_begin "Scenario 5: --dry-run -> zero writes"
T5="$SCRATCH/s5"; mkdir -p "$T5"
before="$(tree_hash "$T5")"
rc=0; run_bootstrap "$T5" --profile minimal --yes --dry-run || rc=$?
after="$(tree_hash "$T5")"
[[ $rc -eq 0 ]] && ok "exit 0" || bad "exit 0 (got $rc)"
[[ "$before" == "$after" ]] && ok "tree hash unchanged (zero writes)" || bad "tree hash unchanged"
[[ ! -e "$T5/.sdd-toolbox" ]] && ok "no .sdd-toolbox created" || bad "no .sdd-toolbox created"
[[ -z "$(cat "$STUB_LOG")" ]] && ok "no uv/specify invoked" || bad "no uv/specify invoked"
scenario_end

# ===========================================================================
# Scenario 6 — unknown profile
scenario_begin "Scenario 6: unknown --profile -> exit 2 + list"
T6="$SCRATCH/s6"; mkdir -p "$T6"
rc=0; run_bootstrap "$T6" --profile nope --yes || rc=$?
[[ $rc -eq 2 ]] && ok "exit 2" || bad "exit 2 (got $rc)"
grep -q 'unknown profile: nope' "$LAST_OUT" && ok "names unknown profile" || bad "names unknown profile"
grep -q 'minimal' "$LAST_OUT" && grep -q 'go-backend' "$LAST_OUT" \
    && ok "lists available profiles" || bad "lists available profiles"
scenario_end

# ===========================================================================
# Scenario 7 — --no-spec-kit
scenario_begin "Scenario 7: --no-spec-kit -> overlay only"
T7="$SCRATCH/s7"; mkdir -p "$T7"
rc=0; run_bootstrap "$T7" --profile minimal --yes --no-spec-kit || rc=$?
[[ $rc -eq 0 ]] && ok "exit 0" || bad "exit 0 (got $rc)"
[[ -f "$T7/.sdd-toolbox/manifest.json" ]] && ok "overlay manifest present" || bad "overlay manifest present"
[[ -f "$T7/.opencode/agent/core/spec-kit-driver.md" ]] && ok "overlay driver installed" || bad "overlay driver installed"
[[ ! -e "$T7/.specify" ]] && ok "no .specify/ created" || bad "no .specify/ created"
[[ -z "$(cat "$STUB_LOG")" ]] && ok "no specify invoked" || bad "no specify invoked"
scenario_end

# ===========================================================================
# Scenario 8 — restricted PATH -> prereq failure
scenario_begin "Scenario 8: restricted PATH -> exit 3 + hint"
T8="$SCRATCH/s8"; mkdir -p "$T8"
RBIN="$SCRATCH/restricted-bin"; mkdir -p "$RBIN"
for t in bash dirname jq awk paste cat tr head sort grep sed find ls mktemp sha256sum git uname chmod cp mkdir rm mv pwd; do
    if p="$(command -v "$t" 2>/dev/null)"; then ln -sf "$p" "$RBIN/$t"; fi
done
rc=0
PATH="$RBIN" STUB_LOG="$STUB_LOG" "$BOOTSTRAP" "$T8" --profile minimal --yes >"$LAST_OUT" 2>&1 || rc=$?
[[ $rc -eq 3 ]] && ok "exit 3" || bad "exit 3 (got $rc)"
grep -q 'missing required tool' "$LAST_OUT" && ok "names missing tool" || bad "names missing tool"
grep -q 'remedy' "$LAST_OUT" && ok "actionable remedy hint" || bad "actionable remedy hint"
[[ ! -e "$T8/.sdd-toolbox" ]] && ok "no writes on prereq failure" || bad "no writes on prereq failure"
scenario_end

# ===========================================================================
printf '\n=============================\n'
printf 'smoke-test: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
