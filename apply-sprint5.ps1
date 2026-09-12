# Sprint 5: Event Leaderboard — applies all new and changed files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-sprint5.ps1
$failures = @()

try {
    $path = "vitest.config.mts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { defineConfig } from "vitest/config";
import { resolve } from "node:path";

// Vitest doesn't read tsconfig "paths" automatically. Previous test
// files avoided this by only using relative imports; leaderboard.ts
// needs the project's standard "@/..." alias (src/lib/scoring), so
// this maps it the same way Next.js already does via tsconfig.json.
export default defineConfig({
  resolve: {
    alias: {
      "@": resolve(__dirname, "./src"),
    },
  },
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     vitest.config.mts"
} catch {
    Write-Host "FAILED: vitest.config.mts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "vitest.config.mts"
}

try {
    $path = "src\lib\leaderboard.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\leaderboard.ts"
} catch {
    Write-Host "FAILED: src\lib\leaderboard.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\leaderboard.ts"
}

try {
    $path = "src\lib\leaderboard.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { assignCompetitionRanks, buildLeaderboard } from "./leaderboard";

describe("assignCompetitionRanks — competition ranking (1224, never dense 1223)", () => {
  it("[95,90,85,80] -> [1,2,3,4]", () => {
    expect(assignCompetitionRanks([95, 90, 85, 80])).toEqual([1, 2, 3, 4]);
  });

  it("[95,90,90,80] -> [1,2,2,4]", () => {
    expect(assignCompetitionRanks([95, 90, 90, 80])).toEqual([1, 2, 2, 4]);
  });

  it("[90,90,90] -> [1,1,1]", () => {
    expect(assignCompetitionRanks([90, 90, 90])).toEqual([1, 1, 1]);
  });

  it("[100,99,99,99,75] -> [1,2,2,2,5] (not dense [1,2,2,2,3])", () => {
    expect(assignCompetitionRanks([100, 99, 99, 99, 75])).toEqual([1, 2, 2, 2, 5]);
  });

  it("empty input -> empty output", () => {
    expect(assignCompetitionRanks([])).toEqual([]);
  });

  it("single entry -> rank 1", () => {
    expect(assignCompetitionRanks([42])).toEqual([1]);
  });
});

describe("buildLeaderboard", () => {
  it("ranks by displayScore, breaking display order (not rank) ties deterministically by publicId", () => {
    const entries = buildLeaderboard([
      { publicId: "zzz", nickname: "Zed", countryCode: null, displayScore: 88 },
      { publicId: "aaa", nickname: "Ana", countryCode: null, displayScore: 88 },
      { publicId: "bbb", nickname: "Bo", countryCode: null, displayScore: 92 },
    ]);
    expect(entries.map((e) => e.publicId)).toEqual(["bbb", "aaa", "zzz"]);
    expect(entries.map((e) => e.rank)).toEqual([1, 2, 2]);
  });

  it("assigns correct score bands via the existing frozen helper", () => {
    const entries = buildLeaderboard([
      { publicId: "a", nickname: null, countryCode: null, displayScore: 95 },
      { publicId: "b", nickname: null, countryCode: null, displayScore: 22 },
    ]);
    expect(entries[0]?.band).toBe("ELITE");
    expect(entries[1]?.band).toBe("MISSED_IT");
  });

  it("never uses submission time — order depends only on score, then publicId", () => {
    // Deliberately reversed input order — result must not reflect input order.
    const entries = buildLeaderboard([
      { publicId: "later", nickname: null, countryCode: null, displayScore: 50 },
      { publicId: "earlier", nickname: null, countryCode: null, displayScore: 80 },
    ]);
    expect(entries[0]?.publicId).toBe("earlier");
  });
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\leaderboard.test.ts"
} catch {
    Write-Host "FAILED: src\lib\leaderboard.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\leaderboard.test.ts"
}

try {
    $path = "src\lib\leaderboard-service.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { scorePrediction, computePercentile } from "@/lib/scoring";
import type { PercentileResult } from "@/lib/scoring";
import { getOfficialResult } from "@/lib/results-db";
import { getLeaderboardRawEntries } from "@/lib/predictions-db";
import { buildLeaderboard } from "@/lib/leaderboard";
import type { LeaderboardEntry } from "@/lib/leaderboard";
import type { ParticipantDataStatus } from "@/lib/participants";

const TOP_N = 50;
/** How many rows on either side of the viewer to show when they fall
 * outside the visible Top N (Sprint 5 brief §19). */
const NEIGHBOR_WINDOW = 2;

export interface EventLeaderboard {
  status: "no_result" | "scored";
  dataStatus: ParticipantDataStatus;
  totalCount: number;
  topEntries: LeaderboardEntry[];
  /** Present only when a viewerPublicId was given and it resolved to
   * an eligible, scored prediction for this event. */
  viewer: {
    entry: LeaderboardEntry;
    /** Only populated when the viewer's rank falls outside topEntries. */
    neighbors: LeaderboardEntry[];
    percentile: PercentileResult;
  } | null;
}

/**
 * Builds the full event leaderboard. Ranking happens here, server-side,
 * over every eligible entry — the client only ever receives the
 * already-ranked, already-trimmed result (brief §19-21), never the raw
 * prediction list.
 *
 * Returns `{ status: "no_result" }` when there's no official/demo
 * result yet — the page renders a "leaderboard locked" state, never a
 * fabricated empty board (brief §28).
 */
export async function getEventLeaderboard(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
  viewerPublicId?: string,
): Promise<EventLeaderboard> {
  const official = await getOfficialResult(eventSlug, dataStatus);
  if (!official) {
    return { status: "no_result", dataStatus, totalCount: 0, topEntries: [], viewer: null };
  }

  const rawEntries = await getLeaderboardRawEntries(eventSlug, dataStatus);

  const scored = rawEntries.map((entry) => ({
    ...entry,
    breakdown: scorePrediction(entry.rankedParticipantIds, official),
  }));

  const leaderboard = buildLeaderboard(
    scored.map((entry) => ({
      publicId: entry.publicId,
      nickname: entry.nickname,
      countryCode: entry.countryCode,
      displayScore: entry.breakdown.displayScore,
    })),
  );

  const topEntries = leaderboard.slice(0, TOP_N);

  let viewer: EventLeaderboard["viewer"] = null;
  if (viewerPublicId) {
    const viewerIndex = leaderboard.findIndex((e) => e.publicId === viewerPublicId);
    if (viewerIndex !== -1) {
      const viewerEntry = leaderboard[viewerIndex]!;
      const viewerScored = scored.find((e) => e.publicId === viewerPublicId)!;
      const otherScores = scored
        .filter((e) => e.publicId !== viewerPublicId)
        .map((e) => e.breakdown.score);
      const percentile = computePercentile(viewerScored.breakdown.score, otherScores);

      const inTop = viewerIndex < TOP_N;
      const neighbors = inTop
        ? []
        : leaderboard.slice(
            Math.max(0, viewerIndex - NEIGHBOR_WINDOW),
            Math.min(leaderboard.length, viewerIndex + NEIGHBOR_WINDOW + 1),
          );

      viewer = { entry: viewerEntry, neighbors, percentile };
    }
  }

  return { status: "scored", dataStatus, totalCount: leaderboard.length, topEntries, viewer };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\leaderboard-service.ts"
} catch {
    Write-Host "FAILED: src\lib\leaderboard-service.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\leaderboard-service.ts"
}

try {
    $path = "src\components\scoring\LeaderboardTracker.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect } from "react";
import { track } from "@/lib/analytics";

export function LeaderboardTracker({
  eventSlug,
  dataStatus,
  leaderboardSize,
  ownRank,
  ownScoreBand,
}: {
  eventSlug: string;
  dataStatus: string;
  leaderboardSize: number;
  ownRank?: number;
  ownScoreBand?: string;
}) {
  useEffect(() => {
    track("leaderboard_viewed", {
      event_slug: eventSlug,
      data_status: dataStatus,
      leaderboard_size: leaderboardSize,
      is_own_prediction: Boolean(ownRank),
    });
    if (ownRank) {
      track("own_rank_viewed", {
        event_slug: eventSlug,
        rank: ownRank,
        score_band: ownScoreBand,
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\LeaderboardTracker.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\LeaderboardTracker.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\LeaderboardTracker.tsx"
}

try {
    $path = "src\components\scoring\LeaderboardRow.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { CountryFlag } from "@/components/CountryFlag";
import { TrackedLink } from "@/components/TrackedLink";
import type { LeaderboardEntry } from "@/lib/leaderboard";

export function LeaderboardRow({
  entry,
  eventSlug,
  isViewer,
  prominent,
}: {
  entry: LeaderboardEntry;
  eventSlug: string;
  isViewer: boolean;
  /** Top 3 get slightly stronger typography — restrained, no medals. */
  prominent: boolean;
}) {
  return (
    <TrackedLink
      href={`/p/${entry.publicId}`}
      event="leaderboard_row_clicked"
      eventProperties={{ event_slug: eventSlug, rank: entry.rank, score_band: entry.band }}
      className={`flex items-center gap-3 rounded border px-4 py-3 transition-colors hover:border-accent ${
        isViewer ? "border-accent bg-accent/10" : "border-border bg-surface"
      }`}
    >
      <span
        className={`font-display shrink-0 text-accent-strong ${prominent ? "w-10 text-3xl" : "w-8 text-base"}`}
      >
        {String(entry.rank).padStart(2, "0")}
      </span>
      <CountryFlag countryCode={entry.countryCode} className={prominent ? "text-2xl" : "text-lg"} />
      <span className={`flex-1 truncate text-text-primary ${prominent ? "text-lg" : "text-sm"}`}>
        {entry.nickname || "Anonymous"}
        {isViewer ? <span className="ml-2 text-xs uppercase tracking-wide text-accent-strong">You</span> : null}
      </span>
      <span className={`font-display text-text-primary ${prominent ? "text-2xl" : "text-base"}`}>
        {entry.score}
      </span>
    </TrackedLink>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\LeaderboardRow.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\LeaderboardRow.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\LeaderboardRow.tsx"
}

try {
    $path = "src\app\events\[slug]\leaderboard\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getEventBySlug, getEntryNoun } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { getEventLeaderboard } from "@/lib/leaderboard-service";
import { MIN_PERCENTILE_SAMPLE } from "@/lib/scoring";
import { LeaderboardRow } from "@/components/scoring/LeaderboardRow";
import { LeaderboardTracker } from "@/components/scoring/LeaderboardTracker";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = getEventBySlug(slug);
  if (!event) return {};

  const participantData = getParticipantsForEvent(slug);
  const isDemo = participantData?.status === "demo";

  return {
    title: `${event.name} Predictions Leaderboard | FOUCH`,
    description: isDemo
      ? "A demo FOUCH predictions leaderboard — not an official result."
      : "See how FOUCH predictions ranked after the result.",
    // Demo leaderboards should never be indexed as if they were real —
    // same non-indexing posture as public prediction pages (Sprint 2).
    robots: isDemo ? { index: false, follow: true } : undefined,
  };
}

export default async function EventLeaderboardPage({
  params,
  searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ from?: string }>;
}) {
  const { slug } = await params;
  const { from } = await searchParams;

  const event = getEventBySlug(slug);
  if (!event) notFound();

  const participantData = getParticipantsForEvent(slug);
  if (!participantData) notFound();

  const leaderboard = await getEventLeaderboard(slug, participantData.status, from);
  const pluralNoun = getEntryNoun(event, true);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>

      <h1 className="mt-6 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-1 font-display text-xl uppercase tracking-tight text-text-primary">
        Event leaderboard
      </p>
      <p className="mt-2 text-sm text-text-secondary">See who called it best.</p>

      {participantData.status === "demo" ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo leaderboard — not an official outcome
        </p>
      ) : null}

      {leaderboard.status === "no_result" ? (
        <div className="mt-10 rounded border border-border bg-surface p-6">
          <p className="font-display text-xl text-text-primary">Leaderboard locked</p>
          <p className="mt-2 text-sm text-text-secondary">
            Results will appear here once {event.name} has been scored.
          </p>
          <Link
            href={`/predict/${slug}`}
            className="mt-5 inline-flex items-center justify-center rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            Make your call
          </Link>
        </div>
      ) : (
        <div className="mt-8">
          <LeaderboardTracker
            eventSlug={slug}
            dataStatus={leaderboard.dataStatus}
            leaderboardSize={leaderboard.totalCount}
            ownRank={leaderboard.viewer?.entry.rank}
            ownScoreBand={leaderboard.viewer?.entry.band}
          />

          {leaderboard.totalCount === 0 ? (
            <p className="text-sm text-text-muted">No scored predictions yet.</p>
          ) : leaderboard.totalCount === 1 ? (
            <p className="text-sm text-text-muted">First call on the board.</p>
          ) : leaderboard.totalCount <= 4 ? (
            <p className="text-sm text-text-muted">The leaderboard is just getting started.</p>
          ) : null}

          {leaderboard.viewer ? (
            <div className="mt-6 rounded border border-accent/40 bg-accent/10 p-5">
              <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-secondary">
                Your finish
              </p>
              <p className="mt-2 font-display text-4xl text-accent-strong">
                #{leaderboard.viewer.entry.rank} of {leaderboard.totalCount}
              </p>
              <p className="mt-1 text-sm text-text-secondary">
                Fouch score {leaderboard.viewer.entry.score}
                {leaderboard.viewer.percentile.percentile !== null
                  ? ` · Top ${Math.max(1, Math.round(100 - leaderboard.viewer.percentile.percentile))}%`
                  : ""}
              </p>
              {leaderboard.viewer.percentile.percentile === null ? (
                <p className="mt-1 text-xs text-text-muted">
                  World ranking unlocks at {MIN_PERCENTILE_SAMPLE} predictions.
                </p>
              ) : null}
            </div>
          ) : null}

          {leaderboard.topEntries.length > 0 ? (
            <ol className="mt-8 space-y-2">
              {leaderboard.topEntries.map((entry) => (
                <li key={entry.publicId}>
                  <LeaderboardRow
                    entry={entry}
                    eventSlug={slug}
                    isViewer={entry.publicId === from}
                    prominent={entry.rank <= 3}
                  />
                </li>
              ))}
            </ol>
          ) : null}

          {leaderboard.viewer && leaderboard.viewer.neighbors.length > 0 ? (
            <div className="mt-8 border-t border-border pt-6">
              <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">
                Your neighborhood
              </p>
              <ol className="mt-3 space-y-2">
                {leaderboard.viewer.neighbors.map((entry) => (
                  <li key={entry.publicId}>
                    <LeaderboardRow
                      entry={entry}
                      eventSlug={slug}
                      isViewer={entry.publicId === from}
                      prominent={false}
                    />
                  </li>
                ))}
              </ol>
            </div>
          ) : null}

          <p className="mt-6 text-xs text-text-muted">
            Showing the top {Math.min(50, leaderboard.totalCount)} {pluralNoun === "picks" ? "predictions" : pluralNoun}
            {leaderboard.totalCount > 50 ? ` of ${leaderboard.totalCount}` : ""}.
          </p>
        </div>
      )}
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\events\[slug]\leaderboard\page.tsx"
} catch {
    Write-Host "FAILED: src\app\events\[slug]\leaderboard\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\events\[slug]\leaderboard\page.tsx"
}

try {
    $path = "FOUCH_SPRINT5_LEADERBOARD.md"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
# FOUCH Sprint 5 — Event Leaderboard

## Product purpose

Answers one question: *"I got a FOUCH Score of 82 — where did I finish?"*
Strictly event-scoped. Not a global leaderboard, rating, or profile system
— see `FOUCH_SCORING_RESEARCH.md` §16 for why cross-event scores aren't
casually comparable.

## Route

`/events/[event-slug]/leaderboard` — e.g. `/events/miss-universe-2026/leaderboard`.
Accepts an optional `?from=<publicId>` query param (same convention as the
existing `?from=` attribution param) to identify the viewer's own
prediction and unlock "Your Finish."

## Eligibility

Identical filters to Sprint 3/4's `getEligiblePredictionsForComparison`
(same event, same `data_status`, `is_final = true`, exactly 10 items) —
implemented as a second, near-identical query
(`getLeaderboardRawEntries`) rather than reusing that function directly,
because that function's contract explicitly promises never to select
nickname/country for privacy reasons elsewhere. The leaderboard's whole
purpose is to show those fields publicly, so it needs its own query
rather than weakening that guarantee for everyone else.

## Ranking semantics

**Competition ranking ("1224"), not dense ranking ("1223").** A tie does
not compress the ranks below it:

```
scores: 100  99  99  99  75
ranks:    1   2   2   2   5
```

Ranking is based on the same rounded `displayScore` the UI already shows
(not hidden full-precision differences) — two rows both reading "88" are
genuinely tied. Ties are broken for **display order only** (not rank) by
`publicId`, deterministically — submission time is never used as a
tiebreaker, per the brief.

Pure, tested function: `assignCompetitionRanks()` in `src/lib/leaderboard.ts`.

## Privacy

Leaderboard rows expose **only**: nickname (or "Anonymous"), country code,
FOUCH Score, band, and the existing public prediction ID (already
shareable). Never exposed: device token, email, internal database IDs,
Supabase identifiers, analytics identifiers. Verified by inspecting
`getLeaderboardRawEntries`'s `select()` call — it lists exactly four
public columns plus prediction items, nothing else.

## Your Finish / own position

When `?from=<publicId>` resolves to an eligible, scored entry, the page
shows a "Your Finish" callout (rank, score, percentile if eligible) and
highlights that row inline if it's within the visible Top 50. If the
viewer's rank falls outside the Top 50, a small "Your neighborhood"
list (2 rows on each side) is shown instead of forcing pagination.

## Percentile

Reuses `computePercentile()` from Sprint 4's scoring engine exactly —
no second percentile formula. Same `MIN_PERCENTILE_SAMPLE = 25`
threshold, same self-exclusion, same tie handling.

## Small-sample states

| Total scored | Copy |
|---|---|
| 0 | "No scored predictions yet." |
| 1 | "First call on the board." |
| 2-4 | "The leaderboard is just getting started." |
| 5+ | Normal presentation, no special copy |

No result yet at all (not even demo) → "Leaderboard locked" state with a
"Make your call" CTA — never a fabricated empty board.

## Demo safety

The leaderboard is scoped to one `data_status` at a time
(`getEventLeaderboard(slug, dataStatus, ...)`); demo and official rows
can never appear on the same board, by construction. The page shows
"Demo leaderboard — not an official outcome" whenever `data_status ===
"demo"` (currently always true), and demo leaderboard pages are excluded
from search indexing (`robots: { index: false }`) so they can't surface
as if they were a real result.

## Performance

Ranking happens entirely server-side over the full eligible set, then
only the Top 50 (+ up to 5 neighbor rows for the viewer) are sent to the
client — never the full prediction list. At the project's current scale
(single-digit to low-hundreds of predictions per event) this is a single
pair of Supabase queries per page view; no new indexes were added since
none are needed yet at this volume. If a single event's prediction count
grows into the thousands, revisit with an actual index review — deferred
deliberately, not overlooked.

## Analytics

`leaderboard_viewed`, `leaderboard_row_clicked`, `own_rank_viewed`,
`leaderboard_from_score_clicked` — properties limited to `event_slug`,
`data_status`, `rank`, `score_band`, `leaderboard_size`,
`is_own_prediction`. No PII.

## Tests

`src/lib/leaderboard.test.ts` — 9 tests: all four required ranking
scenarios (`[95,90,85,80]→[1,2,3,4]`, `[95,90,90,80]→[1,2,2,4]`,
`[90,90,90]→[1,1,1]`, `[100,99,99,99,75]→[1,2,2,2,5]`), plus edge cases
(empty input, single entry) and `buildLeaderboard`'s tie-order/band
assignment. Combined with existing suites, the project now has **76
passing tests**. A `vitest.config.mts` was added so tests can use the
project's standard `@/...` import alias (previous test files avoided
needing it) — this is a one-time test-infrastructure fix, not a product
change.

## Known limitations

- No pagination beyond Top 50 + neighbors — acceptable at current scale,
  the natural next step if a single event's leaderboard grows very large.
- Row identity is nickname-only (+ country); FOUCH still has no
  account/profile system, so duplicate "Anonymous" or repeated nicknames
  are expected and not resolved here, as scoped.
- No dedicated leaderboard share card — the existing Result Card (score +
  band + percentile) already covers the sharing need per the brief.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_SPRINT5_LEADERBOARD.md"
} catch {
    Write-Host "FAILED: FOUCH_SPRINT5_LEADERBOARD.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_SPRINT5_LEADERBOARD.md"
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
  | "leaderboard_from_score_clicked";

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
    $path = "src\components\scoring\FouchScore.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { getEntryNoun } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { getPredictionScore } from "@/lib/scoring-service";
import { getOfficialResult } from "@/lib/results-db";
import { MIN_PERCENTILE_SAMPLE } from "@/lib/scoring";
import { siteUrl } from "@/lib/site";
import { CountryFlag } from "@/components/CountryFlag";
import type { PredictionRecord } from "@/lib/predictions-db";
import type { FouchEvent } from "@/types/event";
import type { ScoreBand } from "@/types/scoring";
import { FouchScoreTracker } from "./FouchScoreTracker";
import { ShareActions } from "@/components/prediction/ShareActions";
import { TrackedLink } from "@/components/TrackedLink";

const BAND_LABEL: Record<ScoreBand, string> = {
  MISSED_IT: "Missed it",
  FAIR: "Fair call",
  GOOD: "Good call",
  EXCELLENT: "Excellent call",
  ELITE: "Elite call",
};

/** "8.333..." -> "8.3", "25.0" -> "25" — one decimal, no trailing ".0". */
function formatPoints(value: number): string {
  const rounded = Math.round(value * 10) / 10;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}

/**
 * Renders nothing (returns null) when there's no official result yet —
 * the pre-result experience is unchanged, never a fabricated score.
 * Server Component: fetches + scores server-side, only the final
 * numbers reach the client (via the tracker's props, not raw data).
 *
 * Sprint 4.1: UI clarity only. Every number below comes straight from
 * the existing score engine's ScoreBreakdown — nothing here
 * recalculates or duplicates scoring logic.
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

  // Re-reads the same official-result row already used inside
  // getPredictionScore, purely to display who the actual winner was —
  // no scoring logic is duplicated, only a read.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);

  const participantData = getParticipantsForEvent(event.slug);
  const participantsById = new Map(
    (participantData?.participants ?? []).map((participant) => [participant.id, participant]),
  );
  const userWinnerPick = prediction.rankedParticipantIds[0]
    ? participantsById.get(prediction.rankedParticipantIds[0])
    : undefined;
  const actualWinner = official ? participantsById.get(official.winner) : undefined;
  const pluralNoun = getEntryNoun(event, true);
  const { breakdown, percentile } = result;
  const { winner, podium, top5, top10, ranking } = breakdown.components;

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
          World ranking unlocks at {MIN_PERCENTILE_SAMPLE} predictions.
        </p>
      )}

      <dl className="mt-6 space-y-3 text-sm">
        <div className="border-b border-border pb-3">
          <dt className="flex items-center justify-between">
            <span className="text-text-secondary">Winner</span>
            <span className="text-text-muted">{formatPoints(winner.earned)} / {winner.max}</span>
          </dt>
          <dd className="mt-2">
            {winner.hit ? (
              <span className="inline-flex items-center gap-1.5 text-accent-strong">
                ✓
                {userWinnerPick ? (
                  <>
                    <CountryFlag countryCode={userWinnerPick.countryCode} />
                    {userWinnerPick.displayName}
                  </>
                ) : (
                  "Correct"
                )}
              </span>
            ) : (
              <div className="space-y-1 text-text-primary">
                <p className="flex items-center gap-1.5">
                  <span className="text-text-muted">✗ Missed — your pick:</span>
                  {userWinnerPick ? (
                    <>
                      <CountryFlag countryCode={userWinnerPick.countryCode} />
                      {userWinnerPick.displayName}
                    </>
                  ) : (
                    "—"
                  )}
                </p>
                {actualWinner ? (
                  <p className="flex items-center gap-1.5 text-text-secondary">
                    <span className="text-text-muted">Actual:</span>
                    <CountryFlag countryCode={actualWinner.countryCode} />
                    {actualWinner.displayName}
                  </p>
                ) : null}
              </div>
            )}
          </dd>
        </div>

        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Podium</dt>
          <dd className="text-text-primary">
            {podium.hits} of {podium.total} · {formatPoints(podium.earned)} / {podium.max}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Top 5</dt>
          <dd className="text-text-primary">
            {top5.hits} of {top5.total} · {formatPoints(top5.earned)} / {top5.max}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Top 10</dt>
          <dd className="text-text-primary">
            {top10.hits} of {top10.total} · {formatPoints(top10.earned)} / {top10.max}
          </dd>
        </div>
        <div>
          <div className="flex items-center justify-between">
            <dt className="text-text-secondary">Ranking</dt>
            <dd className="text-text-primary">
              {formatPoints(ranking.earned)} / {ranking.max}
            </dd>
          </div>
          <p className="mt-1 text-xs text-text-muted">How close your picks were to the official finish.</p>
        </div>
      </dl>

      <div className="mt-8">
        <TrackedLink
          href={`/events/${event.slug}/leaderboard?from=${publicId}`}
          event="leaderboard_from_score_clicked"
          eventProperties={{ event_slug: event.slug }}
          className="inline-flex items-center justify-center rounded border border-border-strong px-6 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          See where you finished
        </TrackedLink>
      </div>

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

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 11 files written successfully." -ForegroundColor Green
}