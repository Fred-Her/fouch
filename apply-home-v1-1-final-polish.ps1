# FOUCH Home v1.1 — Final Visual Polish (visual only, no data/logic changes).
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-home-v1-1-final-polish.ps1
$failures = @()

try {
    $path = "src\content\en.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Dictionary } from "./types";

export const en: Dictionary = {
  meta: {
    title: "Fouch — Make Your Call",
    description:
      "Predict entertainment's biggest moments and see how your picks compare with the world.",
  },
  nav: {
    wordmark: "Fouch",
  },
  hero: {
    headline: "Make your call.",
    subhead: "Predict it. See what the crowd thinks. Prove you called it.",
    cta: "Make your Top 10",
  },
  featuredEvent: {
    eyebrowUpcoming: "Upcoming",
    prompt: "Who makes your Top 10?",
    cta: "Make your Top 10",
  },
  howItWorks: {
    title: "How it works",
    steps: [
      { title: "Predict", body: "Build your ranking." },
      { title: "Compete", body: "See how your picks compare." },
      { title: "Prove it", body: "Get scored when the results are in." },
    ],
  },
  eventPage: {
    back: "Back to Fouch",
    comingSoon: "The prediction builder for this event opens soon.",
  },
  footer: {
    tagline: "Entertainment predictions.",
  },
};
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\content\en.ts"
} catch {
    Write-Host "FAILED: src\content\en.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\content\en.ts"
}

try {
    $path = "src\lib\event-location.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * FOUCH Home v1.1 — a generic, structural transform of an event's
 * subtitle ("<venue>, <city>, <region>") into a short "<city>,
 * <region>" location for compact presentations (Up Next). Derived
 * purely from comma structure, never from a specific event's
 * identity — the full subtitle (with venue) remains available
 * wherever a section chooses to show it (Now Predicting keeps the
 * full string).
 */
export function getShortLocation(subtitle: string): string {
  const parts = subtitle
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
  if (parts.length <= 2) return parts.join(", ");
  return parts.slice(-2).join(", ");
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-location.ts"
} catch {
    Write-Host "FAILED: src\lib\event-location.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-location.ts"
}

try {
    $path = "src\lib\event-location.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { getShortLocation } from "./event-location";

describe("getShortLocation — generic comma-structure transform, never event-specific", () => {
  it("shortens a 3-part venue subtitle to city + region", () => {
    expect(getShortLocation("José Miguel Agrelot Coliseum, San Juan, Puerto Rico")).toBe(
      "San Juan, Puerto Rico",
    );
  });

  it("leaves a 2-part subtitle unchanged", () => {
    expect(getShortLocation("Bangkok, Thailand")).toBe("Bangkok, Thailand");
  });

  it("leaves a single-part subtitle unchanged", () => {
    expect(getShortLocation("Bangkok")).toBe("Bangkok");
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-location.test.ts"
} catch {
    Write-Host "FAILED: src\lib\event-location.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-location.test.ts"
}

try {
    $path = "src\components\UpcomingEvents.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\UpcomingEvents.tsx"
} catch {
    Write-Host "FAILED: src\components\UpcomingEvents.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\UpcomingEvents.tsx"
}

try {
    $path = "src\components\HowItWorks.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
    <section className="relative mx-auto max-w-content px-6 py-20 sm:py-28">
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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\HowItWorks.tsx"
} catch {
    Write-Host "FAILED: src\components\HowItWorks.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\HowItWorks.tsx"
}

try {
    $path = "src\components\Hero.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\Hero.tsx"
} catch {
    Write-Host "FAILED: src\components\Hero.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\Hero.tsx"
}

try {
    $path = "src\components\ClosingMoment.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
    <section className="relative overflow-hidden py-32 text-center sm:py-48">
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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\ClosingMoment.tsx"
} catch {
    Write-Host "FAILED: src\components\ClosingMoment.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\ClosingMoment.tsx"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 7 files written successfully." -ForegroundColor Green
}
