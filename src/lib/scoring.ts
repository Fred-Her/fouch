import type {
  OfficialResultInput,
  ScoreBand,
  ScoreBreakdown,
  StageRankingConfig,
} from "@/types/scoring";

/**
 * FOUCH SCORE v1.0 — frozen. Source of truth: FOUCH_SCORING_RESEARCH.md
 * §19 (formula) and §22 (C2-B stage-placement semantics, validated
 * against the C2-A membership alternative and rejected it explicitly).
 *
 * DO NOT change these weights, DO NOT switch Podium/Top5 to
 * membership-anywhere semantics, without a new research cycle.
 */
export const STAGE_RANKING_V1_CONFIG: StageRankingConfig = {
  mode: "STAGE_RANKING",
  weights: { winner: 30, podium: 25, top5: 15, top10: 15, ranking: 15 },
  predictionSize: 10,
  stages: { podium: 3, top5: 5, top10: 10 },
};

/**
 * Score bands — frozen (FOUCH_SCORING_RESEARCH.md §13, re-confirmed §22).
 * Centralized here on purpose: nothing else in the app should compare a
 * score to 40/60/75/90 directly.
 */
export function getScoreBand(displayScore: number): ScoreBand {
  if (displayScore >= 90) return "ELITE";
  if (displayScore >= 75) return "EXCELLENT";
  if (displayScore >= 60) return "GOOD";
  if (displayScore >= 40) return "FAIR";
  return "MISSED_IT";
}

/**
 * Derives each official stage member's accepted position range directly
 * from the published result structure — never an invented exact
 * position for an unordered Top5/Top10 extra (research §3, §5).
 */
function getAcceptedRanges(official: OfficialResultInput): Map<string, [number, number]> {
  const ranges = new Map<string, [number, number]>();
  ranges.set(official.winner, [1, 1]);
  ranges.set(official.firstRunnerUp, [2, 2]);
  ranges.set(official.secondRunnerUp, [3, 3]);
  for (const id of official.top5Extras) ranges.set(id, [4, 5]);
  for (const id of official.top10Extras) ranges.set(id, [6, 10]);
  return ranges;
}

function podiumSet(official: OfficialResultInput): Set<string> {
  return new Set([official.winner, official.firstRunnerUp, official.secondRunnerUp]);
}
function top5Set(official: OfficialResultInput): Set<string> {
  return new Set([...podiumSet(official), ...official.top5Extras]);
}
function top10Set(official: OfficialResultInput): Set<string> {
  return new Set([...top5Set(official), ...official.top10Extras]);
}

/**
 * FOUCH SCORE v1.0 — STAGE_RANKING. Pure function, no I/O. Implements
 * the frozen formula exactly, with C2-B (stage-placement) semantics:
 * Podium/Top5 credit only counts a member placed within the
 * corresponding predicted positions (0:3 / 0:5) — never merely present
 * somewhere in the Top 10. See FOUCH_SCORING_RESEARCH.md §22 for why.
 */
export function scorePrediction(
  predictedRankedIds: string[],
  official: OfficialResultInput,
  config: StageRankingConfig = STAGE_RANKING_V1_CONFIG,
): ScoreBreakdown {
  const { weights, stages } = config;
  const podium = podiumSet(official);
  const top5 = top5Set(official);
  const top10 = top10Set(official);
  const acceptedRanges = getAcceptedRanges(official);

  const winnerHit = predictedRankedIds[0] === official.winner;
  const winnerComponent = { earned: winnerHit ? weights.winner : 0, max: weights.winner, hit: winnerHit };

  function stageComponent(predictedSlice: string[], officialSet: Set<string>, weight: number, total: number) {
    const hits = predictedSlice.filter((id) => officialSet.has(id)).length;
    return { hits, total, earned: (hits / total) * weight, max: weight };
  }

  const podiumComponent = stageComponent(predictedRankedIds.slice(0, stages.podium), podium, weights.podium, 3);
  const top5Component = stageComponent(predictedRankedIds.slice(0, stages.top5), top5, weights.top5, 5);
  const top10Component = stageComponent(
    predictedRankedIds.slice(0, stages.top10),
    top10,
    weights.top10,
    10,
  );

  let rankingRaw = 0;
  for (const memberId of top10) {
    const predictedPosition = predictedRankedIds.indexOf(memberId) + 1; // 0 if absent
    if (predictedPosition === 0) continue;
    const range = acceptedRanges.get(memberId);
    if (!range) continue;
    const [lo, hi] = range;
    const distance = Math.max(lo - predictedPosition, predictedPosition - hi, 0);
    rankingRaw += Math.max(0, 1 - distance / 9);
  }
  const rankingComponent = { earned: (rankingRaw / 10) * weights.ranking, max: weights.ranking };

  const score =
    winnerComponent.earned +
    podiumComponent.earned +
    top5Component.earned +
    top10Component.earned +
    rankingComponent.earned;

  const displayScore = Math.round(score);

  return {
    score,
    displayScore,
    band: getScoreBand(displayScore),
    components: {
      winner: winnerComponent,
      podium: podiumComponent,
      top5: top5Component,
      top10: top10Component,
      ranking: rankingComponent,
    },
  };
}

// ---------------------------------------------------------------------
// Percentile
// ---------------------------------------------------------------------

/** Never show a percentile claim below this many OTHER eligible, scored
 * predictions for the same event — research §14/§22, restated here as
 * the one place this number lives. */
export const MIN_PERCENTILE_SAMPLE = 25;

export interface PercentileResult {
  /** Number of other eligible predictions this was compared against. */
  population: number;
  /** "You beat N% of other predictions" — null below MIN_PERCENTILE_SAMPLE. */
  percentile: number | null;
}

/**
 * Percentile semantics (explicit, per research §15): "the current
 * prediction" is always EXCLUDED from its own comparison population —
 * consistent with the self-exclusion rule already used by You vs The
 * World (Sprint 3). Ties never count as "beaten": percentile is the
 * fraction of the other population with a STRICTLY lower score, so two
 * identical top scores both correctly show the same percentile rather
 * than one inflating past the other.
 */
export function computePercentile(selfScore: number, otherScores: number[]): PercentileResult {
  const population = otherScores.length;
  if (population < MIN_PERCENTILE_SAMPLE) {
    return { population, percentile: null };
  }
  const beaten = otherScores.filter((s) => s < selfScore).length;
  return { population, percentile: (beaten / population) * 100 };
}