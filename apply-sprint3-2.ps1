# Sprint 3.2: Country flag rendering fix — applies all changed files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-sprint3-2.ps1
$failures = @()

try {
    $path = "package.json"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
{
  "name": "fouch",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "test": "vitest run"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.115.0",
    "country-flag-icons": "^1.6.20",
    "lucide-react": "^1.41.0",
    "nanoid": "^6.0.1",
    "next": "^15.5.25",
    "react": "19.0.0",
    "react-dom": "19.0.0",
    "server-only": "^0.0.1"
  },
  "devDependencies": {
    "@eslint/eslintrc": "^3.3.7",
    "@types/node": "^22.20.2",
    "@types/react": "19.0.7",
    "@types/react-dom": "19.0.3",
    "autoprefixer": "10.4.20",
    "eslint": "9.18.0",
    "eslint-config-next": "15.1.6",
    "postcss": "8.5.1",
    "tailwindcss": "3.4.17",
    "typescript": "5.7.3",
    "vitest": "^5.0.0"
  }
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     package.json"
} catch {
    Write-Host "FAILED: package.json -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "package.json"
}

try {
    $path = "src\components\CountryFlag.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import {
  AR,
  AU,
  BR,
  CA,
  CL,
  CO,
  DE,
  DO,
  EC,
  ES,
  FR,
  GB,
  ID,
  IN,
  IT,
  JM,
  JP,
  KE,
  KR,
  MX,
  NG,
  PA,
  PE,
  PH,
  PR,
  PT,
  PY,
  TH,
  US,
  UY,
  VE,
  VN,
  ZA,
} from "country-flag-icons/react/3x2";

type FlagComponent = typeof CL;

/**
 * Curated to exactly the country codes currently used across
 * src/lib/participants.ts and src/lib/countries.ts, imported as named
 * exports (not the whole `country-flag-icons` set) so bundlers can
 * tree-shake the ~220 flags FOUCH doesn't use. Adding a new country
 * to either seed file means adding one import + one entry here.
 */
const FLAGS: Record<string, FlagComponent> = {
  AR,
  AU,
  BR,
  CA,
  CL,
  CO,
  DE,
  DO,
  EC,
  ES,
  FR,
  GB,
  ID,
  IN,
  IT,
  JM,
  JP,
  KE,
  KR,
  MX,
  NG,
  PA,
  PE,
  PH,
  PR,
  PT,
  PY,
  TH,
  US,
  UY,
  VE,
  VN,
  ZA,
};

/**
 * Root cause this fixes: Unicode regional-indicator flag emoji (what
 * flagEmoji() in src/lib/flags.ts produces) render as actual flags on
 * iOS/Android/macOS, but Windows historically ships no color flag
 * emoji font — Chrome on Windows falls back to showing the two literal
 * regional-indicator letters ("CL" instead of 🇨🇱), which is exactly
 * what QA saw in production. SVG flags render identically everywhere.
 *
 * Decorative by default (aria-hidden) — every call site already shows
 * the country name as visible text right next to this, so a flag
 * doesn't need its own screen-reader announcement (that would read as
 * redundant "Chile flag, Chile").
 */
export function CountryFlag({
  countryCode,
  className = "",
}: {
  countryCode?: string | null;
  className?: string;
}) {
  const code = countryCode?.toUpperCase();
  const Flag = code ? FLAGS[code] : undefined;

  if (!Flag) {
    return (
      <span
        aria-hidden
        className={`inline-flex h-[1em] items-center justify-center rounded-sm bg-surface-raised px-1 text-[0.55em] font-bold leading-none text-text-muted ${className}`}
      >
        {code || "XX"}
      </span>
    );
  }

  return (
    <Flag
      aria-hidden
      className={`inline-block h-[1em] w-[1.5em] rounded-[2px] align-middle ${className}`}
    />
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\CountryFlag.tsx"
} catch {
    Write-Host "FAILED: src\components\CountryFlag.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\CountryFlag.tsx"
}

try {
    $path = "src\components\prediction\TopTenList.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { ChevronUp, ChevronDown, X } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
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
          <CountryFlag countryCode={participant.countryCode} className="text-lg" />
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
import { CountryFlag } from "@/components/CountryFlag";
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
                  <CountryFlag countryCode={participant.countryCode} className="text-lg" />
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
    $path = "src\components\prediction\ReviewContent.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Pencil } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { loadPrediction, clearPrediction } from "@/lib/prediction-storage";
import { getDeviceToken } from "@/lib/device-token";
import { checkExistingSubmission, submitPrediction } from "@/app/predict/[slug]/actions";
import type { Participant } from "@/types/participant";
import { SubmitPanel } from "./SubmitPanel";

export function ReviewContent({
  eventSlug,
  participants,
  requiredCount,
}: {
  eventSlug: string;
  participants: Participant[];
  requiredCount: number;
}) {
  const router = useRouter();
  const [rankedIds, setRankedIds] = useState<string[] | null>(null);
  const [checkingExisting, setCheckingExisting] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    const validIds = new Set(participants.map((participant) => participant.id));
    setRankedIds(loadPrediction(eventSlug, validIds));

    // A submitted prediction is immutable — if this device already has
    // one for this event, go straight to it instead of showing the
    // submit form again.
    const deviceToken = getDeviceToken();
    checkExistingSubmission(eventSlug, deviceToken)
      .then((existing) => {
        if (existing) {
          router.replace(`/p/${existing.publicId}`);
          return;
        }
        setCheckingExisting(false);
      })
      .catch(() => setCheckingExisting(false));
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

  async function handleSubmit(nickname: string, countryCode: string) {
    setSubmitting(true);
    setErrorMessage(null);
    track("prediction_submit_started", { event_slug: eventSlug });

    const deviceToken = getDeviceToken();
    const result = await submitPrediction({
      eventSlug,
      participantIds: rankedIds ?? [],
      nickname: nickname.trim() || undefined,
      countryCode: countryCode || undefined,
      deviceToken,
    });

    if (!result.success) {
      setErrorMessage(result.error);
      setSubmitting(false);
      return;
    }

    track("prediction_submitted", { event_slug: eventSlug });
    clearPrediction(eventSlug);
    router.push(`/p/${result.publicId}?new=1`);
  }

  // Avoid a flash of the form before we know whether this device
  // already has a locked-in prediction.
  if (rankedIds === null || checkingExisting) return null;

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
            <CountryFlag countryCode={participant.countryCode} className="text-xl" />
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

      <SubmitPanel
        requiredCount={requiredCount}
        submitting={submitting}
        errorMessage={errorMessage}
        onSubmit={handleSubmit}
      />
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
    $path = "src\components\prediction\PublicPredictionView.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { siteUrl } from "@/lib/site";
import type { Participant } from "@/types/participant";
import { ShareActions } from "./ShareActions";

export function PublicPredictionView({
  eventSlug,
  publicId,
  rankedParticipants,
  youVsTheWorld,
}: {
  eventSlug: string;
  publicId: string;
  rankedParticipants: Participant[];
  /** The You vs The World section — a Server Component rendered by the
   * page and passed down, since it needs server-side data fetching
   * that a Client Component can't do directly. */
  youVsTheWorld: ReactNode;
}) {
  const searchParams = useSearchParams();
  const isNew = searchParams.get("new") === "1";

  useEffect(() => {
    track("public_prediction_viewed", { event_slug: eventSlug, is_new: isNew });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (isNew) {
      track("prediction_card_generated", { event_slug: eventSlug });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const publicUrl = `${siteUrl}/p/${publicId}`;

  return (
    <div>
      {isNew ? (
        <p className="mt-4 font-display text-lg text-accent-strong">You made your call.</p>
      ) : null}

      <ol className="mt-6 space-y-1.5">
        {rankedParticipants.map((participant, index) => (
          <li
            key={participant.id}
            className="flex items-center gap-3 rounded border border-border bg-surface px-4 py-3"
          >
            <span className="font-display w-7 shrink-0 text-base text-accent-strong">
              {String(index + 1).padStart(2, "0")}
            </span>
            <CountryFlag countryCode={participant.countryCode} className="text-xl" />
            <span className="text-sm text-text-primary">{participant.displayName}</span>
          </li>
        ))}
      </ol>

      {youVsTheWorld}

      <Link
        href={`/predict/${eventSlug}?from=${publicId}`}
        onClick={() => track("public_prediction_cta_clicked", { event_slug: eventSlug })}
        className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        Make your Top 10
      </Link>

      <div id="share" className="mt-10 scroll-mt-20 border-t border-border pt-8">
        <p className="font-display text-lg text-text-primary">Share your prediction</p>
        <div className="mt-3">
          <ShareActions
            eventSlug={eventSlug}
            publicUrl={publicUrl}
            storyCardUrl={`/p/${publicId}/card/story`}
            postCardUrl={`/p/${publicId}/card/post`}
          />
        </div>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\PublicPredictionView.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\PublicPredictionView.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\PublicPredictionView.tsx"
}

try {
    $path = "src\components\prediction\YouVsTheWorld.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { CountryFlag } from "@/components/CountryFlag";
import { getEntryNoun } from "@/lib/events";
import { getEligiblePredictionsForComparison, type PredictionRecord } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import {
  computeComparison,
  getSampleSizeBucket,
  getComparisonDisplayMode,
} from "@/lib/community-comparison";
import type { FouchEvent } from "@/types/event";
import { ShareYourCallCta } from "./ShareYourCallCta";
import { YouVsTheWorldTracker } from "./YouVsTheWorldTracker";

function formatPct(pct: number): string {
  return `${Math.round(pct * 100)}%`;
}

/**
 * Sprint 3.1: for a small sample, "X of Y" is honest; a percentage
 * ("25%") implies more statistical weight than 1-of-4 actually
 * carries. Every place that shows a ratio goes through this one
 * function instead of each component deciding for itself.
 */
function formatRatio(count: number, population: number, mode: ReturnType<typeof getComparisonDisplayMode>): string {
  if (mode === "count") return `${count} OF ${population}`;
  return formatPct(count / population);
}

export async function YouVsTheWorld({
  prediction,
  event,
}: {
  prediction: PredictionRecord;
  event: FouchEvent;
}) {
  const participantData = getParticipantsForEvent(event.slug);
  if (!participantData) return null;

  const participantsById = new Map(
    participantData.participants.map((participant) => [participant.id, participant]),
  );

  const eligible = await getEligiblePredictionsForComparison(event.slug, prediction.dataStatus);
  const comparison = computeComparison(prediction.rankedParticipantIds, eligible, prediction.id);
  const bucket = getSampleSizeBucket(comparison.population);
  const mode = getComparisonDisplayMode(comparison.population);
  const pluralNoun = getEntryNoun(event, true);

  return (
    <section className="mt-12 border-t border-border pt-10">
      <YouVsTheWorldTracker
        eventSlug={event.slug}
        dataStatus={prediction.dataStatus}
        bucket={bucket}
        hasSameWinner={Boolean(comparison.sameWinner)}
        hasTop3Match={Boolean(comparison.top3Match)}
        hasBoldestPick={Boolean(comparison.boldestPick)}
        hasCommunityTop10={comparison.communityTop10.length > 0}
      />
      <p className="font-display text-2xl uppercase tracking-tight text-text-primary">
        You vs the World
      </p>

      {prediction.dataStatus === "demo" ? (
        <p className="mt-2 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo community data — not official {pluralNoun}
        </p>
      ) : null}

      {mode === "none" ? (
        <div className="mt-6">
          <p className="font-display text-xl text-text-primary">You&apos;re early.</p>
          <p className="mt-1 text-sm text-text-secondary">Be the first to set the pace.</p>
          <ShareYourCallCta />
        </div>
      ) : (
        <div className="mt-8 space-y-10">
          {bucket === "1_4" ? (
            <p className="text-sm text-text-muted">
              The crowd is just forming — {comparison.population} other{" "}
              {comparison.population === 1 ? pluralNoun.slice(0, -1) : pluralNoun} in so far.
            </p>
          ) : null}
          {bucket === "5_9" ? (
            <p className="text-xs uppercase tracking-[0.15em] text-text-muted">
              Early signal · based on {comparison.population} other predictions
            </p>
          ) : null}

          {comparison.sameWinner ? (
            <div>
              <p className="font-display text-6xl text-accent-strong">
                {formatRatio(comparison.sameWinner.count, comparison.population, mode)}
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                Same winner
              </p>
              <p className="mt-2 text-text-primary">
                <CountryFlag
                  countryCode={participantsById.get(comparison.sameWinner.participantId)?.countryCode}
                />{" "}
                {participantsById.get(comparison.sameWinner.participantId)?.displayName} —{" "}
                {comparison.sameWinner.count === 0
                  ? "nobody else made the same call."
                  : mode === "count"
                    ? `${comparison.sameWinner.count} of ${comparison.population} other predictions agree.`
                    : `${formatPct(comparison.sameWinner.pct)} of the world agrees. Based on ${comparison.population} other predictions.`}
              </p>
            </div>
          ) : null}

          {comparison.top3Match ? (
            <div>
              <p className="font-display text-6xl text-accent-strong">
                {comparison.top3Match.overlap} / 3
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                Top 3 match
              </p>
              <p className="mt-2 text-text-primary">
                You share {comparison.top3Match.overlap} of your top 3 with the world.
              </p>
            </div>
          ) : null}

          {comparison.boldestPick ? (
            <div>
              <p className="font-display text-4xl text-text-primary">
                <CountryFlag
                  countryCode={participantsById.get(comparison.boldestPick.participantId)?.countryCode}
                />{" "}
                {participantsById.get(comparison.boldestPick.participantId)?.displayName}
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                Your boldest call
              </p>
              <p className="mt-2 text-text-primary">
                {mode === "count"
                  ? `Only ${comparison.boldestPick.count} of ${comparison.population} other predictions have this in their top 10.`
                  : `Only ${formatPct(comparison.boldestPick.inclusionPct)} of other predictions have this in their top 10.`}
              </p>
            </div>
          ) : null}

          {comparison.communityTop10.length > 0 ? (
            <div>
              <p className="font-display text-xl text-text-primary">The world&apos;s top 10</p>
              <p className="mt-1 text-xs text-text-muted">
                Ranked by how high each pick appears across predictions.
              </p>
              <ol className="mt-4 space-y-1.5">
                {comparison.communityTop10.map((entry, index) => {
                  const participant = participantsById.get(entry.participantId);
                  if (!participant) return null;
                  return (
                    <li
                      key={entry.participantId}
                      className="flex items-center gap-3 rounded border border-border bg-surface px-4 py-2.5"
                    >
                      <span className="font-display w-7 shrink-0 text-sm text-accent-strong">
                        {String(index + 1).padStart(2, "0")}
                      </span>
                      <CountryFlag countryCode={participant.countryCode} />
                      <span className="flex-1 text-sm text-text-primary">
                        {participant.displayName}
                      </span>
                      <span className="text-right text-xs text-text-muted">
                        {formatRatio(entry.top10Count, comparison.population, mode)} picked
                        <br />
                        avg #{entry.averagePosition.toFixed(1)}
                      </span>
                    </li>
                  );
                })}
              </ol>
              <p className="mt-2 text-xs text-text-muted">
                Based on {comparison.population} other prediction
                {comparison.population === 1 ? "" : "s"}.
              </p>
            </div>
          ) : null}

          <ShareYourCallCta standsOut={Boolean(comparison.sameWinner && comparison.sameWinner.pct < 0.3)} />
        </div>
      )}
    </section>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\YouVsTheWorld.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\YouVsTheWorld.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\YouVsTheWorld.tsx"
}

try {
    $path = "src\app\p\[publicId]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CountryFlag } from "@/components/CountryFlag";
import { siteUrl } from "@/lib/site";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { PublicPredictionView } from "@/components/prediction/PublicPredictionView";
import { YouVsTheWorld } from "@/components/prediction/YouVsTheWorld";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ publicId: string }>;
}): Promise<Metadata> {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) return {};

  const title = record.prediction.nickname
    ? `${record.prediction.nickname}'s Top 10 — ${record.event.name}`
    : `A Top 10 prediction — ${record.event.name}`;
  const description = "See the prediction, then make your own call.";

  return {
    title,
    description,
    // Sprint 2 decision: public prediction pages are reachable via
    // link but intentionally not indexed — we don't want thousands of
    // thin user-generated pages in search results. `follow` so the
    // "Make your Top 10" CTA is still crawlable back to the real
    // product pages.
    robots: { index: false, follow: true },
    openGraph: {
      title,
      description,
      url: `${siteUrl}/p/${publicId}`,
      images: [`${siteUrl}/p/${publicId}/opengraph-image`],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
    },
  };
}

export default async function PublicPredictionPage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) notFound();

  const { prediction, event, rankedParticipants } = record;
  const heading = prediction.nickname ? `${prediction.nickname}'s Top 10` : "Someone's Top 10";

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>

      <h1 className="mt-6 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-2 font-display text-xl uppercase tracking-tight text-text-primary">
        {heading}
      </p>

      {prediction.countryCode ? (
        <p className="mt-1 text-sm text-text-muted"><CountryFlag countryCode={prediction.countryCode} /></p>
      ) : null}

      {prediction.dataStatus === "demo" ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo prediction — not the official lineup
        </p>
      ) : null}

      <PublicPredictionView
        eventSlug={event.slug}
        publicId={publicId}
        rankedParticipants={rankedParticipants}
        youVsTheWorld={<YouVsTheWorld prediction={prediction} event={event} />}
      />
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\page.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\page.tsx"
}

try {
    $path = "src\app\p\[publicId]\opengraph-image.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ImageResponse } from "next/og";
import { getPredictionWithParticipants } from "@/lib/predictions-db";

export const runtime = "edge";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OpengraphImage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);

  const ink = "#141318";
  const accent = "#A6342E";
  const textPrimary = "#F2EFE6";
  const textMuted = "#A39FB0";

  if (!record) {
    return new ImageResponse(
      (
        <div
          style={{
            width: "100%",
            height: "100%",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            backgroundColor: ink,
            color: textPrimary,
            fontFamily: "Georgia, serif",
            fontSize: 48,
          }}
        >
          FOUCH
        </div>
      ),
      { ...size },
    );
  }

  const top3 = record.rankedParticipants.slice(0, 3);
  const heading = record.prediction.nickname ? `${record.prediction.nickname}'s Top 10` : "A Top 10 prediction";

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "60px 70px",
          backgroundColor: ink,
          color: textPrimary,
          fontFamily: "Georgia, serif",
        }}
      >
        <div style={{ display: "flex", fontSize: 26, letterSpacing: 4, color: accent }}>FOUCH</div>
        <div style={{ display: "flex", fontSize: 46, marginTop: 12 }}>{heading}</div>
        <div style={{ display: "flex", fontSize: 26, color: textMuted, marginTop: 6 }}>
          {record.event.name}
        </div>
        <div style={{ display: "flex", marginTop: 30, gap: 24 }}>
          {top3.map((participant, index) => (
            <div key={participant.id} style={{ display: "flex", alignItems: "center", fontSize: 28 }}>
              <span style={{ display: "flex", color: accent, marginRight: 10 }}>{index + 1}</span>
              <span
                style={{
                  display: "flex",
                  fontSize: 15,
                  fontWeight: 700,
                  color: textMuted,
                  marginRight: 10,
                }}
              >
                {participant.countryCode}
              </span>
              <span style={{ display: "flex" }}>{participant.displayName}</span>
            </div>
          ))}
        </div>
      </div>
    ),
    { ...size },
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\opengraph-image.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\opengraph-image.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\opengraph-image.tsx"
}

# package.json specifically must never keep a BOM (Node's JSON.parse
# doesn't strip it) -- strip it immediately after writing, every time.
try {
    $pkgContent = Get-Content -LiteralPath "package.json" -Raw
    [System.IO.File]::WriteAllText("$PWD\package.json", $pkgContent, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "OK:     package.json (BOM stripped)"
} catch {
    Write-Host "FAILED to strip BOM from package.json -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "package.json (BOM strip)"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 9 files written successfully." -ForegroundColor Green
}