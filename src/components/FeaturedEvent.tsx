import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { getParticipantsForEvent } from "@/lib/participants";
import { getOfficialResult } from "@/lib/results-db";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { getCrowdTopPicks } from "@/lib/crowd-picks";
import { splitEventNameYear } from "@/lib/event-name-split";
import { CinematicBackdrop } from "./CinematicBackdrop";
import { CrowdPanel } from "./CrowdPanel";
import { TrackedLink } from "./TrackedLink";

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
  // driven, never hardcoded to a specific slug — it only appears once
  // an official/demo result genuinely exists to rank against.
  const participantData = await getParticipantsForEvent(event.slug);
  const hasLeaderboard = participantData
    ? Boolean(await getOfficialResult(event.slug, participantData.status))
    : false;

  // Home v1.1: "Now Predicting" must reflect the ACTUAL prediction
  // window, never assume an "upcoming"/"open" DB status means
  // predictions are open right now (brief §3: "Do not label an event
  // NOW PREDICTING if its prediction window is closed").
  const lockConfig = await getEventLockConfig(event.slug);
  const isOpen = isPredictionWindowOpen(lockConfig, Date.now());
  const eyebrow = isOpen ? "Now Predicting" : "Predictions Closed";

  const crowd = participantData ? await getCrowdTopPicks(event.slug, participantData.status) : null;

  const { primary, year } = splitEventNameYear(event.name);

  return (
    <section id="featured-event" className="relative scroll-mt-20 overflow-hidden py-16 sm:py-24">
      <CinematicBackdrop variant={0} />

      <div className="relative mx-auto grid max-w-content gap-y-20 gap-x-12 px-6 lg:grid-cols-[1fr_340px] lg:items-end lg:gap-10">
        <div>
          <div className="flex items-center gap-3">
            <span className="font-display text-sm text-accent-strong/70">01</span>
            <span className="h-px w-8 bg-border-strong" aria-hidden />
            <span
              aria-hidden
              className={
                isOpen
                  ? "h-1.5 w-1.5 rounded-full bg-accent animate-pulse motion-reduce:animate-none"
                  : "h-1.5 w-1.5 rounded-full bg-text-muted"
              }
            />
            <span className="text-xs font-medium uppercase tracking-[0.25em] text-text-secondary">
              {eyebrow}
            </span>
          </div>

          <h2 className="mt-6 font-display leading-[0.9] text-text-primary">
            <span className="block text-3xl sm:text-4xl">{primary}</span>
            {year ? (
              <span className="block bg-gradient-to-b from-text-primary to-text-primary/70 bg-clip-text text-8xl font-semibold tracking-tight text-transparent sm:text-9xl">
                {year}
              </span>
            ) : null}
          </h2>

          <p className="mt-5 text-sm uppercase tracking-[0.2em] text-text-muted">
            {dayMonth} · {event.subtitle}
          </p>

          <p className="mt-8 text-lg text-text-secondary">{dictionary.featuredEvent.prompt}</p>

          <div className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-3">
            <TrackedLink
              href={`/predict/${event.slug}`}
              event="featured_event_clicked"
              eventProperties={{ slug: event.slug }}
              className="group inline-flex items-center gap-2 rounded bg-accent px-8 py-5 text-lg font-medium text-on-accent shadow-[0_8px_40px_-8px_rgba(166,52,46,0.6)] transition-colors hover:bg-accent-strong"
            >
              Make your Top 10
              <ArrowRight
                className="h-5 w-5 transition-transform group-hover:translate-x-0.5"
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
                View leaderboard →
              </TrackedLink>
            ) : null}
          </div>
        </div>

        {crowd ? (
          <CrowdPanel crowd={crowd} eventSlug={event.slug} predictHref={`/predict/${event.slug}`} />
        ) : null}
      </div>
    </section>
  );
}
