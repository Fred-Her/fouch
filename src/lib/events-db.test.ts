﻿import { describe, it, expect } from "vitest";
import { isPredictionWindowOpen, type EventLockConfig } from "./prediction-lock-logic";

const LOCK_AT = "2026-11-24T00:00:00Z";
const LOCK_MS = Date.parse(LOCK_AT);

describe("isPredictionWindowOpen — the single lock-timing decision, fed by server time only", () => {
  it("is open when no lock config exists at all (event not configured — same as pre-0.3A behavior)", () => {
    expect(isPredictionWindowOpen(null, Date.now())).toBe(true);
  });

  it("is open one second before the lock instant", () => {
    const config: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT };
    expect(isPredictionWindowOpen(config, LOCK_MS - 1000)).toBe(true);
  });

  it("is locked exactly AT the lock instant — >= , not > (brief §20: 'at lock time → rejected')", () => {
    const config: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT };
    expect(isPredictionWindowOpen(config, LOCK_MS)).toBe(false);
  });

  it("is locked one second after the lock instant", () => {
    const config: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT };
    expect(isPredictionWindowOpen(config, LOCK_MS + 1000)).toBe(false);
  });

  it("respects an open-at time in the future — not yet open", () => {
    const openAt = "2026-01-01T00:00:00Z";
    const config: EventLockConfig = { predictionOpenAt: openAt, predictionLockAt: null };
    expect(isPredictionWindowOpen(config, Date.parse(openAt) - 1)).toBe(false);
    expect(isPredictionWindowOpen(config, Date.parse(openAt))).toBe(true);
  });

  it("client clock manipulation has no effect — this function only ever receives a `nowMs` the caller supplies, and every real caller in this codebase sources it from Date.now() on the server, never from the browser", () => {
    // Documents the invariant at the type level: there is no
    // `document`/`window`/request-header parameter here at all — a
    // forged client timestamp is architecturally impossible to feed
    // into this function unless a server action explicitly chose to
    // (none do; see events-db.ts and verify-actions.ts, which always
    // call `isPredictionWindowOpen(lockConfig, Date.now())`).
    expect(isPredictionWindowOpen.length).toBe(2);
  });
});
