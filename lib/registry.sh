#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/registry.sh — catalog, vendor bundle and profile access (design §2, §3).
#
# Purpose
#   Load the toolbox catalog from three JSON sources and resolve component
#   references to source paths:
#     - registry.json                custom components (OAC schema v2.0.0)
#     - vendor/oac/bundle.json       vendored OAC components (T09 output)
#     - profiles/<name>.json         declarative per-project-type bundles
#
#   Custom component paths are repo-relative to TOOLBOX_ROOT (e.g.
#   `components/agent/core/spec-kit-driver.md`). Vendored paths are relative to
#   vendor/oac/ and include the `.opencode/` prefix (e.g.
#   `.opencode/agent/core/openagent.md`).
#
# Exported functions
#   catalog_resolve <type:id>        Print "<repo|vendor>\t<path>".
#   profile_json <name>              Print the profile JSON.
#   profile_exists <name>            Return 0 when the profile file exists.
#   profile_components <name>        Print component IDs, one per line.
#   registry_available_profiles      Print available profile names, one per line.
#
# Exported variables
#   TOOLBOX_ROOT   Toolbox repository root. Computed from this script's location
#                  unless already set in the environment (tests override it).
#
# Notes
#   Sourced library: no `set -euo pipefail`, no side effects at source time
#   beyond computing TOOLBOX_ROOT (a pure path computation). jq only, no eval.
# =============================================================================

# Direct-execution guard.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s: sourced library — source it, do not execute it.\n' "${0##*/}" >&2
    exit 2
fi

# Compute the toolbox root from this file's location unless overridden.
if [[ -z "${TOOLBOX_ROOT:-}" ]]; then
    TOOLBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# _registry_registry_file — path to registry.json.
_registry_registry_file() {
    printf '%s/registry.json\n' "${TOOLBOX_ROOT%/}"
}

# _registry_bundle_file — path to the vendored OAC bundle.json.
_registry_bundle_file() {
    printf '%s/vendor/oac/bundle.json\n' "${TOOLBOX_ROOT%/}"
}

# _registry_profile_file <name> — path to a profile JSON.
_registry_profile_file() {
    printf '%s/profiles/%s.json\n' "${TOOLBOX_ROOT%/}" "$1"
}

# _registry_type_key <type> — map a singular type to its registry key.
_registry_type_key() {
    case "$1" in
        agent)    printf 'agents\n' ;;
        subagent) printf 'subagents\n' ;;
        command)  printf 'commands\n' ;;
        tool)     printf 'tools\n' ;;
        context)  printf 'contexts\n' ;;
        *)        printf '\n' ;;
    esac
}

# catalog_resolve <type:id> — resolve a component reference to its source path.
# Prints "<repo|vendor>\t<path>". Returns non-zero with a clear error when the
# reference is malformed or unknown.
catalog_resolve() {
    local ref="$1"
    local type id key reg bundle rel

    if [[ "$ref" != *:* || "${ref%%:*}" == "" || "${ref#*:}" == "" ]]; then
        printf 'registry: invalid component reference (expected type:id): %s\n' "$ref" >&2
        return 1
    fi
    type="${ref%%:*}"
    id="${ref#*:}"
    key="$(_registry_type_key "$type")"
    if [[ -z "$key" ]]; then
        printf 'registry: unknown component type: %s (in %s)\n' "$type" "$ref" >&2
        return 1
    fi

    # 1. Custom components (repo-relative paths).
    reg="$(_registry_registry_file)"
    if [[ -f "$reg" ]]; then
        rel="$(jq -r --arg k "$key" --arg i "$id" \
            '(.components[$k] // [])[] | select(.id == $i) | .path' \
            "$reg" 2>/dev/null | head -n 1)"
        if [[ -n "$rel" && "$rel" != "null" ]]; then
            printf 'repo\t%s\n' "$rel"
            return 0
        fi
    fi

    # 2. Vendored OAC components (paths relative to vendor/oac/).
    bundle="$(_registry_bundle_file)"
    if [[ -f "$bundle" ]]; then
        rel="$(jq -r --arg i "$id" --arg t "$type" \
            '(.files // [])[] | select(.id == $i and .type == $t) | .path' \
            "$bundle" 2>/dev/null | head -n 1)"
        if [[ -n "$rel" && "$rel" != "null" ]]; then
            printf 'vendor\t%s\n' "$rel"
            return 0
        fi
    fi

    printf 'registry: unknown component: %s\n' "$ref" >&2
    return 1
}

# profile_exists <name> — return 0 when profiles/<name>.json exists.
profile_exists() {
    [[ -f "$(_registry_profile_file "$1")" ]]
}

# profile_json <name> — print the profile JSON; non-zero with a clear error
# (including the available profiles) when it does not exist.
profile_json() {
    local name="$1"
    local file
    file="$(_registry_profile_file "$name")"
    if [[ ! -f "$file" ]]; then
        printf 'registry: unknown profile: %s\n' "$name" >&2
        local available
        available="$(registry_available_profiles | tr '\n' ' ')"
        printf 'registry: available profiles: %s\n' "${available% }" >&2
        return 1
    fi
    jq -e . "$file"
}

# profile_components <name> — print the profile's component IDs, one per line.
# Accepts both string entries and objects with an `id` field.
profile_components() {
    local name="$1"
    local file
    file="$(_registry_profile_file "$name")"
    if [[ ! -f "$file" ]]; then
        printf 'registry: unknown profile: %s\n' "$name" >&2
        return 1
    fi
    jq -r '(.components // [])[] | if type == "string" then . else .id end' "$file"
}

# registry_available_profiles — print available profile names, one per line.
registry_available_profiles() {
    local dir="${TOOLBOX_ROOT%/}/profiles"
    local f
    [[ -d "$dir" ]] || return 0
    for f in "$dir"/*.json; do
        [[ -f "$f" ]] || continue
        f="${f##*/}"
        printf '%s\n' "${f%.json}"
    done
}
