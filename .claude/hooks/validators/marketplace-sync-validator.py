#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

"""
PostToolUse Hook: Marketplace Sync Validator

Ensures plugin versions in plugin.json match marketplace.json.
Critical for maintaining version consistency across the marketplace.

Validates:
- Plugin exists in marketplace.json
- Plugin version matches between plugin.json and marketplace.json
- Marketplace version is bumped when plugin versions change

Runs automatically after Edit/Write on plugin.json or marketplace.json.
"""

import json
import subprocess
import sys
from pathlib import Path
from datetime import datetime

LOG_FILE = Path(__file__).parent / "marketplace-sync-validator.log"


def log(message: str):
    """Log message to file for debugging."""
    timestamp = datetime.now().strftime("%H:%M:%S")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] {message}\n")


def get_marketplace_root() -> Path:
    """Get marketplace root directory."""
    # __file__ -> validators/ -> hooks/ -> .claude/ -> marketplace root
    return Path(__file__).parent.parent.parent.parent


def load_json_file(file_path: Path) -> dict | None:
    """Load and parse JSON file."""
    try:
        with open(file_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        log(f"ERROR: Failed to load {file_path}: {e}")
        return None


def validate_marketplace_sync(file_path: Path) -> list[str]:
    """
    Validate version synchronization between plugin.json and marketplace.json.

    Returns list of error messages (empty if valid).
    """
    errors = []
    marketplace_root = get_marketplace_root()

    # Determine if this is a plugin.json or marketplace.json
    is_plugin_json = file_path.name == "plugin.json"
    is_marketplace_json = file_path.name == "marketplace.json"

    if not (is_plugin_json or is_marketplace_json):
        return errors  # Not relevant

    # Load marketplace.json
    marketplace_json_path = marketplace_root / ".claude-plugin" / "marketplace.json"
    marketplace_data = load_json_file(marketplace_json_path)

    if not marketplace_data:
        errors.append("Cannot load marketplace.json for version sync validation")
        return errors

    marketplace_plugins = {
        p["name"]: p["version"]
        for p in marketplace_data.get("plugins", [])
    }

    if is_plugin_json:
        # Validate plugin.json against marketplace.json
        plugin_data = load_json_file(file_path)
        if not plugin_data:
            return ["Cannot load plugin.json for validation"]

        plugin_name = plugin_data.get("name")
        plugin_version = plugin_data.get("version")

        if not plugin_name or not plugin_version:
            return ["Plugin name or version missing"]

        # Check if plugin exists in marketplace
        if plugin_name not in marketplace_plugins:
            errors.append(
                f"Plugin '{plugin_name}' not found in marketplace.json. "
                f"Add it to .claude-plugin/marketplace.json"
            )
            return errors

        # Check version match
        marketplace_version = marketplace_plugins[plugin_name]
        if plugin_version != marketplace_version:
            errors.append(
                f"Version mismatch for '{plugin_name}':\n"
                f"  • plugin.json: {plugin_version}\n"
                f"  • marketplace.json: {marketplace_version}\n"
                f"\n💡 Update marketplace.json to match plugin.json version"
            )

    elif is_marketplace_json:
        # Validate marketplace.json against all plugin.json files
        marketplace_data = load_json_file(file_path)
        if not marketplace_data:
            return ["Cannot load marketplace.json for validation"]

        # Check each plugin in marketplace.json
        for plugin_entry in marketplace_data.get("plugins", []):
            plugin_name = plugin_entry.get("name")
            marketplace_version = plugin_entry.get("version")

            if not plugin_name:
                continue

            # Find corresponding plugin.json
            plugin_json_path = marketplace_root / plugin_name / ".claude-plugin" / "plugin.json"

            if not plugin_json_path.exists():
                errors.append(f"Plugin manifest not found for '{plugin_name}' at {plugin_json_path}")
                continue

            plugin_data = load_json_file(plugin_json_path)
            if not plugin_data:
                continue

            plugin_version = plugin_data.get("version")

            if plugin_version != marketplace_version:
                errors.append(
                    f"Version mismatch for '{plugin_name}':\n"
                    f"  • plugin.json: {plugin_version}\n"
                    f"  • marketplace.json: {marketplace_version}\n"
                    f"\n💡 Sync versions between plugin.json and marketplace.json"
                )

        # Check marketplace top-level version was bumped when plugin versions changed
        errors.extend(validate_marketplace_version_bump(file_path, marketplace_root))

    return errors


def validate_marketplace_version_bump(file_path: Path, marketplace_root: Path) -> list[str]:
    """
    Detect marketplace top-level version drift.

    Compares the current marketplace.json against git HEAD to check if
    any plugin versions changed without bumping the marketplace version.
    """
    errors = []

    try:
        result = subprocess.run(
            ["git", "show", "HEAD:.claude-plugin/marketplace.json"],
            capture_output=True, text=True, cwd=marketplace_root, timeout=5
        )
        if result.returncode != 0:
            return errors  # No git history yet or file not tracked

        old_data = json.loads(result.stdout)
    except Exception:
        return errors  # Can't compare, skip

    new_data = load_json_file(file_path)
    if not new_data:
        return errors

    old_marketplace_version = old_data.get("version", "")
    new_marketplace_version = new_data.get("version", "")

    old_plugin_versions = {
        p["name"]: p["version"] for p in old_data.get("plugins", [])
    }
    new_plugin_versions = {
        p["name"]: p["version"] for p in new_data.get("plugins", [])
    }

    # Check if any plugin version changed
    plugin_versions_changed = old_plugin_versions != new_plugin_versions

    if plugin_versions_changed and old_marketplace_version == new_marketplace_version:
        changed = []
        for name in new_plugin_versions:
            old_v = old_plugin_versions.get(name)
            new_v = new_plugin_versions.get(name)
            if old_v != new_v:
                changed.append(f"{name}: {old_v} → {new_v}")

        errors.append(
            f"Marketplace top-level version not bumped after plugin changes:\n"
            f"  • marketplace.json version: {new_marketplace_version} (unchanged)\n"
            f"  • Changed plugins: {', '.join(changed)}\n"
            f"\n💡 Bump the marketplace 'version' field (currently {new_marketplace_version})"
        )

    return errors


def main():
    log("=" * 50)
    log("MARKETPLACE SYNC VALIDATOR (PostToolUse)")

    # Read hook input from stdin
    try:
        hook_input = json.loads(sys.stdin.read())
    except Exception as e:
        log(f"ERROR: Failed to parse hook input: {e}")
        sys.exit(1)

    # Extract file path
    tool_input = hook_input.get("tool_input", {})
    file_path_str = tool_input.get("file_path")

    if not file_path_str:
        log("WARNING: No file_path in tool_input, skipping validation")
        print(json.dumps({}))  # Pass
        return

    file_path = Path(file_path_str)
    log(f"File: {file_path}")

    # Only validate plugin.json or marketplace.json files
    if file_path.name not in ["plugin.json", "marketplace.json"]:
        log(f"SKIP: Not a plugin.json or marketplace.json file")
        print(json.dumps({}))  # Pass
        return

    log("Validating marketplace version synchronization...")

    # Perform validation
    errors = validate_marketplace_sync(file_path)

    # Output decision
    if errors:
        log(f"BLOCK: Found {len(errors)} error(s)")
        for error in errors:
            log(f"  - {error}")

        error_message = f"🔴 Marketplace version sync failed:\n\n"
        error_message += "\n".join(f"• {e}" for e in errors)

        print(json.dumps({
            "decision": "block",
            "reason": error_message
        }))
    else:
        log("PASS: Marketplace sync validation successful")
        print(json.dumps({}))  # Pass


if __name__ == "__main__":
    main()
