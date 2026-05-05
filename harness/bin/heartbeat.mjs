#!/usr/bin/env node
// Heartbeat daemon — updates elapsed_seconds in running state files every 1.5s
// Usage: node heartbeat.mjs [harness_state_dir]

import { readFileSync, writeFileSync, readdirSync, existsSync } from "fs";
import { join } from "path";

const HARNESS_DIR = process.argv[2] || ".harness";
const INTERVAL_MS = 1500;

if (!existsSync(HARNESS_DIR)) {
  console.error(`[heartbeat] State dir not found: ${HARNESS_DIR}`);
  process.exit(1);
}

console.log(`[heartbeat] Watching ${HARNESS_DIR} every ${INTERVAL_MS}ms`);

function tick() {
  let files;
  try {
    files = readdirSync(HARNESS_DIR).filter((f) => f.endsWith(".json"));
  } catch {
    return;
  }

  for (const file of files) {
    const filePath = join(HARNESS_DIR, file);
    try {
      const raw = readFileSync(filePath, "utf-8");
      const state = JSON.parse(raw);

      if (state.status !== "running" || !state.started_at) continue;

      const startedAt = new Date(state.started_at).getTime();
      const now = Date.now();
      const elapsed = Math.floor((now - startedAt) / 1000);

      state.elapsed_seconds = elapsed;
      state.updated_at = new Date().toISOString();

      writeFileSync(filePath, JSON.stringify(state, null, 2), "utf-8");
    } catch {
      // skip invalid files or write conflicts
    }
  }
}

setInterval(tick, INTERVAL_MS);

// Graceful shutdown
process.on("SIGTERM", () => process.exit(0));
process.on("SIGINT", () => process.exit(0));
