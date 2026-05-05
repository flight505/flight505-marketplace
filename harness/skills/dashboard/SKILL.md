---
name: dashboard
description: "Generate and open the harness run dashboard. Reads .harness/*.json state files, builds a self-contained HTML file, and opens it in the browser. Use when the user asks to see the dashboard, check run status, or view experiment history. For live monitoring during a run, suggest /loop 30s /harness:dashboard."
user-invocable: true
---

# Harness: Dashboard

Generate a self-contained HTML dashboard from `.harness/` state files and open it in the browser.

## Step 1: Locate the harness directory

```bash
if [ -d ".harness" ]; then
  HARNESS_DIR=".harness"
elif [ -d "../.harness" ]; then
  HARNESS_DIR="../.harness"
else
  echo "NO_HARNESS_DIR"
fi
echo "Using: $HARNESS_DIR"
```

If no `.harness/` directory exists, tell the user no runs have been recorded yet and stop.

## Step 2: Generate the dashboard

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/render-dashboard.js" "$HARNESS_DIR"
```

The script writes `$HARNESS_DIR/dashboard.html` and prints a text summary. Capture and show the summary.

## Step 3: Open in browser

```bash
open "${HARNESS_DIR}/dashboard.html" 2>/dev/null \
  || xdg-open "${HARNESS_DIR}/dashboard.html" 2>/dev/null \
  || echo "Open ${HARNESS_DIR}/dashboard.html in your browser"
```

## Step 4: Report to the user

Tell the user:
- The dashboard was opened (or give the path to open manually)
- The text summary from Step 2 (workflow status, phase counts)
- If any phase is `failed`, highlight it

## Live monitoring

If the user wants the dashboard to refresh automatically while a run is in progress:

> Run `/loop 30s /harness:dashboard` to refresh every 30 seconds.
