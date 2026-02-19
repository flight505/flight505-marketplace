#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

"""
PostToolUse Hook: Plugin Manifest Validator

Automatically validates plugin.json files after Edit/Write operations.
Replaces manual validate-plugin-manifests.sh script with automatic validation.

Validates:
- JSON syntax
- Required fields (name, version, description, author)
- Version format (semantic versioning)
- Author structure (must be object with name and url)
- Plugin name matches submodule directory name
- Skills path format (must start with ./)
- Agents path format (must start with ./ and end with .md)
- Commands path format
- Hooks file existence
- File/directory existence

This validator runs automatically - Claude sees errors and fixes them immediately.
"""

import json
import sys
import re
from pathlib import Path
from datetime import datetime

LOG_FILE = Path(__file__).parent / "plugin-manifest-validator.log"

# Plugin directory mapping
PLUGIN_DIRS = {
    "sdk-bridge": "sdk-bridge",
    "taskplex": "taskplex",
    "storybook-assistant": "storybook-assistant",
    "claude-project-planner": "claude-project-planner",
    "nano-banana": "nano-banana",
}


def log(message: str):
    """Log message to file for debugging."""
    timestamp = datetime.now().strftime("%H:%M:%S")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] {message}\n")


def get_marketplace_root() -> Path:
    """Get marketplace root directory."""
    # Go up from .claude/hooks/validators/ to marketplace root
    # __file__ -> validators/ -> hooks/ -> .claude/ -> marketplace root
    return Path(__file__).parent.parent.parent.parent


def get_plugin_dir(plugin_name: str) -> str:
    """Get plugin directory path (handles nested structure)."""
    return PLUGIN_DIRS.get(plugin_name, plugin_name)


def validate_json_syntax(file_path: Path) -> list[str]:
    """Validate JSON syntax."""
    errors = []
    try:
        with open(file_path, 'r') as f:
            json.load(f)
    except json.JSONDecodeError as e:
        errors.append(f"Invalid JSON syntax: {e}")
    except Exception as e:
        errors.append(f"Error reading file: {e}")
    return errors


def validate_required_fields(data: dict) -> list[str]:
    """Validate required fields exist."""
    errors = []
    required_fields = ["name", "version", "description", "author"]

    for field in required_fields:
        if field not in data:
            errors.append(f"Missing required field: {field}")
        elif not data[field]:
            errors.append(f"Required field '{field}' is empty")

    return errors


def validate_version_format(data: dict) -> list[str]:
    """Validate semantic versioning format."""
    errors = []
    version = data.get("version", "")

    if not re.match(r'^\d+\.\d+\.\d+$', version):
        errors.append(
            f"Invalid version format '{version}' - expected semantic versioning (X.Y.Z)"
        )

    return errors


def validate_skills_format(data: dict, plugin_name: str, marketplace_root: Path) -> list[str]:
    """Validate skills array format and paths."""
    errors = []

    if "skills" not in data:
        return errors  # Skills are optional

    skills = data["skills"]
    if not isinstance(skills, list):
        return [f"'skills' must be an array"]

    plugin_dir = get_plugin_dir(plugin_name)

    for skill in skills:
        # Check relative path format
        if not skill.startswith("./"):
            errors.append(
                f"Skill '{skill}' must be a relative path starting with './' "
                f"(e.g., './skills/{skill.lstrip('./')}')"
            )
            continue

        # Check if directory exists
        skill_path = marketplace_root / plugin_dir / skill.lstrip("./")
        if not skill_path.exists():
            errors.append(f"Skill directory not found: {skill}")
            continue

        # Check for SKILL.md
        skill_md = skill_path / "SKILL.md"
        if not skill_md.exists():
            errors.append(f"Missing SKILL.md in skill: {skill}")

    return errors


def validate_agents_format(data: dict, plugin_name: str, marketplace_root: Path) -> list[str]:
    """Validate agents array format and paths."""
    errors = []

    if "agents" not in data:
        return errors  # Agents are optional

    agents = data["agents"]
    if not isinstance(agents, list):
        return [f"'agents' must be an array"]

    plugin_dir = get_plugin_dir(plugin_name)

    for agent in agents:
        # Check relative path format
        if not agent.startswith("./"):
            errors.append(
                f"Agent '{agent}' must be a relative path starting with './' "
                f"(e.g., './agents/{agent.lstrip('./')}')"
            )
            continue

        # Check .md extension
        if not agent.endswith(".md"):
            errors.append(f"Agent '{agent}' must end with '.md'")
            continue

        # Check if file exists
        agent_path = marketplace_root / plugin_dir / agent.lstrip("./")
        if not agent_path.exists():
            errors.append(f"Agent file not found: {agent}")

    return errors


def validate_author_structure(data: dict) -> list[str]:
    """Validate author field is an object with name and url."""
    errors = []
    author = data.get("author")

    if author is None:
        return errors  # Caught by validate_required_fields

    if not isinstance(author, dict):
        errors.append(
            f"'author' must be an object with 'name' and 'url' fields, "
            f"got {type(author).__name__}"
        )
        return errors

    if "name" not in author or not author["name"]:
        errors.append("'author.name' is required and must not be empty")

    if "url" not in author or not author["url"]:
        errors.append("'author.url' is required and must not be empty")

    return errors


def validate_hooks_format(data: dict, plugin_name: str, marketplace_root: Path) -> list[str]:
    """Validate hooks field — check that referenced files exist."""
    errors = []

    if "hooks" not in data:
        return errors  # Hooks are optional

    hooks = data["hooks"]
    plugin_dir = get_plugin_dir(plugin_name)

    if isinstance(hooks, str):
        # String path to a hooks config file
        hooks_path = marketplace_root / plugin_dir / hooks.lstrip("./")
        if not hooks_path.exists():
            errors.append(f"Hooks config file not found: {hooks}")
    elif isinstance(hooks, dict):
        # Inline hooks object — no file path validation needed
        pass
    else:
        errors.append("'hooks' must be a string (file path) or object")

    return errors


def validate_name_matches_directory(data: dict, file_path: Path, marketplace_root: Path) -> list[str]:
    """Validate that plugin name matches the submodule directory name."""
    errors = []
    plugin_name = data.get("name", "")

    if not plugin_name:
        return errors  # Caught by validate_required_fields

    # Resolve the directory containing .claude-plugin/plugin.json
    # file_path is like: /path/to/marketplace/sdk-bridge/.claude-plugin/plugin.json
    # We want the submodule directory name relative to marketplace root
    try:
        relative = file_path.relative_to(marketplace_root)
        # relative is like: sdk-bridge/.claude-plugin/plugin.json
        dir_name = relative.parts[0]
    except (ValueError, IndexError):
        return errors  # Can't determine directory, skip check

    if plugin_name != dir_name:
        errors.append(
            f"Plugin name '{plugin_name}' does not match directory '{dir_name}'. "
            f"These must be identical for marketplace routing to work."
        )

    return errors


def validate_commands_format(data: dict, plugin_name: str, marketplace_root: Path) -> list[str]:
    """Validate commands format (can be string or array)."""
    errors = []

    if "commands" not in data:
        return errors  # Commands are optional

    commands = data["commands"]
    plugin_dir = get_plugin_dir(plugin_name)

    # Commands can be a string (directory) or array of files
    if isinstance(commands, str):
        # Check if directory exists
        commands_path = marketplace_root / plugin_dir / commands.lstrip("./")
        if not commands_path.exists():
            errors.append(f"Commands directory not found: {commands}")
    elif isinstance(commands, list):
        for command in commands:
            # Check relative path format
            if not command.startswith("./"):
                errors.append(
                    f"Command '{command}' should start with './' (recommended)"
                )
                continue

            # Check .md extension
            if not command.endswith(".md"):
                errors.append(f"Command '{command}' should end with '.md'")
                continue

            # Check if file exists
            command_path = marketplace_root / plugin_dir / command.lstrip("./")
            if not command_path.exists():
                errors.append(f"Command file not found: {command}")
    else:
        errors.append("'commands' must be a string (directory) or array of files")

    return errors


def validate_plugin_manifest(file_path: Path) -> list[str]:
    """
    Main validation function - validates all aspects of plugin.json.

    Returns list of error messages (empty if valid).
    """
    all_errors = []

    # 1. Validate JSON syntax
    syntax_errors = validate_json_syntax(file_path)
    if syntax_errors:
        return syntax_errors  # Can't continue if JSON is invalid

    # Load data
    with open(file_path, 'r') as f:
        data = json.load(f)

    # 2. Validate required fields
    all_errors.extend(validate_required_fields(data))

    # 3. Validate version format
    all_errors.extend(validate_version_format(data))

    # 4. Validate author structure
    all_errors.extend(validate_author_structure(data))

    # If basic validation failed, don't continue with path validation
    if all_errors:
        return all_errors

    # 5. Get plugin name and marketplace root
    plugin_name = data.get("name", "unknown")
    marketplace_root = get_marketplace_root()

    # 6. Validate name matches directory
    all_errors.extend(validate_name_matches_directory(data, file_path, marketplace_root))

    # 7. Validate skills format
    all_errors.extend(validate_skills_format(data, plugin_name, marketplace_root))

    # 8. Validate agents format
    all_errors.extend(validate_agents_format(data, plugin_name, marketplace_root))

    # 9. Validate commands format
    all_errors.extend(validate_commands_format(data, plugin_name, marketplace_root))

    # 10. Validate hooks format
    all_errors.extend(validate_hooks_format(data, plugin_name, marketplace_root))

    return all_errors


def main():
    log("=" * 50)
    log("PLUGIN MANIFEST VALIDATOR (PostToolUse)")

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

    # Only validate plugin.json files in .claude-plugin directories
    if file_path.name != "plugin.json":
        log(f"SKIP: Not a plugin.json file (name: {file_path.name})")
        print(json.dumps({}))  # Pass
        return

    if ".claude-plugin" not in file_path.parts:
        log(f"SKIP: Not in .claude-plugin directory")
        print(json.dumps({}))  # Pass
        return

    log("Validating plugin manifest...")

    # Perform validation
    errors = validate_plugin_manifest(file_path)

    # Output decision
    if errors:
        log(f"BLOCK: Found {len(errors)} error(s)")
        for error in errors:
            log(f"  - {error}")

        error_message = f"🔴 Plugin manifest validation failed for {file_path.name}:\n\n"
        error_message += "\n".join(f"• {e}" for e in errors)
        error_message += "\n\n💡 Fix these issues to ensure the plugin is correctly configured."

        print(json.dumps({
            "decision": "block",
            "reason": error_message
        }))
    else:
        log("PASS: Plugin manifest validation successful")
        print(json.dumps({}))  # Pass


if __name__ == "__main__":
    main()
