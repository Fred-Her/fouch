import { describe, it, expect } from "vitest";
import { assignCompetitionRanks, buildLeaderboard } from "./leaderboard";

describe("assignCompetitionRanks — competition ranking (1224, never dense 1223)", () => {
  it("[95,90,85,80] -> [1,2,3,4]", () => {
    expect(assignCompetitionRanks([95, 90, 85, 80])).toEqual([1, 2, 3, 4]);
  });

  it("[95,90,90,80] -> [1,2,2,4]", () => {
    expect(assignCompetitionRanks([95, 90, 90, 80])).toEqual([1, 2, 2, 4]);
  });

  it("[90,90,90] -> [1,1,1]", () => {
    expect(assignCompetitionRanks([90, 90, 90])).toEqual([1, 1, 1]);
  });

  it("[100,99,99,99,75] -> [1,2,2,2,5] (not dense [1,2,2,2,3])", () => {
    expect(assignCompetitionRanks([100, 99, 99, 99, 75])).toEqual([1, 2, 2, 2, 5]);
  });

  it("empty input -> empty output", () => {
    expect(assignCompetitionRanks([])).toEqual([]);
  });

  it("single entry -> rank 1", () => {
    expect(assignCompetitionRanks([42])).toEqual([1]);
  });
});

describe("buildLeaderboard", () => {
  it("ranks by displayScore, breaking display order (not rank) ties deterministically by publicId", () => {
    const entries = buildLeaderboard([
      { publicId: "zzz", nickname: "Zed", countryCode: null, displayScore: 88 },
      { publicId: "aaa", nickname: "Ana", countryCode: null, displayScore: 88 },
      { publicId: "bbb", nickname: "Bo", countryCode: null, displayScore: 92 },
    ]);
    expect(entries.map((e) => e.publicId)).toEqual(["bbb", "aaa", "zzz"]);
    expect(entries.map((e) => e.rank)).toEqual([1, 2, 2]);
  });

  it("assigns correct score bands via the existing frozen helper", () => {
    const entries = buildLeaderboard([
      { publicId: "a", nickname: null, countryCode: null, displayScore: 95 },
      { publicId: "b", nickname: null, countryCode: null, displayScore: 22 },
    ]);
    expect(entries[0]?.band).toBe("ELITE");
    expect(entries[1]?.band).toBe("MISSED_IT");
  });

  it("never uses submission time — order depends only on score, then publicId", () => {
    // Deliberately reversed input order — result must not reflect input order.
    const entries = buildLeaderboard([
      { publicId: "later", nickname: null, countryCode: null, displayScore: 50 },
      { publicId: "earlier", nickname: null, countryCode: null, displayScore: 80 },
    ]);
    expect(entries[0]?.publicId).toBe("earlier");
  });
});