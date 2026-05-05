#!/bin/bash
# TaskCompleted hook — validates that the fix passes the test suite
# Only activates when harness triage-subsystem state files exist
# Exit 0: allow completion
# Exit 2: block completion
set -e

HARNESS_DIR=".harness"

# Find the most recent triage state file
LATEST_STATE=$(ls -t "${HARNESS_DIR}"/triage-*.json 2>/dev/null | head -1 || echo "")

if [ -z "$LATEST_STATE" ]; then
  exit 0
fi

# Extract quality commands from state config
TEST_CMD=$(python3 -c "
import json, sys
try:
    state = json.loads(open(sys.argv[1]).read())
    quality = state.get('config', {}).get('quality', {})
    print(quality.get('test', ''))
except:
    print('')
" "$LATEST_STATE" 2>/dev/null || echo "")

if [ -z "$TEST_CMD" ]; then
  exit 0
fi

if ! OUTPUT=$(eval "$TEST_CMD" 2>&1); then
  TRUNCATED=$(echo "$OUTPUT" | head -c 4000)
  echo -e "Fix validation failed — test suite must pass:\n\n${TRUNCATED}" >&2
  exit 2
fi

exit 0
