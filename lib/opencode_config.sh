#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# lib/opencode_config.sh — project opencode.json ensure (context7 MCP).
#
# ensure_opencode_json <target>
#   Ensures the target project's opencode.json registers the context7 MCP
#   server without ever clobbering user content:
#     * file missing      -> create it with the context7 entry;
#     * context7 present  -> leave the file untouched;
#     * context7 absent   -> jq-merge the entry, preserving everything else;
#     * invalid JSON file -> warn and leave it untouched.
#   The file is intentionally NOT manifest-tracked: once written it belongs to
#   the project, and updates must never rewrite it.
#
# Requires: jq (checked by prereqs); ui_info/ui_warn from lib/ui.sh.
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s: sourced library — source it, do not execute it.\n' "${0##*/}" >&2
    exit 2
fi

# CONTEXT7_JSON — the MCP entry written into opencode.json (keyless default).
CONTEXT7_JSON='{"type":"remote","url":"https://mcp.context7.com/mcp","enabled":true}'

# ensure_opencode_json <target> — create or merge the context7 MCP entry.
ensure_opencode_json() {
    local target="$1"
    local file="$target/opencode.json"
    local tmp

    if [[ ! -e "$file" ]]; then
        if jq -n --argjson c7 "$CONTEXT7_JSON" \
            '{ "$schema": "https://opencode.ai/config.json", mcp: { context7: $c7 } }' > "$file"; then
            ui_info "created $file (context7 MCP)"
        else
            rm -f "$file"
            ui_warn "could not create $file — skipping context7 setup"
        fi
        return 0
    fi

    if ! jq -e . "$file" >/dev/null 2>&1; then
        ui_warn "$file exists but is not valid JSON — leaving it unchanged (add context7 manually if desired)"
        return 0
    fi

    if jq -e '.mcp.context7' "$file" >/dev/null 2>&1; then
        ui_info "$file already defines context7 — leaving it unchanged"
        return 0
    fi

    tmp="$(mktemp "${file}.tmp.XXXXXX")" || { ui_warn "could not create temp file next to $file"; return 0; }
    if jq --argjson c7 "$CONTEXT7_JSON" '.mcp = ((.mcp // {}) + {context7: $c7})' "$file" > "$tmp"; then
        mv "$tmp" "$file"
        ui_info "merged context7 MCP into $file"
    else
        rm -f "$tmp"
        ui_warn "could not merge context7 into $file — leaving it unchanged"
    fi
    return 0
}
