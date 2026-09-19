#!/usr/bin/env bash
# =============================================================================
# scripts/validate.sh — offline repository self-check (design §14.1, task T17).
#
# Verifies, with per-check output:
#   * bash -n on every shell file in the repo (bootstrap.sh, lib/*.sh, scripts/*.sh)
#   * shellcheck on those files when installed (skipped, visibly, when absent)
#   * jq schema of registry.json, every profiles/*.json, vendor/oac/bundle.json
#   * versions.env is sourceable and both pins are non-empty
#   * reference integrity:
#       - every profile component ID resolves via catalog_resolve
#       - every subagent referenced by the driver exists in the vendored subset
#       - every registry path exists on disk
#       - every bundle.json sha256 matches its on-disk file
#
# Offline; makes no network calls and writes nothing outside temporary files.
#
# Environment:
#   TOOLBOX_ROOT   Repo root (default: parent of this script's directory).
#                  Overridable so the checks can be run against a copy.
#
# Exit codes: 0 all checks passed; 7 one or more checks failed.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CODE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$CODE_ROOT}"

# Libraries load from this script's own repository; data comes from TOOLBOX_ROOT
# (which may point at a copy for negative testing).
# shellcheck source=../lib/manifest.sh
. "${CODE_ROOT}/lib/manifest.sh"
# shellcheck source=../lib/registry.sh
. "${CODE_ROOT}/lib/registry.sh"

TOTAL=0
FAILED=0

pass() { TOTAL=$((TOTAL + 1)); printf '  [PASS] %s\n' "$1"; }
fail() { TOTAL=$((TOTAL + 1)); FAILED=$((FAILED + 1)); printf '  [FAIL] %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

REGISTRY="$TOOLBOX_ROOT/registry.json"
BUNDLE="$TOOLBOX_ROOT/vendor/oac/bundle.json"
DRIVER="$TOOLBOX_ROOT/components/agent/core/spec-kit-driver.md"

# list_shell_files — every .sh file in the repo (excluding .git).
list_shell_files() {
    find "$TOOLBOX_ROOT" -type f -name '*.sh' -not -path '*/.git/*' | sort
}

# extract_driver_subagents <file> — print backticked names in the driver's
# "Subagents You Can Delegate To" table (first column).
extract_driver_subagents() {
    awk '
        /^## Subagents You Can Delegate To/ { inb=1; next }
        /^## / { inb=0 }
        inb {
            line=$0
            while (match(line, /`[A-Za-z]+`/)) {
                print substr(line, RSTART+1, RLENGTH-2)
                line=substr(line, RSTART+RLENGTH)
            }
        }
    ' "$1"
}

# driver_subagent_id <Name> — map a driver display name to its vendored id.
driver_subagent_id() {
    case "$1" in
        ContextScout)  printf 'contextscout\n' ;;
        ExternalScout) printf 'externalscout\n' ;;
        TaskManager)   printf 'task-manager\n' ;;
        CoderAgent)    printf 'coder-agent\n' ;;
        BatchExecutor) printf 'batch-executor\n' ;;
        TestEngineer)  printf 'test-engineer\n' ;;
        DocWriter)     printf 'documentation\n' ;;
        *)             printf '\n' ;;
    esac
}

# --- 1. shell syntax ----------------------------------------------------------
section "Shell syntax (bash -n)"
while IFS= read -r f; do
    rel="${f#"$TOOLBOX_ROOT"/}"
    if err="$(bash -n "$f" 2>&1)"; then
        pass "bash -n $rel"
    else
        fail "bash -n $rel: $err"
    fi
done < <(list_shell_files)

# --- 2. shellcheck ------------------------------------------------------------
section "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    while IFS= read -r f; do
        rel="${f#"$TOOLBOX_ROOT"/}"
        if shellcheck -S warning -e SC1091 "$f" >/dev/null 2>&1; then
            pass "shellcheck $rel"
        else
            fail "shellcheck $rel"
        fi
    done < <(list_shell_files)
else
    printf '  [SKIP] shellcheck not installed — install it to enable this check\n'
fi

# --- 3. JSON schemas ----------------------------------------------------------
section "JSON schemas"
if jq -e '.version and .schema_version and (.components | type == "object")' "$REGISTRY" >/dev/null 2>&1; then
    pass "registry.json: top-level schema"
else
    fail "registry.json: top-level schema"
fi
if jq -e '(.components | has("agents") and has("subagents") and has("commands") and has("tools") and has("contexts"))' "$REGISTRY" >/dev/null 2>&1; then
    pass "registry.json: all component groups present"
else
    fail "registry.json: all component groups present"
fi
if jq -e '[.components[] | .[] | has("id") and has("name") and has("type") and has("path") and has("description") and has("category") and has("tags") and has("version")] | all' "$REGISTRY" >/dev/null 2>&1; then
    pass "registry.json: every entry has the required fields"
else
    fail "registry.json: every entry has the required fields"
fi
if jq -e '[.components[] | .[].id] | (length == (unique | length))' "$REGISTRY" >/dev/null 2>&1; then
    pass "registry.json: component IDs are unique"
else
    fail "registry.json: component IDs are unique"
fi

while IFS= read -r pf; do
    base="${pf##*/}"
    name="${base%.json}"
    if jq -e '.name and .description and (.components | type == "array") and (.settings | type == "object")' "$pf" >/dev/null 2>&1; then
        pass "profiles/$name.json: schema"
    else
        fail "profiles/$name.json: schema"
    fi
    pname="$(jq -r '.name // ""' "$pf")"
    if [[ "$pname" == "$name" ]]; then
        pass "profiles/$name.json: name matches filename"
    else
        fail "profiles/$name.json: name matches filename (got '$pname')"
    fi
done < <(find "$TOOLBOX_ROOT/profiles" -type f -name '*.json' | sort)

if jq -e '.version and .provenance and .generated_by and (.files | type == "array") and ([.files[] | has("path") and has("id") and has("type") and has("sha256")] | all)' "$BUNDLE" >/dev/null 2>&1; then
    pass "vendor/oac/bundle.json: schema"
else
    fail "vendor/oac/bundle.json: schema"
fi

if ( set -u; . "$TOOLBOX_ROOT/versions.env"; [[ -n "${OAC_VERSION:-}" && -n "${SPEC_KIT_VERSION:-}" ]] ); then
    pass "versions.env: sourceable with both pins non-empty"
else
    fail "versions.env: sourceable with both pins non-empty"
fi

# --- 4. reference integrity ---------------------------------------------------
section "Reference integrity: registry paths"
while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if [[ -f "$TOOLBOX_ROOT/$p" ]]; then
        pass "registry path exists: $p"
    else
        fail "registry path missing: $p"
    fi
done < <(jq -r '.components[] | .[] | .path' "$REGISTRY")

section "Reference integrity: bundle hashes"
while IFS=$'\t' read -r p sha; do
    [[ -n "$p" ]] || continue
    f="$TOOLBOX_ROOT/vendor/oac/$p"
    if [[ ! -f "$f" ]]; then
        fail "bundle file missing: $p"
        continue
    fi
    actual="$(hash_file "$f")"
    if [[ "$actual" == "$sha" ]]; then
        pass "bundle hash matches: $p"
    else
        fail "bundle hash mismatch: $p"
    fi
done < <(jq -r '.files[] | [.path, .sha256] | @tsv' "$BUNDLE")

section "Reference integrity: profile component IDs"
while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        if catalog_resolve "$id" >/dev/null 2>&1; then
            pass "profile $name: $id resolves"
        else
            fail "profile $name: unresolved component $id"
        fi
    done < <(profile_components "$name")
done < <(registry_available_profiles)

section "Reference integrity: driver subagents in vendored subset"
names="$(extract_driver_subagents "$DRIVER")"
if [[ -z "$names" ]]; then
    fail "driver: subagent table not found in ${DRIVER#"$TOOLBOX_ROOT"/}"
else
    while IFS= read -r nm; do
        [[ -n "$nm" ]] || continue
        id="$(driver_subagent_id "$nm")"
        if [[ -z "$id" ]]; then
            fail "driver references unmapped subagent: $nm"
            continue
        fi
        if jq -e --arg i "$id" '[.files[] | select(.id == $i and .type == "subagent")] | length > 0' "$BUNDLE" >/dev/null 2>&1; then
            pass "driver subagent $nm -> $id is vendored"
        else
            fail "driver subagent $nm -> $id is missing from the vendored subset"
        fi
    done <<< "$names"
fi
for id in contextscout externalscout task-manager coder-agent batch-executor test-engineer documentation; do
    if jq -e --arg i "$id" '[.files[] | select(.id == $i and .type == "subagent")] | length > 0' "$BUNDLE" >/dev/null 2>&1; then
        pass "expected subagent vendored: $id"
    else
        fail "expected subagent missing: $id"
    fi
done

# --- result -------------------------------------------------------------------
printf '\n== Summary ==\n'
if [[ "$FAILED" -eq 0 ]]; then
    printf 'validate: all %d checks passed\n' "$TOTAL"
    exit 0
fi
printf 'validate: %d of %d checks FAILED\n' "$FAILED" "$TOTAL"
exit 7
