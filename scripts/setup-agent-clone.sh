#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/setup-agent-clone.sh <source-repo> <branch> [clone-path]

Create a dedicated autonomous clone for one branch. The script:

  * clones only the requested branch into /tmp by default
  * avoids hardlinking objects back to the source repo
  * enables repo-managed hooks with core.hooksPath=.githooks
  * locks commits and pushes to the assigned branch with codex.allowedBranch

Examples:
  scripts/setup-agent-clone.sh /home/adam/nix-pseudo-design agent/codex
  scripts/setup-agent-clone.sh /home/adam/nix-pseudo-design agent/codex /tmp/nix-pseudo-design-agent-autonomous
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage >&2
  exit 1
fi

source_repo=$1
branch_name=$2

source_repo=$(cd "$source_repo" && pwd)
repo_name=$(basename "$source_repo")
safe_branch=$(printf '%s' "$branch_name" | tr '/[:space:]' '--' | tr -cs 'A-Za-z0-9._-' '-')
clone_path=${3:-"/tmp/${repo_name}-${safe_branch}-autonomous"}

if [ -e "$clone_path" ]; then
  printf "Refusing to reuse existing path '%s'.\n" "$clone_path" >&2
  exit 1
fi

git clone --branch "$branch_name" --single-branch --no-hardlinks "$source_repo" "$clone_path"

git -C "$clone_path" config core.hooksPath .githooks
git -C "$clone_path" config codex.allowedBranch "$branch_name"
git -C "$clone_path" remote set-url origin "$source_repo"

printf "Autonomous clone ready.\n"
printf "  source:   %s\n" "$source_repo"
printf "  branch:   %s\n" "$branch_name"
printf "  clone:    %s\n" "$clone_path"
printf "\n"
printf "Commits in this clone are local to /tmp and constrained to '%s'.\n" "$branch_name"
printf "Approval-needed items should be appended to '%s/docs/agent-review-queue.md'.\n" "$clone_path"
