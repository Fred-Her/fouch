import { describe, expect, it, vi, beforeEach } from "vitest";

/**
 * Regression: a verified user's old DEMO prediction (Miss Universe 2026 launched as a demo
 * event) used to be treated as "your prediction for this event", so saving a real one sent them
 * to the demo page. Every identity/device lookup must now exclude data_status = 'demo'.
 */
const calls: Array<[string, string, unknown]> = [];

function chain(): unknown {
  const q: Record<string, unknown> = {};
  for (const m of ["select", "eq", "neq"]) {
    q[m] = (col: string, val: unknown) => {
      calls.push([m, col, val]);
      return q;
    };
  }
  q.maybeSingle = async () => ({ data: null, error: null });
  return q;
}

vi.mock("server-only", () => ({}));
vi.mock("@/lib/supabase/server", () => ({
  getSupabaseServerClient: () => ({ from: () => chain() }),
}));

import {
  getPredictionByAuthUserId,
  getPredictionByDeviceToken,
  getDeviceTokenIdentity,
} from "@/lib/predictions-db";

describe("demo predictions do not hold the event slot", () => {
  beforeEach(() => {
    calls.length = 0;
  });

  it.each([
    ["getPredictionByDeviceToken", () => getPredictionByDeviceToken("miss-universe-2026", "dev")],
    ["getPredictionByAuthUserId", () => getPredictionByAuthUserId("miss-universe-2026", "user")],
    ["getDeviceTokenIdentity", () => getDeviceTokenIdentity("miss-universe-2026", "dev")],
  ])("%s excludes data_status = demo", async (_name, run) => {
    await run();
    expect(calls).toContainEqual(["neq", "data_status", "demo"]);
  });
});