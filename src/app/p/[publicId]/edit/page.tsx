﻿﻿import { notFound, redirect } from "next/navigation";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { EditPredictionFlow } from "@/components/prediction/EditPredictionFlow";

/**
 * FOUCH 0.3A — the edit entry point. This route is intentionally
 * unreachable in a way that actually matters for two cases, checked
 * server-side (never just hidden in the UI, since a direct URL visit
 * bypasses any client-side hiding):
 *
 *  - legacy anonymous prediction (no verified owner) — there is no
 *    identity to authorize an edit against, and this sprint adds no
 *    way to claim one, so editing is simply never offered;
 *  - the event has passed prediction_lock_at — editing closes at
 *    lock, full stop.
 *
 * Both redirect back to the public page rather than 404 — the
 * prediction itself is real and viewable, only editing isn't
 * available. The actual SAVE action (verify-actions.ts) independently
 * re-checks both of these server-side again at save time — this
 * page's checks are only about whether to show the builder at all,
 * never the authorization boundary itself.
 */
export default async function EditPredictionPage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) notFound();

  const { prediction, event, rankedParticipants } = record;

  if (!prediction.hasVerifiedOwner) {
    redirect(`/p/${publicId}`);
  }

  const lockConfig = await getEventLockConfig(event.slug);
  if (!isPredictionWindowOpen(lockConfig, Date.now())) {
    redirect(`/p/${publicId}`);
  }

  const participantData = getParticipantsForEvent(event.slug);
  if (!participantData) notFound();

  const requiredCount = Math.min(10, participantData.participants.length);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <h1 className="font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-1 text-sm text-text-secondary">Edit your Top {requiredCount}</p>

      <EditPredictionFlow
        eventSlug={event.slug}
        publicId={publicId}
        allParticipants={participantData.participants}
        initialRankedParticipantIds={rankedParticipants.map((participant) => participant.id)}
        requiredCount={requiredCount}
        expectedVersionNumber={prediction.currentVersionNumber}
        predictionLockAt={lockConfig?.predictionLockAt ?? null}
        predictionTimezone={lockConfig?.timezone ?? null}
      />
    </main>
  );
}
