import { flagEmoji } from "@/lib/flags";
import { getEntryNoun } from "@/lib/events";
import { getEligiblePredictionsForComparison, type PredictionRecord } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { computeComparison, getSampleSizeBucket } from "@/lib/community-comparison";
import type { FouchEvent } from "@/types/event";
import { ShareYourCallCta } from "./ShareYourCallCta";
import { YouVsTheWorldTracker } from "./YouVsTheWorldTracker";

function formatPct(pct: number): string {
  return `${Math.round(pct * 100)}%`;
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

      {bucket === "0" ? (
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
                {formatPct(comparison.sameWinner.pct)}
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
                  : `${comparison.sameWinner.count} of ${comparison.population} other predictions agree.`}
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
                Only {formatPct(comparison.boldestPick.inclusionPct)} of other predictions have
                this in their top 10.
              </p>
            </div>
          ) : null}

          {comparison.communityTop10.length > 0 ? (
            <div>
              <p className="font-display text-xl text-text-primary">The world&apos;s top 10</p>
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
                      <span className="text-xs text-text-muted">
                        {formatPct(entry.top10Count / comparison.population)} picked
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