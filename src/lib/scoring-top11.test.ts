import { describe, it, expect } from "vitest";
import { scorePrediction } from "./scoring";
import { validateOfficialResult } from "./official-result-validation";
import type { OfficialResultInput } from "@/types/scoring";
import type { Participant } from "@/types/participant";

/**
 * Miss Grand International 2026 announced a TIED Top 11: winner,
 * 1st/2nd runner-up, two more in the Top 5 (3rd/4th runner-up), and
 * SIX equal 5th runners-up. These tests prove the frozen FOUCH Score
 * v1.0 formula handles that structure with no arbitrary advantage or
 * penalty — WITHOUT changing scoring.ts's behavior.
 */
const W = "W";
const R1 = "R1";
const R2 = "R2";
const E = ["E4", "E5"];
const T = ["T1", "T2", "T3", "T4", "T5", "T6"]; // six equal 5th runners-up
const OTHERS = Array.from({ length: 12 }, (_, i) => `O${i + 1}`);

const OFFICIAL_11: OfficialResultInput = {
  winner: W,
  firstRunnerUp: R1,
  secondRunnerUp: R2,
  top5Extras: E,
  top10Extras: T,
};

const permutations = <X,>(items: X[]): X[][] =>
  items.length <= 1
    ? [items]
    : items.flatMap((item, i) =>
        permutations([...items.slice(0, i), ...items.slice(i + 1)]).map((rest) => [item, ...rest]),
      );

describe("Top 11 (six tied 5th runners-up) — validator", () => {
  const participants: Participant[] = [W, R1, R2, ...E, ...T, ...OTHERS].map((id, i) => ({
    id,
    eventId: "e",
    displayName: id,
    countryCode: "XX",
    countryName: id,
    sortOrder: i,
    isActive: true,
  }));

  it("accepts the real MGI 2026 structure (2 + 6 extras)", () => {
    expect(validateOfficialResult(OFFICIAL_11, participants).valid).toBe(true);
  });

  it("still accepts a conventional Top 10 (2 + 5 extras)", () => {
    expect(validateOfficialResult({ ...OFFICIAL_11, top10Extras: T.slice(0, 5) }, participants).valid).toBe(true);
  });

  it("rejects 4 or 7 top10Extras, and a duplicated tied finalist", () => {
    expect(validateOfficialResult({ ...OFFICIAL_11, top10Extras: T.slice(0, 4) }, participants).valid).toBe(false);
    expect(validateOfficialResult({ ...OFFICIAL_11, top10Extras: [...T, "O1"] }, participants).valid).toBe(false);
    expect(validateOfficialResult({ ...OFFICIAL_11, top10Extras: [...T.slice(0, 5), "T1"] }, participants).valid).toBe(false);
  });

  it("rejects a tied finalist that is not an active participant", () => {
    expect(validateOfficialResult({ ...OFFICIAL_11, top10Extras: [...T.slice(0, 5), "ghost"] }, participants).valid).toBe(false);
  });
});

describe("Top 11 — the frozen formula treats the tie fairly", () => {
  it("a perfect call scores exactly 100 (the maximum is still reachable)", () => {
    const perfect = [W, R1, R2, ...E, ...T.slice(0, 5)];
    expect(scorePrediction(perfect, OFFICIAL_11).score).toBeCloseTo(100, 10);
  });

  it("a perfect call scores 100 whichever ONE of the six tied finalists is left out — no tied finalist is 'required'", () => {
    for (let omit = 0; omit < 6; omit++) {
      const fiveOfSix = T.filter((_, i) => i !== omit);
      const prediction = [W, R1, R2, ...E, ...fiveOfSix];
      expect(scorePrediction(prediction, OFFICIAL_11).score, `omit ${T[omit]}`).toBeCloseTo(100, 10);
    }
  });

  it("symmetry: relabeling WHICH tied finalists a prediction picked (all 720 permutations) never changes its score", () => {
    // A deliberately messy prediction: tied finalists at 1, 4, 6, 8 and 10, a top-5 member at 3.
    const template = [T[0]!, W, E[0]!, T[1]!, O(1), T[2]!, R1, T[3]!, O(2), T[4]!];
    const baseline = scorePrediction(template, OFFICIAL_11).score;
    for (const perm of permutations(T)) {
      const relabeled = template.map((id) => {
        const idx = T.indexOf(id);
        return idx === -1 ? id : perm[idx]!;
      });
      expect(scorePrediction(relabeled, OFFICIAL_11).score).toBeCloseTo(baseline, 10);
    }
  });

  it("a tied finalist placed too high (#4) earns the SAME partial credit whichever of the six it is — no arbitrary position is implied", () => {
    const scores = T.map((id) =>
      scorePrediction([W, R1, R2, id, E[0]!, E[1]!, O(1), O(2), O(3), O(4)], OFFICIAL_11).score,
    );
    for (const s of scores) expect(s).toBeCloseTo(scores[0]!, 10);
  });

  it("tied finalists anywhere in #6-#10 receive no distance penalty (accepted range is the whole tied block)", () => {
    for (let slot = 6; slot <= 10; slot++) {
      const prediction = [W, R1, R2, ...E, O(1), O(2), O(3), O(4), O(5)];
      prediction[slot - 1] = T[0]!;
      const expectedRankingRaw = 5 + 1; // 5 exact + the tied one at full credit
      const ranking = scorePrediction(prediction, OFFICIAL_11).components.ranking.earned;
      expect(ranking).toBeCloseTo((expectedRankingRaw / 10) * 15, 10);
    }
  });

  it("scores always stay within 0-100 (500 deterministic pseudo-random predictions)", () => {
    const pool = [W, R1, R2, ...E, ...T, ...OTHERS];
    let seed = 20261010;
    const rand = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;
    for (let n = 0; n < 500; n++) {
      const shuffled = [...pool].sort(() => rand() - 0.5).slice(0, 10);
      const { score } = scorePrediction(shuffled, OFFICIAL_11);
      expect(score).toBeGreaterThanOrEqual(0);
      expect(score).toBeLessThanOrEqual(100 + 1e-9);
    }
  });

  it("adding a sixth tied finalist to the official result NEVER lowers any prediction's score (monotonic — no hidden penalty)", () => {
    const official10: OfficialResultInput = { ...OFFICIAL_11, top10Extras: T.slice(0, 5) };
    const pool = [W, R1, R2, ...E, ...T, ...OTHERS];
    let seed = 7;
    const rand = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;
    for (let n = 0; n < 500; n++) {
      const prediction = [...pool].sort(() => rand() - 0.5).slice(0, 10);
      expect(scorePrediction(prediction, OFFICIAL_11).score).toBeGreaterThanOrEqual(
        scorePrediction(prediction, official10).score - 1e-9,
      );
    }
  });

  it("podium, winner and Top-5 components are completely unaffected by the extra tied finalist", () => {
    const official10: OfficialResultInput = { ...OFFICIAL_11, top10Extras: T.slice(0, 5) };
    const prediction = [R1, W, R2, E[1]!, E[0]!, T[0]!, T[5]!, O(1), O(2), O(3)];
    const a = scorePrediction(prediction, OFFICIAL_11).components;
    const b = scorePrediction(prediction, official10).components;
    expect(a.winner).toEqual(b.winner);
    expect(a.podium).toEqual(b.podium);
    expect(a.top5).toEqual(b.top5);
  });
});

function O(n: number): string {
  return `O${n}`;
}
