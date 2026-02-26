#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

"""
PostToolUse Hook: TaskPlex Cross-Reference Validator

Catches orphaned references after renames/deletions in the taskplex plugin:
1. using-taskplex skill catalog → skills/ directories
2. hooks.json SubagentStart/Stop matchers → agents/ files
3. implementer.md frontmatter skills → skills/ directories

Triggers on edits to taskplex skill, agent, and hook files.
"""

import json
import re
import sys
from pathlib import Path
from datetime import datetime

LOG_FILE = Path(__file__).parent / "taskplex-crossrefs-validator.log"


def log(message: str):
    timestamp = datetime.now().strftime("%H:%M:%S")
    with open(LOG_FILE, "a") as f:
        f.write(f"[{timestamp}] {message}\n")


def get_marketplace_root() -> Path:
    return Path(__file__).parent.parent.parent.parent


def check_catalog_vs_skills(taskplex_root: Path) -> list[str]:
    """using-taskplex catalog table entries must have matching skills/ dirs."""
    errors = []
    using_file = taskplex_root / "skills" / "using-taskplex" / "SKILL.md"
    if not using_file.exists():
        return []

    text = using_file.read_text()
    # Only match table rows: "| `taskplex:skill-name` |"
    catalog_skills = set(re.findall(r'\| `taskplex:([a-z][-a-z]*)` \|', text))

    for skill in sorted(catalog_skills):
        skill_md = taskplex_root / "skills" / skill / "SKILL.md"
        if not skill_md.exists():
            errors.append(f"Catalog references 'taskplex:{skill}' but skills/{skill}/SKILL.md not found")

    return errors


def check_hook_matchers_vs_agents(taskplex_root: Path) -> list[str]:
    """SubagentStart/Stop matchers must have matching agents/*.md files."""
    errors = []
    hooks_file = taskplex_root / "hooks" / "hooks.json"
    if not hooks_file.exists():
        return []

    try:
        data = json.loads(hooks_file.read_text())
    except json.JSONDecodeError:
        return []

    hooks = data.get("hooks", {})
    matchers = set()
    for event in ("SubagentStart", "SubagentStop"):
        for entry in hooks.get(event, []):
            matcher = entry.get("matcher")
            if matcher:
                matchers.add(matcher)

    for matcher in sorted(matchers):
        agent_file = taskplex_root / "agents" / f"{matcher}.md"
        if not agent_file.exists():
            errors.append(f"Hook matcher '{matcher}' has no agents/{matcher}.md")

    return errors


def check_implementer_skills(taskplex_root: Path) -> list[str]:
    """Implementer frontmatter skills list must have matching skills/ dirs."""
    errors = []
    impl_file = taskplex_root / "agents" / "implementer.md"
    if not impl_file.exists():
        return []

    text = impl_file.read_text()

    # Extract YAML frontmatter between --- delimiters
    parts = text.split("---")
    if len(parts) < 3:
        return []
    frontmatter = parts[1]

    # Find skills list in frontmatter
    in_skills = False
    for line in frontmatter.splitlines():
        if line.strip() == "skills:":
            in_skills = True
            continue
        if in_skills:
            stripped = line.strip()
            if stripped.startswith("- "):
                skill = stripped[2:].strip()
                skill_md = taskplex_root / "skills" / skill / "SKILL.md"
                if not skill_md.exists():
                    errors.append(f"Implementer references skill '{skill}' but skills/{skill}/SKILL.md not found")
            elif stripped and not stripped.startswith("#"):
                break  # End of skills list

    return errors


def main():
    log("=" * 50)
    log("TASKPLEX CROSS-REFS VALIDATOR (PostToolUse)")

    try:
        hook_input = json.loads(sys.stdin.read())
    except Exception as e:
        log(f"ERROR: Failed to parse hook input: {e}")
        sys.exit(1)

    tool_input = hook_input.get("tool_input", {})
    file_path_str = tool_input.get("file_path")

    if not file_path_str:
        print(json.dumps({}))
        return

    file_path = Path(file_path_str)
    log(f"File: {file_path}")

    marketplace_root = get_marketplace_root()
    taskplex_root = marketplace_root / "taskplex"

    # Only trigger on taskplex files that could break cross-refs
    if "taskplex" not in file_path.parts:
        log("SKIP: Not a taskplex file")
        print(json.dumps({}))
        return

    relevant = (
        "SKILL.md" in file_path.name
        or "hooks.json" in file_path.name
        or (file_path.parent.name == "agents" and file_path.suffix == ".md")
        or file_path.name == "plugin.json"
    )
    if not relevant:
        log("SKIP: Not a cross-ref relevant file")
        print(json.dumps({}))
        return

    log("Running cross-reference checks...")

    errors = []
    errors.extend(check_catalog_vs_skills(taskplex_root))
    errors.extend(check_hook_matchers_vs_agents(taskplex_root))
    errors.extend(check_implementer_skills(taskplex_root))

    if errors:
        log(f"BLOCK: {len(errors)} cross-ref error(s)")
        for e in errors:
            log(f"  - {e}")

        msg = "Cross-reference integrity failed for taskplex:\n\n"
        msg += "\n".join(f"* {e}" for e in errors)

        print(json.dumps({"decision": "block", "reason": msg}))
    else:
        log("PASS: All cross-references valid")
        print(json.dumps({}))


if __name__ == "__main__":
    main()
