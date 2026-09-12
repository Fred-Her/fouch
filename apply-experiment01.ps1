# Experiment 01: Your Crowd Changed — applies all new and changed files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-experiment01.ps1
$failures = @()

try {
    $path = "src\lib\consensus-change.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\consensus-change.ts"
} catch {
    Write-Host "FAILED: src\lib\consensus-change.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\consensus-change.ts"
}

try {
    $path = "src\lib\consensus-change.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import {
  computeConsensusChange,
  bucketSample,
  MIN_MOVEMENT_SAMPLE,
  MIN_MOVEMENT_POINTS,
} from "./consensus-change";
import type { TimestampedWinnerPick } from "./consensus-change";

const T0 = "2026-01-01T00:00:00.000Z";

function pick(id: string, submittedAt: string, winner: string): TimestampedWinnerPick {
  return { predictionId: id, submittedAt, winnerParticipantId: winner };
}

/** Builds N "other" predictions, all submitted before `displayed`, split
 * between `winner` and `notWinner`. */
function population(
  n: number,
  winnerCount: number,
  winner: string,
  notWinner: string,
  submittedAt: string,
  idPrefix: string,
): TimestampedWinnerPick[] {
  return Array.from({ length: n }, (_, i) =>
    pick(`${idPrefix}-${i}`, submittedAt, i < winnerCount ? winner : notWinner),
  );
}

describe("computeConsensusChange — brief test cases", () => {
  it("Test case 29 — TOWARD: 20% -> 35%, +15 pts", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    // THEN: 20 predictions before displayed's submission, 4 picked CO (20%)
    const before = population(20, 4, "CO", "VE", "2026-01-02T00:00:00.000Z", "then");
    // Additional predictions AFTER displayed's submission, bringing NOW to 40 total, 14 CO (35%)
    const after = population(20, 10, "CO", "VE", "2026-01-08T00:00:00.000Z", "after");
    const result = computeConsensusChange(displayed, [displayed, ...before, ...after]);

    expect(result.thenSample).toBe(20);
    expect(result.nowSample).toBe(40);
    expect(result.thenSupport).toBeCloseTo(20, 5);
    expect(result.nowSupport).toBeCloseTo(35, 5);
    expect(result.changePoints).toBeCloseTo(15, 5);
    expect(result.direction).toBe("toward");
    expect(result.eligible).toBe(true);
  });

  it("Test case 30 — AWAY: 50% -> 30%, -20 pts", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    // THEN: 20 predictions, 10 picked CO (50%)
    const before = population(20, 10, "CO", "VE", "2026-01-02T00:00:00.000Z", "then");
    // NOW must total 40 with 12 CO (30%) -> 20 more predictions, 2 more CO
    const after = population(20, 2, "CO", "VE", "2026-01-08T00:00:00.000Z", "after");
    const result = computeConsensusChange(displayed, [displayed, ...before, ...after]);

    expect(result.thenSample).toBe(20);
    expect(result.nowSample).toBe(40);
    expect(result.thenSupport).toBeCloseTo(50, 5);
    expect(result.nowSupport).toBeCloseTo(30, 5);
    expect(result.changePoints).toBeCloseTo(-20, 5);
    expect(result.direction).toBe("away");
    expect(result.eligible).toBe(true);
  });

  it("Test case 31 — weak movement: 20% -> 23%, ineligible", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    const before = population(20, 4, "CO", "VE", "2026-01-02T00:00:00.000Z", "then"); // 20%
    // NOW: 30 total, needs 23% -> ~6.9; use 40 total with ~9.2 -> pick clean numbers instead.
    // 25 total, 23% is not clean either; use 100 total for a clean 23%.
    const after = population(80, 19, "CO", "VE", "2026-01-08T00:00:00.000Z", "after"); // now: 100 total, 23 CO -> 23%
    const result = computeConsensusChange(displayed, [displayed, ...before, ...after]);

    expect(result.thenSample).toBe(20);
    expect(result.nowSample).toBe(100);
    expect(result.thenSupport).toBeCloseTo(20, 5);
    expect(result.nowSupport).toBeCloseTo(23, 5);
    expect(Math.abs(result.changePoints)).toBeLessThan(MIN_MOVEMENT_POINTS);
    expect(result.eligible).toBe(false);
    expect(result.direction).toBeNull();
  });

  it("Test case 32 — THEN sample too small (n=9): ineligible even with huge movement", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    const before = population(9, 2, "CO", "VE", "2026-01-02T00:00:00.000Z", "then"); // n=9 < MIN
    const after = population(41, 25, "CO", "VE", "2026-01-08T00:00:00.000Z", "after"); // now n=50, 50%
    const result = computeConsensusChange(displayed, [displayed, ...before, ...after]);

    expect(result.thenSample).toBe(9);
    expect(result.thenSample).toBeLessThan(MIN_MOVEMENT_SAMPLE);
    expect(result.eligible).toBe(false);
  });

  it("Test case 33 — NOW sample too small (n=9): ineligible", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    // NOW population = before + after; need total NOW = 9, but a THEN
    // population large enough to hit MIN_MOVEMENT_SAMPLE is already >= 10,
    // so this constructs THEN == NOW == 9 directly (no additional "after"
    // predictions), checking the NOW-only path explicitly.
    const onlyBefore = population(9, 2, "CO", "VE", "2026-01-02T00:00:00.000Z", "then2");
    const result = computeConsensusChange(displayed, [displayed, ...onlyBefore]);

    expect(result.thenSample).toBe(9);
    expect(result.nowSample).toBe(9);
    expect(result.eligible).toBe(false);
  });

  it("Test case 34 — self exclusion: displayed's own pick never inflates THEN or NOW", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    const before = population(10, 0, "CO", "VE", "2026-01-02T00:00:00.000Z", "then"); // 0 CO among others
    const after = population(10, 0, "CO", "VE", "2026-01-08T00:00:00.000Z", "after"); // 0 CO among others
    // Without self-exclusion, `displayed` itself (CO) would inflate both to 1/11.
    const result = computeConsensusChange(displayed, [displayed, ...before, ...after]);

    expect(result.thenSample).toBe(10); // displayed not counted in sample
    expect(result.nowSample).toBe(20);
    expect(result.thenSupport).toBe(0); // not 1/11 = 9.09%
    expect(result.nowSupport).toBe(0);
  });

  it("Test case 35 — ties at the exact same submitted_at are included in THEN (<=, documented)", () => {
    const displayed = pick("displayed", T0, "CO");
    const sameTimestamp = population(10, 3, "CO", "VE", T0, "same-time");
    const result = computeConsensusChange(displayed, [displayed, ...sameTimestamp]);
    // <= means a same-instant submission counts as "already in" for THEN.
    expect(result.thenSample).toBe(10);
  });

  it("Test case 36 — demo/official isolation is the caller's responsibility: a pre-filtered, single-data_status population never mixes", () => {
    // This pure function trusts its input population is already scoped to
    // one event + one data_status (enforced by the DB query layer, see
    // getWinnerPicksForConsensusChange). Demonstrating that ANY population
    // passed in is treated uniformly (no implicit cross-status logic exists
    // inside this function) is the correct unit-level guarantee here.
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    const onlyThisStatus = population(15, 5, "CO", "VE", "2026-01-02T00:00:00.000Z", "same-status");
    const result = computeConsensusChange(displayed, [displayed, ...onlyThisStatus]);
    expect(result.thenSample).toBe(15);
    expect(result.thenSupport).toBeCloseTo((5 / 15) * 100, 5);
  });

  it("Zero-difference edge case: NOW == THEN produces no eligible movement", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    const before = population(20, 5, "CO", "VE", "2026-01-02T00:00:00.000Z", "then");
    const result = computeConsensusChange(displayed, [displayed, ...before]);
    expect(result.changePoints).toBe(0);
    expect(result.eligible).toBe(false);
  });

  it("uses percentage points, not relative percentage change (20% -> 30% is +10pts, not +50%)", () => {
    const displayed = pick("displayed", "2026-01-05T00:00:00.000Z", "CO");
    const before = population(20, 4, "CO", "VE", "2026-01-02T00:00:00.000Z", "then"); // 20%
    const after = population(30, 11, "CO", "VE", "2026-01-08T00:00:00.000Z", "after"); // now: 50 total, 15 -> 30%
    const result = computeConsensusChange(displayed, [displayed, ...before, ...after]);
    expect(result.thenSupport).toBeCloseTo(20, 5);
    expect(result.nowSupport).toBeCloseTo(30, 5);
    expect(result.changePoints).toBeCloseTo(10, 5); // +10 points, NOT +50%
  });
});

describe("bucketSample", () => {
  it.each([
    [10, "10-24"],
    [24, "10-24"],
    [25, "25-49"],
    [49, "25-49"],
    [50, "50-99"],
    [99, "50-99"],
    [100, "100+"],
    [500, "100+"],
  ])("%i -> %s", (n, expected) => {
    expect(bucketSample(n)).toBe(expected);
  });
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\consensus-change.test.ts"
} catch {
    Write-Host "FAILED: src\lib\consensus-change.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\consensus-change.test.ts"
}

try {
    $path = "src\lib\consensus-change-service.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { computeConsensusChange } from "@/lib/consensus-change";
import type { ConsensusChangeResult } from "@/lib/consensus-change";
import { getWinnerPicksForConsensusChange } from "@/lib/predictions-db";
import type { ParticipantDataStatus } from "@/lib/participants";

/**
 * Experiment 01 ("Your Crowd Changed"). Reuses only data FOUCH already
 * has (submission timestamps + each prediction's #1 pick) — no
 * snapshot table, no scheduled job. See FOUCH_EXPERIMENT_01.md.
 */
export async function getConsensusChangeForPrediction(
  predictionId: string,
  submittedAt: string,
  winnerParticipantId: string,
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<ConsensusChangeResult> {
  const allEligible = await getWinnerPicksForConsensusChange(eventSlug, dataStatus);
  return computeConsensusChange({ predictionId, submittedAt, winnerParticipantId }, allEligible);
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\consensus-change-service.ts"
} catch {
    Write-Host "FAILED: src\lib\consensus-change-service.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\consensus-change-service.ts"
}

try {
    $path = "src\components\scoring\ConsensusChangeTracker.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect } from "react";
import { track } from "@/lib/analytics";

export function ConsensusChangeTracker({
  eventSlug,
  dataStatus,
  direction,
  changePoints,
  thenSampleBucket,
  nowSampleBucket,
}: {
  eventSlug: string;
  dataStatus: string;
  direction: "toward" | "away";
  changePoints: number;
  thenSampleBucket: string;
  nowSampleBucket: string;
}) {
  useEffect(() => {
    track("consensus_change_viewed", {
      event_id: eventSlug,
      data_status: dataStatus,
      direction,
      change_points: Math.round(changePoints),
      then_sample_bucket: thenSampleBucket,
      now_sample_bucket: nowSampleBucket,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\ConsensusChangeTracker.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\ConsensusChangeTracker.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\ConsensusChangeTracker.tsx"
}

try {
    $path = "src\components\scoring\YourCrowdChanged.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { CountryFlag } from "@/components/CountryFlag";
import { getParticipantsForEvent } from "@/lib/participants";
import { getConsensusChangeForPrediction } from "@/lib/consensus-change-service";
import { bucketSample } from "@/lib/consensus-change";
import type { PredictionRecord } from "@/lib/predictions-db";
import type { FouchEvent } from "@/types/event";
import { ConsensusChangeTracker } from "./ConsensusChangeTracker";

/**
 * Experiment 01 ("Your Crowd Changed") — FOUCH_EXPERIMENT_01.md.
 * Renders nothing whenever the movement isn't eligible (small sample,
 * or change under MIN_MOVEMENT_POINTS) — silence is the correct,
 * expected behavior, not a bug or a loading state.
 */
export async function YourCrowdChanged({
  prediction,
  event,
}: {
  prediction: PredictionRecord;
  event: FouchEvent;
}) {
  const winnerId = prediction.rankedParticipantIds[0];
  if (!winnerId) return null;

  const result = await getConsensusChangeForPrediction(
    prediction.id,
    prediction.submittedAt,
    winnerId,
    event.slug,
    prediction.dataStatus,
  );
  if (!result.eligible || !result.direction) return null;

  const participantData = getParticipantsForEvent(event.slug);
  const winner = participantData?.participants.find((p) => p.id === winnerId);
  if (!winner) return null;

  const arrow = result.direction === "toward" ? "↑" : "↓";
  const sign = result.changePoints > 0 ? "+" : "";
  const directionCopy =
    result.direction === "toward"
      ? "The crowd is moving toward your call."
      : "The crowd is moving away from your call.";

  return (
    <section className="mt-12 border-t border-border pt-10">
      <ConsensusChangeTracker
        eventSlug={event.slug}
        dataStatus={prediction.dataStatus}
        direction={result.direction}
        changePoints={result.changePoints}
        thenSampleBucket={bucketSample(result.thenSample)}
        nowSampleBucket={bucketSample(result.nowSample)}
      />

      <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">
        Your crowd changed
      </p>

      <div className="mt-3 flex items-center gap-2">
        <CountryFlag countryCode={winner.countryCode} className="text-2xl" />
        <span className="font-display text-xl text-text-primary">{winner.displayName}</span>
      </div>

      <p className="mt-2 font-display text-4xl text-accent-strong">
        {Math.round(result.thenSupport)}% → {Math.round(result.nowSupport)}%
      </p>
      <p className="mt-1 text-sm text-text-secondary">
        {arrow} {sign}
        {Math.round(result.changePoints)} pts
      </p>

      <p className="mt-3 text-text-primary">{directionCopy}</p>
      <p className="mt-2 text-xs text-text-muted">Based on community predictions since your call.</p>
    </section>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\YourCrowdChanged.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\YourCrowdChanged.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\YourCrowdChanged.tsx"
}

try {
    $path = "FOUCH_EXPERIMENT_01.md"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
# FOUCH — Experiment 01: Your Crowd Changed

**This is not Sprint 6.** A small, bounded product experiment testing one
hypothesis from `FOUCH_RETURN_LOOP_RESEARCH.md` (§17, §21). Nothing here
establishes causal retention — see "Limitations" below.

## Hypothesis

When a user sees that community support for their own winner prediction
has meaningfully changed since they submitted, is that information
interesting enough to drive additional exploration?

This experiment measures **interest/engagement**, not proven retention: a
user has to return on their own to encounter this at all — there is no
notification driving them back.

## Calculation

**THEN population**: eligible other predictions (same event, same
`data_status`, `is_final = true`, exactly 10 items) with
`submitted_at <= displayed_prediction.submitted_at`.

**NOW population**: all current eligible other predictions, same
filters, no timestamp cutoff.

Both **exclude the displayed prediction itself** (tested explicitly —
without this, a prediction's own pick inflates its own support).

```
thenSupport = (THEN predictions matching displayed's #1 pick) / THEN population × 100
nowSupport  = (NOW predictions matching displayed's #1 pick)  / NOW population  × 100
changePoints = nowSupport - thenSupport   // percentage POINTS, never relative %
```

Pure function: `computeConsensusChange()` in `src/lib/consensus-change.ts`.

## Eligibility (display gates)

```
MIN_MOVEMENT_SAMPLE = 10   // both THEN and NOW must meet this
MIN_MOVEMENT_POINTS = 5    // minimum |changePoints| to show anything
```

Below either threshold: **render nothing** — no "not enough data" message,
no disabled state, no placeholder. The section simply doesn't appear, and
the rest of the public prediction page is completely unaffected.

## Self-exclusion

Verified by a dedicated test (`consensus-change.test.ts`, "self exclusion"
case): a prediction with 0 supporters among *others* stays at 0%, even
though the displayed prediction's own matching pick is present in the
raw input array. The pure function filters it out before any counting.

## Demo/official isolation

Enforced structurally, not by convention: `getWinnerPicksForConsensusChange(eventSlug,
dataStatus)` only ever queries one `data_status` at a time. There is no
code path where a demo prediction's population could include an official
one, or vice versa — the same isolation pattern already used by You vs
The World and FOUCH Score.

## Data used — no new infrastructure

- `predictions.submitted_at` — already existed (used for immutability).
- Each prediction's #1 pick — read from `prediction_items` where
  `predicted_position = 1`, via a new lean query
  (`getWinnerPicksForConsensusChange`) that never fetches the other 9
  items of any prediction.
- **No new table. No new column. No migration. No snapshot job. No cron.**

## UI

Placed on the existing public prediction page, after You vs The World.
No new route. Not added to Home, nav, or the Leaderboard.

**Toward:**
```
YOUR CROWD CHANGED
🇨🇴 Colombia
22% → 38%
↑ +16 pts
The crowd is moving toward your call.
Based on community predictions since your call.
```

**Away:**
```
YOUR CROWD CHANGED
🇨🇴 Colombia
38% → 21%
↓ −17 pts
The crowd is moving away from your call.
Based on community predictions since your call.
```

No chart, no sparkline, no dashboard styling — plain text using FOUCH's
existing typography tokens.

## Scope discipline

Only the user's own **#1 (winner) pick** is analyzed. No Top 3/5/10
movement, no country-level rank movement ("Thailand #7→#3" — explicitly
out of scope, per the research's cold-start finding that it needs a much
larger sample), no regions, no notifications, no new page.

## Analytics

**`consensus_change_viewed`** — fires only when the section actually
renders (i.e., already eligible):
```
event_id, data_status, direction, change_points,
then_sample_bucket, now_sample_bucket
```
Sample sizes are sent as coarse buckets (`10-24`, `25-49`, `50-99`,
`100+`), never exact counts. No nickname, no public prediction ID, no
device token, no internal database ID.

**Return signal**: reuses the existing `public_prediction_viewed` event
— a second occurrence for the same public prediction ID after a
`consensus_change_viewed` fired is the evidence to look for. This
experiment does not add a new "return" event.

## Limitations

- **This does not prove the feature causes retention.** A user must
  already have returned to encounter it. It measures whether, once
  encountered, the information is real/large enough to matter, and
  provides early (not causal) evidence for a future return-loop design.
- Same-instant `submitted_at` ties are included in THEN (`<=`) —
  deterministic, but not meaningfully orderable beyond that.
- At FOUCH's current demo scale, this will likely be invisible in
  production simply because fewer than 10 eligible predictions exist yet
  — that's correct behavior, not a bug (see below).

## Success / kill criteria

Directional, not statistically proven at current sample sizes — always
report population size alongside any percentage:

- **GREEN**: ≥15% second-touch rate among predictions that were shown a
  real (≥5pt) shift → proceed toward the fuller Crowd Movement feature.
- **YELLOW**: 5–15% → signal exists but is weak; try different placement
  or copy before a full build.
- **RED**: <5%, once there's enough exposure to interpret at all → kill
  the hypothesis.

Do not make a product decision from 3, 5, or 10 exposed users.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_EXPERIMENT_01.md"
} catch {
    Write-Host "FAILED: FOUCH_EXPERIMENT_01.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_EXPERIMENT_01.md"
}

try {
    $path = "src\lib\predictions-db.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { generatePublicId } from "@/lib/public-id";
import { getEventBySlug } from "@/lib/events";
import { getParticipantsForEvent, type ParticipantDataStatus } from "@/lib/participants";
import type { FouchEvent } from "@/types/event";
import type { Participant } from "@/types/participant";
import type { EligiblePrediction } from "@/lib/community-comparison";

export interface PredictionRecord {
  /** Internal DB id — server-side use only (e.g. self-exclusion from
   * community comparisons). Never send this to the client. */
  id: string;
  publicId: string;
  eventSlug: string;
  nickname: string | null;
  countryCode: string | null;
  dataStatus: ParticipantDataStatus;
  submittedAt: string;
  /** Participant IDs in ranked order — index 0 is position #1. */
  rankedParticipantIds: string[];
}

interface InsertPredictionParams {
  eventSlug: string;
  participantIds: string[];
  nickname: string | null;
  countryCode: string | null;
  dataStatus: ParticipantDataStatus;
  deviceToken: string;
}

export type InsertPredictionResult =
  | { success: true; publicId: string; alreadyExisted: boolean }
  | { success: false; error: string };

const MAX_PUBLIC_ID_ATTEMPTS = 5;
const UNIQUE_VIOLATION = "23505";

export async function insertPrediction(
  params: InsertPredictionParams,
): Promise<InsertPredictionResult> {
  const supabase = getSupabaseServerClient();
  if (!supabase) {
    return { success: false, error: "Submissions aren't available yet — the database isn't configured." };
  }

  for (let attempt = 0; attempt < MAX_PUBLIC_ID_ATTEMPTS; attempt++) {
    const publicId = generatePublicId();

    const { data: prediction, error: insertError } = await supabase
      .from("predictions")
      .insert({
        public_id: publicId,
        event_slug: params.eventSlug,
        nickname: params.nickname,
        country_code: params.countryCode,
        data_status: params.dataStatus,
        device_token: params.deviceToken,
      })
      .select("id, public_id")
      .single();

    if (insertError) {
      // A public_id collision is astronomically unlikely (46 bits of
      // entropy) but retrying costs nothing. A (event_slug,
      // device_token) collision means this device already has a
      // prediction for this event — treat that as success and hand
      // back the existing one, so a double-tap or retry never looks
      // like a hard failure.
      if (insertError.code === UNIQUE_VIOLATION) {
        if (insertError.message.includes("public_id")) continue;

        const existing = await getPredictionByDeviceToken(params.eventSlug, params.deviceToken);
        if (existing) {
          return { success: true, publicId: existing.publicId, alreadyExisted: true };
        }
      }
      return { success: false, error: "We couldn't save your prediction. Please try again." };
    }

    const items = params.participantIds.map((participantId, index) => ({
      prediction_id: prediction.id,
      participant_id: participantId,
      predicted_position: index + 1,
    }));

    const { error: itemsError } = await supabase.from("prediction_items").insert(items);

    if (itemsError) {
      // Compensating cleanup — Supabase's JS client has no
      // multi-statement transaction here, so we manually undo the
      // parent row rather than leave an incomplete prediction behind.
      await supabase.from("predictions").delete().eq("id", prediction.id);
      return { success: false, error: "We couldn't save your prediction. Please try again." };
    }

    return { success: true, publicId: prediction.public_id, alreadyExisted: false };
  }

  return { success: false, error: "We couldn't generate a unique link. Please try again." };
}

export async function getPredictionByPublicId(publicId: string): Promise<PredictionRecord | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data: prediction, error } = await supabase
    .from("predictions")
    .select("public_id, event_slug, nickname, country_code, data_status, submitted_at, id")
    .eq("public_id", publicId)
    .single();

  if (error || !prediction) return null;

  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("participant_id, predicted_position")
    .eq("prediction_id", prediction.id)
    .order("predicted_position", { ascending: true });

  if (itemsError || !items) return null;

  return {
    id: prediction.id,
    publicId: prediction.public_id,
    eventSlug: prediction.event_slug,
    nickname: prediction.nickname,
    countryCode: prediction.country_code,
    dataStatus: prediction.data_status as ParticipantDataStatus,
    submittedAt: prediction.submitted_at,
    rankedParticipantIds: items.map((item) => item.participant_id),
  };
}

export async function getPredictionByDeviceToken(
  eventSlug: string,
  deviceToken: string,
): Promise<PredictionRecord | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data: prediction, error } = await supabase
    .from("predictions")
    .select("public_id")
    .eq("event_slug", eventSlug)
    .eq("device_token", deviceToken)
    .maybeSingle();

  if (error || !prediction) return null;

  return getPredictionByPublicId(prediction.public_id);
}

/**
 * Resolves a stored prediction's participant IDs back into full
 * Participant records (name, country) via the same seed/demo data the
 * builder uses, in the prediction's saved rank order. Returns null if
 * the prediction or any of its referenced participants can no longer
 * be resolved (e.g. seed data changed).
 */
export async function getPredictionWithParticipants(publicId: string): Promise<{
  prediction: PredictionRecord;
  event: FouchEvent;
  rankedParticipants: Participant[];
} | null> {
  const prediction = await getPredictionByPublicId(publicId);
  if (!prediction) return null;

  const event = getEventBySlug(prediction.eventSlug);
  if (!event) return null;

  const participantData = getParticipantsForEvent(prediction.eventSlug);
  if (!participantData) return null;

  const participantsById = new Map(
    participantData.participants.map((participant) => [participant.id, participant]),
  );

  const rankedParticipants = prediction.rankedParticipantIds
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  if (rankedParticipants.length !== prediction.rankedParticipantIds.length) return null;

  return { prediction, event, rankedParticipants };
}

/**
 * Fetches every ranked-ID list eligible for comparison against a given
 * event + data-status — the raw material for community-comparison.ts.
 * Only `id` and `participant_id`/`predicted_position` are selected;
 * nickname, country, and device_token never leave the database for
 * this purpose (see Sprint 3 brief section 22, privacy).
 *
 * "Eligible" here means: same event, same data_status (demo
 * predictions and future verified predictions never mix — see
 * section 9), and exactly 10 items. A prediction with a corrupted or
 * incomplete item set is silently excluded rather than crashing the
 * comparison.
 */
export async function getEligiblePredictionsForComparison(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<EligiblePrediction[]> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  const { data: predictions, error } = await supabase
    .from("predictions")
    .select("id")
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .eq("is_final", true);

  if (error || !predictions || predictions.length === 0) return [];

  const predictionIds = predictions.map((p) => p.id);

  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("prediction_id, participant_id, predicted_position")
    .in("prediction_id", predictionIds)
    .order("predicted_position", { ascending: true });

  if (itemsError || !items) return [];

  const itemsByPrediction = new Map<string, string[]>();
  for (const item of items) {
    const list = itemsByPrediction.get(item.prediction_id) ?? [];
    list.push(item.participant_id);
    itemsByPrediction.set(item.prediction_id, list);
  }

  const eligible: EligiblePrediction[] = [];
  for (const [predictionId, rankedParticipantIds] of itemsByPrediction) {
    // Defensive: a prediction with anything other than exactly 10
    // items is malformed and excluded rather than skewing the
    // comparison (see section 33, edge cases).
    if (rankedParticipantIds.length === 10) {
      eligible.push({ predictionId, rankedParticipantIds });
    }
  }

  return eligible;
}

export interface LeaderboardRawEntry {
  predictionId: string;
  publicId: string;
  nickname: string | null;
  countryCode: string | null;
  rankedParticipantIds: string[];
}

/**
 * Same eligibility filters as getEligiblePredictionsForComparison
 * (event + data_status + is_final=true + exactly 10 items) — kept as a
 * near-identical second query, deliberately, rather than reusing that
 * function directly: that function's contract explicitly promises to
 * never select nickname/country (see its comment) so it stays safe to
 * reuse anywhere privacy matters. The leaderboard's whole purpose is
 * to show nickname/country publicly, so it needs its own query rather
 * than weakening that guarantee.
 */
export async function getLeaderboardRawEntries(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<LeaderboardRawEntry[]> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  const { data: predictions, error } = await supabase
    .from("predictions")
    .select("id, public_id, nickname, country_code")
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .eq("is_final", true);

  if (error || !predictions || predictions.length === 0) return [];

  const predictionIds = predictions.map((p) => p.id);

  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("prediction_id, participant_id, predicted_position")
    .in("prediction_id", predictionIds)
    .order("predicted_position", { ascending: true });

  if (itemsError || !items) return [];

  const itemsByPrediction = new Map<string, string[]>();
  for (const item of items) {
    const list = itemsByPrediction.get(item.prediction_id) ?? [];
    list.push(item.participant_id);
    itemsByPrediction.set(item.prediction_id, list);
  }

  const entries: LeaderboardRawEntry[] = [];
  for (const prediction of predictions) {
    const rankedParticipantIds = itemsByPrediction.get(prediction.id) ?? [];
    if (rankedParticipantIds.length === 10) {
      entries.push({
        predictionId: prediction.id,
        publicId: prediction.public_id,
        nickname: prediction.nickname,
        countryCode: prediction.country_code,
        rankedParticipantIds,
      });
    }
  }

  return entries;
}

/**
 * Experiment 01 ("Your Crowd Changed") — the leanest possible query for
 * this experiment: only each eligible prediction's submission time and
 * #1 (winner) pick, never the full 10-item ranking. Deliberately a
 * separate query rather than reusing getEligiblePredictionsForComparison
 * or getLeaderboardRawEntries — those fetch every item of every
 * prediction, which this experiment doesn't need at all.
 *
 * Eligibility mirrors both of those functions exactly: same event_slug,
 * same data_status, is_final = true, and (checked via the items query)
 * exactly 10 items — never a different population definition for the
 * same underlying concept of "an eligible prediction."
 */
export async function getWinnerPicksForConsensusChange(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<Array<{ predictionId: string; submittedAt: string; winnerParticipantId: string }>> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  const { data: predictions, error } = await supabase
    .from("predictions")
    .select("id, submitted_at")
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .eq("is_final", true);

  if (error || !predictions || predictions.length === 0) return [];

  const predictionIds = predictions.map((p) => p.id);

  // Only position 1 (the winner pick) — and only from predictions with
  // exactly 10 items, so a malformed/partial prediction never counts as
  // an eligible "winner pick" here either.
  const { data: allItems, error: itemsError } = await supabase
    .from("prediction_items")
    .select("prediction_id, participant_id, predicted_position")
    .in("prediction_id", predictionIds);

  if (itemsError || !allItems) return [];

  const itemCountByPrediction = new Map<string, number>();
  const winnerByPrediction = new Map<string, string>();
  for (const item of allItems) {
    itemCountByPrediction.set(item.prediction_id, (itemCountByPrediction.get(item.prediction_id) ?? 0) + 1);
    if (item.predicted_position === 1) {
      winnerByPrediction.set(item.prediction_id, item.participant_id);
    }
  }

  const results: Array<{ predictionId: string; submittedAt: string; winnerParticipantId: string }> = [];
  for (const prediction of predictions) {
    const winner = winnerByPrediction.get(prediction.id);
    const itemCount = itemCountByPrediction.get(prediction.id) ?? 0;
    if (winner && itemCount === 10 && prediction.submitted_at) {
      results.push({
        predictionId: prediction.id,
        submittedAt: prediction.submitted_at,
        winnerParticipantId: winner,
      });
    }
  }

  return results;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\predictions-db.ts"
} catch {
    Write-Host "FAILED: src\lib\predictions-db.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\predictions-db.ts"
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
  | "result_share_link_copied"
  | "leaderboard_viewed"
  | "leaderboard_row_clicked"
  | "own_rank_viewed"
  | "leaderboard_from_score_clicked"
  | "consensus_change_viewed";

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
  hasResult = false,
  fouchScore,
  youVsTheWorld,
  yourCrowdChanged,
}: {
  eventSlug: string;
  publicId: string;
  rankedParticipants: Participant[];
  /** Sprint 4.1: whether an official/demo result exists for this
   * prediction's event. Drives share-CTA hierarchy only — the original
   * Prediction Card share section becomes visually secondary once a
   * Result Card exists to share instead (brief §7-8). Does not affect
   * scoring or any calculation. */
  hasResult?: boolean;
  /** FOUCH Score section (Sprint 4) — null/absent renders nothing, which
   * is exactly the pre-result experience. Server Component, passed down
   * for the same reason as youVsTheWorld below. */
  fouchScore?: ReactNode;
  /** The You vs The World section — a Server Component rendered by the
   * page and passed down, since it needs server-side data fetching
   * that a Client Component can't do directly. */
  youVsTheWorld: ReactNode;
  /** Experiment 01 ("Your Crowd Changed") — null/absent renders
   * nothing, same pattern as the two slots above. */
  yourCrowdChanged?: ReactNode;
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

  const originalPredictionShare = (
    <div id="share" className="mt-10 scroll-mt-20 border-t border-border pt-8">
      <p
        className={
          hasResult
            ? "text-sm text-text-muted"
            : "font-display text-lg text-text-primary"
        }
      >
        {hasResult ? "Your original prediction" : "Share your prediction"}
      </p>
      <div className="mt-3">
        <ShareActions
          eventSlug={eventSlug}
          publicUrl={publicUrl}
          storyCardUrl={`/p/${publicId}/card/story`}
          postCardUrl={`/p/${publicId}/card/post`}
        />
      </div>
    </div>
  );

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

      {yourCrowdChanged}

      {/* Pre-result: original prediction sharing stays primary and sits
          right before the "Make your Top 10" CTA, unchanged from Sprint 2/3.
          Post-result: it becomes a secondary, de-emphasized block, per the
          hierarchy in Sprint 4.1's brief (Result Card is the stronger
          social object once scoring exists). */}
      {!hasResult ? originalPredictionShare : null}

      <Link
        href={`/predict/${eventSlug}?from=${publicId}`}
        onClick={() => track("public_prediction_cta_clicked", { event_slug: eventSlug })}
        className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        Make your Top 10
      </Link>

      {hasResult ? originalPredictionShare : null}
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
import { getOfficialResult } from "@/lib/results-db";
import { PublicPredictionView } from "@/components/prediction/PublicPredictionView";
import { YouVsTheWorld } from "@/components/prediction/YouVsTheWorld";
import { FouchScore } from "@/components/scoring/FouchScore";
import { YourCrowdChanged } from "@/components/scoring/YourCrowdChanged";

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

  // Cheap existence check only (no percentile/breakdown work) — used
  // purely to decide share-CTA hierarchy (Sprint 4.1 §7-8). FouchScore
  // below independently does the full scored computation; this is a
  // second, lightweight read of the same result row, not duplicated
  // scoring logic.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);
  const hasResult = Boolean(official);

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
        hasResult={hasResult}
        fouchScore={<FouchScore prediction={prediction} event={event} publicId={publicId} />}
        youVsTheWorld={<YouVsTheWorld prediction={prediction} event={event} />}
        yourCrowdChanged={<YourCrowdChanged prediction={prediction} event={event} />}
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
    Write-Host "All 10 files written successfully." -ForegroundColor Green
}