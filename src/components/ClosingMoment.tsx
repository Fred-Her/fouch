import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { CinematicBackdrop } from "./CinematicBackdrop";

/**
 * FOUCH Home v1.1 Round 2 — restrained closing brand statement, the
 * "final frame of a trailer": large typography, generous breathing
 * room, one strong CTA. No data dependency, no per-event content.
 */
export function ClosingMoment({ eventSlug }: { eventSlug: string | null }) {
  return (
    <section className="relative overflow-hidden py-20 text-center sm:py-48">
      <CinematicBackdrop variant={0} />
      <div className="relative mx-auto max-w-content px-6">
        <h2 className="font-display text-4xl uppercase leading-[1.05] tracking-tight text-text-primary sm:text-6xl md:text-8xl">
          Everyone has a take.
          <br />
          <span className="text-accent-strong">FOUCH keeps the receipts.</span>
        </h2>
        <p className="mt-8 text-sm uppercase tracking-[0.35em] text-text-muted">
          Predict · Compete · Prove it
        </p>

        {eventSlug ? (
          <Link
            href={`/predict/${eventSlug}`}
            className="group mt-12 inline-flex items-center gap-2 rounded bg-accent px-9 py-5 text-lg font-medium text-on-accent shadow-[0_8px_40px_-8px_rgba(166,52,46,0.6)] transition-colors hover:bg-accent-strong"
          >
            Make your call
            <ArrowRight className="h-5 w-5 transition-transform group-hover:translate-x-0.5" aria-hidden />
          </Link>
        ) : null}
      </div>
    </section>
  );
}
