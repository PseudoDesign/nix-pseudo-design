# Agent Autonomy Policy

This document defines how the dedicated autonomous checkout operates when the goal is to keep progress moving without waiting for human input mid-task.

## Operating Mode

The agent may work freely inside the dedicated checkout and commit to its assigned branch.

The agent should not pause for routine approval during normal implementation work. When a task needs approval, secrets, or a high-risk decision, the agent should defer that item into the review queue and continue with everything else that can be completed safely.

## Autonomous Lane

These actions are allowed without additional review:

* edit, create, rename, and delete files inside the dedicated checkout
* run local builds, tests, formatters, and static analysis that do not need sandbox escalation
* commit changes on the assigned branch inside the dedicated clone under `/tmp`
* make reversible implementation choices when there is a clear safest reasonable default
* document assumptions in commit messages, notes, or follow-up summaries

## Deferred Review Lane

These actions should be recorded for later review instead of blocking the task:

* any command that needs sandbox escalation
* network access, package installation, or dependency downloads that are not already available
* secrets, credentials, production access, or deploy actions
* destructive or hard-to-reverse actions such as history rewrites, resets, or deleting important data
* decisions with meaningful product or operational tradeoffs and no safe default
* conflicts with unrelated user changes that cannot be resolved confidently

## Decision Defaults

When a task is ambiguous, the agent should:

1. choose the safest reversible option that preserves existing behavior
2. note the assumption in the work summary
3. add a review-queue item only if the ambiguity materially affects correctness, security, or irreversible outcomes

## Review Queue

The review queue lives at [docs/agent-review-queue.md](docs/agent-review-queue.md).

Use the helper below to append an item:

```bash
scripts/defer-for-review.sh \
  --title "Need network access for dependency download" \
  --why "The requested verification path requires fetching a missing dependency." \
  --command "cargo test" \
  --risk "Would require sandbox escalation and network access." \
  --blocking "yes"
```

## Human Review Expectations

When reviewing deferred items, the human can:

* approve one or more queued actions
* decide that an item should be skipped
* provide missing context or secrets
* ask the agent to continue with a preferred tradeoff

Until then, the agent should keep making forward progress on everything else that remains safely in scope.

## Recommended Checkout

For long unattended runs in this harness, prefer a dedicated clone under `/tmp` instead of a shared Git worktree. A dedicated clone keeps both the working tree and the Git metadata in the writable sandbox.

Bootstrap one with [scripts/setup-agent-clone.sh](../scripts/setup-agent-clone.sh):

```bash
scripts/setup-agent-clone.sh /home/adam/nix-pseudo-design agent/codex
```
