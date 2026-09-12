/**
 * Experiment 01 — "Your Crowd Changed". Pure calculation, no I/O.
 *
 * IMPORTANT — this experiment does NOT prove causal retention (see
 * FOUCH_EXPERIMENT_01.md). It only measures whether a personalized,
 * meaningful consensus shift is common enough and large enough to be
 * worth showing at all.
 */

/** Minimum THEN and NOW population, each, before showing anything. */
export const MIN_MOVEMENT_SAMPLE = 10;
/** Minimum absolute percentage-point change before showing anything. */
export const MIN_MOVEMENT_POINTS = 5;

export interface TimestampedWinnerPick {
  predictionId: string;
  /** ISO 8601 — compared as a string, which is valid as long as
   * Supabase returns a consistent timestamptz format (it does). */
  submittedAt: string;
  winnerParticipantId: string;
}

export interface ConsensusChangeResult {
  eligible: boolean;
  thenSupport: number; // percentage points, 0-100
  nowSupport: number;
  changePoints: number; // nowSupport - thenSupport; can be negative
  direction: "toward" | "away" | null;
  thenSample: number;
  nowSample: number;
}

/**
 * THEN population: eligible OTHER predictions with
 * `submitted_at <= displayed.submittedAt` — i.e. "everyone who had
 * already predicted by the time this prediction was locked."
 * NOW population: all current eligible OTHER predictions.
 * Both exclude `displayed` itself (research §7 / brief §7).
 */
export function computeConsensusChange(
  displayed: TimestampedWinnerPick,
  allEligible: TimestampedWinnerPick[],
): ConsensusChangeResult {
  const others = allEligible.filter((p) => p.predictionId !== displayed.predictionId);

  const thenPopulation = others.filter((p) => p.submittedAt <= displayed.submittedAt);
  const nowPopulation = others;

  const thenSample = thenPopulation.length;
  const nowSample = nowPopulation.length;

  const ineligible = (thenSupport: number, nowSupport: number, changePoints: number): ConsensusChangeResult => ({
    eligible: false,
    thenSupport,
    nowSupport,
    changePoints,
    direction: null,
    thenSample,
    nowSample,
  });

  if (thenSample < MIN_MOVEMENT_SAMPLE || nowSample < MIN_MOVEMENT_SAMPLE) {
    return ineligible(0, 0, 0);
  }

  const thenMatches = thenPopulation.filter(
    (p) => p.winnerParticipantId === displayed.winnerParticipantId,
  ).length;
  const nowMatches = nowPopulation.filter(
    (p) => p.winnerParticipantId === displayed.winnerParticipantId,
  ).length;

  const thenSupport = (thenMatches / thenSample) * 100;
  const nowSupport = (nowMatches / nowSample) * 100;
  const changePoints = nowSupport - thenSupport;

  if (Math.abs(changePoints) < MIN_MOVEMENT_POINTS) {
    return ineligible(thenSupport, nowSupport, changePoints);
  }

  return {
    eligible: true,
    thenSupport,
    nowSupport,
    changePoints,
    direction: changePoints > 0 ? "toward" : "away",
    thenSample,
    nowSample,
  };
}

/** Sample-size bucket for analytics only (never shown in the UI) — kept
 * coarse on purpose, consistent with the app's existing bucketing
 * pattern (see community-comparison.ts's getSampleSizeBucket). Nothing
 * below MIN_MOVEMENT_SAMPLE is ever displayed, so buckets start there. */
export function bucketSample(n: number): "10-24" | "25-49" | "50-99" | "100+" {
  if (n < 25) return "10-24";
  if (n < 50) return "25-49";
  if (n < 100) return "50-99";
  return "100+";
}