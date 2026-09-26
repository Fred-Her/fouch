import Link from "next/link";
import { ArrowRight, Trophy, BarChart3, Star } from "lucide-react";
import type { Dictionary } from "@/content/types";

export function Hero({
  dictionary,
  eventSlug,
  predictionsOpen,
}: {
  dictionary: Dictionary;
  eventSlug: string | null;
  /** Home v1.1: only true when the featured event's own prediction
   * window is genuinely open right now (isPredictionWindowOpen) —
   * never assumed from event.status alone. Null/false renders no
   * status badge at all rather than a misleading one. */
  predictionsOpen: boolean;
}) {
  return (
    <section className="relative overflow-hidden">
      {/* Subtle decorative glow — not neon, not animated, just enough to
          suggest something is about to happen behind the headline. */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-32 left-1/2 h-[28rem] w-[28rem] -translate-x-1/2 rounded-full bg-accent/10 blur-3xl"
      />
      {/* Right-side atmospheric balance — desktop only, purely CSS: an
          oversized, near-invisible numeral plus a warm glow, giving the
          hero visual weight on the right without any photography, card,
          or fabricated content. */}
      <div
        aria-hidden
        className="pointer-events-none absolute -right-10 top-1/2 hidden -translate-y-1/2 select-none font-display text-[26rem] font-semibold leading-none text-white/[0.025] lg:block"
      >
        01
      </div>
      <div
        aria-hidden
        className="pointer-events-none absolute -right-32 top-1/3 hidden h-[24rem] w-[24rem] rounded-full bg-accent/10 blur-[100px] lg:block"
      />

      <div className="relative mx-auto max-w-content px-6 pb-10 pt-12 sm:pb-14 sm:pt-20">
        <p className="text-xs font-medium uppercase tracking-[0.25em] text-text-muted">
          Entertainment Predictions
        </p>

        <h1 className="mt-3 font-display text-[3.25rem] font-semibold uppercase leading-[0.95] tracking-tight text-text-primary sm:text-7xl">
          Make
          <br />
          your
          <br />
          call.
        </h1>

        <p className="mt-6 max-w-sm text-lg text-text-secondary">
          {dictionary.hero.subhead}
        </p>

        <div className="mt-9 flex flex-wrap items-center gap-x-6 gap-y-4">
          {eventSlug ? (
            <Link
              href={`/predict/${eventSlug}`}
              className="group inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent shadow-[0_0_0_1px_rgba(166,52,46,0.4)] transition-colors hover:bg-accent-strong"
            >
              Start predicting
              <ArrowRight
                className="h-4 w-4 transition-transform group-hover:translate-x-0.5"
                aria-hidden
              />
            </Link>
          ) : null}

          {predictionsOpen ? (
            <span className="inline-flex items-center gap-2 text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">
              <span
                aria-hidden
                className="h-1.5 w-1.5 rounded-full bg-accent animate-pulse motion-reduce:animate-none"
              />
              Predictions Open
            </span>
          ) : null}
        </div>

        <div className="mt-10 flex flex-wrap gap-x-8 gap-y-3 border-t border-border pt-6 text-sm text-text-muted">
          <span className="inline-flex items-center gap-2">
            <Trophy className="h-4 w-4" aria-hidden />
            Predict
            <span className="hidden text-text-secondary sm:inline">Build your Top 10</span>
          </span>
          <span className="inline-flex items-center gap-2">
            <BarChart3 className="h-4 w-4" aria-hidden />
            Compete
            <span className="hidden text-text-secondary sm:inline">See what the crowd thinks</span>
          </span>
          <span className="inline-flex items-center gap-2">
            <Star className="h-4 w-4" aria-hidden />
            Prove it
          </span>
        </div>
      </div>
    </section>
  );
}
