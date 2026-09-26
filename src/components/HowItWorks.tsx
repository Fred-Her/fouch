import { CountryFlag } from "@/components/CountryFlag";
import type { Dictionary } from "@/content/types";

/**
 * FOUCH Home v1.1 Round 2 — each step pairs its copy with a small,
 * explicitly illustrative visual (a mini ranking card, a comparison
 * bar, a score ring). These are demonstrative UI, not live data —
 * none of them read from any real prediction, event, or user, and
 * the score example is labeled "Example score" so it can't be
 * mistaken for real platform activity.
 */
export function HowItWorks({ dictionary }: { dictionary: Dictionary }) {
  const predictCard = (
    <div
      key="predict"
      aria-hidden
      className="mt-5 rounded-lg border border-white/10 bg-white/[0.03] p-4"
    >
      {[
        { pos: 1, code: "CL" },
        { pos: 2, code: "VE" },
        { pos: 3, code: "AR" },
      ].map((row) => (
        <div key={row.pos} className="flex items-center gap-3 py-2">
          <span className="font-display w-5 text-sm text-accent-strong/80">{row.pos}</span>
          <CountryFlag countryCode={row.code} className="h-4 w-6 rounded-sm" />
          <span className="h-2 flex-1 rounded-full bg-white/10" />
        </div>
      ))}
    </div>
  );

  const competeCard = (
    <div key="compete" aria-hidden className="mt-5 space-y-3">
      <div className="flex items-center gap-2 text-xs uppercase tracking-wide text-text-muted">
        <span className="w-14 shrink-0">You</span>
        <span className="h-2 flex-1 overflow-hidden rounded-full bg-white/10">
          <span className="block h-full w-2/3 rounded-full bg-accent" />
        </span>
      </div>
      <div className="flex items-center gap-2 text-xs uppercase tracking-wide text-text-muted">
        <span className="w-14 shrink-0">Crowd</span>
        <span className="h-2 flex-1 overflow-hidden rounded-full bg-white/10">
          <span className="block h-full w-5/12 rounded-full bg-white/30" />
        </span>
      </div>
    </div>
  );

  const proveCard = (
    <div key="prove" aria-hidden className="mt-5 flex flex-col items-start gap-3">
      <div
        className="flex h-32 w-32 shrink-0 items-center justify-center rounded-full"
        style={{ background: "conic-gradient(var(--color-accent-strong, #c94a3f) 82%, rgba(255,255,255,0.08) 0)" }}
      >
        <div className="flex h-26 w-26 flex-col items-center justify-center rounded-full bg-black" style={{ height: "6.25rem", width: "6.25rem" }}>
          <span className="font-display text-4xl text-text-primary">82</span>
          <span className="text-[10px] uppercase tracking-wide text-text-muted">Excellent</span>
        </div>
      </div>
      <span className="text-xs uppercase tracking-[0.2em] text-text-muted">Example score</span>
    </div>
  );

  const visuals = [predictCard, competeCard, proveCard];

  return (
    <section className="relative mx-auto max-w-content px-6 pb-16 pt-10 sm:py-28">
      <p className="text-xs font-medium uppercase tracking-[0.25em] text-text-secondary">
        {dictionary.howItWorks.title}
      </p>
      <div className="mt-8 grid gap-12 sm:grid-cols-3 sm:gap-10">
        {dictionary.howItWorks.steps.map((step, index) => (
          <div key={step.title}>
            <p className="font-display text-5xl text-border-strong">
              {String(index + 1).padStart(2, "0")}
            </p>
            <p className="mt-3 font-display text-2xl uppercase tracking-tight text-text-primary">
              {step.title}
            </p>
            <p className="mt-1 text-sm text-text-secondary">{step.body}</p>
            {visuals[index]}
          </div>
        ))}
      </div>
    </section>
  );
}
