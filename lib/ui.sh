#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/ui.sh — terminal UI helpers for the interactive wizard.
#
# Purpose
#   Logging, confirmation, single-choice and multi-select prompts with a
#   zero-dependency numbered fallback, and optional gum/fzf enhancements
#   (design §6.2). Cancelling (q / Ctrl-C) exits cleanly with "no changes
#   made".
#
# Exported functions
#   ui_info <msg...>                 Informational line to stdout.
#   ui_warn <msg...>                 Warning line to stderr.
#   ui_err  <msg...>                 Error line to stderr.
#   ui_confirm <prompt>              Ask y/n; 0 = yes, 1 = no.
#                                    Honors UI_ASSUME_YES=1 (auto-yes).
#   ui_choose <prompt> <default> <opt...>
#                                    Print the chosen option.
#   ui_multiselect <prompt> <preselected_csv> <opt...>
#                                    Print the chosen option values as CSV.
#   ui_has_enhanced                  0 when gum or fzf is available.
#   ui_cancel                        Print "no changes made" and exit 0.
#
# Exported variables
#   UI_ASSUME_YES   Default 0. When 1, ui_confirm returns 0 without prompting.
#   UI_MAX_ATTEMPTS Default 3. Re-prompt budget before aborting.
#   UI_ENHANCED_THRESHOLD Default 8. Lists at least this long may use fzf.
#
# Notes
#   Sourced library: no `set -euo pipefail`, no side effects at source time.
#   Bash 3.2+ compatible. Non-TTY safe (EOF is handled, never hangs).
# =============================================================================

# Direct-execution guard.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s: sourced library — source it, do not execute it.\n' "${0##*/}" >&2
    exit 2
fi

UI_ASSUME_YES="${UI_ASSUME_YES:-0}"
UI_MAX_ATTEMPTS="${UI_MAX_ATTEMPTS:-3}"
UI_ENHANCED_THRESHOLD="${UI_ENHANCED_THRESHOLD:-8}"

# ui_info <msg...> — print an informational line to stdout.
ui_info() {
    printf '%s\n' "$*"
}

# ui_warn <msg...> — print a warning line to stderr.
ui_warn() {
    printf 'warning: %s\n' "$*" >&2
}

# ui_err <msg...> — print an error line to stderr.
ui_err() {
    printf 'error: %s\n' "$*" >&2
}

# ui_has_enhanced — return 0 when gum or fzf is available, else 1.
ui_has_enhanced() {
    if command -v gum >/dev/null 2>&1; then
        return 0
    fi
    if command -v fzf >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# _ui_gum_available — return 0 when gum may be used for this session.
_ui_gum_available() {
    command -v gum >/dev/null 2>&1 || return 1
    [[ -t 0 && -t 1 ]] || return 1
    return 0
}

# ui_cancel — abort the wizard cleanly: "no changes made", exit 0.
ui_cancel() {
    printf 'no changes made\n'
    exit 0
}

# ui_confirm <prompt> — ask a yes/no question. Returns 0 for yes, 1 for no.
# When UI_ASSUME_YES=1, returns 0 immediately (non-interactive).
ui_confirm() {
    local prompt="$1"
    if [[ "${UI_ASSUME_YES:-0}" -eq 1 ]]; then
        return 0
    fi

    if _ui_gum_available; then
        if gum confirm "$prompt"; then
            return 0
        fi
        return 1
    fi

    local attempt=0 answer
    while [[ "$attempt" -lt "$UI_MAX_ATTEMPTS" ]]; do
        attempt=$((attempt + 1))
        printf '%s [y/N] ' "$prompt" >&2
        if ! IFS= read -r answer; then
            printf '\n' >&2
            return 1
        fi
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]|"")   return 1 ;;
            *) ui_warn "please answer 'y' or 'n' (attempt ${attempt}/${UI_MAX_ATTEMPTS})" ;;
        esac
    done
    ui_warn "no valid answer after ${UI_MAX_ATTEMPTS} attempts"
    return 1
}

# _ui_print_options <opt...> — print numbered options to stdout.
_ui_print_options() {
    local i=1 opt
    for opt in "$@"; do
        printf '  %d) %s\n' "$i" "$opt"
        i=$((i + 1))
    done
}

# _ui_expand_selection <count> <raw> — expand "1,3,5-7" into ordered unique
# indices, one per line. Returns 1 on any malformed/out-of-range token.
_ui_expand_selection() {
    local count="$1"
    local raw="$2"
    local token lo hi i j exists
    local -a idx=()

    raw="${raw//,/ }"
    # Intentional word splitting on the comma-normalized token list.
    # shellcheck disable=SC2086
    for token in $raw; do
        if [[ "$token" =~ ^[0-9]+$ ]]; then
            lo="$token"
            hi="$token"
        elif [[ "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
            lo="${token%%-*}"
            hi="${token##*-}"
        else
            return 1
        fi
        if [[ "$lo" -lt 1 || "$hi" -gt "$count" || "$lo" -gt "$hi" ]]; then
            return 1
        fi
        i="$lo"
        while [[ "$i" -le "$hi" ]]; do
            exists=0
            for j in "${idx[@]+"${idx[@]}"}"; do
                if [[ "$j" == "$i" ]]; then
                    exists=1
                    break
                fi
            done
            if [[ "$exists" -eq 0 ]]; then
                idx+=("$i")
            fi
            i=$((i + 1))
        done
    done

    local k
    for k in "${idx[@]+"${idx[@]}"}"; do
        printf '%s\n' "$k"
    done
    return 0
}

# _ui_join_csv <value...> — join values with commas (no trailing comma).
_ui_join_csv() {
    local out=""
    local v
    for v in "$@"; do
        if [[ -z "$out" ]]; then
            out="$v"
        else
            out="${out},${v}"
        fi
    done
    printf '%s' "$out"
}

# ui_choose <prompt> <default> <opt...> — print the chosen option to stdout.
ui_choose() {
    local prompt="$1"
    local default="$2"
    shift 2
    local -a opts=("$@")
    local count="${#opts[@]}"

    if [[ "$count" -eq 0 ]]; then
        ui_err "ui_choose: no options supplied for '${prompt}'"
        return 1
    fi

    if _ui_gum_available; then
        local chosen
        chosen="$(gum choose "${opts[@]}")" || ui_cancel
        printf '%s\n' "$chosen"
        return 0
    fi

    local attempt=0 answer idx
    while [[ "$attempt" -lt "$UI_MAX_ATTEMPTS" ]]; do
        attempt=$((attempt + 1))
        printf '%s\n' "$prompt" >&2
        _ui_print_options "${opts[@]}" >&2
        printf 'Choose [1-%d] (default: %s): ' "$count" "$default" >&2
        if ! IFS= read -r answer; then
            printf '\n' >&2
            printf '%s\n' "$default"
            return 0
        fi
        if [[ -z "$answer" ]]; then
            printf '%s\n' "$default"
            return 0
        fi
        case "$answer" in
            [Qq])
                ui_cancel
                ;;
        esac
        if [[ "$answer" =~ ^[0-9]+$ ]] && [[ "$answer" -ge 1 && "$answer" -le "$count" ]]; then
            idx=$((answer - 1))
            printf '%s\n' "${opts[$idx]}"
            return 0
        fi
        ui_warn "invalid choice '${answer}' (attempt ${attempt}/${UI_MAX_ATTEMPTS})"
    done
    ui_err "no valid choice after ${UI_MAX_ATTEMPTS} attempts"
    return 1
}

# ui_multiselect <prompt> <preselected_csv> <opt...> — print selected option
# values as a comma-separated list. Accepts "1,3,5-7" style input; an empty
# answer keeps the preselected set.
ui_multiselect() {
    local prompt="$1"
    local preselected="$2"
    shift 2
    local -a opts=("$@")
    local count="${#opts[@]}"

    if [[ "$count" -eq 0 ]]; then
        ui_err "ui_multiselect: no options supplied for '${prompt}'"
        return 1
    fi

    if _ui_gum_available; then
        local raw
        raw="$(gum choose --no-limit "${opts[@]}")" || ui_cancel
        local -a picked=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && picked+=("$line")
        done <<EOF
$raw
EOF
        _ui_join_csv "${picked[@]+"${picked[@]}"}"
        printf '\n'
        return 0
    fi

    # Build the preselected index list from the CSV of option values.
    local -a pre_idx=()
    local i j val
    i=0
    while [[ "$i" -lt "$count" ]]; do
        val="${opts[$i]}"
        local check
        check=",${preselected},"
        if [[ "$check" == *",${val},"* ]]; then
            pre_idx+=("$((i + 1))")
        fi
        i=$((i + 1))
    done

    local attempt=0 answer
    while [[ "$attempt" -lt "$UI_MAX_ATTEMPTS" ]]; do
        attempt=$((attempt + 1))
        printf '%s\n' "$prompt" >&2
        i=1
        for val in "${opts[@]}"; do
            local mark=" "
            for j in "${pre_idx[@]+"${pre_idx[@]}"}"; do
                if [[ "$j" == "$i" ]]; then
                    mark="*"
                    break
                fi
            done
            printf '  %s %d) %s\n' "$mark" "$i" "$val" >&2
            i=$((i + 1))
        done
        printf 'Select (e.g. 1,3,5-7) [enter keeps preselected]: ' >&2
        if ! IFS= read -r answer; then
            printf '\n' >&2
            printf '%s\n' "$preselected"
            return 0
        fi
        case "$answer" in
            [Qq])
                ui_cancel
                ;;
        esac
        if [[ -z "$answer" ]]; then
            printf '%s\n' "$preselected"
            return 0
        fi

        local expanded
        if ! expanded="$(_ui_expand_selection "$count" "$answer")"; then
            ui_warn "invalid selection '${answer}' (attempt ${attempt}/${UI_MAX_ATTEMPTS})"
            continue
        fi
        local -a chosen=()
        while IFS= read -r val; do
            [[ -n "$val" ]] || continue
            chosen+=("${opts[$((val - 1))]}")
        done <<EOF
$expanded
EOF
        _ui_join_csv "${chosen[@]+"${chosen[@]}"}"
        printf '\n'
        return 0
    done
    ui_err "no valid selection after ${UI_MAX_ATTEMPTS} attempts"
    return 1
}
