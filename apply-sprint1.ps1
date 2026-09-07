# Sprint 1: Prediction Builder — applies all new and changed files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-sprint1.ps1
$failures = @()

try {
    $path = "src\types\participant.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
export interface Participant {
  id: string;
  eventId: string;
  displayName: string;
  /** ISO 3166-1 alpha-2. */
  countryCode: string;
  countryName: string;
  sortOrder: number;
  isActive: boolean;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\types\participant.ts"
} catch {
    Write-Host "FAILED: src\types\participant.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\types\participant.ts"
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
    $path = "src\components\Hero.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";

export function Hero({
  dictionary,
  eventSlug,
}: {
  dictionary: Dictionary;
  eventSlug: string | null;
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
        <h1 className="font-display text-[3.25rem] font-semibold uppercase leading-[0.95] tracking-tight text-text-primary sm:text-7xl">
          Make
          <br />
          your
          <br />
          call.
        </h1>

        <p className="mt-6 max-w-sm text-lg text-text-secondary">
          {dictionary.hero.subhead}
        </p>

        {eventSlug ? (
          <Link
            href={`/predict/${eventSlug}`}
            className="group mt-9 inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent shadow-[0_0_0_1px_rgba(166,52,46,0.4)] transition-colors hover:bg-accent-strong"
          >
            {dictionary.hero.cta}
            <ArrowRight
              className="h-4 w-4 transition-transform group-hover:translate-x-0.5"
              aria-hidden
            />
          </Link>
        ) : null}
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
    $path = "src\components\prediction\TopTenList.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { ChevronUp, ChevronDown, X } from "lucide-react";
import { flagEmoji } from "@/lib/flags";
import type { Participant } from "@/types/participant";

export function TopTenList({
  rankedParticipants,
  requiredCount,
  onRemove,
  onMoveUp,
  onMoveDown,
}: {
  rankedParticipants: Participant[];
  requiredCount: number;
  onRemove: (id: string) => void;
  onMoveUp: (index: number) => void;
  onMoveDown: (index: number) => void;
}) {
  if (rankedParticipants.length === 0) {
    return (
      <p className="rounded border border-dashed border-border-strong px-4 py-6 text-sm text-text-muted">
        Tap a country below to give it position 01.
      </p>
    );
  }

  return (
    <ol className="space-y-1.5">
      {rankedParticipants.map((participant, index) => (
        <li
          key={participant.id}
          className="flex items-center gap-3 rounded border border-border bg-surface px-3 py-2.5"
        >
          <span className="font-display w-6 shrink-0 text-sm text-accent-strong">
            {String(index + 1).padStart(2, "0")}
          </span>
          <span aria-hidden className="text-lg">
            {flagEmoji(participant.countryCode)}
          </span>
          <span className="flex-1 truncate text-sm text-text-primary">
            {participant.displayName}
          </span>

          <div className="flex items-center gap-0.5">
            <button
              type="button"
              onClick={() => onMoveUp(index)}
              disabled={index === 0}
              aria-label={`Move ${participant.displayName} up, currently position ${index + 1} of ${requiredCount}`}
              className="rounded p-2 text-text-secondary transition-colors hover:bg-surface-raised disabled:opacity-30"
            >
              <ChevronUp className="h-4 w-4" aria-hidden />
            </button>
            <button
              type="button"
              onClick={() => onMoveDown(index)}
              disabled={index === rankedParticipants.length - 1}
              aria-label={`Move ${participant.displayName} down, currently position ${index + 1} of ${requiredCount}`}
              className="rounded p-2 text-text-secondary transition-colors hover:bg-surface-raised disabled:opacity-30"
            >
              <ChevronDown className="h-4 w-4" aria-hidden />
            </button>
            <button
              type="button"
              onClick={() => onRemove(participant.id)}
              aria-label={`Remove ${participant.displayName} from your Top ${requiredCount}`}
              className="rounded p-2 text-text-secondary transition-colors hover:bg-surface-raised hover:text-accent-strong"
            >
              <X className="h-4 w-4" aria-hidden />
            </button>
          </div>
        </li>
      ))}
    </ol>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\TopTenList.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\TopTenList.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\TopTenList.tsx"
}

try {
    $path = "src\components\prediction\ParticipantBrowser.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useMemo, useState } from "react";
import { Search } from "lucide-react";
import { flagEmoji } from "@/lib/flags";
import type { Participant } from "@/types/participant";

export function ParticipantBrowser({
  participants,
  selectedIds,
  atMax,
  onToggle,
}: {
  participants: Participant[];
  selectedIds: Set<string>;
  atMax: boolean;
  onToggle: (id: string) => void;
}) {
  const [query, setQuery] = useState("");

  const filtered = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    if (!normalized) return participants;

    return participants.filter(
      (participant) =>
        participant.displayName.toLowerCase().includes(normalized) ||
        participant.countryName.toLowerCase().includes(normalized),
    );
  }, [participants, query]);

  return (
    <div>
      <div className="relative">
        <Search
          className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted"
          aria-hidden
        />
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search countries..."
          aria-label="Search countries"
          className="w-full rounded border border-border bg-surface py-2.5 pl-10 pr-3 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
        />
      </div>

      {filtered.length === 0 ? (
        <p className="mt-6 text-sm text-text-muted">No countries match &ldquo;{query}&rdquo;.</p>
      ) : (
        <ul className="mt-4 divide-y divide-border">
          {filtered.map((participant) => {
            const selected = selectedIds.has(participant.id);
            const disabled = atMax && !selected;

            return (
              <li key={participant.id}>
                <button
                  type="button"
                  onClick={() => onToggle(participant.id)}
                  disabled={disabled}
                  aria-pressed={selected}
                  className={`flex w-full items-center gap-3 py-3 text-left transition-colors disabled:cursor-not-allowed disabled:opacity-40 ${
                    selected ? "text-accent-strong" : "text-text-primary hover:text-accent-strong"
                  }`}
                >
                  <span aria-hidden className="text-lg">
                    {flagEmoji(participant.countryCode)}
                  </span>
                  <span className="flex-1 text-sm">{participant.displayName}</span>
                  {selected ? (
                    <span className="text-xs font-medium uppercase tracking-wide">Selected</span>
                  ) : null}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\ParticipantBrowser.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\ParticipantBrowser.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\ParticipantBrowser.tsx"
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
    $path = "src\app\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { en } from "@/content/en";
import { getFeaturedEvent } from "@/lib/events";
import { Nav } from "@/components/Nav";
import { Hero } from "@/components/Hero";
import { FeaturedEvent } from "@/components/FeaturedEvent";
import { HowItWorks } from "@/components/HowItWorks";
import { Footer } from "@/components/Footer";
import { ViewTracker } from "@/components/ViewTracker";

export default function Home() {
  const featuredEvent = getFeaturedEvent();

  return (
    <>
      <ViewTracker event="landing_view" />
      <Nav />
      <main>
        <Hero dictionary={en} eventSlug={featuredEvent?.slug ?? null} />
        {featuredEvent ? (
          <FeaturedEvent event={featuredEvent} dictionary={en} />
        ) : null}
        <HowItWorks dictionary={en} />
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

try {
    $path = "src\app\sitemap.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { MetadataRoute } from "next";
import { getFeaturedEvent } from "@/lib/events";
import { siteUrl } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
  const entries: MetadataRoute.Sitemap = [
    {
      url: siteUrl,
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 1,
    },
  ];

  const featuredEvent = getFeaturedEvent();
  if (featuredEvent) {
    entries.push({
      url: `${siteUrl}/predict/${featuredEvent.slug}`,
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 0.8,
    });
  }

  return entries;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\sitemap.ts"
} catch {
    Write-Host "FAILED: src\app\sitemap.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\sitemap.ts"
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
    $path = "src\app\predict\[slug]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
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
        <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
          ← Back to Fouch
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
        <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
          ← Back to Fouch
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
        className="text-sm text-text-secondary hover:text-text-primary"
      >
        ← Back to builder
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

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed. Re-run this script (it is safe to re-run) or report the exact error above." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 16 files written successfully." -ForegroundColor Green
}