#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — SDD Toolbox entry point (design §5.1, §5.2, §5.3, §12).
#
# Bootstraps opencode-based SDD tooling (pinned GitHub Spec Kit + vendored OAC
# subset + the spec-kit-driver agent) into a target project.
#
# Usage:  bootstrap.sh [<target-dir>] [OPTIONS]     (see `--help`)
#
# Stage flow (design §5.2): parse args -> (wizard | resolved plan) ->
#   check_prereqs -> [spec_kit_ensure -> spec_kit_init -> extensions] ->
#   overlay (install | update | reinstall) -> write_config ->
#   build_managed_files_json -> write_manifest_file (manifest LAST) -> summary.
#
# Exit codes (design §12): 0 ok/cancelled; 1 generic; 2 usage; 3 prerequisite;
#                          5 Spec Kit stage; 6 overlay stage.
#
# Libraries always load from THIS script's directory. TOOLBOX_ROOT defaults to
# this directory but may be overridden via the environment (used by tests) so
# that the data files (registry.json, profiles/, components/, vendor/) come
# from an alternate root while the code stays put.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$SCRIPT_DIR}"
export TOOLBOX_ROOT

STAGING_DIR=""

# _bootstrap_cleanup — EXIT trap: remove the staging directory.
_bootstrap_cleanup() {
    if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
    fi
    return 0
}

# _bootstrap_sigint — INT trap active only during the wizard.
_bootstrap_sigint() {
    printf '\nno changes made\n'
    exit 0
}

# _bootstrap_err <line> — ERR trap: report the failing line, then exit.
_bootstrap_err() {
    printf 'bootstrap: unexpected error at line %s\n' "$1" >&2
}

trap '_bootstrap_cleanup' EXIT
trap '_bootstrap_err $LINENO' ERR

# --- libraries (always from SCRIPT_DIR) ---------------------------------------
# shellcheck source=lib/args.sh
. "${SCRIPT_DIR}/lib/args.sh"
# shellcheck source=lib/ui.sh
. "${SCRIPT_DIR}/lib/ui.sh"
# shellcheck source=lib/prereqs.sh
. "${SCRIPT_DIR}/lib/prereqs.sh"
# shellcheck source=lib/manifest.sh
. "${SCRIPT_DIR}/lib/manifest.sh"
# shellcheck source=lib/registry.sh
. "${SCRIPT_DIR}/lib/registry.sh"
# shellcheck source=lib/spec_kit.sh
. "${SCRIPT_DIR}/lib/spec_kit.sh"
# shellcheck source=lib/installer.sh
. "${SCRIPT_DIR}/lib/installer.sh"
# shellcheck source=lib/update.sh
. "${SCRIPT_DIR}/lib/update.sh"
# shellcheck source=lib/wizard.sh
. "${SCRIPT_DIR}/lib/wizard.sh"

# --- version pins -------------------------------------------------------------
if [[ -f "${TOOLBOX_ROOT}/versions.env" ]]; then
    # shellcheck source=/dev/null
    . "${TOOLBOX_ROOT}/versions.env"
elif [[ -f "${SCRIPT_DIR}/versions.env" ]]; then
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/versions.env"
fi

# _bootstrap_usage_fail <msg...> — usage error (exit 2).
_bootstrap_usage_fail() {
    printf 'bootstrap: %s\n' "$*" >&2
    printf 'bootstrap: run with --help for usage.\n' >&2
    exit 2
}

# _bootstrap_run_wizard — interactive screens; sets WIZ_* globals. SIGINT is
# translated to a clean "no changes made" exit while the wizard is active.
_bootstrap_run_wizard() {
    trap '_bootstrap_sigint' INT
    if ! run_wizard; then
        trap - INT
        exit 1
    fi
    trap - INT
}

# main — orchestrate the bootstrap stages.
main() {
    parse_args "$@"
    if [[ "$SHOW_HELP" -eq 1 ]]; then
        usage
        exit 0
    fi

    # Interactive only on a TTY with no --yes / --profile (design §6.2).
    local interactive=0
    if [[ "$YES" -eq 0 && -z "$PROFILE" && -t 0 && -t 1 ]]; then
        interactive=1
    fi

    local wiz_target="" wiz_action="" wiz_profile="" wiz_components="" wiz_extensions="" wiz_settings=""
    if [[ "$interactive" -eq 1 ]]; then
        _bootstrap_run_wizard
        wiz_target="$WIZ_TARGET"
        wiz_action="$WIZ_ACTION"
        wiz_profile="$WIZ_PROFILE"
        wiz_components="$WIZ_COMPONENTS_CSV"
        wiz_extensions="$WIZ_EXTENSIONS_CSV"
        wiz_settings="$WIZ_SETTINGS_JSON"
    fi

    # Resolve target.
    local target="${TARGET_DIR:-.}"
    if [[ "$interactive" -eq 1 && -n "$wiz_target" ]]; then
        target="$wiz_target"
    fi

    # Resolve action (routing §5.3).
    local action
    if [[ "$interactive" -eq 1 && -n "$wiz_action" ]]; then
        action="$wiz_action"
    elif [[ "$UPDATE" -eq 1 ]]; then
        if [[ "$FORCE" -eq 1 ]]; then action="reinstall"; else action="update"; fi
    elif manifest_exists "$target"; then
        action="update"
    else
        action="install"
    fi

    # --update requires an existing manifest (design §5.3).
    if [[ "$action" == "update" || "$action" == "reinstall" ]]; then
        if ! manifest_exists "$target"; then
            fail_overlay "--update requires an existing manifest at $(manifest_path "$target"); run without --update for a fresh install"
        fi
    fi

    # Resolve profile.
    local profile="${PROFILE:-}"
    if [[ "$interactive" -eq 1 ]]; then
        profile="$wiz_profile"
    elif [[ -z "$profile" ]]; then
        if manifest_exists "$target"; then
            profile="$(manifest_field "$target" '.profile')"
        fi
        [[ -n "$profile" && "$profile" != "null" ]] || profile="minimal"
    fi
    if ! profile_exists "$profile"; then
        printf 'bootstrap: unknown profile: %s\n' "$profile" >&2
        printf 'bootstrap: available profiles: %s\n' "$(registry_available_profiles | tr '\n' ' ')" >&2
        exit 2
    fi

    # Resolve components.
    local components=""
    if [[ "$interactive" -eq 1 ]]; then
        components="$wiz_components"
    else
        components="$(profile_components "$profile" | awk 'NF' | paste -sd, -)"
    fi

    # Resolve extensions (Spec Kit extensions are meaningless without Spec Kit).
    local extensions=""
    if [[ "$NO_SPEC_KIT" -eq 0 ]]; then
        if [[ "$interactive" -eq 1 ]]; then
            extensions="$wiz_extensions"
        elif manifest_exists "$target"; then
            extensions="$(manifest_field "$target" '(.extensions // []) | join(",")' 2>/dev/null || true)"
        fi
    fi

    # Resolve config overrides (interactive advanced screen only).
    local overrides=""
    if [[ "$interactive" -eq 1 && -n "$wiz_settings" ]]; then
        overrides="$wiz_settings"
    fi

    # Resolved plan (design §6.2 prints the plan when non-interactive).
    local ncomp=0
    if [[ -n "$components" ]]; then
        ncomp="$(printf '%s' "$components" | awk -F, '{print NF}')"
    fi
    ui_info "SDD Toolbox bootstrap"
    ui_info "  target:     $target"
    ui_info "  action:     $action"
    ui_info "  profile:    $profile"
    ui_info "  components: $ncomp"
    ui_info "  extensions: ${extensions:-none}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        ui_info "  mode:       dry-run (no changes will be made)"
    fi

    # Stage: prerequisites (design §5.2).
    ui_info "checking prerequisites..."
    check_prereqs

    # Target directory.
    if [[ ! -d "$target" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            ui_info "[dry-run] would create target directory: $target"
        else
            mkdir -p "$target" || fail_overlay "cannot create target directory: $target"
        fi
    fi
    if [[ -d "$target" && ! -w "$target" ]]; then
        printf 'bootstrap: target directory is not writable: %s\n' "$target" >&2
        exit 3
    fi

    # Non-empty target: merge flag for `specify init` + warning.
    local init_force=0
    if [[ -d "$target" && -n "$(ls -A "$target" 2>/dev/null)" ]]; then
        init_force=1
        ui_warn "target is not empty; 'specify init --force' will merge and may replace conflicting managed paths"
    fi

    # Stage: Spec Kit (ensure -> init -> extensions).
    if [[ "$NO_SPEC_KIT" -eq 0 ]]; then
        local force_arg=""
        if [[ "$init_force" -eq 1 ]]; then force_arg=" --force"; fi
        if [[ "$DRY_RUN" -eq 1 ]]; then
            ui_info "[dry-run] would ensure pinned Spec Kit CLI (SPEC_KIT_VERSION=${SPEC_KIT_VERSION:-latest})"
            ui_info "[dry-run] would run: specify init --here --integration opencode --script sh --non-interactive${force_arg}"
            local e
            while IFS= read -r e; do
                [[ -n "$e" ]] || continue
                ui_info "[dry-run] would run: specify extension add $e"
            done <<< "$(printf '%s' "$extensions" | tr ',' '\n')"
        else
            spec_kit_ensure
            spec_kit_init "$target" "$init_force"
            local e
            while IFS= read -r e; do
                [[ -n "$e" ]] || continue
                spec_kit_add_extension "$target" "$e"
            done <<< "$(printf '%s' "$extensions" | tr ',' '\n')"
        fi
    else
        ui_info "skipping Spec Kit stages (--no-spec-kit)"
    fi

    # Stage: overlay (install | update | reinstall).
    case "$action" in
        install)
            if [[ "$DRY_RUN" -eq 1 ]]; then
                ui_info "[dry-run] component install plan:"
                if [[ -d "$target" ]]; then plan_install "$target" "$components"; fi
            else
                ui_info "installing components..."
                install_components "$target" "$components"
            fi
            ;;
        update|reinstall)
            local uforce=0
            if [[ "$action" == "reinstall" ]]; then uforce=1; fi
            if [[ "$DRY_RUN" -eq 1 ]]; then
                ui_info "[dry-run] component update plan (force=$uforce):"
                if [[ -d "$target" ]]; then update_components "$target" "$uforce" 1; fi
            else
                ui_info "updating components (force=$uforce)..."
                update_components "$target" "$uforce" 0
            fi
            ;;
    esac

    # Stage: config + manifest (manifest LAST — design §5.2).
    if [[ "$DRY_RUN" -eq 1 ]]; then
        ui_info "[dry-run] would write config:   $(config_path "$target")"
        ui_info "[dry-run] would write manifest: $(manifest_path "$target")"
    else
        write_config "$target" "$profile" "$overrides"
        STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sdd-toolbox.XXXXXX")"
        # Merge current files with retained stale entries (design §7.2) so a
        # component removed from the catalog is not silently dropped.
        merged_managed_files_json "$target" "$components" > "$STAGING_DIR/managed-files.json"
        write_manifest_file "$target" "$profile" "$extensions" "$(cat "$STAGING_DIR/managed-files.json")"
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        ui_info ""
        ui_info "dry-run complete: no changes made."
        return 0
    fi

    ui_info ""
    ui_info "SDD Toolbox bootstrap complete."
    ui_info "  target:  $target"
    ui_info "  profile: $profile"
    ui_info "  action:  $action"
    ui_info "Next steps:"
    ui_info "  1. cd $target"
    ui_info "  2. Launch opencode."
    ui_info "  3. Run /sdd <request> to start the gated Spec Kit flow."
    return 0
}

main "$@"
