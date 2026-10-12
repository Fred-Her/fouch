import { describe, it, expect } from "vitest";
import { applyLeaderboardExclusions, LEADERBOARD_EXCLUDED_PUBLIC_IDS } from "./leaderboard-exclusions";
import { buildLeaderboard } from "./leaderboard";

const rows = [
  { publicId: "aaa", nickname: "A", countryCode: null, displayScore: 90 },
  { publicId: "bbb", nickname: "B", countryCode: null, displayScore: 80 },
  { publicId: "ccc", nickname: "C", countryCode: null, displayScore: 70 },
];

describe("leaderboard exclusions — explicit IDs only, nothing edited or deleted", () => {
  it("ships EMPTY: nothing is excluded until the founder confirms specific test IDs", () => {
    expect(Object.values(LEADERBOARD_EXCLUDED_PUBLIC_IDS).flat()).toEqual([]);
    expect(applyLeaderboardExclusions(rows, "miss-grand-international-2026")).toEqual(rows);
  });

  it("removes only the listed public_ids for THAT event", () => {
    const excluded = { "event-a": ["bbb"] };
    expect(applyLeaderboardExclusions(rows, "event-a", excluded).map((r) => r.publicId)).toEqual(["aaa", "ccc"]);
    expect(applyLeaderboardExclusions(rows, "event-b", excluded)).toEqual(rows);
  });

  it("ranks the remaining entries correctly (no gap where an excluded test was)", () => {
    const board = buildLeaderboard(applyLeaderboardExclusions(rows, "e", { e: ["aaa"] }));
    expect(board.map((r) => [r.publicId, r.rank])).toEqual([
      ["bbb", 1],
      ["ccc", 2],
    ]);
  });

  it("does not mutate its input", () => {
    const before = JSON.stringify(rows);
    applyLeaderboardExclusions(rows, "e", { e: ["aaa"] });
    expect(JSON.stringify(rows)).toBe(before);
  });
});
