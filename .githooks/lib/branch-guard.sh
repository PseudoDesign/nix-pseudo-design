#!/usr/bin/env bash

set -euo pipefail

branch_guard_allowed_branch() {
  git config --get codex.allowedBranch || true
}

branch_guard_current_branch() {
  git symbolic-ref --quiet --short HEAD 2>/dev/null || true
}

branch_guard_die() {
  printf '%s\n' "$*" >&2
  exit 1
}

branch_guard_require_branch() {
  local allowed_branch current_branch

  allowed_branch=$(branch_guard_allowed_branch)
  if [ -z "$allowed_branch" ]; then
    return 0
  fi

  current_branch=$(branch_guard_current_branch)
  if [ -z "$current_branch" ]; then
    branch_guard_die \
      "This worktree is locked to branch '$allowed_branch', but HEAD is detached." \
      "Switch back to '$allowed_branch' or unset 'codex.allowedBranch' in this worktree."
  fi

  if [ "$current_branch" != "$allowed_branch" ]; then
    branch_guard_die \
      "This worktree is locked to branch '$allowed_branch', but the current branch is '$current_branch'." \
      "Switch back to '$allowed_branch' or unset 'codex.allowedBranch' in this worktree."
  fi
}
