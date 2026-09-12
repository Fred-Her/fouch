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