#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/prereqs.sh — environment prerequisite checks (design §5.2).
#
# Purpose
#   Verify the runtime tools the toolbox needs (bash >= 3.2, jq, uv, curl, and
#   a sha256 implementation) and fail fast with an OS-aware install hint.
#
# Exported functions
#   check_prereqs     Check every prerequisite, printing one status line per
#                     tool. Exits 3 on the first missing tool (after printing
#                     its hint).
#   fail_prereq <tool> <hint>
#                     Print a one-line cause + remedy and exit 3.
#
# Exported variables
#   PREREQ_MIN_BASH_MAJOR / PREREQ_MIN_BASH_MINOR   Minimum bash version.
#
# Notes
#   Sourced library: no `set -euo pipefail`, no side effects at source time.
#   `command -v` honors PATH, so tests can restrict PATH to assert the
#   failure path. Bash 3.2+ compatible. Never uses sudo.
# =============================================================================

# Direct-execution guard.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s: sourced library — source it, do not execute it.\n' "${0##*/}" >&2
    exit 2
fi

PREREQ_MIN_BASH_MAJOR=3
PREREQ_MIN_BASH_MINOR=2

# _prereq_os_hint <tool> — echo an install command suited to the current OS.
_prereq_os_hint() {
    local tool="$1"
    local os
    os="$(uname -s 2>/dev/null || printf 'unknown')"
    case "$os" in
        Darwin)
            printf 'brew install %s' "$tool"
            ;;
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                printf 'sudo apt-get install -y %s' "$tool"
            elif command -v dnf >/dev/null 2>&1; then
                printf 'sudo dnf install -y %s' "$tool"
            elif command -v yum >/dev/null 2>&1; then
                printf 'sudo yum install -y %s' "$tool"
            elif command -v apk >/dev/null 2>&1; then
                printf 'sudo apk add %s' "$tool"
            else
                printf 'install %s with your package manager' "$tool"
            fi
            ;;
        *)
            printf 'install %s with your package manager' "$tool"
            ;;
    esac
}

# fail_prereq <tool> <hint> — report a missing prerequisite and exit 3.
fail_prereq() {
    local tool="$1"
    local hint="$2"
    printf 'prereq: missing required tool: %s\n' "$tool" >&2
    printf 'prereq: remedy: %s\n' "$hint" >&2
    exit 3
}

# _prereq_ok <tool> — print an OK status line for a present tool.
_prereq_ok() {
    printf 'prereq: ok: %s\n' "$1"
}

# check_prereqs — validate every prerequisite, then return 0.
check_prereqs() {
    # bash version
    if [[ "${BASH_VERSINFO[0]}" -lt "$PREREQ_MIN_BASH_MAJOR" ]] || \
       { [[ "${BASH_VERSINFO[0]}" -eq "$PREREQ_MIN_BASH_MAJOR" ]] && \
         [[ "${BASH_VERSINFO[1]}" -lt "$PREREQ_MIN_BASH_MINOR" ]]; }; then
        fail_prereq "bash >= ${PREREQ_MIN_BASH_MAJOR}.${PREREQ_MIN_BASH_MINOR}" \
            "macOS ships bash 3.2; upgrade via 'brew install bash'"
    fi
    _prereq_ok "bash >= ${PREREQ_MIN_BASH_MAJOR}.${PREREQ_MIN_BASH_MINOR} (${BASH_VERSION%%(*})"

    # jq
    if ! command -v jq >/dev/null 2>&1; then
        fail_prereq "jq" "$(_prereq_os_hint jq) (JSON parsing is required)"
    fi
    _prereq_ok "jq"

    # uv (Spec Kit CLI installer)
    if ! command -v uv >/dev/null 2>&1; then
        fail_prereq "uv" "install uv: https://docs.astral.sh/uv/ ($(_prereq_os_hint uv))"
    fi
    _prereq_ok "uv"

    # curl (network reachability + Spec Kit bootstrap)
    if ! command -v curl >/dev/null 2>&1; then
        fail_prereq "curl" "$(_prereq_os_hint curl)"
    fi
    _prereq_ok "curl"

    # sha256: sha256sum (Linux/coreutils) OR shasum -a 256 (macOS)
    if command -v sha256sum >/dev/null 2>&1; then
        _prereq_ok "sha256sum"
    elif command -v shasum >/dev/null 2>&1; then
        _prereq_ok "shasum"
    else
        fail_prereq "sha256sum or shasum" \
            "install coreutils (Linux) or use the macOS built-in shasum"
    fi

    return 0
}
