# Sprint 4.1: Score clarity polish (no math changes) — applies all changed files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-sprint4-1.ps1
$failures = @()

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
    Write-Host "All 3 files written successfully." -ForegroundColor Green
}