import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { fmt } from "@/lib/i18n";
import { getEventShortLabel } from "@/lib/event-name-split";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";

/**
 * Home: a discreet but visible link from a completed event to its
 * final leaderboard (and, through it, every historical prediction).
 */
export function ResultsLink({ event, dictionary }: { event: FouchEvent; dictionary: Dictionary }) {
  return (
    <section className="mx-auto max-w-content px-6 pb-2 pt-2">
      <Link
        href={`/events/${event.slug}/leaderboard`}
        className="group inline-flex items-center gap-2 rounded border border-border-strong px-4 py-2.5 text-sm text-text-secondary transition-colors hover:border-accent hover:text-text-primary"
      >
        <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-accent" />
        {fmt(dictionary.homeResults.link, { event: getEventShortLabel(event.name) })}
        <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
      </Link>
    </section>
  );
}
