"use client";

import { useEffect, type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { Pencil, Check, Minus, X } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { siteUrl } from "@/lib/site";
import { formatEventLocalLockTime } from "@/lib/event-time-display";
import type { Participant } from "@/types/participant";
import type { PickMark } from "@/lib/official-result-display";
import { ShareActions } from "./ShareActions";
import { useI18n } from "@/components/I18nProvider";
import { fmt } from "@/lib/i18n";
import { localizePath } from "@/lib/locale";

export function PublicPredictionView({
  eventSlug,
  publicId,
  rankedParticipants,
  hasResult = false,
  canEdit = false,
  showLockedNotice = false,
  predictionLockAt = null,
  predictionTimezone = null,
  fouchScore,
  officialResultSection,
  pickMarks,
  officialTopSize = 10,
  predictionsClosed = false,
  nextEvent = null,
  youVsTheWorld,
  yourCrowdChanged,
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
  /** FOUCH 0.3A: true only for a verified prediction (auth_user_id
   * set) while the event is still open per Supabase
   * events.prediction_lock_at. A legacy anonymous prediction never
   * gets this — there is no verified identity to authorize an edit
   * against, and this sprint adds no way to claim one. */
  canEdit?: boolean;
  /** FOUCH 0.3A: true for a verified prediction whose event has
   * passed prediction_lock_at — shows "YOUR CALL IS LOCKED" instead
   * of an edit affordance. Never shown for legacy predictions, which
   * never offered editing in the first place. */
  showLockedNotice?: boolean;
  /** ISO datetime, only used for display ("until {date}"). */
  predictionLockAt?: string | null;
  /** FOUCH 0.3A.1 — IANA timezone identifier for the event (e.g.
   * "America/Puerto_Rico"), used ONLY to render predictionLockAt
   * unambiguously in event-local time (see event-time-display.ts).
   * Null falls back to an explicit UTC-labeled rendering — never the
   * viewer's browser timezone. */
  predictionTimezone?: string | null;
  /** FOUCH Score section (Sprint 4) — null/absent renders nothing, which
   * is exactly the pre-result experience. Server Component, passed down
   * for the same reason as youVsTheWorld below. */
  fouchScore?: ReactNode;
  /** Post-event: the official finish (Server Component), rendered
   * right after the score. Absent before a result exists. */
  officialResultSection?: ReactNode;
  /** Post-event: how each of the user's saved picks landed, keyed by
   * participant id — display only, derived from the same ranges the
   * score uses. Absent before a result exists. */
  pickMarks?: Record<string, PickMark>;
  /** 10 for a conventional Top 10, 11 for a tied Top 11 (labels only). */
  officialTopSize?: number;
  /** True once the event's prediction window has ended: the bottom CTA
   * stops pointing at this (closed) event's builder. */
  predictionsClosed?: boolean;
  /** The next event to introduce after this one, if any. */
  nextEvent?: { slug: string; name: string; comingSoon: boolean } | null;
  /** The You vs The World section — a Server Component rendered by the
   * page and passed down, since it needs server-side data fetching
   * that a Client Component can't do directly. */
  youVsTheWorld: ReactNode;
  /** Experiment 01 ("Your Crowd Changed") — null/absent renders
   * nothing, same pattern as the two slots above. */
  yourCrowdChanged?: ReactNode;
}) {
  const searchParams = useSearchParams();
  const { locale, dict } = useI18n();
  const pt = dict.publicPrediction;
  const ut = dict.unavailable;
  const isNew = searchParams.get("new") === "1";
  const isEdited = searchParams.get("edited") === "1";
  const showSavedBanner = isNew || isEdited;

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

  // A shared link carries the language: a Spanish sharer's link opens
  // in Spanish. /es/p/x and /p/x are the SAME prediction.
  const publicPath = localizePath(`/p/${publicId}`, locale);
  const publicUrl = `${siteUrl}${publicPath}`;

  const originalPredictionShare = (
    <div id="share" className="mt-10 scroll-mt-20 border-t border-border pt-8">
      <p
        className={
          hasResult
            ? "text-sm text-text-muted"
            : "font-display text-lg text-text-primary"
        }
      >
        {hasResult ? pt.originalPrediction : pt.shareHeading}
      </p>
      <div className="mt-3">
        <ShareActions
          eventSlug={eventSlug}
          publicId={publicId}
          publicUrl={publicUrl}
          storyCardUrl={`${publicPath}/card/story`}
          postCardUrl={`${publicPath}/card/post`}
        />
      </div>
    </div>
  );

  return (
    <div>
      {showSavedBanner ? (
        <div className="mt-4">
          <p className="font-display text-lg text-accent-strong">{pt.callIsIn}</p>
          {predictionLockAt ? (
            <p className="mt-1 text-sm text-text-secondary">
              {fmt(pt.updateUntil, { when: formatEventLocalLockTime(predictionLockAt, predictionTimezone, locale) })}
            </p>
          ) : null}
        </div>
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
            <span className="truncate text-sm text-text-primary">
              {participant.displayName} <span className="text-text-muted">· {participant.countryName}</span>
            </span>
            {!participant.isActive ? (
              <span className="shrink-0 rounded border border-border-strong px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-accent-strong">
                {pt.pickUnavailableBadge}
              </span>
            ) : null}
            {pickMarks ? <PickMarkIcon mark={pickMarks[participant.id]} topSize={officialTopSize} /> : null}
          </li>
        ))}
      </ol>

      {pickMarks ? (
        <ul className="mt-3 flex flex-wrap gap-x-5 gap-y-1 text-xs text-text-muted">
          <li className="inline-flex items-center gap-1.5">
            <Check className="h-3.5 w-3.5 text-accent-strong" aria-hidden />
            {dict.results.markExact}
          </li>
          <li className="inline-flex items-center gap-1.5">
            <Minus className="h-3.5 w-3.5" aria-hidden />
            {fmt(dict.results.markIn, { n: officialTopSize })}
          </li>
          <li className="inline-flex items-center gap-1.5">
            <X className="h-3.5 w-3.5" aria-hidden />
            {fmt(dict.results.markOut, { n: officialTopSize })}
          </li>
        </ul>
      ) : null}

      {canEdit && rankedParticipants.some((participant) => !participant.isActive) ? (
        <p role="status" className="mt-4 rounded border border-accent/40 bg-accent/10 px-4 py-3 text-sm text-text-primary">
          {pt.pickUnavailableNotice}
        </p>
      ) : null}

      {canEdit ? (
        <div className="mt-4">
          <Link
            href={`/p/${publicId}/edit`}
            className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-2.5 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            <Pencil className="h-4 w-4" aria-hidden />
            {pt.editCta}
          </Link>
          {predictionLockAt ? (
            <p className="mt-2 text-xs text-text-muted">
              {fmt(pt.updateUntil, { when: formatEventLocalLockTime(predictionLockAt, predictionTimezone, locale) })}
            </p>
          ) : null}
        </div>
      ) : showLockedNotice ? (
        <p className="mt-4 text-sm font-medium uppercase tracking-wide text-text-muted">
          {pt.callLocked}
        </p>
      ) : null}

      {fouchScore}

      {officialResultSection}

      {youVsTheWorld}

      {yourCrowdChanged}

      {/* Pre-result: original prediction sharing stays primary and sits
          right before the "Make your Top 10" CTA, unchanged from Sprint 2/3.
          Post-result: it becomes a secondary, de-emphasized block, per the
          hierarchy in Sprint 4.1's brief (Result Card is the stronger
          social object once scoring exists). */}
      {!hasResult ? originalPredictionShare : null}

      {predictionsClosed ? (
        nextEvent ? (
          <Link
            href={`/predict/${nextEvent.slug}`}
            onClick={() => track("public_prediction_cta_clicked", { event_slug: nextEvent.slug })}
            className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            {nextEvent.comingSoon ? fmt(ut.nextEventCta, { event: nextEvent.name }) : pt.makeYourTop}
          </Link>
        ) : null
      ) : (
        <Link
          href={`/predict/${eventSlug}?from=${publicId}`}
          onClick={() => track("public_prediction_cta_clicked", { event_slug: eventSlug })}
          className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
        >
          {pt.makeYourTop}
        </Link>
      )}

      {hasResult ? originalPredictionShare : null}
    </div>
  );
}
/** Per-pick result marker. Icon + accessible label (never color alone). */
function PickMarkIcon({ mark, topSize }: { mark: PickMark | undefined; topSize: number }) {
  const { dict } = useI18n();
  if (!mark) return null;
  if (mark === "exact") {
    const label = dict.results.markExact;
    return (
      <span title={label} aria-label={label} className="shrink-0 text-accent-strong">
        <Check className="h-4 w-4" aria-hidden />
      </span>
    );
  }
  if (mark === "in_top") {
    const label = fmt(dict.results.markIn, { n: topSize });
    return (
      <span title={label} aria-label={label} className="shrink-0 text-text-secondary">
        <Minus className="h-4 w-4" aria-hidden />
      </span>
    );
  }
  const label = fmt(dict.results.markOut, { n: topSize });
  return (
    <span title={label} aria-label={label} className="shrink-0 text-text-muted">
      <X className="h-4 w-4" aria-hidden />
    </span>
  );
}
