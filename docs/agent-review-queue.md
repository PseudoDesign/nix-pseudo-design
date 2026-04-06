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

_None._
