# FOUCH Home v1.1 Round 2 — Cinematic Depth Pass (visual only, no data/logic changes).
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-home-v1-1-round2.ps1
$failures = @()

try {
    $path = "src\components\CinematicBackdrop.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * FOUCH Home v1.1 Round 2 — the reusable "dark cinematic" atmosphere
 * for any event section, used whenever an event has no hero_asset
 * (true for every event today). Pure CSS layers — no photography, no
 * contestant/crown imagery, no external assets, no new dependency.
 *
 * `variant` only shifts WHERE the glow sits and its hue balance — it
 * is derived by the caller from something generic (e.g. a section's
 * position, 0 for the featured event, 1 for the next one), never from
 * a specific event's identity. The same two variants work for any
 * future FOUCH event without new code.
 */
export function CinematicBackdrop({ variant = 0 }: { variant?: 0 | 1 }) {
  const isAlt = variant === 1;

  return (
    <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden bg-black">
      {/* Warm oxblood glow — the dominant light source, positioned
          opposite for each variant so two adjacent sections don't
          read as identical twins. */}
      <div
        className={
          "absolute h-[34rem] w-[34rem] rounded-full bg-accent/25 blur-[110px] " +
          (isAlt ? "-bottom-48 -left-40" : "-top-40 -right-32")
        }
      />
      {/* Cool secondary glow for depth/contrast against the warm one. */}
      <div
        className={
          "absolute h-[26rem] w-[26rem] rounded-full bg-slate-500/10 blur-[120px] " +
          (isAlt ? "-top-32 right-0" : "bottom-0 left-0")
        }
      />
      {/* Vignette — pulls focus to the center, gives the section edges
          depth instead of a flat black rectangle. */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent_35%,rgba(0,0,0,0.75)_100%)]" />
      {/* Very subtle grain, inline SVG noise — no image request, no
          new dependency. Kept faint (opacity ~4%) so it reads as
          texture, not visible static. */}
      <div
        className="absolute inset-0 opacity-[0.04] mix-blend-overlay"
        style={{
          backgroundImage:
            "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='120'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")",
        }}
      />
    </div>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\CinematicBackdrop.tsx"
} catch {
    Write-Host "FAILED: src\components\CinematicBackdrop.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\CinematicBackdrop.tsx"
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

      <div className="relative mx-auto grid max-w-content gap-12 px-6 lg:grid-cols-[1fr_340px] lg:items-end lg:gap-10">
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
    $path = "src\components\CrowdPanel.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import Link from "next/link";
import { CountryFlag } from "@/components/CountryFlag";
import { getSampleSizeBucket } from "@/lib/community-comparison";
import type { CrowdTopPicks } from "@/lib/crowd-picks";

/**
 * FOUCH Home v1.1 Round 2 "The Crowd" — presentational only; all
 * numbers come from getCrowdTopPicks (real, current-version,
 * is_final predictions). Small-sample behavior reuses
 * getSampleSizeBucket's existing "0"/"1_4" tiers unchanged — this
 * pass only restyles the same two states, it does not add a third
 * or move the threshold.
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

  return (
    <div className="relative overflow-hidden rounded-lg border border-white/10 bg-white/[0.03] p-6 backdrop-blur-sm">
      <span className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-accent/60 to-transparent" aria-hidden />

      <div className="flex items-center gap-2">
        <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-accent" />
        <p className="text-xs font-medium uppercase tracking-[0.25em] text-text-secondary">The Crowd</p>
      </div>

      {isEarly ? (
        <>
          <p className="mt-5 font-display text-3xl uppercase tracking-tight text-text-primary">
            It&apos;s early.
          </p>
          <p className="mt-3 text-sm text-text-secondary">
            The first calls are coming in. Make yours before the crowd starts taking shape.
          </p>
          <Link
            href={predictHref}
            className="mt-6 inline-flex items-center gap-1 text-sm font-medium text-accent-strong hover:text-accent"
          >
            Make your call →
          </Link>
        </>
      ) : (
        <>
          <div className="mt-3 flex items-center justify-between">
            <p className="text-sm text-text-secondary">Who does the crowd have winning?</p>
            <Link
              href={`/events/${eventSlug}/leaderboard`}
              className="shrink-0 text-xs text-text-muted hover:text-text-secondary"
            >
              View all →
            </Link>
          </div>

          <ol className="mt-5 space-y-3.5">
            {crowd.picks.map((pick, index) => (
              <li key={pick.participant.id} className="flex items-center gap-3">
                <span className="font-display w-4 shrink-0 text-sm text-text-muted">{index + 1}</span>
                <CountryFlag countryCode={pick.participant.countryCode} className="h-4 w-6 shrink-0 rounded-sm" />
                <span className="flex-1 truncate text-sm text-text-primary">{pick.participant.displayName}</span>
                <div className="flex w-24 items-center gap-2">
                  <span className="h-1 flex-1 overflow-hidden rounded-full bg-white/10">
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

          <p className="mt-5 text-xs text-text-muted">Based on {crowd.population} predictions</p>
        </>
      )}
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
    $path = "src\components\UpcomingEvents.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { splitEventNameYear } from "@/lib/event-name-split";
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
          <section key={event.slug} className="relative overflow-hidden py-12 sm:py-16">
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

                  <h3 className="mt-4 font-display leading-[0.95] text-text-primary">
                    <span className="block text-2xl sm:text-3xl">{primary}</span>
                    {year ? (
                      <span className="block text-5xl font-semibold tracking-tight sm:text-6xl">{year}</span>
                    ) : null}
                  </h3>

                  <p className="mt-3 text-sm uppercase tracking-[0.15em] text-text-muted">
                    {dayMonth} · {event.subtitle}
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
      className="mt-5 rounded-lg border border-white/10 bg-white/[0.03] p-3"
    >
      {[
        { pos: 1, code: "CL" },
        { pos: 2, code: "VE" },
        { pos: 3, code: "AR" },
      ].map((row) => (
        <div key={row.pos} className="flex items-center gap-2.5 py-1.5">
          <span className="font-display w-4 text-xs text-accent-strong/80">{row.pos}</span>
          <CountryFlag countryCode={row.code} className="h-3.5 w-5 rounded-sm" />
          <span className="h-1.5 flex-1 rounded-full bg-white/10" />
        </div>
      ))}
    </div>
  );

  const competeCard = (
    <div key="compete" aria-hidden className="mt-5 space-y-2.5">
      <div className="flex items-center gap-2 text-[10px] uppercase tracking-wide text-text-muted">
        <span className="w-12 shrink-0">You</span>
        <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/10">
          <span className="block h-full w-2/3 rounded-full bg-accent" />
        </span>
      </div>
      <div className="flex items-center gap-2 text-[10px] uppercase tracking-wide text-text-muted">
        <span className="w-12 shrink-0">Crowd</span>
        <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/10">
          <span className="block h-full w-5/12 rounded-full bg-white/30" />
        </span>
      </div>
    </div>
  );

  const proveCard = (
    <div key="prove" aria-hidden className="mt-5 flex items-center gap-4">
      <div
        className="flex h-20 w-20 shrink-0 items-center justify-center rounded-full"
        style={{ background: "conic-gradient(var(--color-accent-strong, #c94a3f) 82%, rgba(255,255,255,0.08) 0)" }}
      >
        <div className="flex h-16 w-16 flex-col items-center justify-center rounded-full bg-black">
          <span className="font-display text-2xl text-text-primary">82</span>
          <span className="text-[9px] uppercase tracking-wide text-text-muted">Excellent</span>
        </div>
      </div>
      <span className="text-xs uppercase tracking-wide text-text-muted">Example score</span>
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
    <section className="relative overflow-hidden py-28 text-center sm:py-40">
      <CinematicBackdrop variant={0} />
      <div className="relative mx-auto max-w-content px-6">
        <h2 className="font-display text-4xl uppercase leading-[1.05] tracking-tight text-text-primary sm:text-6xl md:text-7xl">
          Everyone has a take.
          <br />
          <span className="text-accent-strong">FOUCH keeps the receipts.</span>
        </h2>
        <p className="mt-6 text-sm uppercase tracking-[0.3em] text-text-muted">
          Predict · Compete · Prove it
        </p>

        {eventSlug ? (
          <Link
            href={`/predict/${eventSlug}`}
            className="group mt-10 inline-flex items-center gap-2 rounded bg-accent px-9 py-5 text-lg font-medium text-on-accent shadow-[0_8px_40px_-8px_rgba(166,52,46,0.6)] transition-colors hover:bg-accent-strong"
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
    Write-Host "All 6 files written successfully." -ForegroundColor Green
}
