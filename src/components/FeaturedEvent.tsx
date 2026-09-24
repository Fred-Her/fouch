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
  // driven, never hardcoded to a specific slug â€” it only appears once
  // an official/demo result genuinely exists to rank against.
  const participantData = await getParticipantsForEvent(event.slug);
  const hasLeaderboard = participantData
    ? Boolean(await getOfficialResult(event.slug, participantData.status))
    : false;

  // Decorative only â€” a preview of the ranking mechanic, not real input.
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
          {dayMonth} Â· {event.subtitle}
        </p>

        <p className="mt-8 text-lg text-text-secondary">{dictionary.featuredEvent.prompt}</p>

        {/* Decorative preview of the ranking mechanic â€” not interactive. */}
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
              View leaderboard â†’
            </TrackedLink>
          ) : null}
        </div>
      </div>
    </section>
  );
}