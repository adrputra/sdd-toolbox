#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/wizard.sh — interactive bootstrap wizard (design §6.1).
#
# Purpose
#   Drive the 7 wizard screens and expose the resolved plan as globals. Menus
#   are populated dynamically from the registry/profiles; nothing is hardcoded.
#   Cancelling at any point (q / Ctrl-C) calls ui_cancel.
#
# Exported function
#   run_wizard
#       Sets WIZ_TARGET, WIZ_ACTION (install|update|reinstall), WIZ_PROFILE,
#       WIZ_COMPONENTS_CSV, WIZ_EXTENSIONS_CSV, WIZ_SETTINGS_JSON (overrides
#       only), WIZ_CONFIRMED=1. Returns 1 (with ui_err) when stdin is not a TTY
#       and WIZ_ALLOW_NON_TTY != 1 (the bootstrap decides the non-interactive
#       path).
#   Screens: 1 Target, 2 Action (only when a manifest exists), 3 Profile,
#            4 Components, 5 Extensions, 6 Advanced, 7 Confirm.
#
# Test hook
#   WIZ_ALLOW_NON_TTY=1 lets the numbered fallback run with piped stdin; the
#   TTY guard itself is exercised by calling run_wizard without it.
#
# Dependencies (lazily sourced from this directory): lib/ui.sh,
# lib/registry.sh, lib/manifest.sh. Sourced library: no `set -euo pipefail`, no
# source-time side effects beyond TOOLBOX_ROOT / _WIZARD_LIB_DIR.
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s: sourced library — source it, do not execute it.\n' "${0##*/}" >&2
    exit 2
fi
if [[ -z "${TOOLBOX_ROOT:-}" ]]; then
    TOOLBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
_WIZARD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WIZ_TARGET=""
WIZ_ACTION="install"
WIZ_PROFILE=""
WIZ_COMPONENTS_CSV=""
WIZ_EXTENSIONS_CSV=""
WIZ_SETTINGS_JSON="{}"
WIZ_CONFIRMED=0
_WIZ_CHOICE=""
_WIZ_MULTI=""

# _wizard_ensure_deps — lazily source sibling libraries when not already loaded.
_wizard_ensure_deps() {
    type ui_info >/dev/null 2>&1 || { . "${_WIZARD_LIB_DIR}/ui.sh"; }
    type manifest_exists >/dev/null 2>&1 || { . "${_WIZARD_LIB_DIR}/manifest.sh"; }
    type catalog_resolve >/dev/null 2>&1 || { . "${_WIZARD_LIB_DIR}/registry.sh"; }
}

# _wiz_choose <prompt> <default> <opt...> — set _WIZ_CHOICE; cancel-aware.
_wiz_choose() {
    local out rc
    out="$(ui_choose "$@")"
    rc=$?
    [[ "$rc" -eq 0 ]] || { ui_err "no valid choice"; return 1; }
    case "$out" in *"no changes made"*) ui_cancel ;; esac
    _WIZ_CHOICE="$(printf '%s\n' "$out" | tail -n 1)"
}

# _wiz_multiselect <prompt> <preselected_csv> <opt...> — set _WIZ_MULTI.
_wiz_multiselect() {
    local out rc
    out="$(ui_multiselect "$@")"
    rc=$?
    [[ "$rc" -eq 0 ]] || { ui_err "no valid selection"; return 1; }
    case "$out" in *"no changes made"*) ui_cancel ;; esac
    _WIZ_MULTI="$(printf '%s\n' "$out" | tail -n 1)"
}

# _wizard_component_options — print merged "type:id" options (custom + vendor).
_wizard_component_options() {
    local reg="${TOOLBOX_ROOT%/}/registry.json" bundle="${TOOLBOX_ROOT%/}/vendor/oac/bundle.json"
    local custom="" vend=""
    [[ -f "$reg" ]] && custom="$(jq -r '
        (.components.agents // [])[] | "agent:\(.id)",
        (.components.subagents // [])[] | "subagent:\(.id)",
        (.components.commands // [])[] | "command:\(.id)",
        (.components.tools // [])[] | "tool:\(.id)",
        (.components.contexts // [])[] | "context:\(.id)"' "$reg" 2>/dev/null)"
    [[ -f "$bundle" ]] && vend="$(jq -r '(.files // [])[] | "\(.type):\(.id)"' "$bundle" 2>/dev/null)"
    printf '%s\n%s\n' "$custom" "$vend" | awk 'NF' | sort -u
}

# _wizard_component_legend — print "type:id — description" lines (custom only).
_wizard_component_legend() {
    local reg="${TOOLBOX_ROOT%/}/registry.json"
    [[ -f "$reg" ]] || return 0
    jq -r '
        (.components.agents // [])[] | "  agent:\(.id) — \(.description // "")",
        (.components.subagents // [])[] | "  subagent:\(.id) — \(.description // "")",
        (.components.commands // [])[] | "  command:\(.id) — \(.description // "")",
        (.components.tools // [])[] | "  tool:\(.id) — \(.description // "")",
        (.components.contexts // [])[] | "  context:\(.id) — \(.description // "")"' "$reg" 2>/dev/null
}

# run_wizard — execute the interactive wizard and set the WIZ_* globals.
run_wizard() {
    _wizard_ensure_deps
    WIZ_TARGET=""; WIZ_ACTION="install"; WIZ_PROFILE=""
    WIZ_COMPONENTS_CSV=""; WIZ_EXTENSIONS_CSV=""; WIZ_SETTINGS_JSON="{}"; WIZ_CONFIRMED=0

    if [[ ! -t 0 && "${WIZ_ALLOW_NON_TTY:-0}" -ne 1 ]]; then
        ui_err "wizard needs an interactive terminal; use --profile <name> --yes for non-interactive runs"
        return 1
    fi

    # 1. Target
    local input
    printf 'Target directory [%s]: ' "$PWD"
    if ! IFS= read -r input; then input=""; fi
    case "$input" in q|Q) ui_cancel ;; esac
    [[ -n "$input" ]] || input="$PWD"
    [[ -d "$input" ]] || { ui_err "target directory does not exist: $input"; return 1; }
    [[ -w "$input" ]] || { ui_err "target directory is not writable: $input"; return 1; }
    [[ -z "$(ls -A "$input" 2>/dev/null)" ]] || ui_warn "target directory is not empty: $input"
    WIZ_TARGET="$input"

    # 2. Action (only for an existing install)
    if manifest_exists "$WIZ_TARGET"; then
        _wiz_choose "Existing install detected. Action?" "Update" "Update" "Reinstall" "Cancel" || return 1
        case "$_WIZ_CHOICE" in
            Update)    WIZ_ACTION="update" ;;
            Reinstall) WIZ_ACTION="reinstall" ;;
            *)         ui_cancel ;;
        esac
    fi

    # 3. Profile
    local profiles pname pdesc
    profiles="$(registry_available_profiles | awk 'NF')"
    [[ -n "$profiles" ]] || { ui_err "no profiles under ${TOOLBOX_ROOT%/}/profiles"; return 1; }
    ui_info "Available profiles:"
    local -a popts=()
    while IFS= read -r pname; do
        [[ -n "$pname" ]] || continue
        popts+=("$pname")
        pdesc="$(profile_json "$pname" 2>/dev/null | jq -r '.description // ""')"
        ui_info "  ${pname} — ${pdesc}"
    done <<< "$profiles"
    _wiz_choose "Select a profile" "${popts[0]}" "${popts[@]}" || return 1
    WIZ_PROFILE="$_WIZ_CHOICE"

    # 4. Components
    local opts_lines c pre_csv
    opts_lines="$(_wizard_component_options)"
    [[ -n "$opts_lines" ]] || { ui_err "no components found in the registry"; return 1; }
    ui_info "Component legend:"
    _wizard_component_legend
    local -a copts=()
    while IFS= read -r c; do [[ -n "$c" ]] && copts+=("$c"); done <<< "$opts_lines"
    pre_csv="$(profile_components "$WIZ_PROFILE" | awk 'NF' | paste -sd, -)"
    _wiz_multiselect "Select components" "$pre_csv" "${copts[@]}" || return 1
    WIZ_COMPONENTS_CSV="$_WIZ_MULTI"

    # 5. Extensions (skip when none)
    local exts e
    exts="$(jq -r '(.extensions // {}) | keys[]' "${TOOLBOX_ROOT%/}/registry.json" 2>/dev/null | awk 'NF')"
    if [[ -n "$exts" ]]; then
        local -a eopts=()
        while IFS= read -r e; do [[ -n "$e" ]] && eopts+=("$e"); done <<< "$exts"
        _wiz_multiselect "Select Spec Kit extensions" "" "${eopts[@]}" || return 1
        WIZ_EXTENSIONS_CSV="$_WIZ_MULTI"
    fi

    # 6. Advanced
    local psettings def_ws def_pt def_cmds def_scope ws
    psettings="$(profile_json "$WIZ_PROFILE" | jq '.settings // {}')"
    def_ws="$(printf '%s' "$psettings" | jq -r '.wave_strategy // "auto"')"
    def_pt="$(printf '%s' "$psettings" | jq -r '.parallel_threshold // 5')"
    def_cmds="$(printf '%s' "$psettings" | jq -r '(.validation.commands // []) | join(", ")')"
    def_scope="$(printf '%s' "$psettings" | jq -r '.validation.scope // "repo"')"
    _wiz_choose "Wave strategy" "$def_ws" "auto" "order" || return 1
    ws="$_WIZ_CHOICE"

    local threshold="" attempt=0 ans max="${UI_MAX_ATTEMPTS:-3}"
    while [[ "$attempt" -lt "$max" ]]; do
        attempt=$((attempt + 1))
        printf 'Parallel threshold [%s]: ' "$def_pt"
        if ! IFS= read -r ans; then ans=""; fi
        case "$ans" in q|Q) ui_cancel ;; esac
        [[ -n "$ans" ]] || ans="$def_pt"
        if [[ "$ans" =~ ^[0-9]+$ && "$ans" -ge 1 ]]; then threshold="$ans"; break; fi
        ui_warn "threshold must be a positive integer (attempt ${attempt}/${max})"
    done
    [[ -n "$threshold" ]] || { ui_err "no valid parallel threshold"; return 1; }

    local cmdline
    printf 'Validation commands (comma-separated) [%s]: ' "$def_cmds"
    if ! IFS= read -r cmdline; then cmdline=""; fi
    case "$cmdline" in q|Q) ui_cancel ;; esac
    [[ -n "$cmdline" ]] || cmdline="$def_cmds"

    local converge=0 cmds_json converge_bool
    ui_confirm "Enable converge loop?" && converge=1
    cmds_json="$(printf '%s' "$cmdline" | tr ',' '\n' | awk 'NF { gsub(/^[ \t]+/, ""); gsub(/[ \t]+$/, ""); print }' | jq -R . | jq -s '.')"
    [[ "$converge" -eq 1 ]] && converge_bool="true" || converge_bool="false"
    WIZ_SETTINGS_JSON="$(jq -n --arg ws "$ws" --argjson pt "$threshold" \
        --argjson vc "$cmds_json" --arg sc "$def_scope" --argjson cl "$converge_bool" \
        '{wave_strategy: $ws, parallel_threshold: $pt, validation: {commands: $vc, scope: $sc}, converge_loop: $cl}')"

    # 7. Confirm
    local ncomp=0
    [[ -n "$WIZ_COMPONENTS_CSV" ]] && ncomp="$(printf '%s' "$WIZ_COMPONENTS_CSV" | awk -F, '{print NF}')"
    ui_info "Summary:"
    ui_info "  target:     $WIZ_TARGET"
    ui_info "  action:     $WIZ_ACTION"
    ui_info "  profile:    $WIZ_PROFILE"
    ui_info "  components: $ncomp"
    ui_info "  extensions: ${WIZ_EXTENSIONS_CSV:-none}"
    ui_info "  settings:   $WIZ_SETTINGS_JSON"
    if ui_confirm "Proceed with these settings?"; then
        WIZ_CONFIRMED=1
        return 0
    fi
    ui_cancel
}
