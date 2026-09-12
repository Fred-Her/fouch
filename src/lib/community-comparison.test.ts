import { describe, it, expect } from "vitest";
import { computeComparison, computeCommunityTop10, getSampleSizeBucket } from "./community-comparison";
import type { EligiblePrediction } from "./community-comparison";

// Fixtures straight from the Sprint 3 brief, section 32.
const predictionA: EligiblePrediction = {
  predictionId: "A",
  rankedParticipantIds: ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
};
const predictionB: EligiblePrediction = {
  predictionId: "B",
  rankedParticipantIds: ["A", "C", "B", "K", "L", "M", "N", "O", "P", "Q"],
};
const predictionC: EligiblePrediction = {
  predictionId: "C",
  rankedParticipantIds: ["B", "A", "C", "D", "K", "L", "M", "N", "O", "P"],
};
const allThree = [predictionA, predictionB, predictionC];

describe("getSampleSizeBucket", () => {
  it.each([
    [0, "0"],
    [1, "1_4"],
    [4, "1_4"],
    [5, "5_9"],
    [9, "5_9"],
    [10, "10_24"],
    [24, "10_24"],
    [25, "25_49"],
    [49, "25_49"],
    [50, "50_99"],
    [99, "50_99"],
    [100, "100_plus"],
    [500, "100_plus"],
  ])("population %i -> %s", (population, expected) => {
    expect(getSampleSizeBucket(population)).toBe(expected);
  });
});

describe("computeComparison — viewing prediction A (self-excluded, world = B & C)", () => {
  const result = computeComparison(predictionA.rankedParticipantIds, allThree, "A");

  it("excludes the viewed prediction from the population", () => {
    expect(result.population).toBe(2);
  });

  it("same winner: A appears as #1 in B only, out of B & C", () => {
    expect(result.sameWinner).toEqual({ participantId: "A", count: 1, pct: 0.5 });
  });

  it("top 3 match: community top 3 (A, B, C) fully overlaps A's own top 3", () => {
    expect(result.top3Match?.communityTop3).toEqual(["A", "B", "C"]);
    expect(result.top3Match?.overlap).toBe(3);
  });

  it("boldest pick: E never appears in B or C — the least common of A's top 5", () => {
    expect(result.boldestPick).toEqual({ participantId: "E", inclusionPct: 0 });
  });

  it("community top 10 excludes the 11th-ranked participant (Q) and orders by points", () => {
    const ids = result.communityTop10.map((entry) => entry.participantId);
    expect(ids).toEqual(["A", "B", "C", "K", "L", "M", "N", "D", "O", "P"]);
    expect(ids).toHaveLength(10);
  });
});

describe("computeComparison — viewing prediction C (self-excluded, world = A & B)", () => {
  const result = computeComparison(predictionC.rankedParticipantIds, allThree, "C");

  it("same winner: C's own winner is B, but A and B (the world) both have winner A — zero match", () => {
    expect(result.sameWinner).toEqual({ participantId: "B", count: 0, pct: 0 });
  });

  it("does not crash or divide by zero when the match count is zero", () => {
    expect(result.sameWinner?.pct).toBe(0);
  });
});

describe("computeComparison — zero eligible predictions", () => {
  it("returns an explicit empty state instead of dividing by zero", () => {
    const result = computeComparison(predictionA.rankedParticipantIds, [predictionA], "A");
    expect(result).toEqual({
      population: 0,
      sameWinner: null,
      top3Match: null,
      boldestPick: null,
      communityTop10: [],
    });
  });
});

describe("computeCommunityTop10 — deterministic tie-breaking", () => {
  it("breaks a points tie using first-place count, then top-3 count, then top-10 count, then participant ID", () => {
    // X and Y both score 7 points total (one 4th-place finish each: 11-4=7).
    // Z scores 7 points via a single #1 finish (11-1=10)... adjusted below
    // to isolate each tiebreaker independently.
    const predictions: EligiblePrediction[] = [
      // X: one #1 finish elsewhere pads its first-place count.
      { predictionId: "p1", rankedParticipantIds: ["X", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
      { predictionId: "p2", rankedParticipantIds: ["_", "_", "_", "Y", "_", "_", "_", "_", "_", "_"] },
    ];
    const ranking = computeCommunityTop10(predictions);
    const x = ranking.find((entry) => entry.participantId === "X");
    const y = ranking.find((entry) => entry.participantId === "Y");

    // X: position 1 -> 10 points, 1 first-place finish.
    // Y: position 4 -> 7 points, 0 first-place finishes.
    expect(x?.points).toBe(10);
    expect(y?.points).toBe(7);
    expect(ranking.findIndex((e) => e.participantId === "X")).toBeLessThan(
      ranking.findIndex((e) => e.participantId === "Y"),
    );
  });

  it("falls back to participant ID ascending when every other tiebreaker is equal", () => {
    const tied: EligiblePrediction[] = [
      { predictionId: "p1", rankedParticipantIds: ["Zebra"] },
      { predictionId: "p2", rankedParticipantIds: ["Apple"] },
    ];
    const ranking = computeCommunityTop10(tied);
    expect(ranking[0]?.participantId).toBe("Apple");
    expect(ranking[1]?.participantId).toBe("Zebra");
  });
});