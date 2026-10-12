# FOUCH Home v1.1 — Make It Feel Alive.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-home-v1-1.ps1
$failures = @()

try {
    $path = "src\lib\crowd-picks.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { getEligiblePredictionsForComparison } from "@/lib/predictions-db";
import { computeCommunityTop10 } from "@/lib/community-comparison";
import { resolveParticipantsByIds } from "@/lib/participants";
import type { ParticipantDataStatus } from "@/lib/participants";
import type { Participant } from "@/types/participant";

export interface CrowdTopPick {
  participant: Participant;
  /** % of eligible predictions that picked this participant as their
   * #1 — "who does the crowd have winning", not a Top-10-inclusion
   * rate. Rounded for display only; never re-derives a different
   * ranking than computeCommunityTop10's own points-based order. */
  pct: number;
}

export interface CrowdTopPicks {
  population: number;
  picks: CrowdTopPick[];
}

/**
 * FOUCH Home v1.1 "The Crowd" section — reuses the EXACT same
 * eligibility (getEligiblePredictionsForComparison: is_final = true,
 * scoped by event_slug + data_status, current-version-only) and
 * ranking (computeCommunityTop10, the same function You vs The World
 * uses) as the rest of the product. This is deliberately not a
 * second definition of "the crowd" — it's the same one, just without
 * a specific viewer's own prediction to compare against.
 *
 * Returns null when there's no event to show (never happens for a
 * resolved event, but keeps the caller's null-handling simple) —
 * an empty population returns `{ population: 0, picks: [] }`, which
 * the component renders as the small-sample "IT'S EARLY" state.
 */
export async function getCrowdTopPicks(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
  limit = 5,
): Promise<CrowdTopPicks> {
  const eligible = await getEligiblePredictionsForComparison(eventSlug, dataStatus);
  const population = eligible.length;

  if (population === 0) return { population: 0, picks: [] };

  const ranked = computeCommunityTop10(eligible).slice(0, limit);
  const participantsById = await resolveParticipantsByIds(
    eventSlug,
    ranked.map((entry) => entry.participantId),
  );

  const picks: CrowdTopPick[] = [];
  for (const entry of ranked) {
    const participant = participantsById.get(entry.participantId);
    if (!participant) continue; // Resolvable-by-id failure is a data anomaly, not a reason to show a blank row.
    picks.push({
      participant,
      pct: Math.round((entry.firstPlaceCount / population) * 100),
    });
  }

  return { population, picks };
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\crowd-picks.ts"
} catch {
    Write-Host "FAILED: src\lib\crowd-picks.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\crowd-picks.ts"
}

try {
    $path = "src\components\CrowdPanel.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import Link from "next/link";
import { CountryFlag } from "@/components/CountryFlag";
import { getSampleSizeBucket } from "@/lib/community-comparison";
import type { CrowdTopPicks } from "@/lib/crowd-picks";

/**
 * FOUCH Home v1.1 "The Crowd" — presentational only; all numbers come
 * from getCrowdTopPicks (real, current-version, is_final predictions).
 * Small-sample behavior reuses getSampleSizeBucket's existing "0"/"1_4"
 * tiers (the same ones You vs The World already uses) rather than a
 * new Home-specific threshold — the only new thing here is which
 * COPY renders for the "0" tier ("IT'S EARLY"), not a new number.
 */
export function CrowdPanel({
  crowd,
  eventSlug,
  predictHref,
}: {
  crowd: CrowdTopPicks;
  eventSlug: string;
  predictHref: string;
}) {
  const bucket = getSampleSizeBucket(crowd.population);
  const isEarly = bucket === "0" || bucket === "1_4";

  if (isEarly) {
    return (
      <div className="rounded border border-border bg-background/40 p-6">
        <p className="text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">The Crowd</p>
        <p className="mt-4 font-display text-2xl uppercase tracking-tight text-text-primary">
          It&apos;s early.
        </p>
        <p className="mt-2 text-sm text-text-secondary">
          The first calls are coming in. Make yours before the crowd starts taking shape.
        </p>
        <Link
          href={predictHref}
          className="mt-5 inline-flex items-center gap-1 text-sm font-medium text-accent-strong hover:text-accent"
        >
          Make your call →
        </Link>
      </div>
    );
  }

  return (
    <div className="rounded border border-border bg-background/40 p-6">
      <div className="flex items-center justify-between">
        <p className="text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">The Crowd</p>
        <Link
          href={`/events/${eventSlug}/leaderboard`}
          className="text-xs text-text-muted hover:text-text-secondary"
        >
          View all →
        </Link>
      </div>
      <p className="mt-2 text-sm text-text-secondary">Who does the crowd have winning?</p>

      <ol className="mt-4 space-y-3">
        {crowd.picks.map((pick, index) => (
          <li key={pick.participant.id} className="flex items-center gap-3">
            <span className="w-4 shrink-0 text-sm text-text-muted">{index + 1}</span>
            <CountryFlag countryCode={pick.participant.countryCode} className="h-4 w-6 shrink-0 rounded-sm" />
            <span className="flex-1 truncate text-sm text-text-primary">{pick.participant.displayName}</span>
            <div className="flex w-24 items-center gap-2">
              <span className="h-1 flex-1 overflow-hidden rounded-full bg-border">
                <span
                  className="block h-full rounded-full bg-accent"
                  style={{ width: `${Math.max(4, pick.pct)}%` }}
                />
              </span>
              <span className="w-9 shrink-0 text-right text-xs text-text-muted">{pick.pct}%</span>
            </div>
          </li>
        ))}
      </ol>

      <p className="mt-4 text-xs text-text-muted">Based on {crowd.population} predictions</p>
    </div>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\CrowdPanel.tsx"
} catch {
    Write-Host "FAILED: src\components\CrowdPanel.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\CrowdPanel.tsx"
}

try {
    $path = "src\components\ClosingMoment.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import Link from "next/link";
import { ArrowRight } from "lucide-react";

/**
 * FOUCH Home v1.1 — restrained closing brand statement, purely
 * editorial copy. No data dependency, no per-event content.
 */
export function ClosingMoment({ eventSlug }: { eventSlug: string | null }) {
  return (
    <section className="border-t border-border bg-black py-16 text-center sm:py-24">
      <div className="mx-auto max-w-content px-6">
        <h2 className="font-display text-3xl uppercase leading-[1.05] tracking-tight text-text-primary sm:text-5xl">
          Everyone has a take.
          <br />
          <span className="text-accent-strong">FOUCH keeps the receipts.</span>
        </h2>
        <p className="mt-4 text-sm uppercase tracking-[0.2em] text-text-muted">
          Predict. Compete. Prove it.
        </p>

        {eventSlug ? (
          <Link
            href={`/predict/${eventSlug}`}
            className="group mt-8 inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            Make your call
            <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
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

  // Decorative only — a preview of the ranking mechanic, not real input.
  const previewSlots = [1, 2, 3];

  const { primary, year } = splitEventNameYear(event.name);

  return (
    <section
      id="featured-event"
      className="relative scroll-mt-20 overflow-hidden border-y border-border bg-gradient-to-br from-surface via-background to-black py-14 sm:py-20"
    >
      <div
        aria-hidden
        className="pointer-events-none absolute -right-24 top-1/2 h-96 w-96 -translate-y-1/2 rounded-full bg-accent/10 blur-3xl"
      />

      <div className="relative mx-auto grid max-w-content gap-10 px-6 lg:grid-cols-[1fr_360px] lg:items-start lg:gap-16">
        <div>
          <div className="flex items-center gap-3">
            <span className="font-display text-sm text-border-strong">01</span>
            <span
              aria-hidden
              className={
                isOpen
                  ? "h-1.5 w-1.5 rounded-full bg-accent animate-pulse motion-reduce:animate-none"
                  : "h-1.5 w-1.5 rounded-full bg-text-muted"
              }
            />
            <span className="text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">
              {eyebrow}
            </span>
          </div>

          <h2 className="mt-5 font-display leading-[0.95] text-text-primary">
            <span className="block text-3xl sm:text-4xl">{primary}</span>
            {year ? (
              <span className="block text-7xl font-semibold tracking-tight sm:text-8xl">{year}</span>
            ) : null}
          </h2>

          <p className="mt-4 text-sm uppercase tracking-[0.15em] text-text-muted">
            {dayMonth} · {event.subtitle}
          </p>

          <p className="mt-8 text-lg text-text-secondary">{dictionary.featuredEvent.prompt}</p>

          {/* Decorative preview of the ranking mechanic — not interactive. */}
          <div aria-hidden className="mt-6 max-w-xs space-y-2">
            {previewSlots.map((slot) => (
              <div key={slot} className="flex items-center gap-3">
                <span className="font-display text-sm text-text-muted">
                  {String(slot).padStart(2, "0")}
                </span>
                <span className="h-px flex-1 bg-border-strong" />
              </div>
            ))}
          </div>

          <div className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-3">
            <TrackedLink
              href={`/predict/${event.slug}`}
              event="featured_event_clicked"
              eventProperties={{ slug: event.slug }}
              className="group inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
            >
              {dictionary.featuredEvent.cta}
              <ArrowRight
                className="h-4 w-4 transition-transform group-hover:translate-x-0.5"
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
    $path = "src\components\UpcomingEvents.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { splitEventNameYear } from "@/lib/event-name-split";
import { TrackedLink } from "./TrackedLink";

/**
 * FOUCH 0.3B Home Multi-Event Rendering Fix — the Home's secondary
 * "Upcoming" section, for any event that isn't the current Featured
 * one. Renders name/date/subtitle/CTA entirely from each event's own
 * data (via the same generic splitEventNameYear FeaturedEvent uses) —
 * no per-event branching, so this needs no changes when a third event
 * is added later.
 */
export function UpcomingEvents({ events, dictionary }: { events: FouchEvent[]; dictionary: Dictionary }) {
  if (events.length === 0) return null;

  return (
    <section className="border-t border-border bg-surface py-14 sm:py-20">
      <div className="mx-auto max-w-content px-6">
        {events.map((event, index) => {
          const { primary, year } = splitEventNameYear(event.name);
          const date = new Date(`${event.eventDate}T00:00:00Z`);
          const dayMonth = date
            .toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" })
            .toUpperCase();

          return (
            <div key={event.slug} className="mb-10 last:mb-0">
              <div className="flex items-center gap-3">
                <span className="font-display text-sm text-border-strong">{String(index + 2).padStart(2, "0")}</span>
                <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-text-muted" />
                <span className="text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">
                  {dictionary.featuredEvent.eyebrowUpcoming}
                </span>
              </div>

              <h3 className="mt-4 font-display leading-[0.95] text-text-primary">
                <span className="block text-2xl sm:text-3xl">{primary}</span>
                {year ? (
                  <span className="block text-5xl font-semibold tracking-tight sm:text-6xl">{year}</span>
                ) : null}
              </h3>

              <p className="mt-3 text-sm uppercase tracking-[0.15em] text-text-muted">
                {dayMonth} · {event.subtitle}
              </p>

              <TrackedLink
                href={`/predict/${event.slug}`}
                event="featured_event_clicked"
                eventProperties={{ slug: event.slug, source: "upcoming_secondary" }}
                className="group mt-6 inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
              >
                {dictionary.featuredEvent.cta}
                <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
              </TrackedLink>
            </div>
          );
        })}
      </div>
    </section>
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
import type { Dictionary } from "@/content/types";

/**
 * FOUCH Home v1.1 — each step now pairs its copy with a small,
 * explicitly illustrative visual (a mini ranking card, a comparison
 * bar, a score ring). These are demonstrative UI, not live data —
 * none of them read from any real prediction, event, or user.
 */
export function HowItWorks({ dictionary }: { dictionary: Dictionary }) {
  const visuals = [
    <div key="predict" aria-hidden className="mt-4 space-y-1.5">
      {[1, 2, 3].map((n) => (
        <div key={n} className="flex items-center gap-2 rounded border border-border bg-background/40 px-3 py-2">
          <span className="font-display text-xs text-text-muted">{n}</span>
          <span className="h-1.5 flex-1 rounded-full bg-border-strong" />
        </div>
      ))}
    </div>,
    <div key="compete" aria-hidden className="mt-4 space-y-2">
      <div className="flex items-center gap-2 text-[10px] uppercase tracking-wide text-text-muted">
        <span className="w-14 shrink-0">You</span>
        <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-border">
          <span className="block h-full w-2/3 rounded-full bg-accent" />
        </span>
      </div>
      <div className="flex items-center gap-2 text-[10px] uppercase tracking-wide text-text-muted">
        <span className="w-14 shrink-0">Crowd</span>
        <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-border">
          <span className="block h-full w-5/12 rounded-full bg-border-strong" />
        </span>
      </div>
    </div>,
    <div key="prove" aria-hidden className="mt-4 flex items-center gap-3">
      <div
        className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full text-sm font-semibold text-text-primary"
        style={{ background: "conic-gradient(var(--color-accent, #a6342e) 82%, var(--color-border, #2a2a2a) 0)" }}
      >
        <span className="flex h-11 w-11 items-center justify-center rounded-full bg-background text-xs">
          82
        </span>
      </div>
      <span className="text-xs uppercase tracking-wide text-text-muted">Example score</span>
    </div>,
  ];

  return (
    <section className="mx-auto max-w-content px-6 py-16 sm:py-20">
      <p className="text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">
        {dictionary.howItWorks.title}
      </p>
      <div className="mt-6 grid gap-10 sm:grid-cols-3 sm:gap-8">
        {dictionary.howItWorks.steps.map((step, index) => (
          <div key={step.title}>
            <p className="font-display text-4xl text-border-strong">
              {String(index + 1).padStart(2, "0")}
            </p>
            <p className="mt-2 font-display text-2xl uppercase tracking-tight text-text-primary">
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
    $path = "src\app\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { en } from "@/content/en";
import { getFeaturedEvent, getSecondaryUpcomingEvents } from "@/lib/events";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { Nav } from "@/components/Nav";
import { Hero } from "@/components/Hero";
import { FeaturedEvent } from "@/components/FeaturedEvent";
import { UpcomingEvents } from "@/components/UpcomingEvents";
import { HowItWorks } from "@/components/HowItWorks";
import { ClosingMoment } from "@/components/ClosingMoment";
import { Footer } from "@/components/Footer";
import { ViewTracker } from "@/components/ViewTracker";

// Sprint 5.1: FeaturedEvent checks live result state (for the secondary
// leaderboard link) — force fresh execution so that check is never
// baked into a static build and left stale until the next deploy.
export const dynamic = "force-dynamic";

export default async function Home() {
  const featuredEvent = await getFeaturedEvent();
  const upcomingEvents = await getSecondaryUpcomingEvents(featuredEvent?.slug ?? null);

  // Home v1.1: the Hero's "Predictions Open" badge reflects the same
  // real lock-window check every other prediction-open decision in
  // the app uses — never inferred from event.status.
  const featuredLockConfig = featuredEvent ? await getEventLockConfig(featuredEvent.slug) : null;
  const predictionsOpen = featuredEvent ? isPredictionWindowOpen(featuredLockConfig, Date.now()) : false;

  return (
    <>
      <ViewTracker event="landing_view" />
      <Nav />
      <main>
        <Hero dictionary={en} eventSlug={featuredEvent?.slug ?? null} predictionsOpen={predictionsOpen} />
        {featuredEvent ? (
          <FeaturedEvent event={featuredEvent} dictionary={en} />
        ) : null}
        <UpcomingEvents events={upcomingEvents} dictionary={en} />
        <HowItWorks dictionary={en} />
        <ClosingMoment eventSlug={featuredEvent?.slug ?? null} />
      </main>
      <Footer dictionary={en} />
    </>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\page.tsx"
} catch {
    Write-Host "FAILED: src\app\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\page.tsx"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 8 files written successfully." -ForegroundColor Green
}
