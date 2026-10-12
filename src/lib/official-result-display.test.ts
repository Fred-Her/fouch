import { describe, it, expect } from "vitest";
import { classifyPicks, buildOfficialFinish, allOfficialIds } from "./official-result-display";
import { scorePrediction } from "./scoring";
import type { OfficialResultInput } from "@/types/scoring";

const MGI: OfficialResultInput = {
  winner: "TZ",
  firstRunnerUp: "EC",
  secondRunnerUp: "NL",
  top5Extras: ["GT", "VN"],
  top10Extras: ["CI", "CU", "MX", "PR", "TH", "VE"], // six equal 5th runners-up
};

describe("buildOfficialFinish — the tied Top 11 is shown as announced", () => {
  it("reports an 11-member finish with 3 + 2 + 6 groups and no invented order", () => {
    const finish = buildOfficialFinish(MGI);
    expect(finish.topSize).toBe(11);
    expect(finish.top5Extras).toEqual(["GT", "VN"]);
    expect(finish.remaining).toHaveLength(6);
    expect(allOfficialIds(finish)).toHaveLength(11);
  });

  it("a conventional result is a Top 10", () => {
    expect(buildOfficialFinish({ ...MGI, top10Extras: MGI.top10Extras.slice(0, 5) }).topSize).toBe(10);
  });
});

describe("classifyPicks — marks use the SAME ranges the score uses", () => {
  it("exact when inside the official range; in_top when a finalist elsewhere; out when not a finalist", () => {
    const picks = ["TZ", "NL", "EC", "VE", "GT", "CI", "XX", "CU", "VN", "ZZ"];
    const marks = classifyPicks(picks, MGI);
    expect(marks["TZ"]).toBe("exact"); // winner at #1
    expect(marks["NL"]).toBe("in_top"); // 2nd RU predicted #2? -> official #3
    expect(marks["EC"]).toBe("in_top"); // 1st RU predicted #3 -> official #2
    expect(marks["VE"]).toBe("in_top"); // tied finalist predicted #4 (range 6-10)
    expect(marks["GT"]).toBe("exact"); // top-5 member at #5 (range 4-5)
    expect(marks["CI"]).toBe("exact"); // tied finalist at #6
    expect(marks["CU"]).toBe("exact"); // tied finalist at #8
    expect(marks["VN"]).toBe("in_top"); // top-5 member predicted #9
    expect(marks["XX"]).toBe("out");
    expect(marks["ZZ"]).toBe("out");
  });

  it("every tied finalist gets the identical mark at the same slot (no tied finalist is favored)", () => {
    for (const slot of [4, 5, 6, 8, 10]) {
      const marks = MGI.top10Extras.map((id) => {
        const picks = ["TZ", "EC", "NL", "GT", "VN", "O1", "O2", "O3", "O4", "O5"];
        picks[slot - 1] = id;
        return classifyPicks(picks, MGI)[id];
      });
      expect(new Set(marks).size).toBe(1);
    }
  });

  it("consistency with the scorer: a prediction where every pick is 'exact' earns the full ranking component", () => {
    const perfect = ["TZ", "EC", "NL", "GT", "VN", "CI", "CU", "MX", "PR", "TH"];
    const marks = classifyPicks(perfect, MGI);
    expect(Object.values(marks).every((m) => m === "exact")).toBe(true);
    const { components } = scorePrediction(perfect, MGI);
    expect(components.ranking.earned).toBeCloseTo(components.ranking.max, 10);
  });

  it("never mutates or re-scores: same input, same output", () => {
    const picks = ["TZ", "EC", "NL", "GT", "VN", "CI", "CU", "MX", "PR", "TH"];
    expect(classifyPicks(picks, MGI)).toEqual(classifyPicks([...picks], { ...MGI }));
  });
});
