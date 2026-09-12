import type { ScoreBand } from "@/types/scoring";
import { getScoreBand } from "@/lib/scoring";

export interface LeaderboardEntry {
  publicId: string;
  nickname: string | null;
  countryCode: string | null;
  score: number;
  band: ScoreBand;
  rank: number;
}

/**
 * Standard competition ranking ("1224", not dense "1223"): a tie
 * doesn't compress the ranks below it — the next distinct score jumps
 * straight to its true position. Input MUST already be sorted
 * descending; this function does not sort.
 *
 * [95,90,85,80] -> [1,2,3,4]
 * [95,90,90,80] -> [1,2,2,4]
 * [90,90,90]    -> [1,1,1]
 * [100,99,99,99,75] -> [1,2,2,2,5]
 */
export function assignCompetitionRanks(sortedDescendingScores: number[]): number[] {
  const ranks: number[] = [];
  let lastScore: number | null = null;
  let lastRank = 0;

  sortedDescendingScores.forEach((score, index) => {
    if (score === lastScore) {
      ranks.push(lastRank);
      return;
    }
    const rank = index + 1;
    ranks.push(rank);
    lastRank = rank;
    lastScore = score;
  });

  return ranks;
}

/**
 * Builds ranked leaderboard entries from raw (score, identity) pairs.
 * Ranking is based on the same rounded `displayScore` shown in the UI
 * (see FouchScore.tsx) — two rows both reading "88" are genuinely
 * tied on a leaderboard, regardless of any hidden full-precision
 * difference. Sorting is stable and deterministic (score, then
 * publicId) — never submission time, per Sprint 5 brief §6.
 */
export function buildLeaderboard(
  raw: Array<{ publicId: string; nickname: string | null; countryCode: string | null; displayScore: number }>,
): LeaderboardEntry[] {
  const sorted = [...raw].sort((a, b) => {
    if (b.displayScore !== a.displayScore) return b.displayScore - a.displayScore;
    return a.publicId.localeCompare(b.publicId);
  });

  const ranks = assignCompetitionRanks(sorted.map((r) => r.displayScore));

  return sorted.map((entry, index) => ({
    publicId: entry.publicId,
    nickname: entry.nickname,
    countryCode: entry.countryCode,
    score: entry.displayScore,
    band: getScoreBand(entry.displayScore),
    rank: ranks[index]!,
  }));
}