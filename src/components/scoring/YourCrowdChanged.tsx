import { CountryFlag } from "@/components/CountryFlag";
import { resolveParticipantsByIds } from "@/lib/participants";
import { getConsensusChangeForPrediction } from "@/lib/consensus-change-service";
import { bucketSample } from "@/lib/consensus-change";
import type { PredictionRecord } from "@/lib/predictions-db";
import type { FouchEvent } from "@/types/event";
import { ConsensusChangeTracker } from "./ConsensusChangeTracker";

/**
 * Experiment 01 ("Your Crowd Changed") â€” FOUCH_EXPERIMENT_01.md.
 * Renders nothing whenever the movement isn't eligible (small sample,
 * or change under MIN_MOVEMENT_POINTS) â€” silence is the correct,
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

  // FOUCH 0.3B: resolves regardless of current status â€” winnerId
  // comes from the community's aggregate winner picks and may
  // reference a participant who has since become
  // WITHDRAWN/REPLACED.
  const participantsById = await resolveParticipantsByIds(event.slug, [winnerId]);
  const winner = participantsById.get(winnerId);
  if (!winner) return null;

  const arrow = result.direction === "toward" ? "â†‘" : "â†“";
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
        {Math.round(result.thenSupport)}% â†’ {Math.round(result.nowSupport)}%
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