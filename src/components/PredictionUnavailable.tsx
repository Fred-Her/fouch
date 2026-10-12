import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { fmt } from "@/lib/i18n";
import type { Dictionary } from "@/content/types";

/**
 * Replaces the builder/review when an event can't take predictions:
 *  - "closed": the prediction window has ended -> link to results;
 *  - "coming_soon": the official roster isn't loaded yet (placeholder
 *    data must never be predicted against).
 */
export function PredictionUnavailable({
  variant,
  eventName,
  eventSlug,
  dictionary,
}: {
  variant: "closed" | "coming_soon";
  eventName: string;
  eventSlug: string;
  dictionary: Dictionary;
}) {
  const t = dictionary.unavailable;

  return (
    <main className="mx-auto max-w-content px-6 py-10">
      <div className="flex items-center justify-between">
        <Link href="/" className="inline-flex items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary">
          <ArrowLeft className="h-4 w-4" aria-hidden />
          {t.backHome}
        </Link>
        <LanguageSwitcher eventSlug={eventSlug} />
      </div>

      <p className="mt-10 text-xs font-medium uppercase tracking-[0.25em] text-text-muted">
        {variant === "coming_soon" ? t.comingSoonLabel : eventName}
      </p>
      <h1 className="mt-3 font-display text-3xl uppercase leading-tight tracking-tight text-text-primary sm:text-5xl">
        {variant === "coming_soon" ? fmt(t.comingSoonTitle, { event: eventName }) : t.closedTitle}
      </h1>
      <p className="mt-4 max-w-md text-text-secondary">{variant === "coming_soon" ? t.comingSoonBody : t.closedBody}</p>

      {variant === "closed" ? (
        <Link
          href={`/events/${eventSlug}/leaderboard`}
          className="mt-8 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
        >
          {t.viewResults}
        </Link>
      ) : null}
    </main>
  );
}
