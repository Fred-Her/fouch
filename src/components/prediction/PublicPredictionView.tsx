"use client";

import { useEffect, type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { flagEmoji } from "@/lib/flags";
import { track } from "@/lib/analytics";
import { siteUrl } from "@/lib/site";
import type { Participant } from "@/types/participant";
import { ShareActions } from "./ShareActions";

export function PublicPredictionView({
  eventSlug,
  publicId,
  rankedParticipants,
  youVsTheWorld,
}: {
  eventSlug: string;
  publicId: string;
  rankedParticipants: Participant[];
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
            <span aria-hidden className="text-xl">
              {flagEmoji(participant.countryCode)}
            </span>
            <span className="text-sm text-text-primary">{participant.displayName}</span>
          </li>
        ))}
      </ol>

      {youVsTheWorld}

      <Link
        href={`/predict/${eventSlug}?from=${publicId}`}
        onClick={() => track("public_prediction_cta_clicked", { event_slug: eventSlug })}
        className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        Make your Top 10
      </Link>

      <div id="share" className="mt-10 scroll-mt-20 border-t border-border pt-8">
        <p className="font-display text-lg text-text-primary">Share your prediction</p>
        <div className="mt-3">
          <ShareActions
            eventSlug={eventSlug}
            publicUrl={publicUrl}
            storyCardUrl={`/p/${publicId}/card/story`}
            postCardUrl={`/p/${publicId}/card/post`}
          />
        </div>
      </div>
    </div>
  );
}