#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/update.sh — safe update / reinstall of manifest-managed files (design §7.2).
#
# Purpose
#   Classify every file recorded in `.sdd-toolbox/manifest.json` against its
#   current toolbox source and the target copy, then refresh unmodified files,
#   restore missing ones, preserve user modifications (or back them up and
#   overwrite under force), and refresh manifest hashes. Stale entries (no
#   longer shipped) are reported and left in place — never deleted.
#
# Exported functions
#   update_components <target> [force:0|1] [dry_run:0|1]
#       Perform an update (force=0 preserves modified files) or a reinstall
#       (force=1 backs up modified files under
#       `$target/.sdd-toolbox/backup/<UTC-ts>/<relpath>` then overwrites).
#       dry_run=1 prints the plan and writes nothing.
#       Exits 6 on errors via `_update_fail`.
#
# Actions: skip | overwrite | restore | preserve | backup+overwrite | stale |
#          generated
#
# Dependencies (lazily sourced from this library's own directory):
#   lib/manifest.sh, lib/registry.sh.
#
# Notes
#   Sourced library: no `set -euo pipefail`, no side effects at source time
#   beyond computing TOOLBOX_ROOT / _UPDATE_LIB_DIR. Bash 3.2+ compatible.
#   jq only, no eval.
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s: sourced library — source it, do not execute it.\n' "${0##*/}" >&2
    exit 2
fi

if [[ -z "${TOOLBOX_ROOT:-}" ]]; then
    TOOLBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
_UPDATE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# _update_fail <msg...> — report an update-stage failure and exit 6.
_update_fail() {
    printf 'update: %s\n' "$*" >&2
    exit 6
}

# _update_ensure_deps — lazily source sibling libraries when needed.
_update_ensure_deps() {
    if ! type hash_file >/dev/null 2>&1 || ! type classify_file >/dev/null 2>&1; then
        # shellcheck source=./manifest.sh
        . "${_UPDATE_LIB_DIR}/manifest.sh"
    fi
    if ! type catalog_resolve >/dev/null 2>&1; then
        # shellcheck source=./registry.sh
        . "${_UPDATE_LIB_DIR}/registry.sh"
    fi
}

# _update_source_abs <origin> <rel> — toolbox source path for a resolution.
_update_source_abs() {
    if [[ "$1" == "repo" ]]; then
        printf '%s/%s\n' "${TOOLBOX_ROOT%/}" "$2"
    else
        printf '%s/vendor/oac/%s\n' "${TOOLBOX_ROOT%/}" "$2"
    fi
}

# _update_backup <target> <timestamp> <rel> — back up a target file; echo path.
_update_backup() {
    local target="$1"
    local ts="$2"
    local rel="$3"
    local dest="$target/.sdd-toolbox/backup/$ts/$rel"
    mkdir -p "$(dirname "$dest")" || _update_fail "cannot create backup dir for $rel"
    cp "$target/$rel" "$dest" || _update_fail "cannot back up $rel"
    printf '%s\n' "$dest"
}

# update_components <target> [force:0|1] [dry_run:0|1]
update_components() {
    local target="$1"
    local force="${2:-0}"
    local dry_run="${3:-0}"
    _update_ensure_deps

    local mf
    mf="$(manifest_path "$target")"
    [[ -f "$mf" ]] || _update_fail "no manifest found at $mf (nothing to update)"

    local entries
    entries="$(jq -r '.files[]? | [.path, (.sha256 // ""), (.source // ""), (.component // "")] | @tsv' "$mf")"

    local ts
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    local new_tmp
    new_tmp="$(mktemp)"
    printf '[' > "$new_tmp"

    local first=1 line path oldsha source component
    local n_skip=0 n_over=0 n_restore=0 n_preserve=0 n_backup=0 n_stale=0 n_gen=0
    while IFS=$'\t' read -r path oldsha source component; do
        [[ -n "$path" ]] || continue
        local action="skip" newsha="$oldsha" src="" origin="" rel=""

        if [[ "$source" == "generated" ]]; then
            action="generated"
            n_gen=$((n_gen + 1))
        else
            local resolved=""
            if [[ -n "$component" ]] && resolved="$(catalog_resolve "$component" 2>/dev/null)"; then
                origin="${resolved%%$'\t'*}"
                rel="${resolved#*$'\t'}"
                src="$(_update_source_abs "$origin" "$rel")"
            fi
            if [[ -z "$src" || ! -f "$src" ]]; then
                action="stale"
                n_stale=$((n_stale + 1))
            else
                local desired actual_exists=0 actual_sha=""
                desired="$(hash_file "$src")"
                if [[ -f "$target/$path" ]]; then
                    actual_exists=1
                    actual_sha="$(hash_file "$target/$path")"
                fi
                local state
                state="$(classify_file "$actual_exists" "$actual_sha" "$oldsha" "$desired")"
                case "$state" in
                    identical)
                        action="skip"; n_skip=$((n_skip + 1)); newsha="$desired" ;;
                    unmodified)
                        action="overwrite"; n_over=$((n_over + 1)); newsha="$desired" ;;
                    missing)
                        action="restore"; n_restore=$((n_restore + 1)); newsha="$desired" ;;
                    modified)
                        if [[ "$force" -eq 1 ]]; then
                            action="backup+overwrite"; n_backup=$((n_backup + 1)); newsha="$desired"
                        else
                            action="preserve"; n_preserve=$((n_preserve + 1)); newsha="$oldsha"
                        fi ;;
                    *)
                        action="overwrite"; n_over=$((n_over + 1)); newsha="$desired" ;;
                esac
            fi
        fi

        printf '%s\t%s\n' "$action" "$path"
        if [[ "$dry_run" -eq 0 ]]; then
            case "$action" in
                overwrite|restore)
                    mkdir -p "$(dirname "$target/$path")"
                    cp "$src" "$target/$path" || _update_fail "cannot write $target/$path" ;;
                backup+overwrite)
                    local bpath
                    bpath="$(_update_backup "$target" "$ts" "$path")"
                    printf '  backup: %s\n' "$bpath"
                    cp "$src" "$target/$path" || _update_fail "cannot write $target/$path" ;;
                preserve)
                    printf 'update: preserved user-modified file: %s\n' "$path" >&2 ;;
                stale)
                    printf 'update: stale (no longer shipped), left in place: %s\n' "$path" >&2 ;;
                *) : ;;
            esac
        fi

        [[ "$first" -eq 1 ]] || printf ',' >> "$new_tmp"
        jq -cn --arg p "$path" --arg s "$newsha" --arg k "$source" --arg c "$component" \
            '{path: $p, sha256: $s, source: $k, component: $c}' >> "$new_tmp"
        first=0
    done <<< "$entries"
    printf ']' >> "$new_tmp"

    if [[ "$dry_run" -eq 0 ]]; then
        local newman
        newman="$(mktemp)"
        jq --argjson files "$(cat "$new_tmp")" '.files = $files' "$mf" > "$newman" \
            || { rm -f "$newman" "$new_tmp"; _update_fail "cannot refresh manifest JSON"; }
        write_manifest "$target" "$newman" || { rm -f "$newman" "$new_tmp"; _update_fail "cannot write refreshed manifest"; }
        rm -f "$newman"
    fi
    rm -f "$new_tmp"

    printf 'update: skip=%d overwrite=%d restore=%d preserve=%d backup=%d stale=%d generated=%d\n' \
        "$n_skip" "$n_over" "$n_restore" "$n_preserve" "$n_backup" "$n_stale" "$n_gen"
    return 0
}
