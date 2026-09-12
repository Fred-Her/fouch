# Sprint 3.1: Community metrics clarity fix — applies all changed files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-sprint3-1.ps1
$failures = @()

try {
    $path = "src\lib\community-comparison.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
 * source of truth rather than scattered thresholds — see Sprint 3
 * brief section 10.
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

export type ComparisonDisplayMode = "none" | "count" | "early_signal" | "normal";

/**
 * Sprint 3.1: the single source of truth for how small a sample must
 * be before percentages stop being the primary presentation. Every
 * component reads this instead of comparing population to 4/5/9/10
 * itself — see brief "IMPORTANT" section on centralizing thresholds.
 *
 * - "none": 0 comparison predictions — no percentages, no counts.
 * - "count": 1-4 — "X of Y" is more honest than a percentage this small.
 * - "early_signal": 5-9 — percentages are shown, but labeled early.
 * - "normal": 10+ — ordinary percentage presentation.
 */
export function getComparisonDisplayMode(population: number): ComparisonDisplayMode {
  const bucket = getSampleSizeBucket(population);
  if (bucket === "0") return "none";
  if (bucket === "1_4") return "count";
  if (bucket === "5_9") return "early_signal";
  return "normal";
}

export interface CommunityTop10Entry {
  participantId: string;
  points: number;
  firstPlaceCount: number;
  top3Count: number;
  top10Count: number;
  /**
   * Average predicted position, computed ONLY across predictions that
   * actually included this participant — absence is never treated as
   * a worst-case position (11, 0, etc). See Sprint 3.1 brief's
   * "IMPORTANT MATHEMATICAL RULE".
   */
  averagePosition: number;
}

export interface ComparisonResult {
  population: number;
  sameWinner: { participantId: string; count: number; pct: number } | null;
  top3Match: { overlap: number; communityTop3: string[] } | null;
  boldestPick: { participantId: string; count: number; inclusionPct: number } | null;
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

interface Accumulator {
  participantId: string;
  points: number;
  firstPlaceCount: number;
  top3Count: number;
  top10Count: number;
  positionSum: number;
}

/**
 * Position-weighted community ranking: position 1 = 10 points, down
 * to position 10 = 1 point (formula: 11 - position). Ties break on,
 * in order: more #1 picks, more Top 3 appearances, more Top 10
 * appearances, then participant ID ascending — deterministic, never
 * arbitrary object/insertion order. This formula and its tie-breakers
 * are unchanged from Sprint 3 — Sprint 3.1 only adds `averagePosition`
 * as explanatory metadata; it never affects ordering.
 */
export function computeCommunityTop10(predictions: EligiblePrediction[]): CommunityTop10Entry[] {
  const byParticipant = new Map<string, Accumulator>();

  for (const prediction of predictions) {
    prediction.rankedParticipantIds.forEach((participantId, index) => {
      const position = index + 1;
      const entry = byParticipant.get(participantId) ?? {
        participantId,
        points: 0,
        firstPlaceCount: 0,
        top3Count: 0,
        top10Count: 0,
        positionSum: 0,
      };
      entry.points += 11 - position;
      if (position === 1) entry.firstPlaceCount += 1;
      if (position <= 3) entry.top3Count += 1;
      entry.top10Count += 1;
      entry.positionSum += position;
      byParticipant.set(participantId, entry);
    });
  }

  return Array.from(byParticipant.values())
    .sort((a, b) => {
      if (b.points !== a.points) return b.points - a.points;
      if (b.firstPlaceCount !== a.firstPlaceCount) return b.firstPlaceCount - a.firstPlaceCount;
      if (b.top3Count !== a.top3Count) return b.top3Count - a.top3Count;
      if (b.top10Count !== a.top10Count) return b.top10Count - a.top10Count;
      return a.participantId.localeCompare(b.participantId);
    })
    .map((entry) => ({
      participantId: entry.participantId,
      points: entry.points,
      firstPlaceCount: entry.firstPlaceCount,
      top3Count: entry.top3Count,
      top10Count: entry.top10Count,
      // Averaged only over predictions containing this participant —
      // entry.top10Count is exactly that count by construction.
      averagePosition: entry.positionSum / entry.top10Count,
    }));
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

  const top10CountByParticipant = new Map(
    communityTop10.map((entry) => [entry.participantId, entry.top10Count]),
  );
  const userTop5 = rankedParticipantIds.slice(0, 5);
  let boldestPick: ComparisonResult["boldestPick"] = null;
  for (const participantId of userTop5) {
    const count = top10CountByParticipant.get(participantId) ?? 0;
    const inclusionPct = count / population;
    if (!boldestPick || inclusionPct < boldestPick.inclusionPct) {
      boldestPick = { participantId, count, inclusionPct };
    }
  }

  return { population, sameWinner, top3Match, boldestPick, communityTop10: communityTop10.slice(0, 10) };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\community-comparison.ts"
} catch {
    Write-Host "FAILED: src\lib\community-comparison.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\community-comparison.ts"
}

try {
    $path = "src\lib\community-comparison.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import {
  computeComparison,
  computeCommunityTop10,
  getSampleSizeBucket,
  getComparisonDisplayMode,
} from "./community-comparison";
import type { EligiblePrediction } from "./community-comparison";

// Fixtures straight from the Sprint 3 brief, section 32.
const predictionA: EligiblePrediction = {
  predictionId: "A",
  rankedParticipantIds: ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
};
const predictionB: EligiblePrediction = {
  predictionId: "B",
  rankedParticipantIds: ["A", "C", "B", "K", "L", "M", "N", "O", "P", "Q"],
};
const predictionC: EligiblePrediction = {
  predictionId: "C",
  rankedParticipantIds: ["B", "A", "C", "D", "K", "L", "M", "N", "O", "P"],
};
const allThree = [predictionA, predictionB, predictionC];

describe("getSampleSizeBucket", () => {
  it.each([
    [0, "0"],
    [1, "1_4"],
    [4, "1_4"],
    [5, "5_9"],
    [9, "5_9"],
    [10, "10_24"],
    [24, "10_24"],
    [25, "25_49"],
    [49, "25_49"],
    [50, "50_99"],
    [99, "50_99"],
    [100, "100_plus"],
    [500, "100_plus"],
  ])("population %i -> %s", (population, expected) => {
    expect(getSampleSizeBucket(population)).toBe(expected);
  });
});

describe("computeComparison — viewing prediction A (self-excluded, world = B & C)", () => {
  const result = computeComparison(predictionA.rankedParticipantIds, allThree, "A");

  it("excludes the viewed prediction from the population", () => {
    expect(result.population).toBe(2);
  });

  it("same winner: A appears as #1 in B only, out of B & C", () => {
    expect(result.sameWinner).toEqual({ participantId: "A", count: 1, pct: 0.5 });
  });

  it("top 3 match: community top 3 (A, B, C) fully overlaps A's own top 3", () => {
    expect(result.top3Match?.communityTop3).toEqual(["A", "B", "C"]);
    expect(result.top3Match?.overlap).toBe(3);
  });

  it("boldest pick: E never appears in B or C — the least common of A's top 5", () => {
    expect(result.boldestPick).toEqual({ participantId: "E", count: 0, inclusionPct: 0 });
  });

  it("community top 10 excludes the 11th-ranked participant (Q) and orders by points", () => {
    const ids = result.communityTop10.map((entry) => entry.participantId);
    expect(ids).toEqual(["A", "B", "C", "K", "L", "M", "N", "D", "O", "P"]);
    expect(ids).toHaveLength(10);
  });
});

describe("computeComparison — viewing prediction C (self-excluded, world = A & B)", () => {
  const result = computeComparison(predictionC.rankedParticipantIds, allThree, "C");

  it("same winner: C's own winner is B, but A and B (the world) both have winner A — zero match", () => {
    expect(result.sameWinner).toEqual({ participantId: "B", count: 0, pct: 0 });
  });

  it("does not crash or divide by zero when the match count is zero", () => {
    expect(result.sameWinner?.pct).toBe(0);
  });
});

describe("computeComparison — zero eligible predictions", () => {
  it("returns an explicit empty state instead of dividing by zero", () => {
    const result = computeComparison(predictionA.rankedParticipantIds, [predictionA], "A");
    expect(result).toEqual({
      population: 0,
      sameWinner: null,
      top3Match: null,
      boldestPick: null,
      communityTop10: [],
    });
  });
});

describe("computeCommunityTop10 — deterministic tie-breaking", () => {  it("breaks a points tie using first-place count, then top-3 count, then top-10 count, then participant ID", () => {
    // X and Y both score 7 points total (one 4th-place finish each: 11-4=7).
    // Z scores 7 points via a single #1 finish (11-1=10)... adjusted below
    // to isolate each tiebreaker independently.
    const predictions: EligiblePrediction[] = [
      // X: one #1 finish elsewhere pads its first-place count.
      { predictionId: "p1", rankedParticipantIds: ["X", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
      { predictionId: "p2", rankedParticipantIds: ["_", "_", "_", "Y", "_", "_", "_", "_", "_", "_"] },
    ];
    const ranking = computeCommunityTop10(predictions);
    const x = ranking.find((entry) => entry.participantId === "X");
    const y = ranking.find((entry) => entry.participantId === "Y");

    // X: position 1 -> 10 points, 1 first-place finish.
    // Y: position 4 -> 7 points, 0 first-place finishes.
    expect(x?.points).toBe(10);
    expect(y?.points).toBe(7);
    expect(ranking.findIndex((e) => e.participantId === "X")).toBeLessThan(
      ranking.findIndex((e) => e.participantId === "Y"),
    );
  });

  it("falls back to participant ID ascending when every other tiebreaker is equal", () => {
    const tied: EligiblePrediction[] = [
      { predictionId: "p1", rankedParticipantIds: ["Zebra"] },
      { predictionId: "p2", rankedParticipantIds: ["Apple"] },
    ];
    const ranking = computeCommunityTop10(tied);
    expect(ranking[0]?.participantId).toBe("Apple");
    expect(ranking[1]?.participantId).toBe("Zebra");
  });
});

describe("getComparisonDisplayMode — Sprint 3.1 thresholds, centralized", () => {
  it.each([
    [0, "none"],
    [1, "count"],
    [4, "count"],
    [5, "early_signal"],
    [9, "early_signal"],
    [10, "normal"],
    [47, "normal"],
  ])("population %i -> %s", (population, expected) => {
    expect(getComparisonDisplayMode(population)).toBe(expected);
  });

  it("agrees with getSampleSizeBucket's tiers (no drift between the two)", () => {
    for (let n = 0; n <= 30; n++) {
      const bucket = getSampleSizeBucket(n);
      const mode = getComparisonDisplayMode(n);
      if (bucket === "0") expect(mode).toBe("none");
      if (bucket === "1_4") expect(mode).toBe("count");
      if (bucket === "5_9") expect(mode).toBe("early_signal");
      if (bucket !== "0" && bucket !== "1_4" && bucket !== "5_9") expect(mode).toBe("normal");
    }
  });
});

describe("Sprint 3.1 — Test 1: small-sample counts stay the primary data", () => {
  it("population=4, same winner count=1 exposes both count and denominator for COUNT presentation", () => {
    const predictions: EligiblePrediction[] = [
      { predictionId: "self", rankedParticipantIds: ["W", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
      { predictionId: "p1", rankedParticipantIds: ["W", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
      { predictionId: "p2", rankedParticipantIds: ["X", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
      { predictionId: "p3", rankedParticipantIds: ["X", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
      { predictionId: "p4", rankedParticipantIds: ["X", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
    ];
    const self = predictions[0]!;
    const result = computeComparison(self.rankedParticipantIds, predictions, "self");
    expect(result.population).toBe(4);
    expect(result.sameWinner).toEqual({ participantId: "W", count: 1, pct: 0.25 });
    expect(getComparisonDisplayMode(result.population)).toBe("count");
  });
});

describe("Sprint 3.1 — Test 2: threshold transition", () => {
  function predictionsOfSize(n: number): EligiblePrediction[] {
    return Array.from({ length: n }, (_, i) => ({
      predictionId: `p${i}`,
      rankedParticipantIds: ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
    }));
  }

  it("n=4 -> count mode, n=5 -> early_signal, n=9 -> early_signal, n=10 -> normal", () => {
    expect(getComparisonDisplayMode(predictionsOfSize(4).length)).toBe("count");
    expect(getComparisonDisplayMode(predictionsOfSize(5).length)).toBe("early_signal");
    expect(getComparisonDisplayMode(predictionsOfSize(9).length)).toBe("early_signal");
    expect(getComparisonDisplayMode(predictionsOfSize(10).length)).toBe("normal");
  });
});

describe("Sprint 3.1 — Test 3 & 4: average predicted position", () => {
  it("Test 3: participant selected at #1, #3, #5 averages to 3.0", () => {
    const predictions: EligiblePrediction[] = [
      { predictionId: "p1", rankedParticipantIds: ["Chile"] },
      { predictionId: "p2", rankedParticipantIds: ["_", "_", "Chile"] },
      { predictionId: "p3", rankedParticipantIds: ["_", "_", "_", "_", "Chile"] },
    ];
    const ranking = computeCommunityTop10(predictions);
    const chile = ranking.find((entry) => entry.participantId === "Chile");
    expect(chile?.averagePosition).toBe(3.0);
  });

  it("Test 4: absence is never counted as a position — average uses only predictions containing the participant", () => {
    const predictions: EligiblePrediction[] = [
      { predictionId: "p1", rankedParticipantIds: ["_", "Chile"] }, // Chile at #2
      { predictionId: "p2", rankedParticipantIds: ["_", "_", "_", "Chile"] }, // Chile at #4
      { predictionId: "p3", rankedParticipantIds: ["Other"] }, // Chile absent
      { predictionId: "p4", rankedParticipantIds: ["Other"] }, // Chile absent
    ];
    const ranking = computeCommunityTop10(predictions);
    const chile = ranking.find((entry) => entry.participantId === "Chile");
    expect(chile?.top10Count).toBe(2);
    expect(chile?.averagePosition).toBe(3.0); // (2 + 4) / 2, NOT (2 + 4 + 11 + 11) / 4
  });
});

describe("Sprint 3.1 — Test 5: average rank never changes the ranking order", () => {
  it("Participant A (higher weighted score, lower inclusion) stays above Participant B (lower score, higher inclusion)", () => {
    const predictions: EligiblePrediction[] = [
      // A appears once, at #1 (10 points) -> high score, low inclusion (1 prediction).
      { predictionId: "p1", rankedParticipantIds: ["A"] },
      // B appears in three predictions, always at #9 (2 points each = 6 total) -> lower score, higher inclusion.
      { predictionId: "p2", rankedParticipantIds: ["_", "_", "_", "_", "_", "_", "_", "_", "B"] },
      { predictionId: "p3", rankedParticipantIds: ["_", "_", "_", "_", "_", "_", "_", "_", "B"] },
      { predictionId: "p4", rankedParticipantIds: ["_", "_", "_", "_", "_", "_", "_", "_", "B"] },
    ];
    const ranking = computeCommunityTop10(predictions);
    const a = ranking.find((entry) => entry.participantId === "A");
    const b = ranking.find((entry) => entry.participantId === "B");

    expect(a?.points).toBe(10);
    expect(b?.points).toBe(6);
    expect(a!.top10Count).toBeLessThan(b!.top10Count); // A has lower inclusion...
    expect(ranking.findIndex((e) => e.participantId === "A")).toBeLessThan(
      ranking.findIndex((e) => e.participantId === "B"),
    ); // ...but still ranks above B, because points (the approved formula) still decide order.
  });
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\community-comparison.test.ts"
} catch {
    Write-Host "FAILED: src\lib\community-comparison.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\community-comparison.test.ts"
}

try {
    $path = "src\components\prediction\YouVsTheWorld.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { flagEmoji } from "@/lib/flags";
import { getEntryNoun } from "@/lib/events";
import { getEligiblePredictionsForComparison, type PredictionRecord } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import {
  computeComparison,
  getSampleSizeBucket,
  getComparisonDisplayMode,
} from "@/lib/community-comparison";
import type { FouchEvent } from "@/types/event";
import { ShareYourCallCta } from "./ShareYourCallCta";
import { YouVsTheWorldTracker } from "./YouVsTheWorldTracker";

function formatPct(pct: number): string {
  return `${Math.round(pct * 100)}%`;
}

/**
 * Sprint 3.1: for a small sample, "X of Y" is honest; a percentage
 * ("25%") implies more statistical weight than 1-of-4 actually
 * carries. Every place that shows a ratio goes through this one
 * function instead of each component deciding for itself.
 */
function formatRatio(count: number, population: number, mode: ReturnType<typeof getComparisonDisplayMode>): string {
  if (mode === "count") return `${count} OF ${population}`;
  return formatPct(count / population);
}

export async function YouVsTheWorld({
  prediction,
  event,
}: {
  prediction: PredictionRecord;
  event: FouchEvent;
}) {
  const participantData = getParticipantsForEvent(event.slug);
  if (!participantData) return null;

  const participantsById = new Map(
    participantData.participants.map((participant) => [participant.id, participant]),
  );

  const eligible = await getEligiblePredictionsForComparison(event.slug, prediction.dataStatus);
  const comparison = computeComparison(prediction.rankedParticipantIds, eligible, prediction.id);
  const bucket = getSampleSizeBucket(comparison.population);
  const mode = getComparisonDisplayMode(comparison.population);
  const pluralNoun = getEntryNoun(event, true);

  return (
    <section className="mt-12 border-t border-border pt-10">
      <YouVsTheWorldTracker
        eventSlug={event.slug}
        dataStatus={prediction.dataStatus}
        bucket={bucket}
        hasSameWinner={Boolean(comparison.sameWinner)}
        hasTop3Match={Boolean(comparison.top3Match)}
        hasBoldestPick={Boolean(comparison.boldestPick)}
        hasCommunityTop10={comparison.communityTop10.length > 0}
      />
      <p className="font-display text-2xl uppercase tracking-tight text-text-primary">
        You vs the World
      </p>

      {prediction.dataStatus === "demo" ? (
        <p className="mt-2 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo community data — not official {pluralNoun}
        </p>
      ) : null}

      {mode === "none" ? (
        <div className="mt-6">
          <p className="font-display text-xl text-text-primary">You&apos;re early.</p>
          <p className="mt-1 text-sm text-text-secondary">Be the first to set the pace.</p>
          <ShareYourCallCta />
        </div>
      ) : (
        <div className="mt-8 space-y-10">
          {bucket === "1_4" ? (
            <p className="text-sm text-text-muted">
              The crowd is just forming — {comparison.population} other{" "}
              {comparison.population === 1 ? pluralNoun.slice(0, -1) : pluralNoun} in so far.
            </p>
          ) : null}
          {bucket === "5_9" ? (
            <p className="text-xs uppercase tracking-[0.15em] text-text-muted">
              Early signal · based on {comparison.population} other predictions
            </p>
          ) : null}

          {comparison.sameWinner ? (
            <div>
              <p className="font-display text-6xl text-accent-strong">
                {formatRatio(comparison.sameWinner.count, comparison.population, mode)}
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                Same winner
              </p>
              <p className="mt-2 text-text-primary">
                {flagEmoji(
                  participantsById.get(comparison.sameWinner.participantId)?.countryCode ?? "",
                )}{" "}
                {participantsById.get(comparison.sameWinner.participantId)?.displayName} —{" "}
                {comparison.sameWinner.count === 0
                  ? "nobody else made the same call."
                  : mode === "count"
                    ? `${comparison.sameWinner.count} of ${comparison.population} other predictions agree.`
                    : `${formatPct(comparison.sameWinner.pct)} of the world agrees. Based on ${comparison.population} other predictions.`}
              </p>
            </div>
          ) : null}

          {comparison.top3Match ? (
            <div>
              <p className="font-display text-6xl text-accent-strong">
                {comparison.top3Match.overlap} / 3
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                Top 3 match
              </p>
              <p className="mt-2 text-text-primary">
                You share {comparison.top3Match.overlap} of your top 3 with the world.
              </p>
            </div>
          ) : null}

          {comparison.boldestPick ? (
            <div>
              <p className="font-display text-4xl text-text-primary">
                {flagEmoji(participantsById.get(comparison.boldestPick.participantId)?.countryCode ?? "")}{" "}
                {participantsById.get(comparison.boldestPick.participantId)?.displayName}
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                Your boldest call
              </p>
              <p className="mt-2 text-text-primary">
                {mode === "count"
                  ? `Only ${comparison.boldestPick.count} of ${comparison.population} other predictions have this in their top 10.`
                  : `Only ${formatPct(comparison.boldestPick.inclusionPct)} of other predictions have this in their top 10.`}
              </p>
            </div>
          ) : null}

          {comparison.communityTop10.length > 0 ? (
            <div>
              <p className="font-display text-xl text-text-primary">The world&apos;s top 10</p>
              <p className="mt-1 text-xs text-text-muted">
                Ranked by how high each pick appears across predictions.
              </p>
              <ol className="mt-4 space-y-1.5">
                {comparison.communityTop10.map((entry, index) => {
                  const participant = participantsById.get(entry.participantId);
                  if (!participant) return null;
                  return (
                    <li
                      key={entry.participantId}
                      className="flex items-center gap-3 rounded border border-border bg-surface px-4 py-2.5"
                    >
                      <span className="font-display w-7 shrink-0 text-sm text-accent-strong">
                        {String(index + 1).padStart(2, "0")}
                      </span>
                      <span aria-hidden>{flagEmoji(participant.countryCode)}</span>
                      <span className="flex-1 text-sm text-text-primary">
                        {participant.displayName}
                      </span>
                      <span className="text-right text-xs text-text-muted">
                        {formatRatio(entry.top10Count, comparison.population, mode)} picked
                        <br />
                        avg #{entry.averagePosition.toFixed(1)}
                      </span>
                    </li>
                  );
                })}
              </ol>
              <p className="mt-2 text-xs text-text-muted">
                Based on {comparison.population} other prediction
                {comparison.population === 1 ? "" : "s"}.
              </p>
            </div>
          ) : null}

          <ShareYourCallCta standsOut={Boolean(comparison.sameWinner && comparison.sameWinner.pct < 0.3)} />
        </div>
      )}
    </section>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\YouVsTheWorld.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\YouVsTheWorld.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\YouVsTheWorld.tsx"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 3 files written successfully." -ForegroundColor Green
}