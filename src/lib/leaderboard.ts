import type { ScoreBand } from "@/types/scoring";
import { getScoreBand, computePercentile } from "@/lib/scoring";
import type { PercentileResult } from "@/lib/scoring";

/** Top rows shown directly; how many neighbor rows on each side of an
 * out-of-view viewer (Sprint 5 brief §19). Both live here (not in the
 * server-only service) so the viewer-resolution logic below is a pure,
 * fully unit-testable function with no DB dependency. */
export const LEADERBOARD_TOP_N = 50;
const NEIGHBOR_WINDOW = 2;

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

export interface ViewerContext {
  entry: LeaderboardEntry;
  /** Only populated when the viewer's rank falls outside the visible Top N. */
  neighbors: LeaderboardEntry[];
  percentile: PercentileResult;
}

/**
 * Sprint 5.1 root-cause fix: viewer resolution is a PURE function over
 * an already-built leaderboard. This is what makes "the `from` query
 * param can only ever add optional context, never change whether the
 * leaderboard itself exists" structurally true rather than merely
 * intended — there is no code path here that can affect whether a
 * leaderboard is returned, because this function never sees (and
 * cannot see) the official-result lookup that decides that.
 *
 * Returns null — safely, no throw — whenever `viewerPublicId` is
 * absent, unknown, or belongs to a prediction not on THIS leaderboard
 * (which naturally covers "wrong event" too: a prediction from another
 * event's leaderboard array simply never appears in this one).
 */
export function resolveViewerContext(
  leaderboard: LeaderboardEntry[],
  fullPrecisionScoreByPublicId: Map<string, number>,
  viewerPublicId: string | undefined,
): ViewerContext | null {
  if (!viewerPublicId) return null;

  const viewerIndex = leaderboard.findIndex((entry) => entry.publicId === viewerPublicId);
  if (viewerIndex === -1) return null;

  const viewerEntry = leaderboard[viewerIndex]!;
  const viewerScore = fullPrecisionScoreByPublicId.get(viewerPublicId);
  if (viewerScore === undefined) return null;

  const otherScores = leaderboard
    .filter((entry) => entry.publicId !== viewerPublicId)
    .map((entry) => fullPrecisionScoreByPublicId.get(entry.publicId))
    .filter((score): score is number => score !== undefined);

  const percentile = computePercentile(viewerScore, otherScores);

  const isInTop = viewerIndex < LEADERBOARD_TOP_N;
  const neighbors = isInTop
    ? []
    : leaderboard.slice(
        Math.max(0, viewerIndex - NEIGHBOR_WINDOW),
        Math.min(leaderboard.length, viewerIndex + NEIGHBOR_WINDOW + 1),
      );

  return { entry: viewerEntry, neighbors, percentile };
}