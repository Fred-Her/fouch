import "server-only";
import { getOfficialResult } from "@/lib/results-db";
import { getEligiblePredictionsForComparison } from "@/lib/predictions-db";
import { scorePrediction, computePercentile } from "@/lib/scoring";
import type { PercentileResult } from "@/lib/scoring";
import type { ScoreBreakdown } from "@/types/scoring";
import type { ParticipantDataStatus } from "@/lib/participants";

export interface PredictionScoreResult {
  breakdown: ScoreBreakdown;
  percentile: PercentileResult;
}

/**
 * Scores are computed dynamically on every call, not persisted. This is
 * a deliberate simplicity choice (see FOUCH_SCORE_IMPLEMENTATION.md):
 * it makes "official result changes must not create stale scores"
 * (research §11) trivially true — there is no cache to invalidate —
 * at the cost of recomputing on each page view. At FOUCH's current
 * scale (reusing the same eligible-predictions query You vs The World
 * already runs) this is the safer trade.
 *
 * Returns null when there's no official result yet for this event +
 * data_status (the pre-result experience, unchanged from before
 * Sprint 4) — never a fabricated or partial score.
 */
export async function getPredictionScore(
  predictionId: string,
  rankedParticipantIds: string[],
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<PredictionScoreResult | null> {
  const official = await getOfficialResult(eventSlug, dataStatus);
  if (!official) return null;

  const breakdown = scorePrediction(rankedParticipantIds, official);

  const eligible = await getEligiblePredictionsForComparison(eventSlug, dataStatus);
  const otherScores = eligible
    .filter((p) => p.predictionId !== predictionId)
    .map((p) => scorePrediction(p.rankedParticipantIds, official).score);

  const percentile = computePercentile(breakdown.score, otherScores);

  return { breakdown, percentile };
}