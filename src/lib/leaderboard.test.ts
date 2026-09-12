import { describe, it, expect } from "vitest";
import { assignCompetitionRanks, buildLeaderboard, resolveViewerContext } from "./leaderboard";

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

describe("resolveViewerContext — Sprint 5.1: viewer context is structurally separate from leaderboard existence", () => {
  const board = buildLeaderboard([
    { publicId: "pef", nickname: "Pef", countryCode: null, displayScore: 61 },
    { publicId: "fred1", nickname: "Fred", countryCode: null, displayScore: 25 },
    { publicId: "fred2", nickname: "FRED", countryCode: null, displayScore: 25 },
    { publicId: "ghera", nickname: "Ghera", countryCode: "CL", displayScore: 22 },
    { publicId: "gg", nickname: "gg", countryCode: null, displayScore: 13 },
  ]);
  const scores = new Map([
    ["pef", 61],
    ["fred1", 25],
    ["fred2", 25],
    ["ghera", 22],
    ["gg", 13],
  ]);

  it("Case A: no `from` -> no viewer, no crash, board itself is untouched", () => {
    const viewer = resolveViewerContext(board, scores, undefined);
    expect(viewer).toBeNull();
    expect(board).toHaveLength(5); // the board array itself was never mutated
  });

  it("Case B: valid `from` -> correct entry, rank #4 of 5, matches the production example", () => {
    const viewer = resolveViewerContext(board, scores, "ghera");
    expect(viewer?.entry.rank).toBe(4);
    expect(viewer?.entry.score).toBe(22);
    expect(viewer?.entry.nickname).toBe("Ghera");
  });

  it("Case C: invalid/unknown `from` -> null, no throw", () => {
    expect(() => resolveViewerContext(board, scores, "not-a-real-id")).not.toThrow();
    expect(resolveViewerContext(board, scores, "not-a-real-id")).toBeNull();
  });

  it("Case D: `from` belongs to a prediction not on this leaderboard (e.g. another event) -> null", () => {
    // Simulates a publicId that is valid *somewhere*, just not in this
    // event's leaderboard array — the exact situation a cross-event or
    // stale ID produces once this leaderboard was built independently.
    const viewer = resolveViewerContext(board, scores, "some-other-events-prediction");
    expect(viewer).toBeNull();
  });

  it("Case H: shared tie ranking is preserved when a tied entry is the viewer", () => {
    const viewer = resolveViewerContext(board, scores, "fred1");
    expect(viewer?.entry.rank).toBe(2);
    const otherTied = resolveViewerContext(board, scores, "fred2");
    expect(otherTied?.entry.rank).toBe(2);
  });
});