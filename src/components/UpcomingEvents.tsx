import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { splitEventNameYear } from "@/lib/event-name-split";
import { TrackedLink } from "./TrackedLink";

/**
 * FOUCH 0.3B Home Multi-Event Rendering Fix — the Home's secondary
 * "Upcoming" section, for any event that isn't the current Featured
 * one. Renders name/date/subtitle/CTA entirely from each event's own
 * data (via the same generic splitEventNameYear FeaturedEvent uses) —
 * no per-event branching, so this needs no changes when a third event
 * is added later.
 */
export function UpcomingEvents({ events, dictionary }: { events: FouchEvent[]; dictionary: Dictionary }) {
  if (events.length === 0) return null;

  return (
    <section className="border-t border-border bg-surface py-14 sm:py-20">
      <div className="mx-auto max-w-content px-6">
        {events.map((event) => {
          const { primary, year } = splitEventNameYear(event.name);
          const date = new Date(`${event.eventDate}T00:00:00Z`);
          const dayMonth = date
            .toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" })
            .toUpperCase();

          return (
            <div key={event.slug} className="mb-10 last:mb-0">
              <div className="flex items-center gap-2">
                <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-text-muted" />
                <span className="text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">
                  {dictionary.featuredEvent.eyebrowUpcoming}
                </span>
              </div>

              <h3 className="mt-4 font-display leading-[0.95] text-text-primary">
                <span className="block text-2xl sm:text-3xl">{primary}</span>
                {year ? (
                  <span className="block text-5xl font-semibold tracking-tight sm:text-6xl">{year}</span>
                ) : null}
              </h3>

              <p className="mt-3 text-sm uppercase tracking-[0.15em] text-text-muted">
                {dayMonth} · {event.subtitle}
              </p>

              <TrackedLink
                href={`/predict/${event.slug}`}
                event="featured_event_clicked"
                eventProperties={{ slug: event.slug, source: "upcoming_secondary" }}
                className="group mt-6 inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
              >
                {dictionary.featuredEvent.cta}
                <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
              </TrackedLink>
            </div>
          );
        })}
      </div>
    </section>
  );
}
