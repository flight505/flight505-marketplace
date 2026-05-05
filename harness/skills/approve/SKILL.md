---
name: approve
description: "Approve or reject a pending approval gate in a harness workflow. Used when a conductor run pauses at a type: approval phase."
user-invocable: true
---

# Approve a pending gate

Resolve a `type: approval` phase that paused the conductor.

## Usage

```
/harness:approve <phase_id>              # approve
/harness:approve <phase_id> --reject "reason"   # reject with reason
```

## How it works

1. Read `.harness/pending-approval-{phase_id}.json`
2. If the file doesn't exist, list all pending approvals found in `.harness/pending-approval-*.json` and ask which one
3. Update the file:
   - **Approve:** set `status: "approved"`, `decided_at: <now>`
   - **Reject:** set `status: "rejected"`, `decision_reason: <reason>`, `decided_at: <now>`
4. Print confirmation
5. Remind the user to re-run `/harness:run` to continue the workflow

## Arguments

Parse the arguments:
- First positional arg: `phase_id` (required unless listing)
- `--reject "reason"`: reject instead of approve (optional)
- No args: list all pending approvals

## Implementation

```bash
PHASE_ID="${1:-}"
HARNESS_DIR=".harness"

# List mode
if [ -z "$PHASE_ID" ]; then
  echo "Pending approvals:"
  for f in "$HARNESS_DIR"/pending-approval-*.json; do
    [ -f "$f" ] || { echo "  (none)"; break; }
    PHASE=$(basename "$f" | sed 's/pending-approval-//;s/\.json//')
    STATUS=$(python3 -c "import json; print(json.load(open('$f')).get('status','unknown'))")
    PROMPT=$(python3 -c "import json; print(json.load(open('$f')).get('prompt','')[:80])")
    echo "  $PHASE [$STATUS] — $PROMPT"
  done
  exit 0
fi

APPROVAL_FILE="$HARNESS_DIR/pending-approval-${PHASE_ID}.json"

if [ ! -f "$APPROVAL_FILE" ]; then
  echo "No pending approval found for phase '$PHASE_ID'"
  echo "Check .harness/pending-approval-*.json for available gates"
  exit 1
fi
```

Then check for `--reject`:
- If present, set status to "rejected" with the reason
- Otherwise, set status to "approved"

Write the decision atomically (write to .tmp, rename).

Print:
```
✓ Phase '<phase_id>' approved. Run /harness:run to continue the workflow.
```
or
```
✗ Phase '<phase_id>' rejected: <reason>. Run /harness:run to continue (dependent phases will be skipped).
```
