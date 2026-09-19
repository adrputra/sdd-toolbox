#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/installer.sh — component planning, install, config + manifest assembly.
#
# Purpose
#   Map catalog references to target paths, plan/execute installs, and assemble
#   the config + ownership manifest (design §7.1, §7.2, §11). Path mapping:
#     repo   components/<rest> -> target .opencode/<rest>   (source under repo)
#     vendor .opencode/<rest>  -> target .opencode/<rest>   (source under
#                                vendor/oac/)
#
# Exported functions
#   plan_install <target> <ids_csv>
#       Print "STATE<TAB>target_rel<TAB>source_abs" per file. Exits 6 (via
#       fail_overlay) before writing anything on a conflict (unmanaged file at
#       a planned path) or an unresolvable reference.
#   install_components <target> <ids_csv>
#       Execute the plan: missing->copy, identical->skip, unmodified->overwrite,
#       modified->overwrite (warn); conflict/bad-ref->abort (exit 6). Returns
#       non-zero if any source is missing (no partial writes).
#   build_managed_files_json <target> <ids_csv>
#       Print the manifest `files` array; appends the generated config entry
#       when `.sdd-toolbox/config.json` exists.
#   merged_managed_files_json <target> <ids_csv>
#       As above, but also retain previous manifest entries whose paths are no
#       longer resolved (design §7.2: stale files are kept, never dropped).
#   write_config <target> <profile_name> [overrides_json]
#       Merge profile `.settings` + overrides into `.sdd-toolbox/config.json`;
#       a user-modified config (hash differs from manifest) is preserved.
#   write_manifest_file <target> <profile_name> <extensions_csv> <files_json>
#       Assemble and write the manifest per design §7.1.
#   fail_overlay <msg...>   Print to stderr and exit 6 (overlay stage).
#
# Dependencies (lazily sourced from this directory): lib/manifest.sh,
# lib/registry.sh. Sourced library: no `set -euo pipefail`, no source-time side
# effects beyond TOOLBOX_ROOT / _INSTALLER_LIB_DIR. Bash 3.2+, jq only.
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s: sourced library — source it, do not execute it.\n' "${0##*/}" >&2
    exit 2
fi
if [[ -z "${TOOLBOX_ROOT:-}" ]]; then
    TOOLBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
_INSTALLER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# fail_overlay <msg...> — report an overlay-stage failure and exit 6.
fail_overlay() {
    printf 'overlay: %s\n' "$*" >&2
    exit 6
}

# _installer_ensure_deps — lazily source sibling libraries when not already
# loaded (no source-time side effects in this file).
_installer_ensure_deps() {
    if ! type hash_file >/dev/null 2>&1 || ! type classify_file >/dev/null 2>&1; then
        # shellcheck source=./manifest.sh
        . "${_INSTALLER_LIB_DIR}/manifest.sh"
    fi
    if ! type catalog_resolve >/dev/null 2>&1 || ! type profile_json >/dev/null 2>&1; then
        # shellcheck source=./registry.sh
        . "${_INSTALLER_LIB_DIR}/registry.sh"
    fi
}

# _overlay_resolve_one <id> — echo "origin<TAB>rel<TAB>trel<TAB>src<TAB>kind".
_overlay_resolve_one() {
    local resolved origin rel trel src kind
    resolved="$(catalog_resolve "$1" 2>/dev/null)" || return 1
    origin="${resolved%%$'\t'*}"
    rel="${resolved#*$'\t'}"
    if [[ "$origin" == "repo" ]]; then
        trel=".opencode/${rel#components/}"
        src="${TOOLBOX_ROOT%/}/$rel"
        kind="component"
    else
        trel="$rel"
        src="${TOOLBOX_ROOT%/}/vendor/oac/$rel"
        kind="vendor"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$origin" "$rel" "$trel" "$src" "$kind"
}

# _installer_copy <src> <dest> — copy, creating parents; preserve +x.
_installer_copy() {
    mkdir -p "$(dirname "$2")" || return 1
    cp "$1" "$2" || return 1
    [[ -x "$1" ]] && chmod +x "$2"
    return 0
}

# _overlay_manifest_sha <target> <target_rel> — manifest hash for a path ("").
_overlay_manifest_sha() {
    local mf sha
    mf="$(manifest_path "$1")"
    [[ -f "$mf" ]] || return 0
    sha="$(jq -r --arg p "$2" '.files[]? | select(.path == $p) | .sha256' "$mf" | head -n 1)"
    [[ "$sha" == "null" ]] && sha=""
    printf '%s\n' "$sha"
}

# _overlay_list_state <plan> <state> — print target paths for one state.
_overlay_list_state() {
    printf '%s\n' "$1" | awk -F'\t' -v s="$2" '$1 == s { print $2 }'
}

# _overlay_abort_if <plan> <state> <header> <remedy> — list + exit 6 if present.
_overlay_abort_if() {
    local list
    list="$(_overlay_list_state "$1" "$2")"
    [[ -n "$list" ]] || return 0
    printf 'overlay: %s\n' "$3" >&2
    printf '%s\n' "$list" | while IFS= read -r x; do printf '  - %s\n' "$x" >&2; done
    fail_overlay "$4"
}

# _overlay_plan <target> <ids_csv> — emit plan lines; always returns 0.
# STATES: missing|conflict|identical|unmodified|modified|source-missing|bad-ref
_overlay_plan() {
    local target="$1" ids_csv="$2"
    _installer_ensure_deps
    local list id meta origin rel trel src kind desired exists sha msha
    list="$(printf '%s' "$ids_csv" | tr ',' '\n')"
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        if ! meta="$(_overlay_resolve_one "$id")"; then
            printf 'bad-ref\t%s\t-\n' "$id"
            continue
        fi
        IFS=$'\t' read -r origin rel trel src kind <<< "$meta"
        if [[ ! -f "$src" ]]; then
            printf 'source-missing\t%s\t%s\n' "$trel" "$src"
            continue
        fi
        desired="$(hash_file "$src")"
        exists=0
        sha=""
        if [[ -f "$target/$trel" ]]; then
            exists=1
            sha="$(hash_file "$target/$trel")"
        fi
        msha="$(_overlay_manifest_sha "$target" "$trel")"
        printf '%s\t%s\t%s\n' "$(classify_file "$exists" "$sha" "$msha" "$desired")" "$trel" "$src"
    done <<< "$list"
    return 0
}

# plan_install <target> <ids_csv> — print the plan; abort on conflicts/bad refs.
plan_install() {
    [[ -d "$1" ]] || fail_overlay "target directory does not exist: $1"
    local plan
    plan="$(_overlay_plan "$1" "$2")"
    printf '%s\n' "$plan"
    _overlay_abort_if "$plan" bad-ref \
        "unresolvable component reference(s):" "aborting: fix the component IDs above"
    _overlay_abort_if "$plan" conflict \
        "unmanaged file(s) already exist at planned path(s):" \
        "aborting before writing: move or remove the unmanaged files above"
    return 0
}

# install_components <target> <ids_csv> — execute the plan (no partial writes).
install_components() {
    [[ -d "$1" ]] || fail_overlay "target directory does not exist: $1"
    local plan missing state trel src
    plan="$(_overlay_plan "$1" "$2")"
    _overlay_abort_if "$plan" bad-ref \
        "unresolvable component reference(s):" "aborting: fix the component IDs above"
    _overlay_abort_if "$plan" conflict \
        "unmanaged file(s) already exist at planned path(s):" \
        "aborting before writing: move or remove the unmanaged files above"
    missing="$(_overlay_list_state "$plan" source-missing)"
    if [[ -n "$missing" ]]; then
        printf 'overlay: source file(s) missing from the toolbox:\n' >&2
        printf '%s\n' "$missing" | while IFS= read -r m; do printf '  - %s\n' "$m" >&2; done
        return 1
    fi
    while IFS=$'\t' read -r state trel src; do
        [[ -n "$state" ]] || continue
        case "$state" in
            missing|unmodified|modified)
                [[ "$state" == "modified" ]] && \
                    printf 'overlay: overwriting user-modified managed file: %s\n' "$trel" >&2
                _installer_copy "$src" "$1/$trel" || fail_overlay "cannot write $1/$trel" ;;
            *) : ;;
        esac
    done <<< "$plan"
    return 0
}

# build_managed_files_json <target> <ids_csv> — print the manifest files array.
build_managed_files_json() {
    _installer_ensure_deps
    local tmp first=1 id meta origin rel trel src kind sha cfg list
    tmp="$(mktemp)"
    printf '[' > "$tmp"
    list="$(printf '%s' "$2" | tr ',' '\n')"
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        meta="$(_overlay_resolve_one "$id")" || continue
        IFS=$'\t' read -r origin rel trel src kind <<< "$meta"
        [[ -f "$src" ]] || continue
        sha="$(hash_file "$src")"
        [[ "$first" -eq 1 ]] || printf ',' >> "$tmp"
        jq -cn --arg p "$trel" --arg s "$sha" --arg k "$kind" --arg c "$id" \
            '{path: $p, sha256: $s, source: $k, component: $c}' >> "$tmp"
        first=0
    done <<< "$list"
    cfg="$(config_path "$1")"
    if [[ -f "$cfg" ]]; then
        sha="$(hash_file "$cfg")"
        [[ "$first" -eq 1 ]] || printf ',' >> "$tmp"
        jq -cn --arg p ".sdd-toolbox/config.json" --arg s "$sha" \
            '{path: $p, sha256: $s, source: "generated", component: ""}' >> "$tmp"
    fi
    printf ']' >> "$tmp"
    cat "$tmp"
    rm -f "$tmp"
    return 0
}

# merged_managed_files_json <target> <ids_csv> — the current resolved files plus
# any previous manifest entries whose paths are not in the current set, retained
# as-is (path/sha256/source/component). Implements design §7.2: files recorded
# in the manifest but no longer shipped are reported `stale` and kept, never
# dropped (so re-adding a component at a previously-managed path resolves
# cleanly instead of looking like an unmanaged conflict).
merged_managed_files_json() {
    _installer_ensure_deps
    local target="$1" ids_csv="$2" current mf
    current="$(build_managed_files_json "$target" "$ids_csv")"
    mf="$(manifest_path "$target")"
    if [[ ! -f "$mf" ]]; then
        printf '%s\n' "$current"
        return 0
    fi
    jq -n --argjson cur "$current" --slurpfile prev "$mf" '
        ($cur | map(.path)) as $paths
        | $cur + [ ($prev[0].files // [])[]
                   | select(.path as $p | ($paths | index($p) | not)) ]
    '
}

# write_config <target> <profile_name> [overrides_json] — write the config.
write_config() {
    _installer_ensure_deps
    local target="$1" profile="$2" overrides="${3:-}" settings merged cfg path msha
    profile_exists "$profile" || fail_overlay "unknown profile: $profile"
    settings="$(profile_json "$profile" | jq '.settings // {}')"
    if [[ -n "$overrides" ]]; then
        merged="$(jq -n --argjson base "$settings" --argjson ov "$overrides" '$base * $ov')" \
            || fail_overlay "invalid overrides JSON"
    else
        merged="$settings"
    fi
    cfg="$(jq -n --argjson s "$merged" '{schema: 1} + $s')"
    path="$(config_path "$target")"
    if [[ -f "$path" ]]; then
        msha="$(_overlay_manifest_sha "$target" ".sdd-toolbox/config.json")"
        if [[ -n "$msha" ]] && [[ "$(hash_file "$path")" != "$msha" ]]; then
            printf 'overlay: preserving user-modified config: %s\n' "$path" >&2
            return 0
        fi
    fi
    mkdir -p "$(dirname "$path")" || fail_overlay "cannot create $(dirname "$path")"
    printf '%s\n' "$cfg" > "$path" || fail_overlay "cannot write config: $path"
    return 0
}

# write_manifest_file <target> <profile> <ext_csv> <files_json> — write manifest.
write_manifest_file() {
    _installer_ensure_deps
    local target="$1" profile="$2" ext_csv="${3:-}" files_json="$4"
    local tv commit ext_json tmp
    [[ -n "$files_json" ]] || files_json="[]"
    if [[ -z "${OAC_VERSION:-}" && -z "${SPEC_KIT_VERSION:-}" && -f "${TOOLBOX_ROOT%/}/versions.env" ]]; then
        # shellcheck source=/dev/null
        . "${TOOLBOX_ROOT%/}/versions.env"
    fi
    tv="$(jq -r '.version // "0.0.0"' "${TOOLBOX_ROOT%/}/registry.json" 2>/dev/null)"
    [[ -n "$tv" && "$tv" != "null" ]] || tv="0.0.0"
    commit="$(git -C "${TOOLBOX_ROOT%/}" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
    [[ -n "$commit" ]] || commit="unknown"
    ext_json="$(printf '%s\n' "$ext_csv" | tr ',' '\n' | awk 'NF' | jq -R . | jq -s '.')"
    tmp="$(mktemp)"
    jq -n --arg tv "$tv" --arg commit "$commit" \
        --arg oac "${OAC_VERSION:-}" --arg sk "${SPEC_KIT_VERSION:-}" \
        --arg profile "$profile" --argjson ext "$ext_json" --argjson files "$files_json" \
        '{schema: 1, toolbox: {version: $tv, commit: $commit},
          pins: {oac: $oac, spec_kit: $sk}, profile: $profile,
          extensions: $ext, files: $files}' > "$tmp" \
        || { rm -f "$tmp"; fail_overlay "cannot assemble manifest JSON"; }
    write_manifest "$target" "$tmp" || { rm -f "$tmp"; fail_overlay "cannot write manifest"; }
    rm -f "$tmp"
    return 0
}
