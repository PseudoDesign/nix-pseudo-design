#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/defer-for-review.sh --title TITLE --why REASON [options]

Options:
  --title TEXT       Short summary of the deferred item
  --why TEXT         Why the action was needed
  --command TEXT     Exact command or operation to review later
  --risk TEXT        Risk, approval boundary, or reason for deferral
  --blocking yes|no  Whether the item blocks completion
  --queue PATH       Override the queue file path
  -h, --help         Show this help text

Example:
  scripts/defer-for-review.sh \
    --title "Need network access for dependency download" \
    --why "The requested verification path requires fetching a missing dependency." \
    --command "cargo test" \
    --risk "Would require sandbox escalation and network access." \
    --blocking "yes"
EOF
}

title=""
why=""
command_text=""
risk="Requires later human review."
blocking="no"
queue_path="docs/agent-review-queue.md"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --title)
      title=${2:-}
      shift 2
      ;;
    --why)
      why=${2:-}
      shift 2
      ;;
    --command)
      command_text=${2:-}
      shift 2
      ;;
    --risk)
      risk=${2:-}
      shift 2
      ;;
    --blocking)
      blocking=${2:-}
      shift 2
      ;;
    --queue)
      queue_path=${2:-}
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf "Unknown argument: %s\n" "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$title" ] || [ -z "$why" ]; then
  usage >&2
  exit 1
fi

case "$blocking" in
  yes|no)
    ;;
  *)
    printf "Invalid value for --blocking: %s\n" "$blocking" >&2
    exit 1
    ;;
esac

queue_dir=$(dirname "$queue_path")
mkdir -p "$queue_dir"

if [ ! -f "$queue_path" ]; then
  printf '# Agent Review Queue\n\n## Open Items\n\n' >"$queue_path"
fi

if grep -qx '_None._' "$queue_path"; then
  tmp_file=$(mktemp)
  grep -vx '_None._' "$queue_path" >"$tmp_file"
  mv "$tmp_file" "$queue_path"
fi

timestamp=$(date -Iseconds)

{
  printf '\n### %s\n\n' "$title"
  printf '* Recorded: `%s`\n' "$timestamp"
  printf '* Blocking: `%s`\n' "$blocking"
  printf '* Why: %s\n' "$why"
  printf '* Risk: %s\n' "$risk"
  if [ -n "$command_text" ]; then
    printf '* Command: `%s`\n' "$command_text"
  fi
} >>"$queue_path"

printf "Queued review item in %s\n" "$queue_path"
