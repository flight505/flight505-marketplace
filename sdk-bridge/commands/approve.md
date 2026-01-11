---
description: "Approve or reject pending high-risk feature requests"
argument-hint: "<request-id> [--reject] [--alternative=<alt-id>] [--notes=<text>]"
allowed-tools: ["Bash", "Read", "Write"]
---

# SDK Bridge Approval Command

Handle approval requests for high-risk features detected by the autonomous agent.

## Usage

```bash
# Approve a request
/sdk-bridge:approve <request-id>

# Approve with notes
/sdk-bridge:approve <request-id> --notes="Approved after review with team"

# Reject a request
/sdk-bridge:approve <request-id> --reject

# Reject with alternative approach
/sdk-bridge:approve <request-id> --reject --alternative=alt-001 --notes="Use phased approach instead"
```

## Step 1: Check for Pending Approvals

First, check if there are any pending approvals:

```bash
#!/bin/bash
set -euo pipefail

QUEUE_FILE=".claude/approval-queue.json"

if [ ! -f "$QUEUE_FILE" ]; then
  echo "❌ No approval queue found"
  echo ""
  echo "The approval queue file does not exist. This could mean:"
  echo "  • No approvals have been requested yet"
  echo "  • SDK agent has not started"
  echo "  • v2 features are not enabled"
  exit 1
fi

# Parse pending approvals
PENDING_COUNT=$(jq '.pending_approvals | length' "$QUEUE_FILE")

if [ "$PENDING_COUNT" -eq 0 ]; then
  echo "✅ No pending approvals"
  echo ""
  echo "All approval requests have been resolved."
  exit 0
fi

echo "📋 Pending Approvals: $PENDING_COUNT"
echo ""

# List pending approvals
jq -r '.pending_approvals[] | "ID: \(.id)\nFeature: \(.feature_description)\nRisk: \(.risk_level)\nCreated: \(.created_at)\n"' "$QUEUE_FILE"
```

## Step 2: Get Request Details

If a request ID was provided, show detailed information:

```bash
REQUEST_ID="$1"  # From command argument

# Get request details
REQUEST=$(jq --arg id "$REQUEST_ID" '.pending_approvals[] | select(.id == $id)' "$QUEUE_FILE")

if [ -z "$REQUEST" ]; then
  echo "❌ Request not found: $REQUEST_ID"
  echo ""
  echo "Available pending requests:"
  jq -r '.pending_approvals[] | .id' "$QUEUE_FILE"
  exit 1
fi

# Display request details
echo "📋 Approval Request Details"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "$REQUEST" | jq -r '
"Request ID: \(.id)
Feature: \(.feature_description)
Risk Level: \(.risk_level | ascii_upcase)
Created: \(.created_at)
Timeout: \(.timeout_at)

Impact Assessment:
  Files to modify: \(.impact.files_to_modify | length)
  New dependencies: \(.impact.new_dependencies | length)
  Database changes: \(.impact.database_changes)
  API changes: \(.impact.api_changes)
  Rollback difficulty: \(.impact.rollback_difficulty)

Proposed Changes:
\(.proposed_changes)

Alternatives (\(.alternatives | length)):"
'

# Show alternatives
echo "$REQUEST" | jq -r '.alternatives[] | "
  [\(.id)] \(.approach)
  Pros: \(.pros | join(", "))
  Cons: \(.cons | join(", "))
"'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

## Step 3: Process Approval Decision

Use Python script to handle approval/rejection:

```bash
# Parse arguments
ACTION="approve"  # or "reject" if --reject flag present
ALTERNATIVE_ID=""  # from --alternative=<id>
NOTES=""  # from --notes=<text>

# Run Python approval script
python3 -c "
import sys
sys.path.append('$(dirname $(readlink -f ~/.claude/skills/long-running-agent/harness/approval_system.py 2>/dev/null || echo ~/.claude/skills/long-running-agent/harness/approval_system.py))')
from approval_system import ApprovalQueue

queue = ApprovalQueue()

if '$ACTION' == 'approve':
    success = queue.approve('$REQUEST_ID', notes='$NOTES')
    if success:
        print('✅ Approval request $REQUEST_ID approved')
        print('')
        print('The SDK agent will resume execution with the approved approach.')
    else:
        print('❌ Failed to approve request')
        sys.exit(1)
else:
    success = queue.reject('$REQUEST_ID', alternative_id='$ALTERNATIVE_ID', notes='$NOTES')
    if success:
        print('❌ Approval request $REQUEST_ID rejected')
        if '$ALTERNATIVE_ID':
            print('   Alternative selected: $ALTERNATIVE_ID')
        print('')
        print('The SDK agent will use the alternative approach or skip this feature.')
    else:
        print('❌ Failed to reject request')
        sys.exit(1)
"

# Clear notification
rm -f .claude/notification.txt

echo ""
echo "💡 Next Steps:"
echo "  • SDK agent will automatically detect the decision"
echo "  • Check progress: /sdk-bridge:status"
echo "  • View logs: tail -f .claude/sdk-bridge.log"
```

## Step 4: Notify SDK Agent

The SDK agent will detect the approval/rejection via the updated `approval-queue.json` file.

No additional action needed - the agent checks the queue periodically.

## Examples

### Approve a Request

```
/sdk-bridge:approve abc123
```

Output:
```
✅ Approval request abc123 approved

The SDK agent will resume execution with the approved approach.

💡 Next Steps:
  • SDK agent will automatically detect the decision
  • Check progress: /sdk-bridge:status
  • View logs: tail -f .claude/sdk-bridge.log
```

### Reject with Alternative

```
/sdk-bridge:approve abc123 --reject --alternative=alt-001 --notes="Team prefers phased rollout"
```

Output:
```
❌ Approval request abc123 rejected
   Alternative selected: alt-001

The SDK agent will use the alternative approach or skip this feature.
```

## Error Handling

If request not found:
```
❌ Request not found: xyz789

Available pending requests:
abc123
def456
```

If no pending approvals:
```
✅ No pending approvals

All approval requests have been resolved.
```

## Notes

- Approvals are asynchronous - other features continue while waiting
- Timeout default is 24 hours (configurable in sdk-bridge.local.md)
- After timeout, request auto-rejects with status "timeout"
- Notification files cleared after approval/rejection
- Full audit trail maintained in approval-queue.json
