/**
 * FOUCH Score Engine types.
 *
 * Only STAGE_RANKING is implemented in Sprint 4. FULL_RANKING and
 * CATEGORY_PICK are declared so the architecture doesn't need a
 * rewrite when those event families arrive (see
 * FOUCH_SCORING_RESEARCH.md §15) — nothing about their scoring logic
 * is implemented here.
 */
export type ScoringMode = "STAGE_RANKING" | "FULL_RANKING" | "CATEGORY_PICK";

export interface StageRankingWeights {
  winner: number;
  podium: number;
  top5: number;
  top10: number;
  ranking: number;
}

export interface StageRankingConfig {
  mode: "STAGE_RANKING";
  weights: StageRankingWeights;
  predictionSize: number;
  stages: { podium: number; top5: number; top10: number };
}

/**
 * The official result, expressed only as what was actually published —
 * exact positions for the podium, unordered sets for the Top5/Top10
 * extras. Never a full 1-10 ordering (see FOUCH_SCORING_RESEARCH.md §3).
 */
export interface OfficialResultInput {
  winner: string;
  firstRunnerUp: string;
  secondRunnerUp: string;
  /** Exactly 2 participant IDs, unordered relative to each other. */
  top5Extras: string[];
  /** Exactly 5 participant IDs, unordered relative to each other. */
  top10Extras: string[];
}

export type ScoreBand = "MISSED_IT" | "FAIR" | "GOOD" | "EXCELLENT" | "ELITE";

export interface ScoreComponent {
  earned: number;
  max: number;
  hits?: number;
  total?: number;
  hit?: boolean;
}

export interface ScoreBreakdown {
  /** Full precision — never rounded internally. */
  score: number;
  /** Rounded integer — the only number the UI should ever display. */
  displayScore: number;
  band: ScoreBand;
  components: {
    winner: ScoreComponent;
    podium: ScoreComponent;
    top5: ScoreComponent;
    top10: ScoreComponent;
    ranking: ScoreComponent;
  };
}