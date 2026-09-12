# Sprint 4: FOUCH SCORE v1.0 (STAGE_RANKING) — applies all new and changed files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-sprint4.ps1
$failures = @()

try {
    $path = "supabase\migrations\0003_event_results.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- Sprint 4: official result storage for FOUCH SCORE v1.0 (STAGE_RANKING).
--
-- Deliberately minimal: one row per (event_slug, data_status). Winner /
-- 1st RU / 2nd RU are exact single participant IDs; top5_extras and
-- top10_extras are unordered arrays — the schema itself makes it
-- impossible to store an invented exact position for an unordered
-- stage member, matching FOUCH_SCORING_RESEARCH.md §3/§5.
--
-- No separate "result status" state machine: a NULL/missing row means
-- "no official result yet" (existing pre-result experience, unchanged),
-- and a row's mere existence means "sufficient result to score" because
-- validate_official_result() (application-side, see
-- src/lib/official-result-validation.ts) is required before any insert.
-- This is a deliberate simplicity choice, documented in
-- FOUCH_SCORE_IMPLEMENTATION.md, appropriate for the project's current
-- scale.

create table if not exists event_results (
  id uuid primary key default gen_random_uuid(),
  event_slug text not null,
  data_status text not null check (data_status in ('demo', 'verified')),
  winner_participant_id text not null,
  first_runner_up_participant_id text not null,
  second_runner_up_participant_id text not null,
  -- Exactly 2 — enforced application-side (validateOfficialResult) since
  -- Postgres array-length CHECK constraints on a nullable array are
  -- fragile; the app is the single write path (service-role only, see
  -- RLS below), so this is sufficient defense-in-depth.
  top5_extra_participant_ids text[] not null,
  top10_extra_participant_ids text[] not null,
  source_note text,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_slug, data_status)
);

create index if not exists event_results_event_slug_idx on event_results (event_slug);

alter table event_results enable row level security;

-- Public read: the whole point is that anyone with a prediction link can
-- see whether/how it scored.
drop policy if exists "event_results are publicly readable" on event_results;
create policy "event_results are publicly readable"
  on event_results for select
  using (true);

-- No insert/update/delete policy for anon/authenticated — with RLS
-- enabled and no matching policy, those are denied by default. Only the
-- service-role key (used exclusively by scripts/set-official-result.ts,
-- server-side) can write. See FOUCH_SCORE_IMPLEMENTATION.md for how to
-- enter a result.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0003_event_results.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0003_event_results.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0003_event_results.sql"
}

try {
    $path = "src\types\scoring.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\types\scoring.ts"
} catch {
    Write-Host "FAILED: src\types\scoring.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\types\scoring.ts"
}

try {
    $path = "src\lib\scoring.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\scoring.ts"
} catch {
    Write-Host "FAILED: src\lib\scoring.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\scoring.ts"
}

try {
    $path = "src\lib\scoring.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import {
  scorePrediction,
  getScoreBand,
  computePercentile,
  MIN_PERCENTILE_SAMPLE,
  STAGE_RANKING_V1_CONFIG,
} from "./scoring";
import { validateOfficialResult } from "./official-result-validation";
import type { OfficialResultInput } from "@/types/scoring";
import type { Participant } from "@/types/participant";

// Ranks 1-24 as string IDs, matching the research's abstraction exactly.
const R = (n: number) => `r${n}`;
const OFFICIAL: OfficialResultInput = {
  winner: R(1),
  firstRunnerUp: R(2),
  secondRunnerUp: R(3),
  top5Extras: [R(4), R(5)],
  top10Extras: [R(6), R(7), R(8), R(9), R(10)],
};

function ids(nums: number[]): string[] {
  return nums.map(R);
}

describe("scorePrediction — reproduces FOUCH_SCORING_RESEARCH.md cases exactly", () => {
  it("1. Perfect call -> 100", () => {
    const result = scorePrediction(ids([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), OFFICIAL);
    expect(result.score).toBeCloseTo(100, 5);
    expect(result.displayScore).toBe(100);
    expect(result.band).toBe("ELITE");
  });

  it("2. Winner only, rest poor -> ~44.33", () => {
    const result = scorePrediction(ids([1, 15, 16, 17, 18, 19, 20, 21, 22, 23]), OFFICIAL);
    expect(result.score).toBeCloseTo(44.33, 1);
    expect(result.components.winner.hit).toBe(true);
  });

  it("3. Great field, wrong winner -> ~55.67 (must exceed 'winner only')", () => {
    const winnerOnly = scorePrediction(ids([1, 15, 16, 17, 18, 19, 20, 21, 22, 23]), OFFICIAL);
    const greatField = scorePrediction(ids([11, 2, 3, 4, 5, 6, 7, 8, 9, 10]), OFFICIAL);
    expect(greatField.score).toBeCloseTo(55.67, 1);
    // The exact test that sank the original C1 formula — must never regress.
    expect(greatField.score).toBeGreaterThan(winnerOnly.score);
  });

  it("4. Runner-up predicted #2 -> strong contribution", () => {
    const result = scorePrediction(ids([15, 2, 16, 17, 18, 19, 20, 21, 22, 23]), OFFICIAL);
    expect(result.score).toBeCloseTo(14.33, 1);
    expect(result.components.podium.hits).toBe(1);
  });

  it("5. Runner-up predicted #9 -> ~1.83 (stage-placement semantics: NO podium credit)", () => {
    const result = scorePrediction(ids([15, 16, 17, 18, 19, 20, 21, 22, 2, 23]), OFFICIAL);
    expect(result.score).toBeCloseTo(1.83, 1);
    expect(result.components.podium.hits).toBe(0); // C2-B: not in predicted[0:3]
  });

  it("6. 10/10 correct but podium buried at #8-10 -> ~30.67", () => {
    const result = scorePrediction(ids([4, 5, 6, 7, 8, 9, 10, 1, 2, 3]), OFFICIAL);
    expect(result.score).toBeCloseTo(30.67, 1);
    expect(result.components.podium.hits).toBe(0); // winner/RU1/RU2 are at positions 8-10, not 1-3
    expect(result.components.top10.hits).toBe(10);
  });

  it("7. Near perfect -> ~97", () => {
    const result = scorePrediction(ids([1, 2, 3, 4, 5, 6, 7, 8, 9, 15]), OFFICIAL);
    expect(result.score).toBeCloseTo(97, 1);
    expect(result.band).toBe("ELITE");
  });

  it("13a. Top5-only member at #4 or #5 receives no distance penalty", () => {
    const at4 = scorePrediction(ids([11, 12, 13, 4, 16, 17, 18, 19, 20, 21]), OFFICIAL);
    const at5 = scorePrediction(ids([11, 12, 13, 16, 4, 17, 18, 19, 20, 21]), OFFICIAL);
    // Ranking credit for this one member should be full (1/10 share) either way.
    expect(at4.components.ranking.earned).toBeCloseTo(at5.components.ranking.earned, 5);
  });

  it("13b. Top10-only member anywhere in #6-#10 receives no distance penalty", () => {
    const positions = [6, 7, 8, 9, 10];
    const scores = positions.map((pos) => {
      const base = [11, 12, 13, 14, 16, 17, 18, 19, 20, 21];
      base[pos - 1] = 8;
      return scorePrediction(ids(base), OFFICIAL).components.ranking.earned;
    });
    // All five placements are within the accepted [6,10] band -> identical ranking credit.
    const [first, ...rest] = scores;
    for (const s of rest) expect(s).toBeCloseTo(first!, 5);
  });
});

describe("getScoreBand — exact boundaries (research §13, restated §22)", () => {
  it.each([
    [0, "MISSED_IT"],
    [39, "MISSED_IT"],
    [40, "FAIR"],
    [59, "FAIR"],
    [60, "GOOD"],
    [74, "GOOD"],
    [75, "EXCELLENT"],
    [89, "EXCELLENT"],
    [90, "ELITE"],
    [100, "ELITE"],
  ])("displayScore %i -> %s", (score, expected) => {
    expect(getScoreBand(score)).toBe(expected);
  });
});

describe("computePercentile", () => {
  it("hides percentile below MIN_PERCENTILE_SAMPLE (24 others)", () => {
    const others = Array.from({ length: MIN_PERCENTILE_SAMPLE - 1 }, () => 50);
    const result = computePercentile(80, others);
    expect(result.population).toBe(24);
    expect(result.percentile).toBeNull();
  });

  it("shows percentile at exactly MIN_PERCENTILE_SAMPLE (25 others)", () => {
    const others = Array.from({ length: MIN_PERCENTILE_SAMPLE }, () => 50);
    const result = computePercentile(80, others);
    expect(result.population).toBe(25);
    expect(result.percentile).toBe(100); // beats all 25
  });

  it("ties never count as 'beaten' (two identical top scores both read the same percentile)", () => {
    const others = [...Array.from({ length: 24 }, () => 50), 80]; // 25 others, one tied at 80
    const result = computePercentile(80, others);
    expect(result.percentile).toBe((24 / 25) * 100); // beats the 24 at 50, not the tied 80
  });

  it("0 comparison predictions -> no percentile, no division by zero", () => {
    const result = computePercentile(80, []);
    expect(result.population).toBe(0);
    expect(result.percentile).toBeNull();
  });

  it("excludes self from the population by construction (caller passes only OTHER scores)", () => {
    // computePercentile takes an already-self-excluded array — this test
    // documents that contract rather than re-deriving it.
    const others = Array.from({ length: 30 }, () => 10);
    const result = computePercentile(10, others);
    expect(result.percentile).toBe(0); // beats none — everyone else tied at the same score
  });
});

describe("validateOfficialResult", () => {
  const participants: Participant[] = Array.from({ length: 24 }, (_, i) => ({
    id: R(i + 1),
    eventId: "e",
    displayName: `Country ${i + 1}`,
    countryCode: "XX",
    countryName: `Country ${i + 1}`,
    sortOrder: i,
    isActive: true,
  }));

  it("accepts a well-formed result", () => {
    expect(validateOfficialResult(OFFICIAL, participants).valid).toBe(true);
  });

  it("rejects a result with a duplicated participant", () => {
    const bad: OfficialResultInput = { ...OFFICIAL, secondRunnerUp: OFFICIAL.winner };
    const result = validateOfficialResult(bad, participants);
    expect(result.valid).toBe(false);
  });

  it("rejects a result referencing an unknown/inactive participant", () => {
    const bad: OfficialResultInput = { ...OFFICIAL, winner: "not-a-real-id" };
    const result = validateOfficialResult(bad, participants);
    expect(result.valid).toBe(false);
  });

  it("rejects top5Extras with the wrong size", () => {
    const bad: OfficialResultInput = { ...OFFICIAL, top5Extras: [R(4)] };
    expect(validateOfficialResult(bad, participants).valid).toBe(false);
  });

  it("rejects top10Extras with the wrong size", () => {
    const bad: OfficialResultInput = { ...OFFICIAL, top10Extras: [R(6), R(7)] };
    expect(validateOfficialResult(bad, participants).valid).toBe(false);
  });
});

describe("STAGE_RANKING_V1_CONFIG — frozen weights sanity check", () => {
  it("weights sum to 100", () => {
    const w = STAGE_RANKING_V1_CONFIG.weights;
    expect(w.winner + w.podium + w.top5 + w.top10 + w.ranking).toBe(100);
  });

  it("matches the frozen research formula exactly", () => {
    expect(STAGE_RANKING_V1_CONFIG.weights).toEqual({
      winner: 30,
      podium: 25,
      top5: 15,
      top10: 15,
      ranking: 15,
    });
  });
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\scoring.test.ts"
} catch {
    Write-Host "FAILED: src\lib\scoring.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\scoring.test.ts"
}

try {
    $path = "src\lib\official-result-validation.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { OfficialResultInput } from "@/types/scoring";
import type { Participant } from "@/types/participant";

export type OfficialResultValidation = { valid: true } | { valid: false; error: string };

/**
 * Validates an official result BEFORE it's accepted (research §24).
 * Rejects invalid structures outright — never silently corrects them.
 */
export function validateOfficialResult(
  result: OfficialResultInput,
  activeParticipants: Participant[],
): OfficialResultValidation {
  if (result.top5Extras.length !== 2) {
    return { valid: false, error: "top5Extras must contain exactly 2 participants." };
  }
  if (result.top10Extras.length !== 5) {
    return { valid: false, error: "top10Extras must contain exactly 5 participants." };
  }

  const allIds = [
    result.winner,
    result.firstRunnerUp,
    result.secondRunnerUp,
    ...result.top5Extras,
    ...result.top10Extras,
  ];

  if (new Set(allIds).size !== allIds.length) {
    return { valid: false, error: "Duplicate participant appears more than once in the result." };
  }

  const validIds = new Set(activeParticipants.map((p) => p.id));
  const unknown = allIds.filter((id) => !validIds.has(id));
  if (unknown.length > 0) {
    return { valid: false, error: `Unknown or inactive participant(s): ${unknown.join(", ")}` };
  }

  // Nested-stage consistency is implied by construction (winner/RU1/RU2 are
  // disjoint from top5Extras/top10Extras by the duplicate check above), but
  // stated explicitly per research §24's "podium belongs to Top5, Top5
  // belongs to Top10" requirement — true here by definition of the sets.

  return { valid: true };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\official-result-validation.ts"
} catch {
    Write-Host "FAILED: src\lib\official-result-validation.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\official-result-validation.ts"
}

try {
    $path = "src\lib\results-db.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { OfficialResultInput } from "@/types/scoring";
import type { ParticipantDataStatus } from "@/lib/participants";

/**
 * Returns the official result for an event, scoped to a specific
 * data_status. Returns null when no result exists yet (pre-result
 * state — the public page keeps its existing pre-Sprint-4 experience)
 * OR when a result exists only for a DIFFERENT data_status than the
 * one requested (research §12/§22: demo predictions must never be
 * scored against an official result, or vice versa — returning null
 * here is what enforces that, at the query itself).
 */
export async function getOfficialResult(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<OfficialResultInput | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("event_results")
    .select(
      "winner_participant_id, first_runner_up_participant_id, second_runner_up_participant_id, top5_extra_participant_ids, top10_extra_participant_ids",
    )
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .maybeSingle();

  if (error || !data) return null;

  return {
    winner: data.winner_participant_id,
    firstRunnerUp: data.first_runner_up_participant_id,
    secondRunnerUp: data.second_runner_up_participant_id,
    top5Extras: data.top5_extra_participant_ids,
    top10Extras: data.top10_extra_participant_ids,
  };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\results-db.ts"
} catch {
    Write-Host "FAILED: src\lib\results-db.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\results-db.ts"
}

try {
    $path = "src\lib\scoring-service.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\scoring-service.ts"
} catch {
    Write-Host "FAILED: src\lib\scoring-service.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\scoring-service.ts"
}

try {
    $path = "scripts\set-official-result.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Enters (or replaces) the official result for an event, validated
 * before it's ever written. This is the "smallest practical way to
 * enter a result" per research/Sprint 4 §23 — no admin UI, run by
 * hand from a trusted machine with the service-role key available.
 *
 * Usage:
 *   npx tsx scripts/set-official-result.ts
 *
 * To use a different result, edit RESULT below and rerun — the script
 * validates every participant ID before writing anything.
 *
 * SAFETY: this uses the service-role key (via getSupabaseServerClient),
 * which bypasses RLS. Never run this against production without
 * reviewing RESULT first.
 */
import { getEventBySlug } from "../src/lib/events";
import { getParticipantsForEvent } from "../src/lib/participants";
import { validateOfficialResult } from "../src/lib/official-result-validation";
import { getSupabaseServerClient } from "../src/lib/supabase/server";
import type { OfficialResultInput } from "../src/types/scoring";

const EVENT_SLUG = "miss-universe-2026";

/**
 * FICTIONAL / DEMO RESULT — Miss Universe 2026 has not happened yet.
 * This is for development/testing only, matching the demo participant
 * dataset. Never presented as an official result in the product (the
 * public page and Result Card both read data_status and show a "Demo
 * result" label whenever this is used — see FouchScore.tsx).
 */
const DEMO_RESULT: OfficialResultInput = {
  winner: "demo-co", // Colombia
  firstRunnerUp: "demo-ve", // Venezuela
  secondRunnerUp: "demo-th", // Thailand
  top5Extras: ["demo-ph", "demo-pr"], // Philippines, Puerto Rico
  top10Extras: ["demo-in", "demo-mx", "demo-br", "demo-cl", "demo-es"], // India, Mexico, Brazil, Chile, Spain
};

async function main() {
  const event = getEventBySlug(EVENT_SLUG);
  if (!event) {
    console.error(`Event not found: ${EVENT_SLUG}`);
    process.exit(1);
  }

  const participantData = getParticipantsForEvent(EVENT_SLUG);
  if (!participantData) {
    console.error(`No participants configured for: ${EVENT_SLUG}`);
    process.exit(1);
  }

  const validation = validateOfficialResult(DEMO_RESULT, participantData.participants);
  if (!validation.valid) {
    console.error(`Result rejected: ${validation.error}`);
    process.exit(1);
  }

  const supabase = getSupabaseServerClient();
  if (!supabase) {
    console.error(
      "Supabase isn't configured (missing NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY).",
    );
    process.exit(1);
  }

  const { error } = await supabase.from("event_results").upsert(
    {
      event_slug: EVENT_SLUG,
      data_status: participantData.status, // "demo" today — never mixed with "verified"
      winner_participant_id: DEMO_RESULT.winner,
      first_runner_up_participant_id: DEMO_RESULT.firstRunnerUp,
      second_runner_up_participant_id: DEMO_RESULT.secondRunnerUp,
      top5_extra_participant_ids: DEMO_RESULT.top5Extras,
      top10_extra_participant_ids: DEMO_RESULT.top10Extras,
      source_note: "Development/demo fixture — not an official result.",
      updated_at: new Date().toISOString(),
    },
    { onConflict: "event_slug,data_status" },
  );

  if (error) {
    console.error("Failed to write result:", error.message);
    process.exit(1);
  }

  console.log(`OK: official result set for ${EVENT_SLUG} (data_status=${participantData.status}).`);
}

main();
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     scripts\set-official-result.ts"
} catch {
    Write-Host "FAILED: scripts\set-official-result.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "scripts\set-official-result.ts"
}

try {
    $path = "src\components\scoring\FouchScore.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { getEntryNoun } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { getPredictionScore } from "@/lib/scoring-service";
import { MIN_PERCENTILE_SAMPLE } from "@/lib/scoring";
import { siteUrl } from "@/lib/site";
import type { PredictionRecord } from "@/lib/predictions-db";
import type { FouchEvent } from "@/types/event";
import type { ScoreBand } from "@/types/scoring";
import { FouchScoreTracker } from "./FouchScoreTracker";
import { ShareActions } from "@/components/prediction/ShareActions";

const BAND_LABEL: Record<ScoreBand, string> = {
  MISSED_IT: "Missed it",
  FAIR: "Fair call",
  GOOD: "Good call",
  EXCELLENT: "Excellent call",
  ELITE: "Elite call",
};

/**
 * Renders nothing (returns null) when there's no official result yet —
 * the pre-result experience is unchanged, never a fabricated score.
 * Server Component: fetches + scores server-side, only the final
 * numbers reach the client (via the tracker's props, not raw data).
 */
export async function FouchScore({
  prediction,
  event,
  publicId,
}: {
  prediction: PredictionRecord;
  event: FouchEvent;
  publicId: string;
}) {
  const result = await getPredictionScore(
    prediction.id,
    prediction.rankedParticipantIds,
    event.slug,
    prediction.dataStatus,
  );
  if (!result) return null;

  const participantData = getParticipantsForEvent(event.slug);
  const participantsById = new Map(
    (participantData?.participants ?? []).map((participant) => [participant.id, participant]),
  );
  const userWinnerPick = prediction.rankedParticipantIds[0]
    ? participantsById.get(prediction.rankedParticipantIds[0])
    : undefined;
  const pluralNoun = getEntryNoun(event, true);
  const { breakdown, percentile } = result;

  return (
    <section className="mt-12 border-t border-border pt-10">
      <FouchScoreTracker
        eventSlug={event.slug}
        scoreBand={breakdown.band}
        percentileAvailable={percentile.percentile !== null}
        dataStatus={prediction.dataStatus}
      />

      <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">Fouch score</p>

      {prediction.dataStatus === "demo" ? (
        <p className="mt-2 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo result — not an official outcome
        </p>
      ) : null}

      <p className="mt-3 font-display text-7xl text-accent-strong">{breakdown.displayScore}</p>
      <p className="mt-1 font-display text-2xl uppercase tracking-tight text-text-primary">
        {BAND_LABEL[breakdown.band]}
      </p>

      {percentile.percentile !== null ? (
        <p className="mt-2 text-sm text-text-secondary">
          You beat {Math.round(percentile.percentile)}% of {pluralNoun === "picks" ? "predictions" : pluralNoun} for
          this event, based on {percentile.population} other predictions.
        </p>
      ) : (
        <p className="mt-2 text-xs text-text-muted">
          Not enough predictions yet for a world ranking (needs {MIN_PERCENTILE_SAMPLE}+).
        </p>
      )}

      <dl className="mt-6 space-y-2 text-sm">
        <div className="flex items-center justify-between border-b border-border pb-2">
          <dt className="text-text-secondary">Winner</dt>
          <dd className="text-text-primary">
            {breakdown.components.winner.hit ? "✓ Correct" : "✗ Missed"}
            {userWinnerPick ? ` — your pick: ${userWinnerPick.displayName}` : null}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-2">
          <dt className="text-text-secondary">Podium</dt>
          <dd className="text-text-primary">
            {breakdown.components.podium.hits} / {breakdown.components.podium.total}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-2">
          <dt className="text-text-secondary">Top 5</dt>
          <dd className="text-text-primary">
            {breakdown.components.top5.hits} / {breakdown.components.top5.total}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-2">
          <dt className="text-text-secondary">Top 10</dt>
          <dd className="text-text-primary">
            {breakdown.components.top10.hits} / {breakdown.components.top10.total}
          </dd>
        </div>
        <div className="flex items-center justify-between">
          <dt className="text-text-secondary">Ranking</dt>
          <dd className="text-text-primary">
            {breakdown.components.ranking.earned.toFixed(1)} / {breakdown.components.ranking.max}
          </dd>
        </div>
      </dl>

      <div className="mt-8">
        <p className="font-display text-lg text-text-primary">Share your result</p>
        <div className="mt-3">
          <ShareActions
            variant="result"
            eventSlug={event.slug}
            publicUrl={`${siteUrl}/p/${publicId}`}
            storyCardUrl={`/p/${publicId}/result-card/story`}
            postCardUrl={`/p/${publicId}/result-card/post`}
          />
        </div>
      </div>
    </section>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\FouchScore.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\FouchScore.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\FouchScore.tsx"
}

try {
    $path = "src\components\scoring\FouchScoreTracker.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect } from "react";
import { track } from "@/lib/analytics";
import type { ScoreBand } from "@/types/scoring";

export function FouchScoreTracker({
  eventSlug,
  scoreBand,
  percentileAvailable,
  dataStatus,
}: {
  eventSlug: string;
  scoreBand: ScoreBand;
  percentileAvailable: boolean;
  dataStatus: string;
}) {
  useEffect(() => {
    const properties = { event_slug: eventSlug, score_band: scoreBand, data_status: dataStatus };
    track("score_viewed", properties);
    track("score_breakdown_viewed", properties);
    track("result_card_generated", properties);
    if (percentileAvailable) {
      track("percentile_viewed", { ...properties, percentile_available: true });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\FouchScoreTracker.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\FouchScoreTracker.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\FouchScoreTracker.tsx"
}

try {
    $path = "src\components\scoring\ResultCardMarkup.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { ScoreBreakdown, ScoreBand } from "@/types/scoring";

export interface ResultCardData {
  eventName: string;
  nickname: string | null;
  countryCode: string | null;
  isDemo: boolean;
  breakdown: ScoreBreakdown;
  percentile: number | null;
}

const INK = "#141318";
const SURFACE = "#232028";
const ACCENT = "#A6342E";
const ACCENT_STRONG = "#C44C42";
const TEXT_PRIMARY = "#F2EFE6";
const TEXT_MUTED = "#A39FB0";

const BAND_LABEL: Record<ScoreBand, string> = {
  MISSED_IT: "Missed it",
  FAIR: "Fair call",
  GOOD: "Good call",
  EXCELLENT: "Excellent call",
  ELITE: "Elite call",
};

/**
 * Same visual system as PredictionCardMarkup — same tokens, same
 * "no Unicode emoji, no photography" constraints (Satori can't render
 * flag emoji reliably; see PredictionCardMarkup.tsx's note). This is a
 * separate component (not a reskin of PredictionCardMarkup) because its
 * content is fundamentally different — a result, not a pick list — but
 * it deliberately reuses every token and spacing decision so it reads
 * as unmistakably the same product.
 */
export function ResultCardMarkup({
  data,
  width,
  height,
  siteDomain,
}: {
  data: ResultCardData;
  width: number;
  height: number;
  siteDomain: string;
}) {
  const scale = Math.min(1.32, Math.max(1, height / 1350));
  const whoBy = data.nickname
    ? `${data.nickname}${data.countryCode ? ` · ${data.countryCode}` : ""}`
    : data.countryCode;
  const { breakdown } = data;

  return (
    <div
      style={{
        width,
        height,
        display: "flex",
        flexDirection: "column",
        backgroundColor: INK,
        fontFamily: "Georgia, serif",
        padding: `${64 * scale}px 56px`,
        color: TEXT_PRIMARY,
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div style={{ display: "flex", fontSize: 28, letterSpacing: 4, color: TEXT_MUTED }}>FOUCH</div>
        {data.isDemo ? (
          <div
            style={{
              display: "flex",
              fontSize: 22,
              color: TEXT_MUTED,
              border: `1px solid ${TEXT_MUTED}`,
              borderRadius: 6,
              padding: "6px 14px",
            }}
          >
            DEMO
          </div>
        ) : null}
      </div>

      <div style={{ display: "flex", fontSize: 30, color: TEXT_MUTED, marginTop: 24 }}>{data.eventName}</div>
      {whoBy ? (
        <div style={{ display: "flex", fontSize: 26, color: ACCENT_STRONG, marginTop: 8 }}>{whoBy}</div>
      ) : null}

      {/* Score — the hero element */}
      <div
        style={{
          display: "flex",
          fontSize: 170 * scale,
          fontWeight: 700,
          marginTop: 20,
          lineHeight: 1,
          letterSpacing: 4,
        }}
      >
        {breakdown.displayScore}
      </div>
      <div style={{ display: "flex", fontSize: 46 * scale, fontWeight: 700, color: ACCENT, marginTop: 4 }}>
        {BAND_LABEL[breakdown.band].toUpperCase()}
      </div>

      {/* Breakdown */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: 64 * scale, gap: 28 * scale }}>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>Winner</div>
          <div style={{ display: "flex", color: breakdown.components.winner.hit ? ACCENT_STRONG : TEXT_MUTED }}>
            {breakdown.components.winner.hit ? "Correct" : "Missed"}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>Podium</div>
          <div style={{ display: "flex" }}>
            {breakdown.components.podium.hits} / {breakdown.components.podium.total}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>Top 5</div>
          <div style={{ display: "flex" }}>
            {breakdown.components.top5.hits} / {breakdown.components.top5.total}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>Top 10</div>
          <div style={{ display: "flex" }}>
            {breakdown.components.top10.hits} / {breakdown.components.top10.total}
          </div>
        </div>
      </div>

      {data.percentile !== null ? (
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            marginTop: 44 * scale,
            padding: "28px 32px",
            backgroundColor: SURFACE,
            borderRadius: 16,
          }}
        >
          <div style={{ display: "flex", fontSize: 30 * scale, color: TEXT_MUTED }}>TOP {100 - Math.round(data.percentile)}%</div>
          <div style={{ display: "flex", fontSize: 38 * scale, fontWeight: 700 }}>WORLDWIDE</div>
        </div>
      ) : null}

      {/* Footer */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: "auto" }}>
        <div style={{ display: "flex", fontSize: 34, fontWeight: 700 }}>THINK YOU COULD BEAT IT?</div>
        <div style={{ display: "flex", fontSize: 24, color: TEXT_MUTED, marginTop: 6 }}>{siteDomain}</div>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\ResultCardMarkup.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\ResultCardMarkup.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\ResultCardMarkup.tsx"
}

try {
    $path = "src\app\p\[publicId]\result-card\story\route.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ImageResponse } from "next/og";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getPredictionScore } from "@/lib/scoring-service";
import { ResultCardMarkup } from "@/components/scoring/ResultCardMarkup";
import { siteUrl } from "@/lib/site";

export const runtime = "edge";

const WIDTH = 1080;
const HEIGHT = 1920;

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ publicId: string }> },
) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) return new Response("Prediction not found", { status: 404 });

  const result = await getPredictionScore(
    record.prediction.id,
    record.prediction.rankedParticipantIds,
    record.event.slug,
    record.prediction.dataStatus,
  );
  if (!result) return new Response("No official result yet", { status: 404 });

  return new ImageResponse(
    (
      <ResultCardMarkup
        width={WIDTH}
        height={HEIGHT}
        siteDomain={siteUrl.replace(/^https?:\/\//, "")}
        data={{
          eventName: record.event.name,
          nickname: record.prediction.nickname,
          countryCode: record.prediction.countryCode,
          isDemo: record.prediction.dataStatus === "demo",
          breakdown: result.breakdown,
          percentile: result.percentile.percentile,
        }}
      />
    ),
    { width: WIDTH, height: HEIGHT },
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\result-card\story\route.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\result-card\story\route.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\result-card\story\route.tsx"
}

try {
    $path = "src\app\p\[publicId]\result-card\post\route.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ImageResponse } from "next/og";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getPredictionScore } from "@/lib/scoring-service";
import { ResultCardMarkup } from "@/components/scoring/ResultCardMarkup";
import { siteUrl } from "@/lib/site";

export const runtime = "edge";

const WIDTH = 1080;
const HEIGHT = 1350;

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ publicId: string }> },
) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) return new Response("Prediction not found", { status: 404 });

  const result = await getPredictionScore(
    record.prediction.id,
    record.prediction.rankedParticipantIds,
    record.event.slug,
    record.prediction.dataStatus,
  );
  if (!result) return new Response("No official result yet", { status: 404 });

  return new ImageResponse(
    (
      <ResultCardMarkup
        width={WIDTH}
        height={HEIGHT}
        siteDomain={siteUrl.replace(/^https?:\/\//, "")}
        data={{
          eventName: record.event.name,
          nickname: record.prediction.nickname,
          countryCode: record.prediction.countryCode,
          isDemo: record.prediction.dataStatus === "demo",
          breakdown: result.breakdown,
          percentile: result.percentile.percentile,
        }}
      />
    ),
    { width: WIDTH, height: HEIGHT },
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\result-card\post\route.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\result-card\post\route.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\result-card\post\route.tsx"
}

try {
    $path = "FOUCH_SCORE_IMPLEMENTATION.md"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
# FOUCH Score — Implementation (Sprint 4)

This is the implementation reference. For *why* the formula is what it
is, see `FOUCH_SCORING_RESEARCH.md` (historical research — not
rewritten here).

## Architecture

```
scorePrediction(predictedRankedIds, officialResult, config)
  → pure function, src/lib/scoring.ts, no I/O
```

The engine is generic over `ScoringMode` (`STAGE_RANKING` |
`FULL_RANKING` | `CATEGORY_PICK`), but only `STAGE_RANKING` is
implemented. The other two are declared as types only
(`src/types/scoring.ts`) so a future sprint doesn't require touching
this file's shape.

## Schema

**New table**: `event_results` (migration `0003_event_results.sql`).
One row per `(event_slug, data_status)`. Winner/1st RU/2nd RU are
single participant IDs; `top5_extra_participant_ids` and
`top10_extra_participant_ids` are unordered arrays — the schema itself
makes it impossible to store an invented exact position for an
unordered stage member.

RLS: public `SELECT` (anyone with a prediction link can see whether it
scored); no `INSERT`/`UPDATE`/`DELETE` policy for anon — only the
service-role key (used exclusively by `scripts/set-official-result.ts`)
can write.

**No separate result-status state machine.** A missing row means "no
official result yet" (pre-Sprint-4 experience, unchanged). A row's
existence means "sufficient to score," because
`validateOfficialResult()` is required before any insert — this is a
deliberate simplification appropriate to the project's current scale,
not an oversight.

## Scoring config (frozen)

```ts
STAGE_RANKING_V1_CONFIG = {
  mode: "STAGE_RANKING",
  weights: { winner: 30, podium: 25, top5: 15, top10: 15, ranking: 15 },
  predictionSize: 10,
  stages: { podium: 3, top5: 5, top10: 10 },
}
```

Do not change these weights without a new research cycle (see research
§33/§34 in the validation follow-up).

## Stage-placement semantics (C2-B) — restated

Podium/Top5 credit only counts a member the user placed **within the
corresponding predicted positions** (`predictedTop10[0:3]` /
`[0:5]`) — never merely present anywhere in the Top 10. Ranking
Quality is the only order-sensitive component beyond that. See
`FOUCH_SCORING_RESEARCH.md` §22 for the full justification (this exact
question was tested against the alternative — membership-anywhere —
and rejected).

## Accepted ranges

Derived directly from the official result structure, never invented:

| Stage member | Accepted range |
|---|---|
| Winner | [1,1] |
| 1st Runner-Up | [2,2] |
| 2nd Runner-Up | [3,3] |
| Top5 extra (×2) | [4,5] |
| Top10 extra (×5) | [6,10] |

## Score bands (frozen)

| Range | Band |
|---|---|
| 0-39 | MISSED_IT |
| 40-59 | FAIR |
| 60-74 | GOOD |
| 75-89 | EXCELLENT |
| 90-100 | ELITE |

Centralized in `getScoreBand()` (`src/lib/scoring.ts`) — nothing else
compares a score to these numbers directly.

## Percentile

- **Population**: all other eligible, scored predictions for the same
  `(event_slug, data_status)` — the current prediction is always
  excluded from its own comparison, consistent with You vs The World's
  established convention.
- **Ties**: never counted as "beaten." Percentile = (count of others
  strictly below your score) / population. Two identical top scores
  both report the same, correct percentile.
- **Minimum sample**: `MIN_PERCENTILE_SAMPLE = 25` (`src/lib/scoring.ts`).
  Below that, no percentile is shown — the score and breakdown still
  render normally.

## Score calculation — dynamic, not persisted

Scores are computed on every request (`src/lib/scoring-service.ts`),
not stored. This makes "an official result correction must not create
a stale score" trivially true (there's no cache to invalidate) at the
cost of recomputing per page view. It reuses the exact same
`getEligiblePredictionsForComparison()` query You vs The World already
runs, so this doesn't add a second, duplicate data-fetching path — see
"Known limitations" below for when this trade-off should be revisited.

## Demo vs. official safety

`getOfficialResult(eventSlug, dataStatus)` only returns a result when
its `data_status` matches the one requested. A demo prediction can
never be scored against an official result, or vice versa — enforced
at the query itself, not by a downstream check that could be
forgotten. The UI additionally shows a "Demo result — not an official
outcome" label whenever `data_status === "demo"` (currently always
true for Miss Universe 2026, since the participant roster itself is
still demo data).

## How to enter a result

There is no admin UI — for this project's current scale, a reviewed
script is the safer, simpler choice.

1. Edit `RESULT` in `scripts/set-official-result.ts` (winner, runners-up,
   Top5/Top10 extras — all by participant ID).
2. Run `npx tsx scripts/set-official-result.ts` from a machine with
   `NEXT_PUBLIC_SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` configured.
3. The script validates every participant ID and rejects duplicates or
   unknown IDs *before* writing anything (`validateOfficialResult()`).
4. Scoring activates immediately — no deploy needed, since the score is
   computed dynamically from the database.

## Public prediction page — new state

`/p/[publicId]` now conditionally renders a **FOUCH Score** section
(`src/components/scoring/FouchScore.tsx`) between the ranked prediction
and You vs The World, exactly when `getOfficialResult()` returns
non-null for that prediction's event + data_status. When it returns
null (no result yet), the page renders exactly as it did before Sprint
4 — this is strictly additive.

## Result Card

A second shareable card (`src/components/scoring/ResultCardMarkup.tsx`),
separate from the Sprint 2 Prediction Card, generated via the same
`next/og` `ImageResponse` infrastructure at `/p/[publicId]/result-card/{story,post}`.
Reuses `ShareActions` (extended with a `variant="result"` prop for
distinct analytics event names — the "prediction" variant's behavior
is unchanged) rather than a second sharing component. Uses text
country-code badges, not flag emoji — Satori/`next/og` doesn't render
Unicode flag emoji reliably (confirmed in Sprint 2), and this keeps the
Result Card consistent with the existing Prediction Card's approach.

## Tests

`src/lib/scoring.test.ts` — 31 tests, all passing:
- Reproduces the research's headline cases exactly (perfect call = 100,
  winner-only ≈ 44.33, great-field-wrong-winner ≈ 55.67 and must exceed
  winner-only, the critical runner-up-at-#9 case ≈ 1.83, buried-podium
  ≈ 30.67, near-perfect ≈ 97).
- Score band boundaries, exact (0/39/40/59/60/74/75/89/90/100).
- Percentile: below-threshold, at-threshold, ties, zero population.
- `validateOfficialResult`: accepts well-formed results, rejects
  duplicates, unknown participants, and wrong-sized stage arrays.

Combined with the existing `community-comparison.test.ts` (36 tests),
the project has **67 passing tests**. None depend on live Supabase
data.

## Known limitations

- **Dynamic (non-persisted) scoring** re-runs the full eligible-
  predictions query on every page view. Fine at hundreds to low
  thousands of predictions per event; if a single event's prediction
  count grows much larger, persisting scores (with an explicit
  recompute-on-result-change step) is the natural next iteration —
  intentionally deferred rather than built preemptively.
- **No admin UI** for entering results — a reviewed script is the
  entire "result entry" surface for now, as scoped.
- The current event's participant roster (and therefore every score
  computed against it) is demo data. Nothing about the scoring engine
  itself is Miss-Universe-specific, but this sprint did not add a
  second event to prove that in practice.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_SCORE_IMPLEMENTATION.md"
} catch {
    Write-Host "FAILED: FOUCH_SCORE_IMPLEMENTATION.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_SCORE_IMPLEMENTATION.md"
}

try {
    $path = "src\lib\analytics.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Minimal analytics seam.
 *
 * Intentionally NOT wired to PostHog (or any provider) yet — adding an
 * SDK before we know we need it is dead weight. This gives every call
 * site a single, typed function to import, so plugging in a real
 * provider later is a one-file change instead of a hunt through
 * components. Never throws, never blocks rendering, and is silent
 * when analytics isn't configured (e.g. local dev).
 *
 * Properties must never carry personally identifiable information or
 * free-text nickname/contestant input — only structural values like
 * an event slug, a count, a position, or a share method.
 */

export type FouchAnalyticsEvent =
  | "landing_view"
  | "featured_event_clicked"
  | "start_prediction"
  | "participant_selected"
  | "participant_removed"
  | "prediction_reordered"
  | "prediction_completed"
  | "prediction_reviewed"
  | "prediction_submit_started"
  | "prediction_submitted"
  | "prediction_card_generated"
  | "share_clicked"
  | "native_share_opened"
  | "copy_link_clicked"
  | "image_downloaded"
  | "public_prediction_viewed"
  | "public_prediction_cta_clicked"
  | "you_vs_world_viewed"
  | "same_winner_viewed"
  | "top3_match_viewed"
  | "boldest_pick_viewed"
  | "community_top10_viewed"
  | "community_share_clicked"
  | "score_viewed"
  | "score_breakdown_viewed"
  | "percentile_viewed"
  | "result_card_generated"
  | "result_card_shared"
  | "result_card_saved"
  | "result_share_link_copied";

export function track(event: FouchAnalyticsEvent, properties?: Record<string, unknown>) {
  if (typeof window === "undefined") return;
  if (!process.env.NEXT_PUBLIC_ANALYTICS_ENABLED) return;

  // Placeholder sink until a provider (e.g. PostHog) is configured behind
  // NEXT_PUBLIC_POSTHOG_KEY. Kept as a console log, not a network call,
  // so this never depends on an external analytics endpoint.
  console.debug("[fouch:analytics]", event, properties ?? {});
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\analytics.ts"
} catch {
    Write-Host "FAILED: src\lib\analytics.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\analytics.ts"
}

try {
    $path = "src\components\prediction\ShareActions.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useState } from "react";
import { Share2, Download, Link2, Check } from "lucide-react";
import { track } from "@/lib/analytics";
import type { FouchAnalyticsEvent } from "@/lib/analytics";

interface ShareEventNames {
  share: FouchAnalyticsEvent;
  nativeOpened: FouchAnalyticsEvent | null;
  download: FouchAnalyticsEvent;
  copyLink: FouchAnalyticsEvent;
}

const EVENT_NAMES: Record<"prediction" | "result", ShareEventNames> = {
  prediction: {
    share: "share_clicked",
    nativeOpened: "native_share_opened",
    download: "image_downloaded",
    copyLink: "copy_link_clicked",
  },
  result: {
    share: "result_card_shared",
    nativeOpened: null,
    download: "result_card_saved",
    copyLink: "result_share_link_copied",
  },
};

export function ShareActions({
  eventSlug,
  publicUrl,
  storyCardUrl,
  postCardUrl,
  variant = "prediction",
}: {
  eventSlug: string;
  publicUrl: string;
  storyCardUrl: string;
  postCardUrl: string;
  /** Defaults to "prediction" — the existing, unchanged behavior. Pass
   * "result" to reuse this exact component for the post-result Result
   * Card, firing the distinct result_* analytics events instead. */
  variant?: "prediction" | "result";
}) {
  const [format, setFormat] = useState<"story" | "post">("story");
  const [copied, setCopied] = useState(false);
  const [canNativeShare, setCanNativeShare] = useState(false);
  const events = EVENT_NAMES[variant];

  // navigator.share only exists client-side — checked once after mount
  // so server and initial client render stay consistent (no
  // hydration mismatch).
  useEffect(() => {
    if (typeof navigator !== "undefined" && "share" in navigator) {
      setCanNativeShare(true);
    }
  }, []);

  const activeCardUrl = format === "story" ? storyCardUrl : postCardUrl;

  async function handleShare() {
    track(events.share, { event_slug: eventSlug, share_method: "native" });
    if (!canNativeShare) return;

    try {
      await navigator.share({ title: "My Fouch prediction", url: publicUrl });
      if (events.nativeOpened) track(events.nativeOpened, { event_slug: eventSlug });
    } catch {
      // User cancelled the share sheet — not an error worth surfacing.
    }
  }

  async function handleCopyLink() {
    track(events.copyLink, { event_slug: eventSlug });
    try {
      await navigator.clipboard.writeText(publicUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard API unavailable — the link is still visible/selectable
      // in the UI as a fallback (see the public page).
    }
  }

  function handleDownload() {
    track(events.download, { event_slug: eventSlug, share_method: format });
  }

  return (
    <div>
      <div className="inline-flex rounded border border-border p-1 text-sm">
        <button
          type="button"
          onClick={() => setFormat("story")}
          className={`rounded px-3 py-1.5 transition-colors ${
            format === "story" ? "bg-surface-raised text-text-primary" : "text-text-muted"
          }`}
        >
          Story
        </button>
        <button
          type="button"
          onClick={() => setFormat("post")}
          className={`rounded px-3 py-1.5 transition-colors ${
            format === "post" ? "bg-surface-raised text-text-primary" : "text-text-muted"
          }`}
        >
          Post
        </button>
      </div>

      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={activeCardUrl}
        alt={variant === "result" ? "Your Fouch result card" : "Your Fouch prediction card"}
        className="mt-3 w-full max-w-xs rounded border border-border"
      />

      <div className="mt-4 flex flex-wrap gap-2">
        {canNativeShare ? (
          <button
            type="button"
            onClick={handleShare}
            className="inline-flex items-center gap-2 rounded bg-accent px-5 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            <Share2 className="h-4 w-4" aria-hidden />
            Share
          </button>
        ) : null}

        <a
          href={activeCardUrl}
          download={`fouch-${variant}-${format}.png`}
          onClick={handleDownload}
          className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          <Download className="h-4 w-4" aria-hidden />
          Save image
        </a>

        <button
          type="button"
          onClick={handleCopyLink}
          className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          {copied ? <Check className="h-4 w-4" aria-hidden /> : <Link2 className="h-4 w-4" aria-hidden />}
          {copied ? "Copied" : "Copy link"}
        </button>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\ShareActions.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\ShareActions.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\ShareActions.tsx"
}

try {
    $path = "src\components\prediction\PublicPredictionView.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { siteUrl } from "@/lib/site";
import type { Participant } from "@/types/participant";
import { ShareActions } from "./ShareActions";

export function PublicPredictionView({
  eventSlug,
  publicId,
  rankedParticipants,
  fouchScore,
  youVsTheWorld,
}: {
  eventSlug: string;
  publicId: string;
  rankedParticipants: Participant[];
  /** FOUCH Score section (Sprint 4) — null/absent renders nothing, which
   * is exactly the pre-result experience. Server Component, passed down
   * for the same reason as youVsTheWorld below. */
  fouchScore?: ReactNode;
  /** The You vs The World section — a Server Component rendered by the
   * page and passed down, since it needs server-side data fetching
   * that a Client Component can't do directly. */
  youVsTheWorld: ReactNode;
}) {
  const searchParams = useSearchParams();
  const isNew = searchParams.get("new") === "1";

  useEffect(() => {
    track("public_prediction_viewed", { event_slug: eventSlug, is_new: isNew });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (isNew) {
      track("prediction_card_generated", { event_slug: eventSlug });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const publicUrl = `${siteUrl}/p/${publicId}`;

  return (
    <div>
      {isNew ? (
        <p className="mt-4 font-display text-lg text-accent-strong">You made your call.</p>
      ) : null}

      <ol className="mt-6 space-y-1.5">
        {rankedParticipants.map((participant, index) => (
          <li
            key={participant.id}
            className="flex items-center gap-3 rounded border border-border bg-surface px-4 py-3"
          >
            <span className="font-display w-7 shrink-0 text-base text-accent-strong">
              {String(index + 1).padStart(2, "0")}
            </span>
            <CountryFlag countryCode={participant.countryCode} className="text-xl" />
            <span className="text-sm text-text-primary">{participant.displayName}</span>
          </li>
        ))}
      </ol>

      {fouchScore}

      {youVsTheWorld}

      <Link
        href={`/predict/${eventSlug}?from=${publicId}`}
        onClick={() => track("public_prediction_cta_clicked", { event_slug: eventSlug })}
        className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        Make your Top 10
      </Link>

      <div id="share" className="mt-10 scroll-mt-20 border-t border-border pt-8">
        <p className="font-display text-lg text-text-primary">Share your prediction</p>
        <div className="mt-3">
          <ShareActions
            eventSlug={eventSlug}
            publicUrl={publicUrl}
            storyCardUrl={`/p/${publicId}/card/story`}
            postCardUrl={`/p/${publicId}/card/post`}
          />
        </div>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\PublicPredictionView.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\PublicPredictionView.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\PublicPredictionView.tsx"
}

try {
    $path = "src\app\p\[publicId]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CountryFlag } from "@/components/CountryFlag";
import { siteUrl } from "@/lib/site";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { PublicPredictionView } from "@/components/prediction/PublicPredictionView";
import { YouVsTheWorld } from "@/components/prediction/YouVsTheWorld";
import { FouchScore } from "@/components/scoring/FouchScore";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ publicId: string }>;
}): Promise<Metadata> {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) return {};

  const title = record.prediction.nickname
    ? `${record.prediction.nickname}'s Top 10 — ${record.event.name}`
    : `A Top 10 prediction — ${record.event.name}`;
  const description = "See the prediction, then make your own call.";

  return {
    title,
    description,
    // Sprint 2 decision: public prediction pages are reachable via
    // link but intentionally not indexed — we don't want thousands of
    // thin user-generated pages in search results. `follow` so the
    // "Make your Top 10" CTA is still crawlable back to the real
    // product pages.
    robots: { index: false, follow: true },
    openGraph: {
      title,
      description,
      url: `${siteUrl}/p/${publicId}`,
      images: [`${siteUrl}/p/${publicId}/opengraph-image`],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
    },
  };
}

export default async function PublicPredictionPage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) notFound();

  const { prediction, event, rankedParticipants } = record;
  const heading = prediction.nickname ? `${prediction.nickname}'s Top 10` : "Someone's Top 10";

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>

      <h1 className="mt-6 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-2 font-display text-xl uppercase tracking-tight text-text-primary">
        {heading}
      </p>

      {prediction.countryCode ? (
        <p className="mt-1 text-sm text-text-muted"><CountryFlag countryCode={prediction.countryCode} /></p>
      ) : null}

      {prediction.dataStatus === "demo" ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo prediction — not the official lineup
        </p>
      ) : null}

      <PublicPredictionView
        eventSlug={event.slug}
        publicId={publicId}
        rankedParticipants={rankedParticipants}
        fouchScore={<FouchScore prediction={prediction} event={event} publicId={publicId} />}
        youVsTheWorld={<YouVsTheWorld prediction={prediction} event={event} />}
      />
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\page.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\page.tsx"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 18 files written successfully." -ForegroundColor Green
}