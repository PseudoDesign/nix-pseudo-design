# Agent Worktree Workflow

This repository now includes a pragmatic "sandboxed branch" workflow for running an agent inside a dedicated Git worktree.

What it does:

* creates a dedicated worktree for the agent
* enables repo-managed hooks from `.githooks`
* stores the allowed branch in worktree-local Git config
* blocks commits, merge commits, patch application, and pushes when that worktree is not on the assigned branch
* supports an autonomous workflow where approval-needed items are deferred into a review queue

What it does not do:

* it does not create a real OS sandbox by itself
* it does not prevent branch checkout; it prevents committing or pushing from the wrong branch
* it does not stop root/system access if a human approves escalated commands
* it may still leave some Git metadata writes subject to sandbox review, because worktree metadata lives under the primary checkout's `.git`

## Quick Start

Create a dedicated branch and worktree:

```bash
scripts/setup-agent-worktree.sh agent/codex /tmp/nix-pseudo-design-agent-codex
```

Then run the agent from that worktree:

```bash
cd /tmp/nix-pseudo-design-agent-codex
git status --branch
git config --show-origin --get codex.allowedBranch
```

If you prefer the default worktree location, omit the second argument:

```bash
scripts/setup-agent-worktree.sh agent/codex
```

## How Enforcement Works

The branch lock is stored only in the configured worktree:

```bash
git config --worktree codex.allowedBranch agent/codex
```

The shared hooks live in `.githooks` and are enabled with:

```bash
git config core.hooksPath "$(git rev-parse --show-toplevel)/.githooks"
```

Because `core.hooksPath` is repo-local and `codex.allowedBranch` is worktree-local, normal developer worktrees stay flexible while the dedicated agent worktree is constrained.

## Removing the Lock

To remove the branch restriction from the current worktree:

```bash
git config --worktree --unset codex.allowedBranch
```

## Recommended Operating Rules

* keep the agent in the dedicated worktree
* do not approve escalated commands if you want to avoid root/system access
* let the agent keep working autonomously on reversible local changes
* record approval-needed or high-risk items in [docs/agent-review-queue.md](docs/agent-review-queue.md)
* review and merge the agent branch from a normal human-controlled worktree

## Autonomous Runs

If you want the agent to keep moving without waiting for input:

* treat the dedicated worktree as the autonomous lane
* let the agent commit normally on the assigned branch when the sandbox allows the underlying Git metadata write
* defer approvals, secrets, destructive actions, and ambiguous high-risk choices into the review queue

The detailed policy lives in [docs/agent-autonomy-policy.md](docs/agent-autonomy-policy.md).

If you need fully autonomous commits in this harness, a dedicated clone under `/tmp` is stronger than a shared Git worktree.
