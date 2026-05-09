#!/usr/bin/env python3
"""Atomic state-file mutator for harness build-state files.

Replaces the bash → python heredoc pattern in harness/hooks/_lib.sh::mutate_state
with named operations. Each op is a documented mutation with a stable CLI;
the heredoc-style "embedded snippet" approach is gone. Tests cover each op.

Usage:
    state-mutate.py mark-task-completed <state-file> <task-id> [teammate-name]
        Mark <task-id> as completed in output.tasks, set completed_by, and
        update progress.{current,total} + output.stories_{completed,total}.

    state-mutate.py record-teammate-status <state-file> <name> <agent-type> <status> [team-name]
        Find or append a teammate in teammates[]. Set status. Optionally
        update top-level team_name.

Writes are atomic via .tmp + os.replace. Always updates state.updated_at.

Exit codes:
    0  success
    1  state file missing or unparseable, or unknown op
    2  bad arguments
"""
import json
import os
import sys
import datetime
from pathlib import Path


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def load_state(path):
    p = Path(path)
    if not p.exists():
        print(f"state file not found: {path}", file=sys.stderr)
        sys.exit(1)
    try:
        return json.loads(p.read_text())
    except json.JSONDecodeError as e:
        print(f"state file not valid JSON: {path}: {e}", file=sys.stderr)
        sys.exit(1)


def save_state(path, state):
    state["updated_at"] = now_iso()
    tmp = str(path) + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, path)


def op_mark_task_completed(args):
    if len(args) < 2:
        print("usage: mark-task-completed <state-file> <task-id> [teammate-name]", file=sys.stderr)
        sys.exit(2)
    state_file, task_id = args[0], args[1]
    teammate = args[2] if len(args) > 2 else None

    state = load_state(state_file)
    output = state.setdefault("output", {})
    tasks = output.setdefault("tasks", {})
    if task_id in tasks:
        tasks[task_id]["status"] = "completed"
        tasks[task_id]["completed_by"] = teammate

    completed = sum(1 for t in tasks.values() if t.get("status") == "completed")
    progress = state.setdefault("progress", {"current": 0, "total": len(tasks), "unit": "stories"})
    progress["current"] = completed
    if progress.get("total", 0) == 0:
        progress["total"] = len(tasks)
    output["stories_completed"] = completed
    output["stories_total"] = progress["total"]

    save_state(state_file, state)


def op_record_teammate_status(args):
    if len(args) < 4:
        print("usage: record-teammate-status <state-file> <name> <agent-type> <status> [team-name]",
              file=sys.stderr)
        sys.exit(2)
    state_file, name, agent_type, status = args[0], args[1], args[2], args[3]
    team_name = args[4] if len(args) > 4 else None

    state = load_state(state_file)
    teammates = state.setdefault("teammates", [])
    found = False
    for m in teammates:
        if m.get("name") == name:
            m["status"] = status
            m["agent_type"] = agent_type
            found = True
            break
    if not found:
        teammates.append({
            "name": name,
            "agent_type": agent_type,
            "status": status,
            "tasks_completed": 0,
        })
    if team_name:
        state["team_name"] = team_name

    save_state(state_file, state)


def op_add_task(args):
    if len(args) < 3:
        print("usage: add-task <state-file> <task-id> <task-subject>", file=sys.stderr)
        sys.exit(2)
    state_file, task_id, subject = args[0], args[1], args[2]
    state = load_state(state_file)
    tasks = state.setdefault("output", {}).setdefault("tasks", {})
    tasks[task_id] = {"subject": subject, "status": "pending"}
    progress = state.setdefault("progress", {"current": 0, "total": 0, "unit": "stories"})
    progress["total"] = max(progress.get("total", 0), len(tasks))
    save_state(state_file, state)


OPS = {
    "mark-task-completed": op_mark_task_completed,
    "record-teammate-status": op_record_teammate_status,
    "add-task": op_add_task,
}


def main(argv):
    if len(argv) < 2:
        print(f"usage: state-mutate.py <op> [args...]\n  ops: {', '.join(OPS)}", file=sys.stderr)
        sys.exit(2)
    op = argv[1]
    fn = OPS.get(op)
    if not fn:
        print(f"unknown op: {op}\n  available: {', '.join(OPS)}", file=sys.stderr)
        sys.exit(1)
    fn(argv[2:])


if __name__ == "__main__":
    main(sys.argv)
