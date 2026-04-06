# Agent Review Queue

This file collects actions that were intentionally deferred so autonomous work could continue without waiting for input.

## How To Use It

Each item should capture:

* what action was deferred
* why it was needed
* the risk or approval boundary involved
* whether the item blocks completion or only limits verification
* the exact command or operation to review later, when relevant

Append new items with:

```bash
scripts/defer-for-review.sh --title "Short title" --why "Reason"
```

## Open Items


### Allow a branch-local commit for agent/codex

* Recorded: `2026-04-06T05:52:23-04:00`
* Blocking: `no`
* Why: The autonomous workflow files are ready, but git commit failed because this worktree writes metadata under the primary checkout's .git/worktrees path.
* Risk: Would require sandbox approval for Git metadata writes outside the worktree path.
* Command: `git -C /tmp/nix-pseudo-design-agent-codex commit -m 'Add autonomous agent worktree workflow'`
