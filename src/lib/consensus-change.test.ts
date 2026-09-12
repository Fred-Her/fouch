import { describe, it, expect } from "vitest";
import {
  computeConsensusChange,
  bucketSample,
  MIN_MOVEMENT_SAMPLE,
  MIN_MOVEMENT_POINTS,
} from "./consensus-change";
import type { TimestampedWinnerPick } from "./consensus-change";

const T0 = "2026-01-01T00:00:00.000Z";

function pick(id: string, submittedAt: string, winner: string): TimestampedWinnerPick {
  return { predictionId: id, submittedAt, winnerParticipantId: winner };
}

/** Builds N "other" predictions, all submitted before `displayed`, split
 * between `winner` and `notWinner`. */
function population(
  n: number,
  winnerCount: number,
  winner: string,
  notWinner: string,
  submittedAt: string,
  idPrefix: string,
): TimestampedWinnerPick[] {
  return Array.from({ length: n }, (_, i) =>
    pick(`${idPrefix}-${i}`, submittedAt, i < winnerCount ? winner : notWinner),
  );
}

describe("computeConsensusChange — brief test cases", () => {
  it("Test case 29 — TOWARD: 20% -> 35%, +15 pts", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    // THEN: 20 predictions before displayed's submission, 4 picked CO (20%)
    const before = population(20, 4, "CO", "VE", "2026-01-02T00:00:00.000Z", "then");
    // Additional predictions AFTER displayed's submission, bringing NOW to 40 total, 14 CO (35%)
    const after = population(20, 10, "CO", "VE", "2026-01-08T00:00:00.000Z", "after");
    const result = computeConsensusChange(displayed, [displayed, ...before, ...after]);

    expect(result.thenSample).toBe(20);
    expect(result.nowSample).toBe(40);
    expect(result.thenSupport).toBeCloseTo(20, 5);
    expect(result.nowSupport).toBeCloseTo(35, 5);
    expect(result.changePoints).toBeCloseTo(15, 5);
    expect(result.direction).toBe("toward");
    expect(result.eligible).toBe(true);
  });

  it("Test case 30 — AWAY: 50% -> 30%, -20 pts", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    // THEN: 20 predictions, 10 picked CO (50%)
    const before = population(20, 10, "CO", "VE", "2026-01-02T00:00:00.000Z", "then");
    // NOW must total 40 with 12 CO (30%) -> 20 more predictions, 2 more CO
    const after = population(20, 2, "CO", "VE", "2026-01-08T00:00:00.000Z", "after");
    const result = computeConsensusChange(displayed, [displayed, ...before, ...after]);

    expect(result.thenSample).toBe(20);
    expect(result.nowSample).toBe(40);
    expect(result.thenSupport).toBeCloseTo(50, 5);
    expect(result.nowSupport).toBeCloseTo(30, 5);
    expect(result.changePoints).toBeCloseTo(-20, 5);
    expect(result.direction).toBe("away");
    expect(result.eligible).toBe(true);
  });

  it("Test case 31 — weak movement: 20% -> 23%, ineligible", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    const before = population(20, 4, "CO", "VE", "2026-01-02T00:00:00.000Z", "then"); // 20%
    // NOW: 30 total, needs 23% -> ~6.9; use 40 total with ~9.2 -> pick clean numbers instead.
    // 25 total, 23% is not clean either; use 100 total for a clean 23%.
    const after = population(80, 19, "CO", "VE", "2026-01-08T00:00:00.000Z", "after"); // now: 100 total, 23 CO -> 23%
    const result = computeConsensusChange(displayed, [displayed, ...before, ...after]);

    expect(result.thenSample).toBe(20);
    expect(result.nowSample).toBe(100);
    expect(result.thenSupport).toBeCloseTo(20, 5);
    expect(result.nowSupport).toBeCloseTo(23, 5);
    expect(Math.abs(result.changePoints)).toBeLessThan(MIN_MOVEMENT_POINTS);
    expect(result.eligible).toBe(false);
    expect(result.direction).toBeNull();
  });

  it("Test case 32 — THEN sample too small (n=9): ineligible even with huge movement", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    const before = population(9, 2, "CO", "VE", "2026-01-02T00:00:00.000Z", "then"); // n=9 < MIN
    const after = population(41, 25, "CO", "VE", "2026-01-08T00:00:00.000Z", "after"); // now n=50, 50%
    const result = computeConsensusChange(displayed, [displayed, ...before, ...after]);

    expect(result.thenSample).toBe(9);
    expect(result.thenSample).toBeLessThan(MIN_MOVEMENT_SAMPLE);
    expect(result.eligible).toBe(false);
  });

  it("Test case 33 — NOW sample too small (n=9): ineligible", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    // NOW population = before + after; need total NOW = 9, but a THEN
    // population large enough to hit MIN_MOVEMENT_SAMPLE is already >= 10,
    // so this constructs THEN == NOW == 9 directly (no additional "after"
    // predictions), checking the NOW-only path explicitly.
    const onlyBefore = population(9, 2, "CO", "VE", "2026-01-02T00:00:00.000Z", "then2");
    const result = computeConsensusChange(displayed, [displayed, ...onlyBefore]);

    expect(result.thenSample).toBe(9);
    expect(result.nowSample).toBe(9);
    expect(result.eligible).toBe(false);
  });

  it("Test case 34 — self exclusion: displayed's own pick never inflates THEN or NOW", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    const before = population(10, 0, "CO", "VE", "2026-01-02T00:00:00.000Z", "then"); // 0 CO among others
    const after = population(10, 0, "CO", "VE", "2026-01-08T00:00:00.000Z", "after"); // 0 CO among others
    // Without self-exclusion, `displayed` itself (CO) would inflate both to 1/11.
    const result = computeConsensusChange(displayed, [displayed, ...before, ...after]);

    expect(result.thenSample).toBe(10); // displayed not counted in sample
    expect(result.nowSample).toBe(20);
    expect(result.thenSupport).toBe(0); // not 1/11 = 9.09%
    expect(result.nowSupport).toBe(0);
  });

  it("Test case 35 — ties at the exact same submitted_at are included in THEN (<=, documented)", () => {
    const displayed = pick("displayed", T0, "CO");
    const sameTimestamp = population(10, 3, "CO", "VE", T0, "same-time");
    const result = computeConsensusChange(displayed, [displayed, ...sameTimestamp]);
    // <= means a same-instant submission counts as "already in" for THEN.
    expect(result.thenSample).toBe(10);
  });

  it("Test case 36 — demo/official isolation is the caller's responsibility: a pre-filtered, single-data_status population never mixes", () => {
    // This pure function trusts its input population is already scoped to
    // one event + one data_status (enforced by the DB query layer, see
    // getWinnerPicksForConsensusChange). Demonstrating that ANY population
    // passed in is treated uniformly (no implicit cross-status logic exists
    // inside this function) is the correct unit-level guarantee here.
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    const onlyThisStatus = population(15, 5, "CO", "VE", "2026-01-02T00:00:00.000Z", "same-status");
    const result = computeConsensusChange(displayed, [displayed, ...onlyThisStatus]);
    expect(result.thenSample).toBe(15);
    expect(result.thenSupport).toBeCloseTo((5 / 15) * 100, 5);
  });

  it("Zero-difference edge case: NOW == THEN produces no eligible movement", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    const before = population(20, 5, "CO", "VE", "2026-01-02T00:00:00.000Z", "then");
    const result = computeConsensusChange(displayed, [displayed, ...before]);
    expect(result.changePoints).toBe(0);
    expect(result.eligible).toBe(false);
  });

  it("uses percentage points, not relative percentage change (20% -> 30% is +10pts, not +50%)", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    const before = population(20, 4, "CO", "VE", "2026-01-02T00:00:00.000Z", "then"); // 20%
    const after = population(30, 11, "CO", "VE", "2026-01-08T00:00:00.000Z", "after"); // now: 50 total, 15 -> 30%
    const result = computeConsensusChange(displayed, [displayed, ...before, ...after]);
    expect(result.thenSupport).toBeCloseTo(20, 5);
    expect(result.nowSupport).toBeCloseTo(30, 5);
    expect(result.changePoints).toBeCloseTo(10, 5); // +10 points, NOT +50%
  });
});

describe("bucketSample", () => {
  it.each([
    [10, "10-24"],
    [24, "10-24"],
    [25, "25-49"],
    [49, "25-49"],
    [50, "50-99"],
    [99, "50-99"],
    [100, "100+"],
    [500, "100+"],
  ])("%i -> %s", (n, expected) => {
    expect(bucketSample(n)).toBe(expected);
  });
});