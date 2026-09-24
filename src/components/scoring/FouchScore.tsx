import { getEntryNoun } from "@/lib/events";
import { resolveParticipantsByIds } from "@/lib/participants";
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

/** "8.333..." -> "8.3", "25.0" -> "25" â€” one decimal, no trailing ".0". */
function formatPoints(value: number): string {
  const rounded = Math.round(value * 10) / 10;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}

/**
 * Renders nothing (returns null) when there's no official result yet â€”
 * the pre-result experience is unchanged, never a fabricated score.
 * Server Component: fetches + scores server-side, only the final
 * numbers reach the client (via the tracker's props, not raw data).
 *
 * Sprint 4.1: UI clarity only. Every number below comes straight from
 * the existing score engine's ScoreBreakdown â€” nothing here
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
  // getPredictionScore, purely to display who the actual winner was â€”
  // no scoring logic is duplicated, only a read.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);

  // FOUCH 0.3B: resolves regardless of current participant status â€”
  // both the user's own historical winner pick and the official
  // result's winner id must still render even if that country's
  // delegate has since become WITHDRAWN/REPLACED.
  const idsToResolve = new Set<string>();
  if (prediction.rankedParticipantIds[0]) idsToResolve.add(prediction.rankedParticipantIds[0]);
  if (official) idsToResolve.add(official.winner);

  const participantsById = await resolveParticipantsByIds(event.slug, Array.from(idsToResolve));
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
          Demo result â€” not an official outcome
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
                âœ“
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
                  <span className="text-text-muted">âœ— Missed â€” your pick:</span>
                  {userWinnerPick ? (
                    <>
                      <CountryFlag countryCode={userWinnerPick.countryCode} />
                      {userWinnerPick.displayName}
                    </>
                  ) : (
                    "â€”"
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
            {podium.hits} of {podium.total} Â· {formatPoints(podium.earned)} / {podium.max}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Top 5</dt>
          <dd className="text-text-primary">
            {top5.hits} of {top5.total} Â· {formatPoints(top5.earned)} / {top5.max}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Top 10</dt>
          <dd className="text-text-primary">
            {top10.hits} of {top10.total} Â· {formatPoints(top10.earned)} / {top10.max}
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