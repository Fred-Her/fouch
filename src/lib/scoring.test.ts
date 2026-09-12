import { describe, it, expect } from "vitest";
import {
  scorePrediction,
  getScoreBand,
  computePercentile,
  MIN_PERCENTILE_SAMPLE,
  STAGE_RANKING_V1_CONFIG,
} from "./scoring";
import { validateOfficialResult } from "./official-result-validation";
import type { OfficialResultInput } from "@/types/scoring";
import type { Participant } from "@/types/participant";

// Ranks 1-24 as string IDs, matching the research's abstraction exactly.
const R = (n: number) => `r${n}`;
const OFFICIAL: OfficialResultInput = {
  winner: R(1),
  firstRunnerUp: R(2),
  secondRunnerUp: R(3),
  top5Extras: [R(4), R(5)],
  top10Extras: [R(6), R(7), R(8), R(9), R(10)],
};

function ids(nums: number[]): string[] {
  return nums.map(R);
}

describe("scorePrediction — reproduces FOUCH_SCORING_RESEARCH.md cases exactly", () => {
  it("1. Perfect call -> 100", () => {
    const result = scorePrediction(ids([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), OFFICIAL);
    expect(result.score).toBeCloseTo(100, 5);
    expect(result.displayScore).toBe(100);
    expect(result.band).toBe("ELITE");
  });

  it("2. Winner only, rest poor -> ~44.33", () => {
    const result = scorePrediction(ids([1, 15, 16, 17, 18, 19, 20, 21, 22, 23]), OFFICIAL);
    expect(result.score).toBeCloseTo(44.33, 1);
    expect(result.components.winner.hit).toBe(true);
  });

  it("3. Great field, wrong winner -> ~55.67 (must exceed 'winner only')", () => {
    const winnerOnly = scorePrediction(ids([1, 15, 16, 17, 18, 19, 20, 21, 22, 23]), OFFICIAL);
    const greatField = scorePrediction(ids([11, 2, 3, 4, 5, 6, 7, 8, 9, 10]), OFFICIAL);
    expect(greatField.score).toBeCloseTo(55.67, 1);
    // The exact test that sank the original C1 formula — must never regress.
    expect(greatField.score).toBeGreaterThan(winnerOnly.score);
  });

  it("4. Runner-up predicted #2 -> strong contribution", () => {
    const result = scorePrediction(ids([15, 2, 16, 17, 18, 19, 20, 21, 22, 23]), OFFICIAL);
    expect(result.score).toBeCloseTo(14.33, 1);
    expect(result.components.podium.hits).toBe(1);
  });

  it("5. Runner-up predicted #9 -> ~1.83 (stage-placement semantics: NO podium credit)", () => {
    const result = scorePrediction(ids([15, 16, 17, 18, 19, 20, 21, 22, 2, 23]), OFFICIAL);
    expect(result.score).toBeCloseTo(1.83, 1);
    expect(result.components.podium.hits).toBe(0); // C2-B: not in predicted[0:3]
  });

  it("6. 10/10 correct but podium buried at #8-10 -> ~30.67", () => {
    const result = scorePrediction(ids([4, 5, 6, 7, 8, 9, 10, 1, 2, 3]), OFFICIAL);
    expect(result.score).toBeCloseTo(30.67, 1);
    expect(result.components.podium.hits).toBe(0); // winner/RU1/RU2 are at positions 8-10, not 1-3
    expect(result.components.top10.hits).toBe(10);
  });

  it("7. Near perfect -> ~97", () => {
    const result = scorePrediction(ids([1, 2, 3, 4, 5, 6, 7, 8, 9, 15]), OFFICIAL);
    expect(result.score).toBeCloseTo(97, 1);
    expect(result.band).toBe("ELITE");
  });

  it("13a. Top5-only member at #4 or #5 receives no distance penalty", () => {
    const at4 = scorePrediction(ids([11, 12, 13, 4, 16, 17, 18, 19, 20, 21]), OFFICIAL);
    const at5 = scorePrediction(ids([11, 12, 13, 16, 4, 17, 18, 19, 20, 21]), OFFICIAL);
    // Ranking credit for this one member should be full (1/10 share) either way.
    expect(at4.components.ranking.earned).toBeCloseTo(at5.components.ranking.earned, 5);
  });

  it("13b. Top10-only member anywhere in #6-#10 receives no distance penalty", () => {
    const positions = [6, 7, 8, 9, 10];
    const scores = positions.map((pos) => {
      const base = [11, 12, 13, 14, 16, 17, 18, 19, 20, 21];
      base[pos - 1] = 8;
      return scorePrediction(ids(base), OFFICIAL).components.ranking.earned;
    });
    // All five placements are within the accepted [6,10] band -> identical ranking credit.
    const [first, ...rest] = scores;
    for (const s of rest) expect(s).toBeCloseTo(first!, 5);
  });
});

describe("getScoreBand — exact boundaries (research §13, restated §22)", () => {
  it.each([
    [0, "MISSED_IT"],
    [39, "MISSED_IT"],
    [40, "FAIR"],
    [59, "FAIR"],
    [60, "GOOD"],
    [74, "GOOD"],
    [75, "EXCELLENT"],
    [89, "EXCELLENT"],
    [90, "ELITE"],
    [100, "ELITE"],
  ])("displayScore %i -> %s", (score, expected) => {
    expect(getScoreBand(score)).toBe(expected);
  });
});

describe("computePercentile", () => {
  it("hides percentile below MIN_PERCENTILE_SAMPLE (24 others)", () => {
    const others = Array.from({ length: MIN_PERCENTILE_SAMPLE - 1 }, () => 50);
    const result = computePercentile(80, others);
    expect(result.population).toBe(24);
    expect(result.percentile).toBeNull();
  });

  it("shows percentile at exactly MIN_PERCENTILE_SAMPLE (25 others)", () => {
    const others = Array.from({ length: MIN_PERCENTILE_SAMPLE }, () => 50);
    const result = computePercentile(80, others);
    expect(result.population).toBe(25);
    expect(result.percentile).toBe(100); // beats all 25
  });

  it("ties never count as 'beaten' (two identical top scores both read the same percentile)", () => {
    const others = [...Array.from({ length: 24 }, () => 50), 80]; // 25 others, one tied at 80
    const result = computePercentile(80, others);
    expect(result.percentile).toBe((24 / 25) * 100); // beats the 24 at 50, not the tied 80
  });

  it("0 comparison predictions -> no percentile, no division by zero", () => {
    const result = computePercentile(80, []);
    expect(result.population).toBe(0);
    expect(result.percentile).toBeNull();
  });

  it("excludes self from the population by construction (caller passes only OTHER scores)", () => {
    // computePercentile takes an already-self-excluded array — this test
    // documents that contract rather than re-deriving it.
    const others = Array.from({ length: 30 }, () => 10);
    const result = computePercentile(10, others);
    expect(result.percentile).toBe(0); // beats none — everyone else tied at the same score
  });
});

describe("validateOfficialResult", () => {
  const participants: Participant[] = Array.from({ length: 24 }, (_, i) => ({
    id: R(i + 1),
    eventId: "e",
    displayName: `Country ${i + 1}`,
    countryCode: "XX",
    countryName: `Country ${i + 1}`,
    sortOrder: i,
    isActive: true,
  }));

  it("accepts a well-formed result", () => {
    expect(validateOfficialResult(OFFICIAL, participants).valid).toBe(true);
  });

  it("rejects a result with a duplicated participant", () => {
    const bad: OfficialResultInput = { ...OFFICIAL, secondRunnerUp: OFFICIAL.winner };
    const result = validateOfficialResult(bad, participants);
    expect(result.valid).toBe(false);
  });

  it("rejects a result referencing an unknown/inactive participant", () => {
    const bad: OfficialResultInput = { ...OFFICIAL, winner: "not-a-real-id" };
    const result = validateOfficialResult(bad, participants);
    expect(result.valid).toBe(false);
  });

  it("rejects top5Extras with the wrong size", () => {
    const bad: OfficialResultInput = { ...OFFICIAL, top5Extras: [R(4)] };
    expect(validateOfficialResult(bad, participants).valid).toBe(false);
  });

  it("rejects top10Extras with the wrong size", () => {
    const bad: OfficialResultInput = { ...OFFICIAL, top10Extras: [R(6), R(7)] };
    expect(validateOfficialResult(bad, participants).valid).toBe(false);
  });
});

describe("STAGE_RANKING_V1_CONFIG — frozen weights sanity check", () => {
  it("weights sum to 100", () => {
    const w = STAGE_RANKING_V1_CONFIG.weights;
    expect(w.winner + w.podium + w.top5 + w.top10 + w.ranking).toBe(100);
  });

  it("matches the frozen research formula exactly", () => {
    expect(STAGE_RANKING_V1_CONFIG.weights).toEqual({
      winner: 30,
      podium: 25,
      top5: 15,
      top10: 15,
      ranking: 15,
    });
  });
});