#!/usr/bin/env node
// Heartbeat daemon — keeps state files marked alive while a workflow is running.
//
// Each tick (1.5s default), updates running state files with:
//   - elapsed_seconds: wall-clock seconds since started_at
//   - last_heartbeat:  ISO timestamp of this tick (the liveness signal)
//   - heartbeat_pid:   this daemon's PID (for liveness detection)
//   - updated_at:      ISO now
//
// `last_heartbeat` is the canonical liveness signal. Hook scripts that read
// state files (see harness/hooks/_lib.sh::find_active_build_state) compare it
// to now — if older than HARNESS_STALE_THRESHOLD_SECONDS (default 600s), the
// state is treated as abandoned and the hook no-ops.
//
// Writes are atomic via .tmp + rename so concurrent readers see consistent
// JSON. Files without a `running` status are skipped.
//
// Usage: node heartbeat.mjs [harness_state_dir]
// Env:   HARNESS_HEARTBEAT_INTERVAL_MS (default 1500)

import { readFileSync, writeFileSync, renameSync, readdirSync, existsSync } from "fs";
import { join } from "path";

const HARNESS_DIR = process.argv[2] || ".harness";
const INTERVAL_MS = Number(process.env.HARNESS_HEARTBEAT_INTERVAL_MS) || 1500;
const PID = process.pid;

if (!existsSync(HARNESS_DIR)) {
  console.error(`[heartbeat] State dir not found: ${HARNESS_DIR}`);
  process.exit(1);
}

console.log(`[heartbeat] Watching ${HARNESS_DIR} every ${INTERVAL_MS}ms (pid=${PID})`);

function writeAtomic(path, obj) {
  const tmp = path + ".tmp";
  writeFileSync(tmp, JSON.stringify(obj, null, 2), "utf-8");
  renameSync(tmp, path);
}

function tick() {
  let files;
  try {
    files = readdirSync(HARNESS_DIR).filter((f) => f.endsWith(".json"));
  } catch {
    return;
  }

  const nowIso = new Date().toISOString();
  const now = Date.now();

  for (const file of files) {
    const filePath = join(HARNESS_DIR, file);
    try {
      const raw = readFileSync(filePath, "utf-8");
      const state = JSON.parse(raw);

      if (state.status !== "running" || !state.started_at) continue;

      const startedAt = new Date(state.started_at).getTime();
      const elapsed = Math.floor((now - startedAt) / 1000);

      state.elapsed_seconds = elapsed;
      state.last_heartbeat = nowIso;
      state.heartbeat_pid = PID;
      state.updated_at = nowIso;

      writeAtomic(filePath, state);
    } catch {
      // skip invalid files or write conflicts
    }
  }
}

setInterval(tick, INTERVAL_MS);

// Graceful shutdown — clear last_heartbeat to mark state as no-longer-live.
function shutdown() {
  try {
    const files = readdirSync(HARNESS_DIR).filter((f) => f.endsWith(".json"));
    for (const file of files) {
      const filePath = join(HARNESS_DIR, file);
      try {
        const state = JSON.parse(readFileSync(filePath, "utf-8"));
        if (state.heartbeat_pid !== PID) continue;
        delete state.heartbeat_pid;
        state.updated_at = new Date().toISOString();
        writeAtomic(filePath, state);
      } catch { /* ignore */ }
    }
  } catch { /* ignore */ }
  process.exit(0);
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
