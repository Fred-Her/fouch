"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Pencil } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { loadPrediction, clearPrediction } from "@/lib/prediction-storage";
import { getDeviceToken } from "@/lib/device-token";
import { checkExistingSubmission, submitPrediction } from "@/app/predict/[slug]/actions";
import type { Participant } from "@/types/participant";
import { SubmitPanel } from "./SubmitPanel";

export function ReviewContent({
  eventSlug,
  participants,
  requiredCount,
}: {
  eventSlug: string;
  participants: Participant[];
  requiredCount: number;
}) {
  const router = useRouter();
  const [rankedIds, setRankedIds] = useState<string[] | null>(null);
  const [checkingExisting, setCheckingExisting] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    const validIds = new Set(participants.map((participant) => participant.id));
    setRankedIds(loadPrediction(eventSlug, validIds));

    // A submitted prediction is immutable — if this device already has
    // one for this event, go straight to it instead of showing the
    // submit form again.
    const deviceToken = getDeviceToken();
    checkExistingSubmission(eventSlug, deviceToken)
      .then((existing) => {
        if (existing) {
          router.replace(`/p/${existing.publicId}`);
          return;
        }
        setCheckingExisting(false);
      })
      .catch(() => setCheckingExisting(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const participantsById = new Map(participants.map((participant) => [participant.id, participant]));
  const ranked = (rankedIds ?? [])
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  useEffect(() => {
    if (rankedIds !== null && ranked.length >= requiredCount) {
      track("prediction_reviewed", { event_slug: eventSlug });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rankedIds]);

  async function handleSubmit(nickname: string, countryCode: string) {
    setSubmitting(true);
    setErrorMessage(null);
    track("prediction_submit_started", { event_slug: eventSlug });

    const deviceToken = getDeviceToken();
    const result = await submitPrediction({
      eventSlug,
      participantIds: rankedIds ?? [],
      nickname: nickname.trim() || undefined,
      countryCode: countryCode || undefined,
      deviceToken,
    });

    if (!result.success) {
      setErrorMessage(result.error);
      setSubmitting(false);
      return;
    }

    track("prediction_submitted", { event_slug: eventSlug });
    clearPrediction(eventSlug);
    router.push(`/p/${result.publicId}?new=1`);
  }

  // Avoid a flash of the form before we know whether this device
  // already has a locked-in prediction.
  if (rankedIds === null || checkingExisting) return null;

  if (ranked.length < requiredCount) {
    return (
      <div>
        <p className="text-text-secondary">
          We don&apos;t have a complete prediction for this event yet on this device.
        </p>
        <Link
          href={`/predict/${eventSlug}`}
          className="mt-4 inline-flex items-center gap-2 rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
        >
          Build your Top {requiredCount}
        </Link>
      </div>
    );
  }

  return (
    <div>
      <ol className="space-y-1.5">
        {ranked.map((participant, index) => (
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

      <Link
        href={`/predict/${eventSlug}`}
        className="mt-6 inline-flex items-center gap-2 rounded border border-border-strong px-6 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
      >
        <Pencil className="h-4 w-4" aria-hidden />
        Edit my Top {requiredCount}
      </Link>

      <SubmitPanel
        requiredCount={requiredCount}
        submitting={submitting}
        errorMessage={errorMessage}
        onSubmit={handleSubmit}
      />
    </div>
  );
}