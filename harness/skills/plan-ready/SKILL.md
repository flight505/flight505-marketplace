---
name: plan-ready
description: "Signal that an ultraplan phase's plan has been saved and the conductor can resume. Used after the user reviews and teleports a plan from Claude Code on the web."
user-invocable: true
---

# Signal plan ready

Tell the conductor that the ultraplan-generated plan file is in place and the workflow can resume.

## Usage

```
/harness:plan-ready <phase_id>
```

## What it does

1. Verify `.harness/artifacts/<phase_id>/plan.md` exists
2. If yes: write a signal file `.harness/pending-approval-<phase_id>.json` with `status: "approved"` so the conductor's resume logic picks it up
3. If no: print an error listing what's expected and where

## Implementation

```bash
PHASE_ID="${1:-}"
if [ -z "$PHASE_ID" ]; then
  echo "Usage: /harness:plan-ready <phase_id>"
  exit 1
fi

ARTIFACT=".harness/artifacts/${PHASE_ID}/plan.md"
if [ ! -f "$ARTIFACT" ]; then
  echo "Plan file not found at: ${ARTIFACT}"
  echo ""
  echo "Expected steps:"
  echo "  1. Run /ultraplan with your planning prompt"
  echo "  2. Review the plan in your browser"
  echo "  3. Choose 'Approve plan and teleport back to terminal'"
  echo "  4. In the dialog, choose 'Cancel' to save the plan to a file"
  echo "  5. Copy the saved file to: ${ARTIFACT}"
  echo "  6. Re-run this command"
  exit 1
fi
```

Then write the signal file:

```python
import json, datetime
signal = {
    "phase_id": PHASE_ID,
    "status": "approved",
    "decided_at": datetime.now(UTC).isoformat(),
    "plan_file": ARTIFACT
}
# write to .harness/pending-approval-{phase_id}.json
```

Print confirmation:

```
Plan ready at ${ARTIFACT}. Run /harness:run to resume the workflow.
```
