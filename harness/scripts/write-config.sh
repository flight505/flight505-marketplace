#!/usr/bin/env bash
# Write harness optimize config.json from stdin
# Usage: echo '{"version":1,...}' | bash write-config.sh

set -euo pipefail

CONFIG_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.harness}"
CONFIG_FILE="${CONFIG_DIR}/config.json"

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

config_json="$(cat)"

if ! echo "$config_json" | python3 -m json.tool > /dev/null 2>&1; then
    echo "ERROR: Invalid JSON" >&2
    exit 1
fi

tmp_file="${CONFIG_FILE}.tmp"
echo "$config_json" > "$tmp_file"
chmod 600 "$tmp_file"
mv "$tmp_file" "$CONFIG_FILE"

echo "Config saved to ${CONFIG_FILE}"
