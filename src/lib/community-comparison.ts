export interface EligiblePrediction {
  /** Used only to exclude the viewed prediction from its own comparison. */
  predictionId: string;
  /** Participant IDs in ranked order — index 0 is position #1. */
  rankedParticipantIds: string[];
}

export type SampleSizeBucket = "0" | "1_4" | "5_9" | "10_24" | "25_49" | "50_99" | "100_plus";

/**
 * Sample-size tiers drive both UI copy (see YouVsTheWorld.tsx) and the
 * analytics property `comparison_population_bucket`. Kept as one
 * source of truth rather than scattered thresholds — see brief
 * section 10.
 */
export function getSampleSizeBucket(population: number): SampleSizeBucket {
  if (population <= 0) return "0";
  if (population <= 4) return "1_4";
  if (population <= 9) return "5_9";
  if (population <= 24) return "10_24";
  if (population <= 49) return "25_49";
  if (population <= 99) return "50_99";
  return "100_plus";
}

export interface CommunityTop10Entry {
  participantId: string;
  points: number;
  firstPlaceCount: number;
  top3Count: number;
  top10Count: number;
}

export interface ComparisonResult {
  population: number;
  sameWinner: { participantId: string; count: number; pct: number } | null;
  top3Match: { overlap: number; communityTop3: string[] } | null;
  boldestPick: { participantId: string; inclusionPct: number } | null;
  communityTop10: CommunityTop10Entry[];
}

/**
 * Excludes the viewed prediction from the comparison population, per
 * brief section 12 — "PREDICTION vs EVERYONE ELSE" must never let a
 * prediction inflate its own agreement numbers.
 */
function excludeSelf(
  predictions: EligiblePrediction[],
  excludePredictionId?: string,
): EligiblePrediction[] {
  if (!excludePredictionId) return predictions;
  return predictions.filter((prediction) => prediction.predictionId !== excludePredictionId);
}

/**
 * Position-weighted community ranking: position 1 = 10 points, down
 * to position 10 = 1 point (formula: 11 - position). Ties break on,
 * in order: more #1 picks, more Top 3 appearances, more Top 10
 * appearances, then participant ID ascending — deterministic, never
 * arbitrary object/insertion order.
 */
export function computeCommunityTop10(predictions: EligiblePrediction[]): CommunityTop10Entry[] {
  const byParticipant = new Map<string, CommunityTop10Entry>();

  for (const prediction of predictions) {
    prediction.rankedParticipantIds.forEach((participantId, index) => {
      const position = index + 1;
      const entry = byParticipant.get(participantId) ?? {
        participantId,
        points: 0,
        firstPlaceCount: 0,
        top3Count: 0,
        top10Count: 0,
      };
      entry.points += 11 - position;
      if (position === 1) entry.firstPlaceCount += 1;
      if (position <= 3) entry.top3Count += 1;
      entry.top10Count += 1;
      byParticipant.set(participantId, entry);
    });
  }

  return Array.from(byParticipant.values()).sort((a, b) => {
    if (b.points !== a.points) return b.points - a.points;
    if (b.firstPlaceCount !== a.firstPlaceCount) return b.firstPlaceCount - a.firstPlaceCount;
    if (b.top3Count !== a.top3Count) return b.top3Count - a.top3Count;
    if (b.top10Count !== a.top10Count) return b.top10Count - a.top10Count;
    return a.participantId.localeCompare(b.participantId);
  });
}

/**
 * The full You vs The World comparison for one ranked prediction
 * against a comparison population. Pure function — no I/O — so it can
 * be unit-tested with fixtures (see community-comparison.test.ts) and
 * reused by both the public prediction page and analytics.
 */
export function computeComparison(
  rankedParticipantIds: string[],
  allPredictions: EligiblePrediction[],
  excludePredictionId?: string,
): ComparisonResult {
  const predictions = excludeSelf(allPredictions, excludePredictionId);
  const population = predictions.length;

  const communityTop10 = computeCommunityTop10(predictions);

  if (population === 0) {
    return { population: 0, sameWinner: null, top3Match: null, boldestPick: null, communityTop10: [] };
  }

  const userWinner = rankedParticipantIds[0];
  const sameWinnerCount = userWinner
    ? predictions.filter((p) => p.rankedParticipantIds[0] === userWinner).length
    : 0;
  const sameWinner = userWinner
    ? { participantId: userWinner, count: sameWinnerCount, pct: sameWinnerCount / population }
    : null;

  const communityTop3Ids = communityTop10.slice(0, 3).map((entry) => entry.participantId);
  const userTop3 = new Set(rankedParticipantIds.slice(0, 3));
  const top3Overlap = communityTop3Ids.filter((id) => userTop3.has(id)).length;
  const top3Match =
    communityTop3Ids.length > 0 ? { overlap: top3Overlap, communityTop3: communityTop3Ids } : null;

  const inclusionByParticipant = new Map(
    communityTop10.map((entry) => [entry.participantId, entry.top10Count / population]),
  );
  const userTop5 = rankedParticipantIds.slice(0, 5);
  let boldestPick: ComparisonResult["boldestPick"] = null;
  for (const participantId of userTop5) {
    const inclusionPct = inclusionByParticipant.get(participantId) ?? 0;
    if (!boldestPick || inclusionPct < boldestPick.inclusionPct) {
      boldestPick = { participantId, inclusionPct };
    }
  }

  return { population, sameWinner, top3Match, boldestPick, communityTop10: communityTop10.slice(0, 10) };
}