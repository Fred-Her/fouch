import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";

export function Hero({ dictionary }: { dictionary: Dictionary }) {
  return (
    <section className="relative overflow-hidden">
      {/* Subtle decorative glow â€” not neon, not animated, just enough to
          suggest something is about to happen behind the headline. */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-40 left-1/2 h-[32rem] w-[32rem] -translate-x-1/2 rounded-full bg-accent/10 blur-3xl"
      />

      <div className="relative mx-auto max-w-content px-6 pb-12 pt-14 sm:pb-16 sm:pt-24">
        <p className="font-display text-sm tracking-[0.2em] text-text-muted">FOUCH</p>

        <h1 className="mt-4 font-display text-[3.25rem] font-semibold uppercase leading-[0.95] tracking-tight text-text-primary sm:text-7xl">
          Make
          <br />
          your
          <br />
          call.
        </h1>

        <p className="mt-6 max-w-sm text-lg text-text-secondary">
          {dictionary.hero.subhead}
        </p>

        <a
          href="#featured-event"
          className="group mt-9 inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent shadow-[0_0_0_1px_rgba(166,52,46,0.4)] transition-colors hover:bg-accent-strong"
        >
          {dictionary.hero.cta}
          <ArrowRight
            className="h-4 w-4 transition-transform group-hover:translate-x-0.5"
            aria-hidden
          />
        </a>
      </div>
    </section>
  );
}