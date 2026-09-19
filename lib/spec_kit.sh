#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/spec_kit.sh — GitHub Spec Kit CLI integration (design §8).
#
# Purpose
#   Resolve and record the pinned Spec Kit release tag, ensure the `specify`
#   CLI is installed at that pin via `uv`, enforce the version-mismatch policy,
#   and wrap `specify init` / `specify extension add`.
#
# Exported functions
#   pick_latest_tag                  Read tag lines on stdin; print the highest
#                                    stable vX.Y.Z tag (ignores rc/alpha/beta).
#   resolve_latest_stable_tag        Query GitHub tags and print the latest
#                                    stable tag (network).
#   spec_kit_ensure                  Ensure the pinned `specify` CLI is present.
#   spec_kit_init <target> <force>   Run `specify init` in <target>.
#   spec_kit_add_extension <target> <name>
#                                    Run `specify extension add <name>`.
#   fail_spec_kit <message...>       Print cause and exit 5 (spec-kit stage).
#
# Exported variables
#   TOOLBOX_ROOT       Computed from this file's location unless overridden.
#   SPEC_KIT_VERSION   Pinned tag; read from the environment/versions.env.
#   SDD_SPEC_KIT_FORCE When 1, a major-version mismatch only warns.
#
# Notes
#   Sourced library: no `set -euo pipefail`, no side effects at source time
#   beyond computing TOOLBOX_ROOT. Bash 3.2+ compatible. No eval.
# =============================================================================

# Direct-execution guard.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s: sourced library — source it, do not execute it.\n' "${0##*/}" >&2
    exit 2
fi

if [[ -z "${TOOLBOX_ROOT:-}" ]]; then
    TOOLBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

SPEC_KIT_GIT_URL="https://github.com/github/spec-kit.git"

# fail_spec_kit <message...> — report a Spec Kit stage failure and exit 5.
fail_spec_kit() {
    printf 'spec-kit: %s\n' "$*" >&2
    exit 5
}

# pick_latest_tag — read candidate tag lines from stdin and print the highest
# stable `vX.Y.Z` tag. Pre-release tags (rc/alpha/beta) and non-tag lines are
# ignored. Portable: no `sort -V`.
pick_latest_tag() {
    local line tag maj min pat
    local best="" best_maj=-1 best_min=-1 best_pat=-1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        # Accept a bare tag or a refs/tags/... line.
        tag="${line##*refs/tags/}"
        tag="${tag## }"
        tag="${tag%% }"
        [[ "$tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || continue
        maj=$((10#${BASH_REMATCH[1]}))
        min=$((10#${BASH_REMATCH[2]}))
        pat=$((10#${BASH_REMATCH[3]}))
        if [[ "$maj" -gt "$best_maj" ]] || \
           { [[ "$maj" -eq "$best_maj" ]] && [[ "$min" -gt "$best_min" ]]; } || \
           { [[ "$maj" -eq "$best_maj" ]] && [[ "$min" -eq "$best_min" ]] && [[ "$pat" -gt "$best_pat" ]]; }; then
            best="v${maj}.${min}.${pat}"
            best_maj="$maj"
            best_min="$min"
            best_pat="$pat"
        fi
    done
    if [[ -n "$best" ]]; then
        printf '%s\n' "$best"
    fi
    return 0
}

# resolve_latest_stable_tag — query the Spec Kit repo tags and print the latest
# stable tag. Returns non-zero when git/network fails or no stable tag exists.
resolve_latest_stable_tag() {
    local raw
    if ! raw="$(git ls-remote --tags --refs "$SPEC_KIT_GIT_URL" 'v*' 2>/dev/null)"; then
        printf 'spec-kit: git ls-remote failed for %s\n' "$SPEC_KIT_GIT_URL" >&2
        return 1
    fi
    local latest
    latest="$(printf '%s\n' "$raw" | awk '{ print $2 }' | pick_latest_tag)"
    if [[ -z "$latest" ]]; then
        printf 'spec-kit: no stable vX.Y.Z tag found for %s\n' "$SPEC_KIT_GIT_URL" >&2
        return 1
    fi
    printf '%s\n' "$latest"
}

# _spec_kit_record_version <version> — rewrite SPEC_KIT_VERSION in versions.env,
# preserving all comments and other lines (temp file + mv).
_spec_kit_record_version() {
    local version="$1"
    local file="${TOOLBOX_ROOT%/}/versions.env"
    local tmp line found=0
    if [[ ! -f "$file" ]]; then
        printf 'spec-kit: versions.env not found: %s\n' "$file" >&2
        return 1
    fi
    tmp="${file}.tmp.$$"
    : > "$tmp" || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*SPEC_KIT_VERSION= ]]; then
            printf 'SPEC_KIT_VERSION="%s"\n' "$version" >> "$tmp"
            found=1
        else
            printf '%s\n' "$line" >> "$tmp"
        fi
    done < "$file"
    if [[ "$found" -eq 0 ]]; then
        printf 'SPEC_KIT_VERSION="%s"\n' "$version" >> "$tmp"
    fi
    mv "$tmp" "$file" || {
        printf 'spec-kit: cannot update %s\n' "$file" >&2
        return 1
    }
    return 0
}

# _spec_kit_parse_version <string> — extract the first X.Y.Z from a version
# string (leading v optional). Prints nothing when no version is present.
_spec_kit_parse_version() {
    local text="$1"
    if [[ "$text" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        printf '%s.%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
        return 0
    fi
    return 1
}

# _spec_kit_installed_version — print the installed `specify` version, or fail.
_spec_kit_installed_version() {
    command -v specify >/dev/null 2>&1 || return 1
    local out
    out="$(specify version 2>/dev/null)" || return 1
    _spec_kit_parse_version "$out"
}

# _spec_kit_is_interactive — return 0 when it is safe to prompt the user.
_spec_kit_is_interactive() {
    [[ "${UI_ASSUME_YES:-0}" -ne 1 ]] || return 1
    [[ -t 0 && -t 1 ]] || return 1
    return 0
}

# _spec_kit_install <version> — install the pinned specify-cli via uv.
_spec_kit_install() {
    local version="$1"
    local from="git+${SPEC_KIT_GIT_URL}@${version}"
    printf 'spec-kit: installing specify-cli from %s\n' "$from" >&2
    uv tool install specify-cli --from "$from" || fail_spec_kit "uv tool install failed for ${version}"
}

# spec_kit_ensure — ensure the pinned specify CLI is installed and matches.
# Resolves + records the tag when SPEC_KIT_VERSION is empty. On a major-version
# mismatch: interactive offers reinstall; non-interactive aborts unless
# SDD_SPEC_KIT_FORCE=1. Minor/patch mismatches only warn.
spec_kit_ensure() {
    local version="${SPEC_KIT_VERSION:-}"
    if [[ -z "$version" ]]; then
        version="$(resolve_latest_stable_tag)" || fail_spec_kit "could not resolve latest stable Spec Kit tag"
        _spec_kit_record_version "$version" || fail_spec_kit "could not record SPEC_KIT_VERSION in versions.env"
        SPEC_KIT_VERSION="$version"
    fi

    local pinned="${version#v}"
    local installed
    if ! installed="$(_spec_kit_installed_version)"; then
        _spec_kit_install "$version"
        return 0
    fi

    if [[ "$installed" == "$pinned" ]]; then
        printf 'spec-kit: specify %s already installed\n' "$installed" >&2
        return 0
    fi

    local imaj imin pmaj pmin
    imaj="${installed%%.*}"
    imin="${installed#*.}"; imin="${imin%%.*}"
    pmaj="${pinned%%.*}"
    pmin="${pinned#*.}"; pmin="${pmin%%.*}"

    if [[ "$imaj" != "$pmaj" ]]; then
        if _spec_kit_is_interactive; then
            if type ui_confirm >/dev/null 2>&1 && ui_confirm "Installed specify ${installed} differs from pinned ${pinned} (major). Reinstall pinned?"; then
                _spec_kit_install "$version"
                return 0
            fi
            printf 'spec-kit: continuing with specify %s (pinned %s)\n' "$installed" "$pinned" >&2
            return 0
        fi
        if [[ "${SDD_SPEC_KIT_FORCE:-0}" -eq 1 ]]; then
            printf 'spec-kit: WARNING major version mismatch (installed %s, pinned %s); continuing (SDD_SPEC_KIT_FORCE=1)\n' \
                "$installed" "$pinned" >&2
            return 0
        fi
        fail_spec_kit "major version mismatch (installed ${installed}, pinned ${pinned}); set SDD_SPEC_KIT_FORCE=1 to override"
    fi

    # Same major, different minor/patch: warn and continue.
    printf 'spec-kit: WARNING installed specify %s differs from pinned %s (same major); continuing\n' \
        "$installed" "$pinned" >&2
    return 0
}

# spec_kit_init <target> <force:0|1> — initialise Spec Kit in <target>.
# Empty/new target: no --force. Existing target: pass --force (merge).
spec_kit_init() {
    local target="$1"
    local force="${2:-0}"
    command -v specify >/dev/null 2>&1 || fail_spec_kit "specify CLI not found on PATH"
    [[ -d "$target" ]] || fail_spec_kit "target directory does not exist: $target"

    local -a args=()
    args=(init --here --integration opencode --script sh --non-interactive)
    if [[ "$force" -eq 1 ]]; then
        args+=(--force)
    fi
    if ! ( cd "$target" && specify "${args[@]}" ); then
        fail_spec_kit "specify init failed in ${target}"
    fi
    return 0
}

# spec_kit_add_extension <target> <name> — install a Spec Kit extension.
spec_kit_add_extension() {
    local target="$1"
    local name="$2"
    command -v specify >/dev/null 2>&1 || fail_spec_kit "specify CLI not found on PATH"
    [[ -d "$target" ]] || fail_spec_kit "target directory does not exist: $target"
    if ! ( cd "$target" && specify extension add "$name" ); then
        fail_spec_kit "specify extension add ${name} failed in ${target}"
    fi
    return 0
}
