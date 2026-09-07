# Encoding fix — re-writes every file that was ever delivered through
# a BOM-less .ps1 script, this time WITH a UTF-8 BOM so Windows
# PowerShell 5.1 (powershell.exe) parses this script's own special
# characters correctly instead of misreading them via the system ANSI
# codepage.
# Run from the project root: powershell -ExecutionPolicy Bypass -File fix-encoding.ps1
$failures = @()

try {
    $path = "src\app\predict\[slug]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getEventBySlug } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { PredictionBuilder } from "@/components/prediction/PredictionBuilder";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = getEventBySlug(slug);
  if (!event) return {};

  return {
    title: `Build your Top 10 — ${event.name}`,
    description: "Choose the 10 contestants you think will go furthest.",
  };
}

const REQUIRED_SELECTIONS = 10;

export default async function PredictPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const event = getEventBySlug(slug);
  if (!event) notFound();

  const participantData = getParticipantsForEvent(slug);
  if (!participantData || participantData.participants.length === 0) {
    return (
      <main className="mx-auto max-w-content px-6 py-16">
        <Link
          href="/"
          className="inline-flex items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden />
          Back to Fouch
        </Link>
        <p className="mt-8 text-text-secondary">
          No participants are available for this event yet. Check back soon.
        </p>
      </main>
    );
  }

  const { status, participants } = participantData;
  const requiredCount = Math.min(REQUIRED_SELECTIONS, participants.length);

  return (
    <main>
      <div className="mx-auto max-w-content px-6 pt-8">
        <Link
          href="/"
          className="inline-flex items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden />
          Back to Fouch
        </Link>

        <p className="mt-6 font-display text-sm tracking-[0.2em] text-text-muted">FOUCH</p>
        <h1 className="mt-1 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
        <p className="mt-3 font-display text-xl uppercase tracking-tight text-text-primary">
          Build your Top {requiredCount}
        </p>
        <p className="mt-2 max-w-md text-sm text-text-secondary">
          Choose the {requiredCount} contestants you think will go furthest.
        </p>

        {status === "demo" ? (
          <p className="mt-4 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
            Demo participant data — not the official lineup
          </p>
        ) : null}
      </div>

      <div className="mt-8">
        <PredictionBuilder
          eventSlug={slug}
          participants={participants}
          requiredCount={requiredCount}
        />
      </div>
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\predict\[slug]\page.tsx"
} catch {
    Write-Host "FAILED: src\app\predict\[slug]\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\predict\[slug]\page.tsx"
}

try {
    $path = "src\app\predict\[slug]\review\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getEventBySlug } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { ReviewContent } from "@/components/prediction/ReviewContent";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = getEventBySlug(slug);
  if (!event) return {};

  return { title: `Your Top 10 — ${event.name}` };
}

const REQUIRED_SELECTIONS = 10;

export default async function ReviewPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const event = getEventBySlug(slug);
  if (!event) notFound();

  const participantData = getParticipantsForEvent(slug);
  if (!participantData || participantData.participants.length === 0) notFound();

  const requiredCount = Math.min(REQUIRED_SELECTIONS, participantData.participants.length);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link
        href={`/predict/${slug}`}
        className="inline-flex items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary"
      >
        <ArrowLeft className="h-4 w-4" aria-hidden />
        Back to builder
      </Link>

      <p className="mt-6 font-display text-sm tracking-[0.2em] text-text-muted">FOUCH</p>
      <h1 className="mt-1 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-3 font-display text-xl uppercase tracking-tight text-text-primary">
        Your Top {requiredCount}
      </p>

      <div className="mt-8">
        <ReviewContent
          eventSlug={slug}
          participants={participantData.participants}
          requiredCount={requiredCount}
        />
      </div>
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\predict\[slug]\review\page.tsx"
} catch {
    Write-Host "FAILED: src\app\predict\[slug]\review\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\predict\[slug]\review\page.tsx"
}

try {
    $path = "src\components\FeaturedEvent.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { TrackedLink } from "./TrackedLink";

const statusLabel: Record<FouchEvent["status"], string> = {
  upcoming: "Upcoming",
  open: "Open",
  live: "Live",
  completed: "Completed",
};

export function FeaturedEvent({
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

  // Decorative only — a preview of the ranking mechanic, not real input.
  const previewSlots = [1, 2, 3];

  return (
    <section
      id="featured-event"
      className="relative scroll-mt-20 overflow-hidden border-y border-border bg-surface py-14 sm:py-20"
    >
      <div
        aria-hidden
        className="pointer-events-none absolute -right-24 top-1/2 h-96 w-96 -translate-y-1/2 rounded-full bg-accent/10 blur-3xl"
      />

      <div className="relative mx-auto max-w-content px-6">
        <div className="flex items-center gap-2">
          <span
            aria-hidden
            className={
              event.status === "live"
                ? "h-1.5 w-1.5 rounded-full bg-accent animate-pulse motion-reduce:animate-none"
                : "h-1.5 w-1.5 rounded-full bg-text-muted"
            }
          />
          <span className="text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">
            {statusLabel[event.status]}
          </span>
        </div>

        <h2 className="mt-5 font-display leading-[0.95] text-text-primary">
          <span className="block text-3xl sm:text-4xl">Miss Universe</span>
          <span className="block text-7xl font-semibold tracking-tight sm:text-8xl">
            2026
          </span>
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

        <TrackedLink
          href={`/predict/${event.slug}`}
          event="featured_event_clicked"
          eventProperties={{ slug: event.slug }}
          className="group mt-8 inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
        >
          {dictionary.featuredEvent.cta}
          <ArrowRight
            className="h-4 w-4 transition-transform group-hover:translate-x-0.5"
            aria-hidden
          />
        </TrackedLink>
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
    $path = "src\app\layout.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import { en } from "@/content/en";
import { siteUrl } from "@/lib/site";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  alternates: {
    canonical: "/",
  },
  title: {
    default: en.meta.title,
    template: "%s · Fouch",
  },
  description: en.meta.description,
  openGraph: {
    title: en.meta.title,
    description: en.meta.description,
    url: siteUrl,
    siteName: "Fouch",
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: en.meta.title,
    description: en.meta.description,
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\layout.tsx"
} catch {
    Write-Host "FAILED: src\app\layout.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\layout.tsx"
}

try {
    $path = "src\lib\site.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Central source of truth for the site's absolute URL.
 *
 * Resolution order:
 * 1. NEXT_PUBLIC_SITE_URL — set this once we own a real custom domain.
 * 2. VERCEL_PROJECT_PRODUCTION_URL — Vercel's stable alias for
 *    "current production" (e.g. fouch-tau.vercel.app). Preferred over
 *    VERCEL_URL, which changes per-deployment.
 * 3. VERCEL_URL — this specific deployment's URL, as a last resort.
 * 4. localhost — local dev.
 *
 * Every check is an explicit truthy `if`, not `??` — Vercel can create
 * NEXT_PUBLIC_SITE_URL as an empty string (not undefined) when it
 * auto-detects env vars from .env.example, and `??` only falls back on
 * null/undefined, which would let an empty string slip through and
 * break `new URL("")` at build time.
 */
function resolveSiteUrl(): string {
  if (process.env.NEXT_PUBLIC_SITE_URL) {
    return process.env.NEXT_PUBLIC_SITE_URL;
  }
  if (process.env.VERCEL_PROJECT_PRODUCTION_URL) {
    return `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`;
  }
  if (process.env.VERCEL_URL) {
    return `https://${process.env.VERCEL_URL}`;
  }
  return "http://localhost:3000";
}

export const siteUrl = resolveSiteUrl();
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\site.ts"
} catch {
    Write-Host "FAILED: src\lib\site.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\site.ts"
}

try {
    $path = "src\lib\analytics.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Minimal analytics seam.
 *
 * Intentionally NOT wired to PostHog (or any provider) yet — adding an
 * SDK before we know we need it is dead weight. This gives every call
 * site a single, typed function to import, so plugging in a real
 * provider later is a one-file change instead of a hunt through
 * components. Never throws, never blocks rendering, and is silent
 * when analytics isn't configured (e.g. local dev).
 *
 * Properties must never carry personally identifiable information or
 * free-text contestant/user input — only structural values like an
 * event slug, a count, or a position.
 */

export type FouchAnalyticsEvent =
  | "landing_view"
  | "featured_event_clicked"
  | "start_prediction"
  | "participant_selected"
  | "participant_removed"
  | "prediction_reordered"
  | "prediction_completed"
  | "prediction_reviewed";

export function track(event: FouchAnalyticsEvent, properties?: Record<string, unknown>) {
  if (typeof window === "undefined") return;
  if (!process.env.NEXT_PUBLIC_ANALYTICS_ENABLED) return;

  // Placeholder sink until a provider (e.g. PostHog) is configured behind
  // NEXT_PUBLIC_POSTHOG_KEY. Kept as a console log, not a network call,
  // so this never depends on an external analytics endpoint.
  console.debug("[fouch:analytics]", event, properties ?? {});
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\analytics.ts"
} catch {
    Write-Host "FAILED: src\lib\analytics.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\analytics.ts"
}

try {
    $path = "src\lib\flags.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
const REGIONAL_INDICATOR_OFFSET = 127397;

/**
 * Converts an ISO 3166-1 alpha-2 code (e.g. "TH") to its Unicode flag
 * emoji. No image assets, no flag library — just two regional
 * indicator symbols. Reliable on modern iOS/Android/desktop browsers,
 * which is Fouch's whole audience.
 */
export function flagEmoji(countryCode: string): string {
  return countryCode
    .toUpperCase()
    .replace(/./g, (char) =>
      String.fromCodePoint(char.charCodeAt(0) + REGIONAL_INDICATOR_OFFSET),
    );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\flags.ts"
} catch {
    Write-Host "FAILED: src\lib\flags.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\flags.ts"
}

try {
    $path = "src\lib\prediction-storage.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
const STORAGE_PREFIX = "fouch:prediction:";

interface StoredPrediction {
  eventSlug: string;
  /** Participant IDs, in ranked order — index 0 is position #1. */
  participantIds: string[];
}

function storageKey(eventSlug: string): string {
  return `${STORAGE_PREFIX}${eventSlug}`;
}

/**
 * Reads and validates a stored in-progress prediction for an event.
 * Never throws: a missing key, malformed JSON, or a shape that
 * doesn't match `StoredPrediction` all just return null so the caller
 * can fail safely and start fresh — this is browser-only scratch
 * state, not a database record.
 *
 * `validParticipantIds` lets the caller drop any stored ID that no
 * longer corresponds to an active participant (e.g. the seed data
 * changed), rather than restoring a broken prediction.
 */
export function loadPrediction(
  eventSlug: string,
  validParticipantIds: Set<string>,
): string[] {
  if (typeof window === "undefined") return [];

  try {
    const raw = window.localStorage.getItem(storageKey(eventSlug));
    if (!raw) return [];

    const parsed: unknown = JSON.parse(raw);
    if (
      typeof parsed !== "object" ||
      parsed === null ||
      !("eventSlug" in parsed) ||
      !("participantIds" in parsed)
    ) {
      return [];
    }

    const stored = parsed as StoredPrediction;
    if (stored.eventSlug !== eventSlug || !Array.isArray(stored.participantIds)) {
      return [];
    }

    return stored.participantIds.filter(
      (id): id is string => typeof id === "string" && validParticipantIds.has(id),
    );
  } catch {
    return [];
  }
}

export function savePrediction(eventSlug: string, participantIds: string[]): void {
  if (typeof window === "undefined") return;

  try {
    const payload: StoredPrediction = { eventSlug, participantIds };
    window.localStorage.setItem(storageKey(eventSlug), JSON.stringify(payload));
  } catch {
    // Storage can fail (private browsing, quota, disabled). The
    // prediction still works for the current session either way —
    // this is a convenience, not a requirement.
  }
}

export function clearPrediction(eventSlug: string): void {
  if (typeof window === "undefined") return;

  try {
    window.localStorage.removeItem(storageKey(eventSlug));
  } catch {
    // See savePrediction.
  }
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\prediction-storage.ts"
} catch {
    Write-Host "FAILED: src\lib\prediction-storage.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\prediction-storage.ts"
}

try {
    $path = "src\lib\participants.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Participant } from "@/types/participant";

/**
 * DEMO / DEVELOPMENT DATA — NOT the official Miss Universe 2026 lineup.
 *
 * The full, verified list of national delegates for Miss Universe 2026
 * is not yet finalized/confirmed by the organization at the time of
 * writing. Rather than invent an official-looking roster, this is a
 * clearly-marked demo set of real countries, used only to test the
 * Top 10 mechanic. See `getParticipantsForEvent`'s returned `status`
 * field — the UI must surface "Demo participant data" whenever it is
 * "demo", and this must never be presented as the official lineup.
 */
const demoCountries: Array<{ code: string; name: string }> = [
  { code: "AR", name: "Argentina" },
  { code: "AU", name: "Australia" },
  { code: "BR", name: "Brazil" },
  { code: "CA", name: "Canada" },
  { code: "CL", name: "Chile" },
  { code: "CO", name: "Colombia" },
  { code: "DO", name: "Dominican Republic" },
  { code: "ES", name: "Spain" },
  { code: "FR", name: "France" },
  { code: "IN", name: "India" },
  { code: "ID", name: "Indonesia" },
  { code: "IT", name: "Italy" },
  { code: "JM", name: "Jamaica" },
  { code: "JP", name: "Japan" },
  { code: "KE", name: "Kenya" },
  { code: "KR", name: "South Korea" },
  { code: "MX", name: "Mexico" },
  { code: "NG", name: "Nigeria" },
  { code: "PE", name: "Peru" },
  { code: "PH", name: "Philippines" },
  { code: "PR", name: "Puerto Rico" },
  { code: "TH", name: "Thailand" },
  { code: "VE", name: "Venezuela" },
  { code: "VN", name: "Vietnam" },
  { code: "ZA", name: "South Africa" },
].sort((a, b) => a.name.localeCompare(b.name));

const missUniverse2026Participants: Participant[] = demoCountries.map((country, index) => ({
  id: `demo-${country.code.toLowerCase()}`,
  eventId: "seed-miss-universe-2026",
  displayName: country.name,
  countryCode: country.code,
  countryName: country.name,
  sortOrder: index,
  isActive: true,
}));

const participantsByEventSlug: Record<string, Participant[]> = {
  "miss-universe-2026": missUniverse2026Participants,
};

export type ParticipantDataStatus = "demo" | "verified";

export function getParticipantsForEvent(
  slug: string,
): { status: ParticipantDataStatus; participants: Participant[] } | null {
  const participants = participantsByEventSlug[slug];
  if (!participants) return null;

  return {
    status: "demo",
    participants: participants.filter((participant) => participant.isActive),
  };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\participants.ts"
} catch {
    Write-Host "FAILED: src\lib\participants.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\participants.ts"
}

try {
    $path = "src\components\prediction\PredictionBuilder.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { track } from "@/lib/analytics";
import { loadPrediction, savePrediction } from "@/lib/prediction-storage";
import type { Participant } from "@/types/participant";
import { TopTenList } from "./TopTenList";
import { ParticipantBrowser } from "./ParticipantBrowser";

export function PredictionBuilder({
  eventSlug,
  participants,
  requiredCount,
}: {
  eventSlug: string;
  participants: Participant[];
  requiredCount: number;
}) {
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [hydrated, setHydrated] = useState(false);
  const hasFiredCompletion = useRef(false);

  const participantsById = new Map(participants.map((participant) => [participant.id, participant]));

  // Restore any in-progress prediction once, on mount, then mark
  // "hydrated" so we don't overwrite it with an empty save before the
  // restore runs.
  useEffect(() => {
    const validIds = new Set(participants.map((participant) => participant.id));
    const restored = loadPrediction(eventSlug, validIds);
    setSelectedIds(restored.slice(0, requiredCount));
    setHydrated(true);
    track("start_prediction", { event_slug: eventSlug });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    savePrediction(eventSlug, selectedIds);

    if (selectedIds.length >= requiredCount && !hasFiredCompletion.current) {
      hasFiredCompletion.current = true;
      track("prediction_completed", { event_slug: eventSlug, selected_count: selectedIds.length });
    }
    if (selectedIds.length < requiredCount) {
      hasFiredCompletion.current = false;
    }
  }, [selectedIds, eventSlug, requiredCount, hydrated]);

  function handleToggle(id: string) {
    setSelectedIds((current) => {
      if (current.includes(id)) {
        track("participant_removed", { event_slug: eventSlug, selected_count: current.length - 1 });
        return current.filter((selectedId) => selectedId !== id);
      }
      if (current.length >= requiredCount) return current;

      track("participant_selected", { event_slug: eventSlug, position: current.length + 1 });
      return [...current, id];
    });
  }

  function handleRemove(id: string) {
    setSelectedIds((current) => {
      track("participant_removed", { event_slug: eventSlug, selected_count: current.length - 1 });
      return current.filter((selectedId) => selectedId !== id);
    });
  }

  function swap(array: string[], i: number, j: number): string[] {
    const next = [...array];
    const a = next[i];
    const b = next[j];
    if (a === undefined || b === undefined) return array;
    next[i] = b;
    next[j] = a;
    return next;
  }

  function handleMoveUp(index: number) {
    if (index === 0) return;
    setSelectedIds((current) => {
      track("prediction_reordered", { event_slug: eventSlug });
      return swap(current, index - 1, index);
    });
  }

  function handleMoveDown(index: number) {
    setSelectedIds((current) => {
      if (index === current.length - 1) return current;
      track("prediction_reordered", { event_slug: eventSlug });
      return swap(current, index, index + 1);
    });
  }

  const rankedParticipants = selectedIds
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  const isComplete = selectedIds.length >= requiredCount;

  return (
    <div>
      {/* Compact sticky progress — one line, not a large banner. */}
      <div className="sticky top-0 z-10 w-full border-b border-border bg-background/95 backdrop-blur">
        <div className="mx-auto flex max-w-content items-center justify-between px-6 py-3">
          <span className="text-xs font-medium uppercase tracking-[0.15em] text-text-secondary">
            {selectedIds.length} / {requiredCount} selected
          </span>
          <div className="h-1 w-24 overflow-hidden rounded-full bg-surface-raised">
            <div
              className="h-full bg-accent transition-[width]"
              style={{ width: `${(selectedIds.length / requiredCount) * 100}%` }}
            />
          </div>
        </div>
      </div>

      <div className="mx-auto max-w-content px-6 py-8 lg:grid lg:grid-cols-[380px_1fr] lg:gap-10">
        <section aria-label="Your Top 10" className="lg:sticky lg:top-20 lg:self-start">
          <h2 className="font-display text-lg text-text-primary">Your Top {requiredCount}</h2>
          <div className="mt-3">
            <TopTenList
              rankedParticipants={rankedParticipants}
              requiredCount={requiredCount}
              onRemove={handleRemove}
              onMoveUp={handleMoveUp}
              onMoveDown={handleMoveDown}
            />
          </div>

          {isComplete ? (
            <div className="mt-6 rounded border border-accent/40 bg-accent/10 p-4">
              <p className="font-display text-base text-text-primary">Your Top {requiredCount} is ready.</p>
              <Link
                href={`/predict/${eventSlug}/review`}
                className="group mt-3 inline-flex items-center gap-2 rounded bg-accent px-5 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
              >
                Review my prediction
                <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
              </Link>
            </div>
          ) : null}
        </section>

        <section aria-label="All contestants" className="mt-10 lg:mt-0">
          <h2 className="font-display text-lg text-text-primary">All contestants</h2>
          <div className="mt-3">
            <ParticipantBrowser
              participants={participants}
              selectedIds={new Set(selectedIds)}
              atMax={isComplete}
              onToggle={handleToggle}
            />
          </div>
        </section>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\PredictionBuilder.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\PredictionBuilder.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\PredictionBuilder.tsx"
}

try {
    $path = "src\components\prediction\ReviewContent.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Pencil } from "lucide-react";
import { flagEmoji } from "@/lib/flags";
import { track } from "@/lib/analytics";
import { loadPrediction } from "@/lib/prediction-storage";
import type { Participant } from "@/types/participant";

export function ReviewContent({
  eventSlug,
  participants,
  requiredCount,
}: {
  eventSlug: string;
  participants: Participant[];
  requiredCount: number;
}) {
  const [rankedIds, setRankedIds] = useState<string[] | null>(null);

  useEffect(() => {
    const validIds = new Set(participants.map((participant) => participant.id));
    setRankedIds(loadPrediction(eventSlug, validIds));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const participantsById = new Map(participants.map((participant) => [participant.id, participant]));
  const ranked = (rankedIds ?? [])
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  useEffect(() => {
    if (rankedIds !== null && ranked.length >= requiredCount) {
      track("prediction_reviewed", { event_slug: eventSlug });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rankedIds]);

  // Avoid a flash of "no prediction" before localStorage is read.
  if (rankedIds === null) return null;

  if (ranked.length < requiredCount) {
    return (
      <div>
        <p className="text-text-secondary">
          We don&apos;t have a complete prediction for this event yet on this device.
        </p>
        <Link
          href={`/predict/${eventSlug}`}
          className="mt-4 inline-flex items-center gap-2 rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
        >
          Build your Top {requiredCount}
        </Link>
      </div>
    );
  }

  return (
    <div>
      <ol className="space-y-1.5">
        {ranked.map((participant, index) => (
          <li
            key={participant.id}
            className="flex items-center gap-3 rounded border border-border bg-surface px-4 py-3"
          >
            <span className="font-display w-7 shrink-0 text-base text-accent-strong">
              {String(index + 1).padStart(2, "0")}
            </span>
            <span aria-hidden className="text-xl">
              {flagEmoji(participant.countryCode)}
            </span>
            <span className="text-sm text-text-primary">{participant.displayName}</span>
          </li>
        ))}
      </ol>

      <Link
        href={`/predict/${eventSlug}`}
        className="mt-6 inline-flex items-center gap-2 rounded border border-border-strong px-6 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
      >
        <Pencil className="h-4 w-4" aria-hidden />
        Edit my Top {requiredCount}
      </Link>

      <p className="mt-6 max-w-md text-xs text-text-muted">
        This prediction is saved on this device only — it hasn&apos;t been submitted yet.
        Submitting and scoring are coming in a future update.
      </p>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\ReviewContent.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\ReviewContent.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\ReviewContent.tsx"
}

try {
    $path = "src\app\events\[slug]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { redirect, notFound } from "next/navigation";
import { getEventBySlug } from "@/lib/events";

/**
 * `/events/[slug]` predates the Prediction Builder (Sprint 0's
 * "coming soon" placeholder). Now that `/predict/[slug]` is real, this
 * route would just be a stale duplicate of the homepage's featured
 * event card — so it redirects straight to the builder instead of
 * carrying copy that's no longer true.
 */
export default async function EventPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const event = getEventBySlug(slug);
  if (!event) notFound();

  redirect(`/predict/${slug}`);
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\events\[slug]\page.tsx"
} catch {
    Write-Host "FAILED: src\app\events\[slug]\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\events\[slug]\page.tsx"
}

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
    subhead: "Predict the moments everyone will be talking about.",
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
    $path = "src\content\es.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Dictionary } from "./types";

// Prepared for future localization. Not yet wired into routing in Sprint 0 —
// English is the only live locale. Kept in sync with en.ts's shape so a
// future locale switch is a routing change, not a content rewrite.
export const es: Dictionary = {
  meta: {
    title: "Fouch — Haz tu predicción",
    description:
      "Predice los momentos más comentados del entretenimiento y compara tus picks con el mundo.",
  },
  nav: {
    wordmark: "Fouch",
  },
  hero: {
    headline: "Haz tu predicción.",
    subhead: "Predice los momentos de los que todos hablarán.",
    cta: "Arma tu Top 10",
  },
  featuredEvent: {
    eyebrowUpcoming: "Próximamente",
    prompt: "¿Quién entra en tu Top 10?",
    cta: "Arma tu Top 10",
  },
  howItWorks: {
    title: "Cómo funciona",
    steps: [
      { title: "Predice", body: "Arma tu ranking." },
      { title: "Compite", body: "Compara tus picks con los demás." },
      { title: "Compruébalo", body: "Recibe tu puntaje cuando salgan los resultados." },
    ],
  },
  eventPage: {
    back: "Volver a Fouch",
    comingSoon: "El constructor de predicciones de este evento abre pronto.",
  },
  footer: {
    tagline: "Predicciones de entretenimiento.",
  },
};
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\content\es.ts"
} catch {
    Write-Host "FAILED: src\content\es.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\content\es.ts"
}

try {
    $path = "src\content\pt.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Dictionary } from "./types";

// Prepared for future localization. Not yet wired into routing in Sprint 0 —
// English is the only live locale.
export const pt: Dictionary = {
  meta: {
    title: "Fouch — Faça sua previsão",
    description:
      "Preveja os maiores momentos do entretenimento e veja como suas escolhas se comparam com o mundo.",
  },
  nav: {
    wordmark: "Fouch",
  },
  hero: {
    headline: "Faça sua previsão.",
    subhead: "Preveja os momentos dos quais todos vão falar.",
    cta: "Monte seu Top 10",
  },
  featuredEvent: {
    eyebrowUpcoming: "Em breve",
    prompt: "Quem entra no seu Top 10?",
    cta: "Monte seu Top 10",
  },
  howItWorks: {
    title: "Como funciona",
    steps: [
      { title: "Preveja", body: "Monte seu ranking." },
      { title: "Compita", body: "Veja como suas escolhas se comparam." },
      { title: "Comprove", body: "Receba sua pontuação quando sair o resultado." },
    ],
  },
  eventPage: {
    back: "Voltar ao Fouch",
    comingSoon: "O criador de previsões deste evento abre em breve.",
  },
  footer: {
    tagline: "Previsões de entretenimento.",
  },
};
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\content\pt.ts"
} catch {
    Write-Host "FAILED: src\content\pt.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\content\pt.ts"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 15 files re-written successfully." -ForegroundColor Green
}