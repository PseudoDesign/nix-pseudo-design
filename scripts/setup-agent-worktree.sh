#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/setup-agent-worktree.sh <branch> [worktree-path]

Create or configure a dedicated worktree for an agent. The script:

  * enables repo-managed hooks from the repo's .githooks directory
  * enables worktree-local Git config
  * creates the target worktree if needed
  * locks that worktree to one branch for commits and pushes

Examples:
  scripts/setup-agent-worktree.sh agent/codex
  scripts/setup-agent-worktree.sh agent/codex /tmp/nix-pseudo-design-agent-codex
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage >&2
  exit 1
fi

branch_name=$1

repo_root=$(git rev-parse --show-toplevel)
repo_name=$(basename "$repo_root")
safe_branch=$(printf '%s' "$branch_name" | tr '/[:space:]' '--' | tr -cs 'A-Za-z0-9._-' '-')
worktree_path=${2:-"/tmp/${repo_name}-${safe_branch}"}

if [ ! -d "$repo_root/.githooks" ]; then
  printf "Expected hooks directory at '%s/.githooks'.\n" "$repo_root" >&2
  exit 1
fi

git -C "$repo_root" config extensions.worktreeConfig true
git -C "$repo_root" config core.hooksPath "$repo_root/.githooks"

if git -C "$worktree_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  current_branch=$(git -C "$worktree_path" branch --show-current)
  if [ "$current_branch" != "$branch_name" ]; then
    printf "Existing worktree at '%s' is on branch '%s', not '%s'.\n" \
      "$worktree_path" "$current_branch" "$branch_name" >&2
    exit 1
  fi
else
  if [ -e "$worktree_path" ] && [ -n "$(ls -A "$worktree_path" 2>/dev/null)" ]; then
    printf "Refusing to reuse non-empty path '%s'.\n" "$worktree_path" >&2
    exit 1
  fi

  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch_name"; then
    git -C "$repo_root" worktree add "$worktree_path" "$branch_name"
  else
    git -C "$repo_root" worktree add -b "$branch_name" "$worktree_path"
  fi
fi

git -C "$worktree_path" config --worktree codex.allowedBranch "$branch_name"

printf "Agent worktree ready.\n"
printf "  repo:     %s\n" "$repo_root"
printf "  branch:   %s\n" "$branch_name"
printf "  worktree: %s\n" "$worktree_path"
printf "\n"
printf "Commits and pushes from this worktree are now restricted to '%s'.\n" "$branch_name"
printf "Keep the agent in that worktree and do not approve escalated commands if you want to avoid root/system access.\n"
printf "Deferred approval-needed items can be queued in '%s/docs/agent-review-queue.md'.\n" "$worktree_path"
