# FOUCH Home v1.1 — Mobile spacing fix only (desktop composition unchanged).
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-home-v1-1-mobile-spacing.ps1
$failures = @()

try {
    $path = "src\components\FeaturedEvent.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { getParticipantsForEvent } from "@/lib/participants";
import { getOfficialResult } from "@/lib/results-db";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { getCrowdTopPicks } from "@/lib/crowd-picks";
import { splitEventNameYear } from "@/lib/event-name-split";
import { CinematicBackdrop } from "./CinematicBackdrop";
import { CrowdPanel } from "./CrowdPanel";
import { TrackedLink } from "./TrackedLink";

export async function FeaturedEvent({
  event,
  dictionary,
}: {
  event: FouchEvent;
  dictionary: Dictionary;
}) {
  const date = new Date(`${event.eventDate}T00:00:00Z`);
  const dayMonth = date
    .toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" })
    .toUpperCase();

  // Sprint 5.1: the secondary leaderboard link is event/result-state
  // driven, never hardcoded to a specific slug — it only appears once
  // an official/demo result genuinely exists to rank against.
  const participantData = await getParticipantsForEvent(event.slug);
  const hasLeaderboard = participantData
    ? Boolean(await getOfficialResult(event.slug, participantData.status))
    : false;

  // Home v1.1: "Now Predicting" must reflect the ACTUAL prediction
  // window, never assume an "upcoming"/"open" DB status means
  // predictions are open right now (brief §3: "Do not label an event
  // NOW PREDICTING if its prediction window is closed").
  const lockConfig = await getEventLockConfig(event.slug);
  const isOpen = isPredictionWindowOpen(lockConfig, Date.now());
  const eyebrow = isOpen ? "Now Predicting" : "Predictions Closed";

  const crowd = participantData ? await getCrowdTopPicks(event.slug, participantData.status) : null;

  const { primary, year } = splitEventNameYear(event.name);

  return (
    <section id="featured-event" className="relative scroll-mt-20 overflow-hidden py-16 sm:py-24">
      <CinematicBackdrop variant={0} />

      <div className="relative mx-auto grid max-w-content gap-y-20 gap-x-12 px-6 lg:grid-cols-[1fr_340px] lg:items-end lg:gap-10">
        <div>
          <div className="flex items-center gap-3">
            <span className="font-display text-sm text-accent-strong/70">01</span>
            <span className="h-px w-8 bg-border-strong" aria-hidden />
            <span
              aria-hidden
              className={
                isOpen
                  ? "h-1.5 w-1.5 rounded-full bg-accent animate-pulse motion-reduce:animate-none"
                  : "h-1.5 w-1.5 rounded-full bg-text-muted"
              }
            />
            <span className="text-xs font-medium uppercase tracking-[0.25em] text-text-secondary">
              {eyebrow}
            </span>
          </div>

          <h2 className="mt-6 font-display leading-[0.9] text-text-primary">
            <span className="block text-3xl sm:text-4xl">{primary}</span>
            {year ? (
              <span className="block bg-gradient-to-b from-text-primary to-text-primary/70 bg-clip-text text-8xl font-semibold tracking-tight text-transparent sm:text-9xl">
                {year}
              </span>
            ) : null}
          </h2>

          <p className="mt-5 text-sm uppercase tracking-[0.2em] text-text-muted">
            {dayMonth} · {event.subtitle}
          </p>

          <p className="mt-8 text-lg text-text-secondary">{dictionary.featuredEvent.prompt}</p>

          <div className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-3">
            <TrackedLink
              href={`/predict/${event.slug}`}
              event="featured_event_clicked"
              eventProperties={{ slug: event.slug }}
              className="group inline-flex items-center gap-2 rounded bg-accent px-8 py-5 text-lg font-medium text-on-accent shadow-[0_8px_40px_-8px_rgba(166,52,46,0.6)] transition-colors hover:bg-accent-strong"
            >
              Make your Top 10
              <ArrowRight
                className="h-5 w-5 transition-transform group-hover:translate-x-0.5"
                aria-hidden
              />
            </TrackedLink>

            {hasLeaderboard ? (
              <TrackedLink
                href={`/events/${event.slug}/leaderboard`}
                event="leaderboard_from_score_clicked"
                eventProperties={{ event_slug: event.slug, source: "home" }}
                className="text-sm text-text-secondary transition-colors hover:text-accent-strong"
              >
                View leaderboard →
              </TrackedLink>
            ) : null}
          </div>
        </div>

        {crowd ? (
          <CrowdPanel crowd={crowd} eventSlug={event.slug} predictHref={`/predict/${event.slug}`} />
        ) : null}
      </div>
    </section>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\FeaturedEvent.tsx"
} catch {
    Write-Host "FAILED: src\components\FeaturedEvent.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\FeaturedEvent.tsx"
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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\HowItWorks.tsx"
} catch {
    Write-Host "FAILED: src\components\HowItWorks.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\HowItWorks.tsx"
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
    Write-Host "All 3 files written successfully." -ForegroundColor Green
}
