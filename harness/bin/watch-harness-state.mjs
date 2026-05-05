#!/usr/bin/env node
// Watch .harness/*.json and emit a one-line summary on each change.
// Used by harness/monitors/monitors.json — every stdout line becomes a
// notification to Claude, so the agent gets live phase progress without
// reading the dashboard.
//
// Usage: node watch-harness-state.mjs [harness_state_dir]

import { readFileSync, readdirSync, statSync, existsSync } from "fs";
import { join } from "path";

const HARNESS_DIR = process.argv[2] || ".harness";
const POLL_MS = 2000;

const seen = new Map(); // file path → last mtime ms

function summarize(path) {
  let state;
  try {
    state = JSON.parse(readFileSync(path, "utf-8"));
  } catch {
    return null; // mid-write, skip this tick
  }

  if (state.schema !== "harness/v1") return null;

  const plugin = state.plugin || "?";
  const phase = state.phase_id || "?";
  const status = state.status || "?";

  const parts = [`[harness] ${plugin}/${phase}`, `status=${status}`];

  if (state.progress) {
    parts.push(`${state.progress.current}/${state.progress.total} ${state.progress.unit}`);
  }

  if (state.metric && state.metric.current != null) {
    const direction = state.metric.direction === "lower" ? "↓" : "↑";
    parts.push(
      `${state.metric.name}=${state.metric.current}${direction} (best=${state.metric.best ?? "?"})`
    );
  }

  if (state.error?.message) {
    parts.push(`error: ${state.error.message.slice(0, 80)}`);
  }

  return parts.join(" ");
}

function tick() {
  if (!existsSync(HARNESS_DIR)) return;

  let files;
  try {
    files = readdirSync(HARNESS_DIR).filter((f) => f.endsWith(".json"));
  } catch {
    return;
  }

  for (const f of files) {
    const path = join(HARNESS_DIR, f);
    let mtime;
    try {
      mtime = statSync(path).mtimeMs;
    } catch {
      continue;
    }

    const last = seen.get(path);
    if (last === mtime) continue;

    // Skip first read so we don't flood notifications at startup
    if (last !== undefined) {
      const line = summarize(path);
      if (line) console.log(line);
    }

    seen.set(path, mtime);
  }
}

setInterval(tick, POLL_MS);

process.on("SIGTERM", () => process.exit(0));
process.on("SIGINT", () => process.exit(0));
