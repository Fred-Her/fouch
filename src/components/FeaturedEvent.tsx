import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { TrackedLink } from "./TrackedLink";

const statusLabel: Record<FouchEvent["status"], string> = {
  upcoming: "Upcoming",
  open: "Open",
  live: "Live",
  completed: "Completed",
};

export function FeaturedEvent({
  event,
  dictionary,
}: {
  event: FouchEvent;
  dictionary: Dictionary;
}) {
  const formattedDate = new Date(event.eventDate).toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  });

  return (
    <section id="featured-event" className="mx-auto max-w-content px-6 pb-16 scroll-mt-20">
      <div className="rounded-md border border-border bg-surface p-6 sm:p-8">
        <span className="inline-block rounded-sm border border-border-strong px-2 py-1 text-xs font-medium tracking-[0.08em] text-text-secondary">
          {statusLabel[event.status]}
        </span>

        <h2 className="mt-4 font-display text-2xl text-text-primary sm:text-3xl">
          {event.name}
        </h2>

        {event.subtitle ? (
          <p className="mt-1 text-sm text-text-muted">
            {event.subtitle} · {formattedDate}
          </p>
        ) : null}

        <p className="mt-6 text-lg text-text-secondary">{dictionary.featuredEvent.prompt}</p>

        <TrackedLink
          href={`/events/${event.slug}`}
          event="featured_event_clicked"
          eventProperties={{ slug: event.slug }}
          className="mt-6 inline-flex items-center justify-center rounded border border-border-strong px-6 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          {dictionary.featuredEvent.cta}
        </TrackedLink>
      </div>
    </section>
  );
}
