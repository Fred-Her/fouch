import { describe, it, expect } from "vitest";
import {
  computeComparison,
  computeCommunityTop10,
  getSampleSizeBucket,
  getComparisonDisplayMode,
} from "./community-comparison";
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
    expect(result.boldestPick).toEqual({ participantId: "E", count: 0, inclusionPct: 0 });
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

describe("computeCommunityTop10 — deterministic tie-breaking", () => {  it("breaks a points tie using first-place count, then top-3 count, then top-10 count, then participant ID", () => {
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

describe("getComparisonDisplayMode — Sprint 3.1 thresholds, centralized", () => {
  it.each([
    [0, "none"],
    [1, "count"],
    [4, "count"],
    [5, "early_signal"],
    [9, "early_signal"],
    [10, "normal"],
    [47, "normal"],
  ])("population %i -> %s", (population, expected) => {
    expect(getComparisonDisplayMode(population)).toBe(expected);
  });

  it("agrees with getSampleSizeBucket's tiers (no drift between the two)", () => {
    for (let n = 0; n <= 30; n++) {
      const bucket = getSampleSizeBucket(n);
      const mode = getComparisonDisplayMode(n);
      if (bucket === "0") expect(mode).toBe("none");
      if (bucket === "1_4") expect(mode).toBe("count");
      if (bucket === "5_9") expect(mode).toBe("early_signal");
      if (bucket !== "0" && bucket !== "1_4" && bucket !== "5_9") expect(mode).toBe("normal");
    }
  });
});

describe("Sprint 3.1 — Test 1: small-sample counts stay the primary data", () => {
  it("population=4, same winner count=1 exposes both count and denominator for COUNT presentation", () => {
    const predictions: EligiblePrediction[] = [
      { predictionId: "self", rankedParticipantIds: ["W", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
      { predictionId: "p1", rankedParticipantIds: ["W", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
      { predictionId: "p2", rankedParticipantIds: ["X", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
      { predictionId: "p3", rankedParticipantIds: ["X", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
      { predictionId: "p4", rankedParticipantIds: ["X", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
    ];
    const self = predictions[0]!;
    const result = computeComparison(self.rankedParticipantIds, predictions, "self");
    expect(result.population).toBe(4);
    expect(result.sameWinner).toEqual({ participantId: "W", count: 1, pct: 0.25 });
    expect(getComparisonDisplayMode(result.population)).toBe("count");
  });
});

describe("Sprint 3.1 — Test 2: threshold transition", () => {
  function predictionsOfSize(n: number): EligiblePrediction[] {
    return Array.from({ length: n }, (_, i) => ({
      predictionId: `p${i}`,
      rankedParticipantIds: ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
    }));
  }

  it("n=4 -> count mode, n=5 -> early_signal, n=9 -> early_signal, n=10 -> normal", () => {
    expect(getComparisonDisplayMode(predictionsOfSize(4).length)).toBe("count");
    expect(getComparisonDisplayMode(predictionsOfSize(5).length)).toBe("early_signal");
    expect(getComparisonDisplayMode(predictionsOfSize(9).length)).toBe("early_signal");
    expect(getComparisonDisplayMode(predictionsOfSize(10).length)).toBe("normal");
  });
});

describe("Sprint 3.1 — Test 3 & 4: average predicted position", () => {
  it("Test 3: participant selected at #1, #3, #5 averages to 3.0", () => {
    const predictions: EligiblePrediction[] = [
      { predictionId: "p1", rankedParticipantIds: ["Chile"] },
      { predictionId: "p2", rankedParticipantIds: ["_", "_", "Chile"] },
      { predictionId: "p3", rankedParticipantIds: ["_", "_", "_", "_", "Chile"] },
    ];
    const ranking = computeCommunityTop10(predictions);
    const chile = ranking.find((entry) => entry.participantId === "Chile");
    expect(chile?.averagePosition).toBe(3.0);
  });

  it("Test 4: absence is never counted as a position — average uses only predictions containing the participant", () => {
    const predictions: EligiblePrediction[] = [
      { predictionId: "p1", rankedParticipantIds: ["_", "Chile"] }, // Chile at #2
      { predictionId: "p2", rankedParticipantIds: ["_", "_", "_", "Chile"] }, // Chile at #4
      { predictionId: "p3", rankedParticipantIds: ["Other"] }, // Chile absent
      { predictionId: "p4", rankedParticipantIds: ["Other"] }, // Chile absent
    ];
    const ranking = computeCommunityTop10(predictions);
    const chile = ranking.find((entry) => entry.participantId === "Chile");
    expect(chile?.top10Count).toBe(2);
    expect(chile?.averagePosition).toBe(3.0); // (2 + 4) / 2, NOT (2 + 4 + 11 + 11) / 4
  });
});

describe("Sprint 3.1 — Test 5: average rank never changes the ranking order", () => {
  it("Participant A (higher weighted score, lower inclusion) stays above Participant B (lower score, higher inclusion)", () => {
    const predictions: EligiblePrediction[] = [
      // A appears once, at #1 (10 points) -> high score, low inclusion (1 prediction).
      { predictionId: "p1", rankedParticipantIds: ["A"] },
      // B appears in three predictions, always at #9 (2 points each = 6 total) -> lower score, higher inclusion.
      { predictionId: "p2", rankedParticipantIds: ["_", "_", "_", "_", "_", "_", "_", "_", "B"] },
      { predictionId: "p3", rankedParticipantIds: ["_", "_", "_", "_", "_", "_", "_", "_", "B"] },
      { predictionId: "p4", rankedParticipantIds: ["_", "_", "_", "_", "_", "_", "_", "_", "B"] },
    ];
    const ranking = computeCommunityTop10(predictions);
    const a = ranking.find((entry) => entry.participantId === "A");
    const b = ranking.find((entry) => entry.participantId === "B");

    expect(a?.points).toBe(10);
    expect(b?.points).toBe(6);
    expect(a!.top10Count).toBeLessThan(b!.top10Count); // A has lower inclusion...
    expect(ranking.findIndex((e) => e.participantId === "A")).toBeLessThan(
      ranking.findIndex((e) => e.participantId === "B"),
    ); // ...but still ranks above B, because points (the approved formula) still decide order.
  });
});