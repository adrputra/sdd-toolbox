#!/usr/bin/env bash
# =============================================================================
# scripts/vendor-sync.sh — refresh the vendored OAC subset (design §3, §15).
#
# Maintainer-only tool. Copies a curated set of `.opencode/**` files from a
# local OAC source checkout into vendor/oac/ and writes vendor/oac/bundle.json
# (version, provenance, per-file sha256). No network access.
#
# Usage:
#   scripts/vendor-sync.sh --source <dir> --version <ver> [OPTIONS]
#
# Options:
#   --source <dir>        Local OAC checkout (must contain .opencode/). Required.
#   --version <ver>       Version label for the snapshot. Required.
#   --provenance <str>    Provenance note (default: unknown).
#   --selection <file>    Selection list (default: vendor/selection.txt).
#   --dry-run             Print the plan + bundle JSON; write nothing.
#   -h, --help            Show this help.
#
# Environment:
#   VENDOR_ROOT   Destination root (default: <toolbox>/vendor/oac).
#
# Exit codes: 0 ok; 2 usage; 3 missing source/.opencode; 1 missing selections.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
VENDOR_ROOT="${VENDOR_ROOT:-${TOOLBOX_ROOT}/vendor/oac}"

# Reuse the portable sha256 wrapper from the manifest library.
# shellcheck source=../lib/manifest.sh
. "${TOOLBOX_ROOT}/lib/manifest.sh"

usage() {
    cat <<'USAGE'
Usage: scripts/vendor-sync.sh --source <dir> --version <ver> [OPTIONS]

Copy a curated set of .opencode/** files from a local OAC checkout into
vendor/oac/ and write vendor/oac/bundle.json. No network access.

Options:
  --source <dir>      Local OAC checkout containing .opencode/ (required).
  --version <ver>     Version label for the snapshot (required).
  --provenance <str>  Provenance note (default: unknown).
  --selection <file>  Selection list (default: vendor/selection.txt).
  --dry-run           Print the plan and bundle JSON; write nothing.
  -h, --help          Show this help.

Environment:
  VENDOR_ROOT         Destination root (default: <toolbox>/vendor/oac).
USAGE
}

# --- argument parsing ---------------------------------------------------------
SOURCE=""
VERSION=""
PROVENANCE="unknown"
SELECTION=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            [[ $# -ge 2 ]] || { printf 'vendor-sync: missing value for --source\n' >&2; exit 2; }
            SOURCE="$2"; shift 2 ;;
        --version)
            [[ $# -ge 2 ]] || { printf 'vendor-sync: missing value for --version\n' >&2; exit 2; }
            VERSION="$2"; shift 2 ;;
        --provenance)
            [[ $# -ge 2 ]] || { printf 'vendor-sync: missing value for --provenance\n' >&2; exit 2; }
            PROVENANCE="$2"; shift 2 ;;
        --selection)
            [[ $# -ge 2 ]] || { printf 'vendor-sync: missing value for --selection\n' >&2; exit 2; }
            SELECTION="$2"; shift 2 ;;
        --dry-run)
            DRY_RUN=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            printf 'vendor-sync: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2 ;;
    esac
done

if [[ -z "$SOURCE" || -z "$VERSION" ]]; then
    printf 'vendor-sync: --source and --version are required\n' >&2
    usage >&2
    exit 2
fi
if [[ -z "$SELECTION" ]]; then
    SELECTION="${TOOLBOX_ROOT}/vendor/selection.txt"
fi

if [[ ! -d "${SOURCE}/.opencode" ]]; then
    printf 'vendor-sync: source has no .opencode/ directory: %s\n' "$SOURCE" >&2
    printf 'vendor-sync: point --source at an OAC checkout (e.g. a repo with .opencode/)\n' >&2
    exit 3
fi
if [[ ! -f "$SELECTION" ]]; then
    printf 'vendor-sync: selection file not found: %s\n' "$SELECTION" >&2
    exit 3
fi

# --- helpers ------------------------------------------------------------------
infer_type() {
    case "$1" in
        agent/subagents/*) printf 'subagent\n' ;;
        agent/*)           printf 'agent\n' ;;
        command/*)         printf 'command\n' ;;
        context/*)         printf 'context\n' ;;
        *)                 printf 'unknown\n' ;;
    esac
}

# Read selection entries (relative to .opencode/), skipping blanks and comments.
read_selection() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        case "$line" in \#*) continue ;; esac
        printf '%s\n' "$line"
    done < "$SELECTION"
}

# --- pre-flight: collect every missing selected file --------------------------
missing=()
while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    if [[ ! -f "${SOURCE}/.opencode/${rel}" ]]; then
        missing+=("$rel")
    fi
done < <(read_selection)

if [[ "${#missing[@]}" -gt 0 ]]; then
    printf 'vendor-sync: %d selected file(s) missing from %s/.opencode/:\n' \
        "${#missing[@]}" "$SOURCE" >&2
    for rel in "${missing[@]}"; do
        printf '  - %s\n' "$rel" >&2
    done
    printf 'vendor-sync: fix vendor/selection.txt or the --source checkout, then retry\n' >&2
    exit 1
fi

# --- plan ---------------------------------------------------------------------
records="$(mktemp)"
trap 'rm -f "$records"' EXIT

count=0
while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    src="${SOURCE}/.opencode/${rel}"
    sha="$(hash_file "$src")"
    base="${rel##*/}"
    id="${base%.md}"
    type="$(infer_type "$rel")"
    printf '%s\t%s\t%s\t%s\n' ".opencode/${rel}" "$id" "$type" "$sha" >> "$records"
    count=$((count + 1))

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '[dry-run] copy %s -> %s/.opencode/%s\n' "$src" "$VENDOR_ROOT" "$rel"
    else
        dest="${VENDOR_ROOT}/.opencode/${rel}"
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
    fi
done < <(read_selection)

files_json="$(jq -R -s '
    split("\n")
    | map(select(length > 0) | split("\t"))
    | map({path: .[0], id: .[1], type: .[2], sha256: .[3]})
' "$records")"

bundle="$(jq -n \
    --arg version "$VERSION" \
    --arg provenance "$PROVENANCE" \
    --argjson files "$files_json" \
    '{version: $version, provenance: $provenance, generated_by: "scripts/vendor-sync.sh", files: $files}')"

if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] would write %s/bundle.json (%d file(s))\n' "$VENDOR_ROOT" "$count"
    printf '%s\n' "$bundle"
    exit 0
fi

mkdir -p "$VENDOR_ROOT"
printf '%s\n' "$bundle" > "${VENDOR_ROOT}/bundle.json"
printf 'vendor-sync: wrote %s/bundle.json (%d file(s))\n' "$VENDOR_ROOT" "$count"
