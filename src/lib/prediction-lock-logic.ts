﻿/**
 * FOUCH 0.3A — pure decision logic split out of events-db.ts
 * specifically so it has NO "server-only" import and can be unit
 * tested directly (vitest's jsdom environment cannot import a
 * server-only-guarded module, the same reason prediction-validation.ts
 * only ever type-imports EventLockConfig rather than importing
 * events-db.ts's runtime code). events-db.ts re-exports both symbols
 * below unchanged, so every existing import site is unaffected.
 */
export interface EventLockConfig {
  predictionOpenAt: string | null;
  predictionLockAt: string | null;
}

/**
 * Given a lock config and the current SERVER time, decides whether
 * predictions/edits are currently allowed. Every real caller sources
 * `nowMs` from `Date.now()` on the server — never anything the client
 * supplies — per the frozen rule that client clocks must never be
 * trusted (brief §3/§20).
 */
export function isPredictionWindowOpen(config: EventLockConfig | null, nowMs: number): boolean {
  if (!config) return true; // No configured window — same as before 0.3A (unrestricted).
  if (config.predictionOpenAt && nowMs < Date.parse(config.predictionOpenAt)) return false;
  if (config.predictionLockAt && nowMs >= Date.parse(config.predictionLockAt)) return false;
  return true;
}
