#!/usr/bin/env bash
# Roadmap loop runner — drives the roadmap-driver headlessly.
#
# One iteration = one `opencode run` session advance. State lives in
# .sdd-toolbox/roadmap.json, so sessions are interchangeable and resumable.
#
# Exit codes:
#   0  active milestone complete (or nothing left to run)
#   2  checkpoint pending — owner approval required
#   3  blocked — owner decision required
#   1  error (opencode failure, stall, or unexpected state)
set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE="$ROOT/.sdd-toolbox/roadmap.json"
JOURNAL="$ROOT/.sdd-toolbox/journal"
AGENT="roadmap-driver"
MODEL=""

FEATURE=""
APPROVE=""
AUTO_CHECKPOINT=false
MAX_ITERATIONS=""
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: scripts/loop.sh [options]

Options:
  --feature F00x        Run (or resume) a single feature
  --approve F00x        Owner approval: commit the checkpoint and advance
  --auto-checkpoint     Unattended: pre-approve every feature checkpoint
                        (commit + continue); stops only on blockers/errors
  --max-iterations N    Safety cap on opencode invocations (default: derived)
  --model P/M           Model override (provider/model)
  --dry-run             Print what would run; do not invoke opencode
  -h, --help            Show this help

Exit: 0 milestone done | 2 checkpoint pending | 3 blocked | 1 error
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --feature) FEATURE="$2"; shift 2 ;;
    --approve) APPROVE="$2"; shift 2 ;;
    --auto-checkpoint) AUTO_CHECKPOINT=true; shift ;;
    --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

for bin in opencode jq git; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' is required." >&2; exit 1; }
done
[[ -f "$STATE" ]] || { echo "ERROR: $STATE not found." >&2; exit 1; }
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: $ROOT is not a git repo." >&2; exit 1; }

# Anchor the session to the project root so the script is location-independent.
cd "$ROOT"

mkdir -p "$JOURNAL"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$JOURNAL/loop-$STAMP.log"
MODEL_ARGS=()
[[ -n "$MODEL" ]] && MODEL_ARGS=(--model "$MODEL")

milestone="$(jq -r '.active_milestone' "$STATE")"

if [[ -z "$MAX_ITERATIONS" ]]; then
  pending="$(jq --arg m "$milestone" '[.features[] | select(.milestone == $m and (.status == "pending" or .status == "in_progress"))] | length' "$STATE")"
  MAX_ITERATIONS=$(( (pending + 1) * 3 ))
  [[ "$MAX_ITERATIONS" -lt 3 ]] && MAX_ITERATIONS=3
fi

status_summary() {
  jq -r --arg m "$milestone" '
    "milestone \(.active_milestone):",
    (.features[] | select(.milestone == $m) |
      "  \(.id)  \(.status)\(if .blocker then "  <- " + (.blocker.reason // "blocked") else "" end)")
  ' "$STATE"
}

# Build the per-iteration instruction.
build_message() {
  local base="Roadmap loop iteration. Follow .opencode/context/roadmap/loop-protocol.md. Resolve any awaiting_approval or blocked feature first; otherwise dispatch the next eligible feature in the active milestone. Stop at checkpoints, blockers, or milestone completion and print the LOOP: line."
  if [[ -n "$APPROVE" ]]; then
    base="The owner approved feature $APPROVE at its checkpoint. Commit it, mark it done, update the state file, and then continue the roadmap loop. $base"
  elif [[ -n "$FEATURE" ]]; then
    base="Run roadmap feature $FEATURE through the full loop. $base"
  fi
  if [[ "$AUTO_CHECKPOINT" == true ]]; then
    base="$base AUTO_CHECKPOINT: the owner pre-approved feature checkpoints for this unattended run — approve each completed feature (commit, mark done) and continue until the milestone completes or something blocks."
  fi
  printf '%s' "$base"
}

echo "== roadmap loop ==" | tee "$LOG"
status_summary | tee -a "$LOG"
echo "log: $LOG" | tee -a "$LOG"

last_hash=""
iteration=0
while [[ "$iteration" -lt "$MAX_ITERATIONS" ]]; do
  iteration=$((iteration + 1))
  message="$(build_message)"
  APPROVE="" # one-shot: an approval applies to exactly one iteration

  echo "" | tee -a "$LOG"
  echo "-- iteration $iteration/$MAX_ITERATIONS --" | tee -a "$LOG"

  if [[ "$DRY_RUN" == true ]]; then
    echo "would run: opencode run --agent $AGENT --auto ${MODEL_ARGS[*]:-} \"$message\"" | tee -a "$LOG"
    exit 0
  else
    continue_flag=()
    [[ "$iteration" -gt 1 ]] && continue_flag=(--continue)
    opencode run --agent "$AGENT" --auto "${continue_flag[@]}" "${MODEL_ARGS[@]}" --title "roadmap-loop $STAMP" "$message" 2>&1 | tee -a "$LOG"
  fi

  awaiting="$(jq -r '[.features[] | select(.status == "awaiting_approval")] | length' "$STATE")"
  blocked="$(jq -r '[.features[] | select(.status == "blocked")] | length' "$STATE")"
  active_open="$(jq -r --arg m "$milestone" '[.features[] | select(.milestone == $m and (.status != "done" and .status != "skipped"))] | length' "$STATE")"
  in_progress="$(jq -r --arg m "$milestone" '[.features[] | select(.milestone == $m and .status == "in_progress")] | length' "$STATE")"

  status_summary | tee -a "$LOG"

  if [[ "$awaiting" -gt 0 ]]; then
    feature_id="$(jq -r '[.features[] | select(.status == "awaiting_approval")][0].id' "$STATE")"
    if [[ "$AUTO_CHECKPOINT" == true ]]; then
      echo "LOOP: CHECKPOINT $feature_id — auto-approved, committing and continuing" | tee -a "$LOG"
      APPROVE="$feature_id"
      continue
    fi
    echo "LOOP: CHECKPOINT $feature_id" | tee -a "$LOG"
    echo "Approve with: scripts/loop.sh --approve $feature_id   (or /roadmap approve $feature_id)"
    exit 2
  fi

  if [[ "$blocked" -gt 0 ]]; then
    feature_id="$(jq -r '[.features[] | select(.status == "blocked")][0].id' "$STATE")"
    reason="$(jq -r '[.features[] | select(.status == "blocked")][0].blocker.reason // "unknown"' "$STATE")"
    echo "LOOP: BLOCKED $feature_id — $reason" | tee -a "$LOG"
    echo "Resolve with: /roadmap status  (interactive), then rerun scripts/loop.sh --feature $feature_id"
    exit 3
  fi

  if [[ "$active_open" -eq 0 ]]; then
    echo "LOOP: MILESTONE $milestone DONE" | tee -a "$LOG"
    exit 0
  fi

  if [[ "$in_progress" -eq 0 ]]; then
    echo "LOOP: no eligible feature and nothing in progress — check dependencies and blockers in $STATE" | tee -a "$LOG"
    exit 1
  fi

  current_hash="$(jq -S . "$STATE" | sha256sum | cut -d' ' -f1)"
  if [[ "$current_hash" == "$last_hash" ]]; then
    echo "LOOP: stall detected — state unchanged after an iteration. Stopping." | tee -a "$LOG"
    exit 1
  fi
  last_hash="$current_hash"
done

echo "LOOP: max iterations ($MAX_ITERATIONS) reached — stopping." | tee -a "$LOG"
exit 1
