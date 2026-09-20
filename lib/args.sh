#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/args.sh — command-line argument parsing for bootstrap.sh.
#
# Purpose
#   Parses the bootstrap CLI surface defined in design §5.1 and exposes the
#   resolved values as plain globals for the rest of the toolbox.
#
# Exported functions
#   usage              Print the usage/help text to stdout.
#   parse_args "$@"    Parse arguments; on error prints cause + usage to stderr
#                      and exits 2 (usage).
#
# Exported variables (set by parse_args, reset on every call)
#   TARGET_DIR     Target project directory (default ".").
#   PROFILE        Profile name from --profile (default "").
#   YES            1 when --yes was given, else 0.
#   UPDATE         1 when --update was given, else 0.
#   FORCE          1 when --force was given, else 0 (requires --update).
#   DRY_RUN        1 when --dry-run was given, else 0.
#   NO_SPEC_KIT    1 when --no-spec-kit was given, else 0.
#   SHOW_HELP      1 when -h/--help was given, else 0.
#
# Notes
#   Sourced library: no `set -euo pipefail` and no side effects at source time.
#   Bash 3.2+ compatible (macOS system bash). No eval.
# =============================================================================

# Direct-execution guard: this file is a sourced library, not a program.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s: sourced library — source it, do not execute it.\n' "${0##*/}" >&2
    exit 2
fi

# usage — print the bootstrap CLI help text to stdout.
usage() {
    cat <<'USAGE'
Usage: bootstrap.sh [<target-dir>] [OPTIONS]

Bootstrap opencode-based SDD tooling (Spec Kit + vendored OAC subset +
spec-kit-driver agent) into a target project.

Arguments:
  <target-dir>         Directory to install into (default: current directory).

Options:
  --profile <name>     Non-interactive profile selection (e.g. minimal, go-backend, node-typescript).
  --yes                Assume yes for all prompts (implies non-interactive).
  --update             Update mode; requires an existing toolbox manifest.
  --force              With --update: reinstall mode (overwrite modified files).
  --dry-run            Print planned actions without writing anything.
  --no-spec-kit        Skip the Spec Kit stages (install the toolbox overlay only).
  -h, --help           Show this help and exit.

Exit codes:
  0 success/cancelled   2 usage   3 prerequisite   5 spec-kit
  6 overlay   7 validation
USAGE
}

# _args_die <message> — print the cause and usage to stderr, then exit 2.
_args_die() {
    printf 'args: %s\n' "$1" >&2
    printf 'args: run with --help for usage.\n' >&2
    usage >&2
    exit 2
}

# parse_args "$@" — parse the bootstrap argument vector.
# Resets all exported variables to their defaults, then applies flags.
# Exits 2 (usage) on unknown flags, missing values, extra positionals, or
# --force without --update.
parse_args() {
    TARGET_DIR="."
    PROFILE=""
    YES=0
    UPDATE=0
    FORCE=0
    DRY_RUN=0
    NO_SPEC_KIT=0
    SHOW_HELP=0

    local positional_seen=0
    local arg

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --profile)
                [[ $# -ge 2 ]] || _args_die "missing value for --profile"
                [[ -n "$2" ]] || _args_die "empty value for --profile"
                PROFILE="$2"
                shift 2
                ;;
            --yes)
                YES=1
                shift
                ;;
            --update)
                UPDATE=1
                shift
                ;;
            --force)
                FORCE=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --no-spec-kit)
                NO_SPEC_KIT=1
                shift
                ;;
            -h|--help)
                SHOW_HELP=1
                shift
                ;;
            --)
                shift
                while [[ $# -gt 0 ]]; do
                    if [[ "$positional_seen" -eq 1 ]]; then
                        _args_die "unexpected extra argument: $1"
                    fi
                    TARGET_DIR="$1"
                    positional_seen=1
                    shift
                done
                ;;
            -*)
                _args_die "unknown option: $arg"
                ;;
            *)
                if [[ "$positional_seen" -eq 1 ]]; then
                    _args_die "unexpected extra argument: $arg"
                fi
                TARGET_DIR="$arg"
                positional_seen=1
                shift
                ;;
        esac
    done

    if [[ "$FORCE" -eq 1 && "$UPDATE" -ne 1 ]]; then
        _args_die "--force is only valid together with --update"
    fi

    return 0
}
