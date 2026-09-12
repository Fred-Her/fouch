# Sprint 5.1: Leaderboard access & navigation fix — applies all changed files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-sprint5-1.ps1
$failures = @()

try {
    $path = "vitest.config.mts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { defineConfig } from "vitest/config";

// Vitest doesn't read tsconfig "paths" automatically. Previous test
// files avoided this by only using relative imports; leaderboard.ts
// needs the project's standard "@/..." alias (src/lib/scoring), so
// this maps it the same way Next.js already does via tsconfig.json.
export default defineConfig({
  resolve: {
    alias: {
      "@": new URL("./src", import.meta.url).pathname,
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
import { assignCompetitionRanks, buildLeaderboard, resolveViewerContext } from "./leaderboard";

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

describe("resolveViewerContext — Sprint 5.1: viewer context is structurally separate from leaderboard existence", () => {
  const board = buildLeaderboard([
    { publicId: "pef", nickname: "Pef", countryCode: null, displayScore: 61 },
    { publicId: "fred1", nickname: "Fred", countryCode: null, displayScore: 25 },
    { publicId: "fred2", nickname: "FRED", countryCode: null, displayScore: 25 },
    { publicId: "ghera", nickname: "Ghera", countryCode: "CL", displayScore: 22 },
    { publicId: "gg", nickname: "gg", countryCode: null, displayScore: 13 },
  ]);
  const scores = new Map([
    ["pef", 61],
    ["fred1", 25],
    ["fred2", 25],
    ["ghera", 22],
    ["gg", 13],
  ]);

  it("Case A: no `from` -> no viewer, no crash, board itself is untouched", () => {
    const viewer = resolveViewerContext(board, scores, undefined);
    expect(viewer).toBeNull();
    expect(board).toHaveLength(5); // the board array itself was never mutated
  });

  it("Case B: valid `from` -> correct entry, rank #4 of 5, matches the production example", () => {
    const viewer = resolveViewerContext(board, scores, "ghera");
    expect(viewer?.entry.rank).toBe(4);
    expect(viewer?.entry.score).toBe(22);
    expect(viewer?.entry.nickname).toBe("Ghera");
  });

  it("Case C: invalid/unknown `from` -> null, no throw", () => {
    expect(() => resolveViewerContext(board, scores, "not-a-real-id")).not.toThrow();
    expect(resolveViewerContext(board, scores, "not-a-real-id")).toBeNull();
  });

  it("Case D: `from` belongs to a prediction not on this leaderboard (e.g. another event) -> null", () => {
    // Simulates a publicId that is valid *somewhere*, just not in this
    // event's leaderboard array — the exact situation a cross-event or
    // stale ID produces once this leaderboard was built independently.
    const viewer = resolveViewerContext(board, scores, "some-other-events-prediction");
    expect(viewer).toBeNull();
  });

  it("Case H: shared tie ranking is preserved when a tied entry is the viewer", () => {
    const viewer = resolveViewerContext(board, scores, "fred1");
    expect(viewer?.entry.rank).toBe(2);
    const otherTied = resolveViewerContext(board, scores, "fred2");
    expect(otherTied?.entry.rank).toBe(2);
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
import { scorePrediction } from "@/lib/scoring";
import { getOfficialResult } from "@/lib/results-db";
import { getLeaderboardRawEntries } from "@/lib/predictions-db";
import { buildLeaderboard, resolveViewerContext, LEADERBOARD_TOP_N } from "@/lib/leaderboard";
import type { LeaderboardEntry, ViewerContext } from "@/lib/leaderboard";
import type { ParticipantDataStatus } from "@/lib/participants";

export interface EventLeaderboard {
  status: "no_result" | "scored";
  dataStatus: ParticipantDataStatus;
  totalCount: number;
  topEntries: LeaderboardEntry[];
  /** Present only when a viewerPublicId was given AND it resolved to
   * an eligible, scored prediction on THIS leaderboard. Absent
   * viewer context never affects `status` or `topEntries` above —
   * see resolveViewerContext() in src/lib/leaderboard.ts, which this
   * calls as a pure, separately-tested step. */
  viewer: ViewerContext | null;
}

/**
 * Builds the full event leaderboard. Ranking happens here, server-side,
 * over every eligible entry — the client only ever receives the
 * already-ranked, already-trimmed result (brief §19-21), never the raw
 * prediction list.
 *
 * Returns `{ status: "no_result" }` when there's no official/demo
 * result yet — the page renders a "leaderboard locked" state, never a
 * fabricated empty board (brief §28). This decision is made BEFORE
 * `viewerPublicId` is even read below — the leaderboard's existence
 * can never depend on who's asking (Sprint 5.1 fix).
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

  const fullPrecisionScoreByPublicId = new Map(scored.map((e) => [e.publicId, e.breakdown.score]));
  const viewer = resolveViewerContext(leaderboard, fullPrecisionScoreByPublicId, viewerPublicId);

  return {
    status: "scored",
    dataStatus,
    totalCount: leaderboard.length,
    topEntries: leaderboard.slice(0, LEADERBOARD_TOP_N),
    viewer,
  };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\leaderboard-service.ts"
} catch {
    Write-Host "FAILED: src\lib\leaderboard-service.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\leaderboard-service.ts"
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

// Sprint 5.1: this route reads Supabase state that changes independently
// of any URL parameter (a new prediction being scored, a result being
// entered) — force fresh server execution on every request rather than
// risk this being treated as a cacheable static/ISR route.
export const dynamic = "force-dynamic";

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
    $path = "src\components\FeaturedEvent.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { getParticipantsForEvent } from "@/lib/participants";
import { getOfficialResult } from "@/lib/results-db";
import { TrackedLink } from "./TrackedLink";

const statusLabel: Record<FouchEvent["status"], string> = {
  upcoming: "Upcoming",
  open: "Open",
  live: "Live",
  completed: "Completed",
};

export async function FeaturedEvent({
  event,
  dictionary,
}: {
  event: FouchEvent;
  dictionary: Dictionary;
}) {
  const date = new Date(`${event.eventDate}T00:00:00Z`);
  const dayMonth = date
    .toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" })
    .toUpperCase();

  // Sprint 5.1: the secondary leaderboard link is event/result-state
  // driven, never hardcoded to a specific slug — it only appears once
  // an official/demo result genuinely exists to rank against.
  const participantData = getParticipantsForEvent(event.slug);
  const hasLeaderboard = participantData
    ? Boolean(await getOfficialResult(event.slug, participantData.status))
    : false;

  // Decorative only — a preview of the ranking mechanic, not real input.
  const previewSlots = [1, 2, 3];

  return (
    <section
      id="featured-event"
      className="relative scroll-mt-20 overflow-hidden border-y border-border bg-surface py-14 sm:py-20"
    >
      <div
        aria-hidden
        className="pointer-events-none absolute -right-24 top-1/2 h-96 w-96 -translate-y-1/2 rounded-full bg-accent/10 blur-3xl"
      />

      <div className="relative mx-auto max-w-content px-6">
        <div className="flex items-center gap-2">
          <span
            aria-hidden
            className={
              event.status === "live"
                ? "h-1.5 w-1.5 rounded-full bg-accent animate-pulse motion-reduce:animate-none"
                : "h-1.5 w-1.5 rounded-full bg-text-muted"
            }
          />
          <span className="text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">
            {statusLabel[event.status]}
          </span>
        </div>

        <h2 className="mt-5 font-display leading-[0.95] text-text-primary">
          <span className="block text-3xl sm:text-4xl">Miss Universe</span>
          <span className="block text-7xl font-semibold tracking-tight sm:text-8xl">
            2026
          </span>
        </h2>

        <p className="mt-4 text-sm uppercase tracking-[0.15em] text-text-muted">
          {dayMonth} · {event.subtitle}
        </p>

        <p className="mt-8 text-lg text-text-secondary">{dictionary.featuredEvent.prompt}</p>

        {/* Decorative preview of the ranking mechanic — not interactive. */}
        <div aria-hidden className="mt-6 max-w-xs space-y-2">
          {previewSlots.map((slot) => (
            <div key={slot} className="flex items-center gap-3">
              <span className="font-display text-sm text-text-muted">
                {String(slot).padStart(2, "0")}
              </span>
              <span className="h-px flex-1 bg-border-strong" />
            </div>
          ))}
        </div>

        <div className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-3">
          <TrackedLink
            href={`/predict/${event.slug}`}
            event="featured_event_clicked"
            eventProperties={{ slug: event.slug }}
            className="group inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            {dictionary.featuredEvent.cta}
            <ArrowRight
              className="h-4 w-4 transition-transform group-hover:translate-x-0.5"
              aria-hidden
            />
          </TrackedLink>

          {hasLeaderboard ? (
            <TrackedLink
              href={`/events/${event.slug}/leaderboard`}
              event="leaderboard_from_score_clicked"
              eventProperties={{ event_slug: event.slug, source: "home" }}
              className="text-sm text-text-secondary transition-colors hover:text-accent-strong"
            >
              View leaderboard →
            </TrackedLink>
          ) : null}
        </div>
      </div>
    </section>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\FeaturedEvent.tsx"
} catch {
    Write-Host "FAILED: src\components\FeaturedEvent.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\FeaturedEvent.tsx"
}

try {
    $path = "src\app\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { en } from "@/content/en";
import { getFeaturedEvent } from "@/lib/events";
import { Nav } from "@/components/Nav";
import { Hero } from "@/components/Hero";
import { FeaturedEvent } from "@/components/FeaturedEvent";
import { HowItWorks } from "@/components/HowItWorks";
import { Footer } from "@/components/Footer";
import { ViewTracker } from "@/components/ViewTracker";

// Sprint 5.1: FeaturedEvent checks live result state (for the secondary
// leaderboard link) — force fresh execution so that check is never
// baked into a static build and left stale until the next deploy.
export const dynamic = "force-dynamic";

export default function Home() {
  const featuredEvent = getFeaturedEvent();

  return (
    <>
      <ViewTracker event="landing_view" />
      <Nav />
      <main>
        <Hero dictionary={en} eventSlug={featuredEvent?.slug ?? null} />
        {featuredEvent ? (
          <FeaturedEvent event={featuredEvent} dictionary={en} />
        ) : null}
        <HowItWorks dictionary={en} />
      </main>
      <Footer dictionary={en} />
    </>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\page.tsx"
} catch {
    Write-Host "FAILED: src\app\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\page.tsx"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 7 files written successfully." -ForegroundColor Green
}