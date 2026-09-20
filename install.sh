#!/usr/bin/env bash
#
# SDD Toolbox — remote installer.
#
# Fetches (or refreshes) a managed toolbox checkout and delegates to its
# bootstrap.sh, forwarding every argument. This is the script behind the
# one-line install:
#
#   curl -fsSL https://raw.githubusercontent.com/adrputra/sdd-toolbox/main/install.sh \
#     | bash -s -- <target-dir> --profile go-backend --yes
#
# Interactive wizard (needs a terminal on stdin):
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/adrputra/sdd-toolbox/main/install.sh)
#
# Environment:
#   SDD_TOOLBOX_REPO  git URL to fetch from (default: https://github.com/adrputra/sdd-toolbox.git)
#   SDD_TOOLBOX_REF   branch or tag to use  (default: main)
#   SDD_TOOLBOX_HOME  managed checkout dir  (default: ~/.sdd-toolbox)
#
# The checkout is managed: local edits there are overwritten on refresh.
# Run bootstrap.sh --help for the full bootstrap option list.

set -euo pipefail

SDD_TOOLBOX_REPO="${SDD_TOOLBOX_REPO:-https://github.com/adrputra/sdd-toolbox.git}"
SDD_TOOLBOX_REF="${SDD_TOOLBOX_REF:-main}"
SDD_TOOLBOX_HOME="${SDD_TOOLBOX_HOME:-$HOME/.sdd-toolbox}"

usage() {
    cat <<'EOF'
SDD Toolbox — remote installer

Fetches/refreshes a managed toolbox checkout, then runs its bootstrap.sh with
all arguments forwarded.

Usage:
  curl -fsSL <install-url> | bash -s -- [options]
  bash <(curl -fsSL <install-url>)        # interactive wizard

Common bootstrap options (forwarded verbatim):
  <target-dir>        directory to install into (default: current directory)
  --profile <name>    profile to install (minimal | go-backend | node-typescript)
  --yes               non-interactive; assume yes for all prompts
  --update            update an existing install
  --force             with --update: reinstall (overwrite modified files)
  --dry-run           print the plan; write nothing
  --no-spec-kit       skip Spec Kit stages (toolbox overlay only)

Environment:
  SDD_TOOLBOX_REPO   git URL to fetch from (default: https://github.com/adrputra/sdd-toolbox.git)
  SDD_TOOLBOX_REF    branch or tag to use  (default: main)
  SDD_TOOLBOX_HOME   managed checkout dir  (default: ~/.sdd-toolbox)
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

if ! command -v git >/dev/null 2>&1; then
    echo "install: git is required to fetch the toolbox (install git and re-run)" >&2
    exit 3
fi

if [ -d "$SDD_TOOLBOX_HOME/.git" ]; then
    echo "install: refreshing toolbox at $SDD_TOOLBOX_HOME (ref: $SDD_TOOLBOX_REF)"
    if git -C "$SDD_TOOLBOX_HOME" fetch --quiet --depth 1 origin "$SDD_TOOLBOX_REF"; then
        git -C "$SDD_TOOLBOX_HOME" checkout --quiet --force --detach FETCH_HEAD
    else
        echo "install: warning: fetch failed — using the existing checkout" >&2
    fi
elif [ -e "$SDD_TOOLBOX_HOME" ]; then
    if [ ! -f "$SDD_TOOLBOX_HOME/bootstrap.sh" ]; then
        echo "install: $SDD_TOOLBOX_HOME exists but is not a toolbox checkout" >&2
        exit 1
    fi
    echo "install: using existing toolbox at $SDD_TOOLBOX_HOME"
else
    echo "install: cloning toolbox (ref: $SDD_TOOLBOX_REF) into $SDD_TOOLBOX_HOME"
    git clone --quiet --depth 1 --branch "$SDD_TOOLBOX_REF" "$SDD_TOOLBOX_REPO" "$SDD_TOOLBOX_HOME"
fi

if [ ! -f "$SDD_TOOLBOX_HOME/bootstrap.sh" ]; then
    echo "install: bootstrap.sh not found in $SDD_TOOLBOX_HOME — cannot continue" >&2
    exit 1
fi

if [ ! -t 0 ] && [ "$#" -eq 0 ]; then
    echo "install: no arguments in a non-interactive session — defaults apply (target '.', profile 'minimal'); pass flags for explicit control" >&2
fi

exec bash "$SDD_TOOLBOX_HOME/bootstrap.sh" "$@"
