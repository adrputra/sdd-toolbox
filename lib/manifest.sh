#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/manifest.sh — ownership manifest, config, hashing and file classification.
#
# Purpose
#   Read/write `.sdd-toolbox/manifest.json` and `.sdd-toolbox/config.json`, hash
#   files portably, and classify a target file against manifest + desired state
#   (design §7.1, §7.2, §7.3).
#
# Exported functions
#   hash_file <file>                 Print the sha256 hex of <file>.
#   manifest_path <target>           Print <target>/.sdd-toolbox/manifest.json.
#   config_path <target>             Print <target>/.sdd-toolbox/config.json.
#   manifest_exists <target>         Return 0 when the manifest file exists.
#   manifest_field <target> <jq>     Print `jq -r <jq>` from the manifest.
#   config_field <target> <jq>       Print `jq -r <jq>` from the config.
#   write_manifest <target> <json>   Validate + atomically install a manifest.
#   classify_file <exists> <actual> <manifest> <desired>
#                                    Print missing|conflict|identical|
#                                    unmodified|modified.
#
# Notes
#   Sourced library: no `set -euo pipefail`, no side effects at source time.
#   Bash 3.2+ compatible. JSON handled with jq only.
# =============================================================================

# Direct-execution guard.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s: sourced library — source it, do not execute it.\n' "${0##*/}" >&2
    exit 2
fi

# hash_file <file> — print the sha256 hex digest of <file>.
# Uses sha256sum when available, else shasum -a 256 (macOS).
hash_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        printf 'manifest: cannot hash missing file: %s\n' "$file" >&2
        return 1
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
        return 0
    fi
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
        return 0
    fi
    printf 'manifest: no sha256 tool found (need sha256sum or shasum)\n' >&2
    return 3
}

# manifest_path <target> — print the absolute-ish manifest path for a target.
manifest_path() {
    printf '%s/.sdd-toolbox/manifest.json\n' "${1%/}"
}

# config_path <target> — print the config path for a target.
config_path() {
    printf '%s/.sdd-toolbox/config.json\n' "${1%/}"
}

# manifest_exists <target> — return 0 when the target manifest exists.
manifest_exists() {
    [[ -f "$(manifest_path "$1")" ]]
}

# manifest_field <target> <jq-filter> — print a jq -r value from the manifest.
# Returns 1 when the manifest is absent or the filter yields nothing.
manifest_field() {
    local target="$1"
    local filter="$2"
    local path
    path="$(manifest_path "$target")"
    if [[ ! -f "$path" ]]; then
        return 1
    fi
    jq -r "$filter" "$path"
}

# config_field <target> <jq-filter> — print a jq -r value from the config.
# Returns 1 when the config is absent.
config_field() {
    local target="$1"
    local filter="$2"
    local path
    path="$(config_path "$target")"
    if [[ ! -f "$path" ]]; then
        return 1
    fi
    jq -r "$filter" "$path"
}

# write_manifest <target> <json-file> — validate and install a manifest.
# Writes via a temp file + mv so the manifest is only ever complete JSON.
write_manifest() {
    local target="$1"
    local src="$2"
    local path dir tmp
    path="$(manifest_path "$target")"
    dir="$(dirname "$path")"

    if [[ ! -f "$src" ]]; then
        printf 'manifest: source JSON not found: %s\n' "$src" >&2
        return 6
    fi
    if ! jq -e . "$src" >/dev/null 2>&1; then
        printf 'manifest: refusing to write invalid JSON: %s\n' "$src" >&2
        return 6
    fi

    mkdir -p "$dir" || {
        printf 'manifest: cannot create %s\n' "$dir" >&2
        return 6
    }
    tmp="${path}.tmp.$$"
    if ! cp "$src" "$tmp"; then
        printf 'manifest: cannot stage manifest in %s\n' "$dir" >&2
        return 6
    fi
    mv "$tmp" "$path" || {
        printf 'manifest: cannot install manifest at %s\n' "$path" >&2
        return 6
    }
    return 0
}

# classify_file <actual_exists:0|1> <actual_sha> <manifest_sha> <desired_sha>
# Print exactly one of: missing | conflict | identical | unmodified | modified.
#
# Precedence (design §7.2):
#   1. actual missing                         -> missing
#   2. manifest hash empty/absent             -> conflict (unmanaged file)
#   3. actual == desired                      -> identical
#   4. actual == manifest                     -> unmodified
#   5. otherwise                              -> modified
classify_file() {
    local actual_exists="$1"
    local actual_sha="$2"
    local manifest_sha="$3"
    local desired_sha="$4"

    if [[ "$actual_exists" -eq 0 ]]; then
        printf 'missing\n'
        return 0
    fi
    if [[ -z "$manifest_sha" || "$manifest_sha" == "null" ]]; then
        printf 'conflict\n'
        return 0
    fi
    if [[ "$actual_sha" == "$desired_sha" ]]; then
        printf 'identical\n'
        return 0
    fi
    if [[ "$actual_sha" == "$manifest_sha" ]]; then
        printf 'unmodified\n'
        return 0
    fi
    printf 'modified\n'
}
