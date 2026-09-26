import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { splitEventNameYear } from "@/lib/event-name-split";
import { getShortLocation } from "@/lib/event-location";
import { CinematicBackdrop } from "./CinematicBackdrop";
import { TrackedLink } from "./TrackedLink";

/**
 * FOUCH Home v1.1 Round 2 — the Home's secondary "Up Next" section, a
 * more compact "trailer" treatment than Now Predicting. Renders
 * name/date/subtitle/CTA entirely from each event's own data (via the
 * same generic splitEventNameYear FeaturedEvent uses) — no per-event
 * branching. Variant 1 of the shared cinematic backdrop gives it a
 * subtly different atmosphere from the featured section, derived only
 * from its position in the list, never from which event it is.
 */
export function UpcomingEvents({ events, dictionary }: { events: FouchEvent[]; dictionary: Dictionary }) {
  if (events.length === 0) return null;

  return (
    <>
      {events.map((event, index) => {
        const { primary, year } = splitEventNameYear(event.name);
        const date = new Date(`${event.eventDate}T00:00:00Z`);
        const dayMonth = date
          .toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" })
          .toUpperCase();

        return (
          <section key={event.slug} className="relative overflow-hidden py-8 sm:py-11">
            <CinematicBackdrop variant={1} />
            <div className="relative mx-auto max-w-content px-6">
              <div className="flex flex-wrap items-end justify-between gap-6">
                <div>
                  <div className="flex items-center gap-3">
                    <span className="font-display text-sm text-accent-strong/70">
                      {String(index + 2).padStart(2, "0")}
                    </span>
                    <span className="h-px w-8 bg-border-strong" aria-hidden />
                    <span className="text-xs font-medium uppercase tracking-[0.25em] text-text-secondary">
                      {dictionary.featuredEvent.eyebrowUpcoming}
                    </span>
                  </div>

                  <h3 className="mt-3 font-display leading-[0.95] text-text-primary">
                    <span className="block text-xl sm:text-2xl">{primary}</span>
                    {year ? (
                      <span className="block text-4xl font-semibold tracking-tight sm:text-5xl">{year}</span>
                    ) : null}
                  </h3>

                  <p className="mt-2 text-sm uppercase tracking-[0.15em] text-text-muted">
                    {dayMonth} · {getShortLocation(event.subtitle ?? "")}
                  </p>
                </div>

                <TrackedLink
                  href={`/predict/${event.slug}`}
                  event="featured_event_clicked"
                  eventProperties={{ slug: event.slug, source: "upcoming_secondary" }}
                  className="group inline-flex shrink-0 items-center gap-2 rounded bg-accent px-6 py-3.5 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
                >
                  {dictionary.featuredEvent.cta}
                  <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
                </TrackedLink>
              </div>
            </div>
          </section>
        );
      })}
    </>
  );
}
