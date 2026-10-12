# FOUCH Cohort 0 UX — Country Recognition (name alongside flag, no schema/logic changes).
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-country-recognition.ps1
$failures = @()

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
              <span style={{ display: "flex" }}>{participant.displayName}</span>
              <span
                style={{
                  display: "flex",
                  fontSize: 15,
                  fontWeight: 700,
                  color: textMuted,
                  marginLeft: 10,
                  overflow: "hidden",
                  whiteSpace: "nowrap",
                  textOverflow: "ellipsis",
                  maxWidth: 160,
                }}
              >
                · {participant.countryName}
              </span>
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
                <span className="flex-1 truncate text-sm text-text-primary">
                  {pick.participant.displayName}{" "}
                  <span className="text-text-muted">· {pick.participant.countryName}</span>
                </span>
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
                  <span className="flex-1 truncate text-sm">
                    {participant.displayName} <span className="text-text-muted">· {participant.countryName}</span>
                  </span>
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
    $path = "src\components\prediction\PredictionCardMarkup.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Participant } from "@/types/participant";

export interface CardData {
  eventName: string;
  nickname: string | null;
  countryCode: string | null;
  isDemo: boolean;
  rankedParticipants: Participant[];
}

const INK = "#141318";
const SURFACE = "#232028";
const ACCENT = "#A6342E";
const ACCENT_STRONG = "#C44C42";
const TEXT_PRIMARY = "#F2EFE6";
const TEXT_MUTED = "#A39FB0";

/**
 * `next/og` (Satori under the hood) does not render Unicode flag
 * emoji reliably — confirmed by generating and visually inspecting
 * the actual output, which showed blank space where a flag should be.
 * Plain country-name text is the robust substitute: no emoji font
 * dependency, no network fetch, renders identically everywhere — and,
 * per Cohort 0 feedback, is what users actually asked for (a bare ISO
 * code like "VE" wasn't recognizable on its own). `maxWidth` + the
 * overflow/ellipsis trio keeps a long country name from breaking this
 * fixed-size image's layout.
 */
function CountryBadge({ name, fontSize, maxWidth }: { name: string; fontSize: number; maxWidth: number }) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "flex-end",
        fontSize,
        fontWeight: 700,
        color: TEXT_MUTED,
        maxWidth,
        overflow: "hidden",
        whiteSpace: "nowrap",
        textOverflow: "ellipsis",
      }}
    >
      {name}
    </div>
  );
}

/**
 * Shared visual system for both the Story (1080x1920) and Post
 * (1080x1350) formats — same tokens as the product UI (ink
 * background, oxblood accent) but bolder/bigger, per the approved
 * "energetic / shareable" direction for social cards. `height` also
 * drives a scale factor so the taller Story format fills its frame
 * instead of leaving a dead zone below a 10-item list.
 */
export function PredictionCardMarkup({
  data,
  width,
  height,
  siteDomain,
}: {
  data: CardData;
  width: number;
  height: number;
  siteDomain: string;
}) {
  const scale = Math.min(1.32, Math.max(1, height / 1350));
  const top3 = data.rankedParticipants.slice(0, 3);
  const rest = data.rankedParticipants.slice(3, 10);
  const whoBy = data.nickname
    ? `${data.nickname}${data.countryCode ? ` · ${data.countryCode}` : ""}`
    : data.countryCode;

  return (
    <div
      style={{
        width,
        height,
        display: "flex",
        flexDirection: "column",
        backgroundColor: INK,
        fontFamily: "Georgia, serif",
        padding: `${64 * scale}px 56px`,
        color: TEXT_PRIMARY,
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", flexDirection: "column" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div style={{ display: "flex", fontSize: 28, letterSpacing: 4, color: TEXT_MUTED }}>
            FOUCH
          </div>
          {data.isDemo ? (
            <div
              style={{
                display: "flex",
                fontSize: 22,
                color: TEXT_MUTED,
                border: `1px solid ${TEXT_MUTED}`,
                borderRadius: 6,
                padding: "6px 14px",
              }}
            >
              DEMO
            </div>
          ) : null}
        </div>
        <div style={{ display: "flex", fontSize: 46 * scale, fontWeight: 700, marginTop: 18 }}>
          MAKE YOUR CALL.
        </div>
        <div style={{ display: "flex", fontSize: 30, color: TEXT_MUTED, marginTop: 8 }}>
          {data.eventName}
        </div>
        {whoBy ? (
          <div style={{ display: "flex", fontSize: 28, color: ACCENT_STRONG, marginTop: 10 }}>
            {whoBy}
          </div>
        ) : null}
      </div>

      {/* Top 3 — big, energetic blocks */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: 44 * scale, gap: 18 * scale }}>
        {top3.map((participant, index) => (
          <div
            key={participant.id}
            style={{
              display: "flex",
              alignItems: "center",
              backgroundColor: index === 0 ? ACCENT : SURFACE,
              borderRadius: 20,
              padding: `${26 * scale}px 32px`,
            }}
          >
            <div style={{ display: "flex", fontSize: 64 * scale, fontWeight: 700, width: 110 }}>
              {index + 1}
            </div>
            <div style={{ display: "flex", fontSize: 40 * scale, fontWeight: 700, flex: 1 }}>
              {participant.displayName}
            </div>
            <CountryBadge name={participant.countryName} fontSize={26 * scale} maxWidth={230} />
          </div>
        ))}
      </div>

      {/* 4-10 — compact list */}
      {rest.length > 0 ? (
        <div style={{ display: "flex", flexDirection: "column", marginTop: 26 * scale, gap: 12 * scale }}>
          {rest.map((participant, index) => (
            <div key={participant.id} style={{ display: "flex", alignItems: "center", fontSize: 27 * scale }}>
              <div style={{ display: "flex", width: 60, color: TEXT_MUTED }}>{index + 4}</div>
              <div style={{ display: "flex", flex: 1, color: TEXT_PRIMARY }}>{participant.displayName}</div>
              <CountryBadge name={participant.countryName} fontSize={20} maxWidth={170} />
            </div>
          ))}
        </div>
      ) : null}

      {/* Footer */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: "auto" }}>
        <div style={{ display: "flex", fontSize: 34, fontWeight: 700 }}>WHO YOU GOT?</div>
        <div style={{ display: "flex", fontSize: 24, color: TEXT_MUTED, marginTop: 6 }}>
          {siteDomain}
        </div>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\PredictionCardMarkup.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\PredictionCardMarkup.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\PredictionCardMarkup.tsx"
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
import { Pencil } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { siteUrl } from "@/lib/site";
import { formatEventLocalLockTime } from "@/lib/event-time-display";
import type { Participant } from "@/types/participant";
import { ShareActions } from "./ShareActions";

export function PublicPredictionView({
  eventSlug,
  publicId,
  rankedParticipants,
  hasResult = false,
  canEdit = false,
  showLockedNotice = false,
  predictionLockAt = null,
  predictionTimezone = null,
  fouchScore,
  youVsTheWorld,
  yourCrowdChanged,
}: {
  eventSlug: string;
  publicId: string;
  rankedParticipants: Participant[];
  /** Sprint 4.1: whether an official/demo result exists for this
   * prediction's event. Drives share-CTA hierarchy only — the original
   * Prediction Card share section becomes visually secondary once a
   * Result Card exists to share instead (brief §7-8). Does not affect
   * scoring or any calculation. */
  hasResult?: boolean;
  /** FOUCH 0.3A: true only for a verified prediction (auth_user_id
   * set) while the event is still open per Supabase
   * events.prediction_lock_at. A legacy anonymous prediction never
   * gets this — there is no verified identity to authorize an edit
   * against, and this sprint adds no way to claim one. */
  canEdit?: boolean;
  /** FOUCH 0.3A: true for a verified prediction whose event has
   * passed prediction_lock_at — shows "YOUR CALL IS LOCKED" instead
   * of an edit affordance. Never shown for legacy predictions, which
   * never offered editing in the first place. */
  showLockedNotice?: boolean;
  /** ISO datetime, only used for display ("until {date}"). */
  predictionLockAt?: string | null;
  /** FOUCH 0.3A.1 — IANA timezone identifier for the event (e.g.
   * "America/Puerto_Rico"), used ONLY to render predictionLockAt
   * unambiguously in event-local time (see event-time-display.ts).
   * Null falls back to an explicit UTC-labeled rendering — never the
   * viewer's browser timezone. */
  predictionTimezone?: string | null;
  /** FOUCH Score section (Sprint 4) — null/absent renders nothing, which
   * is exactly the pre-result experience. Server Component, passed down
   * for the same reason as youVsTheWorld below. */
  fouchScore?: ReactNode;
  /** The You vs The World section — a Server Component rendered by the
   * page and passed down, since it needs server-side data fetching
   * that a Client Component can't do directly. */
  youVsTheWorld: ReactNode;
  /** Experiment 01 ("Your Crowd Changed") — null/absent renders
   * nothing, same pattern as the two slots above. */
  yourCrowdChanged?: ReactNode;
}) {
  const searchParams = useSearchParams();
  const isNew = searchParams.get("new") === "1";
  const isEdited = searchParams.get("edited") === "1";
  const showSavedBanner = isNew || isEdited;

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

  const originalPredictionShare = (
    <div id="share" className="mt-10 scroll-mt-20 border-t border-border pt-8">
      <p
        className={
          hasResult
            ? "text-sm text-text-muted"
            : "font-display text-lg text-text-primary"
        }
      >
        {hasResult ? "Your original prediction" : "Share your prediction"}
      </p>
      <div className="mt-3">
        <ShareActions
          eventSlug={eventSlug}
          publicUrl={publicUrl}
          storyCardUrl={`/p/${publicId}/card/story`}
          postCardUrl={`/p/${publicId}/card/post`}
        />
      </div>
    </div>
  );

  return (
    <div>
      {showSavedBanner ? (
        <div className="mt-4">
          <p className="font-display text-lg text-accent-strong">YOUR CALL IS IN</p>
          {predictionLockAt ? (
            <p className="mt-1 text-sm text-text-secondary">
              You can update your picks until {formatEventLocalLockTime(predictionLockAt, predictionTimezone)}.
            </p>
          ) : null}
        </div>
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
            <span className="truncate text-sm text-text-primary">
              {participant.displayName} <span className="text-text-muted">· {participant.countryName}</span>
            </span>
          </li>
        ))}
      </ol>

      {canEdit ? (
        <div className="mt-4">
          <Link
            href={`/p/${publicId}/edit`}
            className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-2.5 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            <Pencil className="h-4 w-4" aria-hidden />
            Edit my Top 10
          </Link>
          {predictionLockAt ? (
            <p className="mt-2 text-xs text-text-muted">
              You can update your picks until {formatEventLocalLockTime(predictionLockAt, predictionTimezone)}.
            </p>
          ) : null}
        </div>
      ) : showLockedNotice ? (
        <p className="mt-4 text-sm font-medium uppercase tracking-wide text-text-muted">
          YOUR CALL IS LOCKED
        </p>
      ) : null}

      {fouchScore}

      {youVsTheWorld}

      {yourCrowdChanged}

      {/* Pre-result: original prediction sharing stays primary and sits
          right before the "Make your Top 10" CTA, unchanged from Sprint 2/3.
          Post-result: it becomes a secondary, de-emphasized block, per the
          hierarchy in Sprint 4.1's brief (Result Card is the stronger
          social object once scoring exists). */}
      {!hasResult ? originalPredictionShare : null}

      <Link
        href={`/predict/${eventSlug}?from=${publicId}`}
        onClick={() => track("public_prediction_cta_clicked", { event_slug: eventSlug })}
        className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        Make your Top 10
      </Link>

      {hasResult ? originalPredictionShare : null}
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
import { captureUtmSource } from "@/lib/attribution";
import { loadPrediction, clearPrediction } from "@/lib/prediction-storage";
import { getDeviceToken } from "@/lib/device-token";
import { checkExistingSubmission } from "@/app/predict/[slug]/actions";
import {
  startEmailVerification,
  verifyEmailAndLockPrediction,
  retryLockWithVerifiedSession,
  type VerifyAndLockResult,
} from "@/app/predict/[slug]/verify-actions";
import type { Participant } from "@/types/participant";
import { SubmitPanel } from "./SubmitPanel";
import { EmailStep } from "./EmailStep";
import { OtpStep } from "./OtpStep";

type Step = "review" | "email" | "otp";

/**
 * Beta Hardening 0.2 Phase C — GATE 1 implementation. This component
 * now runs the full email-OTP verified-lock flow client-side. It is
 * fully wired and tested, but production still has the old
 * `predictions_event_device_unique` constraint active — deploying
 * this to production before that constraint is dropped (Gate 2,
 * founder-approved cutover) would risk incorrectly blocking two
 * different verified people sharing a device. See
 * FOUCH_BETA_HARDENING_02_PHASE_C.md before deploying.
 */
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

  const [step, setStep] = useState<Step>("review");
  const [pendingNickname, setPendingNickname] = useState("");
  const [pendingCountryCode, setPendingCountryCode] = useState("");

  const [emailSubmitting, setEmailSubmitting] = useState(false);
  const [emailError, setEmailError] = useState<string | null>(null);
  const [email, setEmail] = useState("");

  const [otpSubmitting, setOtpSubmitting] = useState(false);
  const [otpError, setOtpError] = useState<string | null>(null);
  const [wrongAttemptCount, setWrongAttemptCount] = useState(0);
  /** Present only after OTP verification succeeded but the lock
   * insert failed transiently — enables a no-new-OTP retry. */
  const [accessTokenForRetry, setAccessTokenForRetry] = useState<string | null>(null);

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

  function handleProceedToEmail(nickname: string, countryCode: string) {
    setPendingNickname(nickname);
    setPendingCountryCode(countryCode);
    setStep("email");
  }

  async function handleSendCode(targetEmail: string) {
    if (emailSubmitting) return;
    setEmailSubmitting(true);
    setEmailError(null);
    track("verification_started", { event_slug: eventSlug });

    let result;
    try {
      result = await startEmailVerification(targetEmail);
    } catch {
      setEmailError("We couldn't send a code — try again in a moment.");
      setEmailSubmitting(false);
      return;
    }

    setEmailSubmitting(false);

    if (!result.success) {
      setEmailError(result.error);
      return;
    }

    track("verification_sent", { event_slug: eventSlug });
    setEmail(targetEmail);
    setOtpError(null);
    setWrongAttemptCount(0);
    setAccessTokenForRetry(null);
    setStep("otp");
  }

  function handleLockResult(result: VerifyAndLockResult) {
    if (result.success) {
      track("verification_completed", { event_slug: eventSlug });
      if (result.duplicateDeviceSignal) {
        track("duplicate_prediction_attempt", { event_slug: eventSlug });
      }
      const utmSource = captureUtmSource();
      track("prediction_submitted", {
        event_slug: eventSlug,
        ...(utmSource ? { utm_source: utmSource } : {}),
      });
      clearPrediction(eventSlug);
      router.push(`/p/${result.publicId}?new=1`);
      return;
    }

    track("verification_failed", { event_slug: eventSlug, failure_reason: result.failureReason });
    setOtpError(result.error);
    setAccessTokenForRetry(result.accessToken ?? null);
    if (result.failureReason === "invalid_code") {
      setWrongAttemptCount((count) => count + 1);
    }
  }

  async function handleVerify(code: string) {
    if (otpSubmitting) return;
    setOtpSubmitting(true);
    setOtpError(null);

    let result: VerifyAndLockResult;
    try {
      result = await verifyEmailAndLockPrediction(email, code, {
        eventSlug,
        participantIds: rankedIds ?? [],
        nickname: pendingNickname.trim() || undefined,
        countryCode: pendingCountryCode || undefined,
        deviceToken: getDeviceToken(),
      });
    } catch {
      setOtpSubmitting(false);
      setOtpError("We couldn't verify your code — try again.");
      return;
    }

    setOtpSubmitting(false);
    handleLockResult(result);
  }

  async function handleRetryLock() {
    if (otpSubmitting || !accessTokenForRetry) return;
    setOtpSubmitting(true);
    setOtpError(null);

    let result: VerifyAndLockResult;
    try {
      result = await retryLockWithVerifiedSession(accessTokenForRetry, {
        eventSlug,
        participantIds: rankedIds ?? [],
        nickname: pendingNickname.trim() || undefined,
        countryCode: pendingCountryCode || undefined,
        deviceToken: getDeviceToken(),
      });
    } catch {
      setOtpSubmitting(false);
      setOtpError("We couldn't lock your prediction. Your Top 10 is still saved — try again.");
      return;
    }

    setOtpSubmitting(false);
    handleLockResult(result);
  }

  function handleUseDifferentEmail() {
    setStep("email");
    setEmail("");
    setOtpError(null);
    setEmailError(null);
    setWrongAttemptCount(0);
    setAccessTokenForRetry(null);
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
            <span className="truncate text-sm text-text-primary">
              {participant.displayName} <span className="text-text-muted">· {participant.countryName}</span>
            </span>
          </li>
        ))}
      </ol>

      {step === "review" ? (
        <Link
          href={`/predict/${eventSlug}`}
          className="mt-6 inline-flex items-center gap-2 rounded border border-border-strong px-6 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          <Pencil className="h-4 w-4" aria-hidden />
          Edit my Top {requiredCount}
        </Link>
      ) : null}

      {step === "review" ? (
        <SubmitPanel
          requiredCount={requiredCount}
          submitting={false}
          errorMessage={null}
          onSubmit={handleProceedToEmail}
        />
      ) : null}

      {step === "email" ? (
        <EmailStep mode="create" submitting={emailSubmitting} errorMessage={emailError} onSendCode={handleSendCode} />
      ) : null}

      {step === "otp" && accessTokenForRetry ? (
        <div className="mt-8 border-t border-border pt-6">
          {otpError ? (
            <p className="text-sm text-accent-strong" role="alert" aria-live="polite">
              {otpError}
            </p>
          ) : null}
          <button
            type="button"
            disabled={otpSubmitting}
            onClick={handleRetryLock}
            className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
          >
            {otpSubmitting ? "Trying again…" : "Try again"}
          </button>
        </div>
      ) : step === "otp" ? (
        <OtpStep
          email={email}
          submitting={otpSubmitting}
          errorMessage={otpError}
          wrongAttemptCount={wrongAttemptCount}
          onVerify={handleVerify}
          onResend={() => handleSendCode(email)}
          onUseDifferentEmail={handleUseDifferentEmail}
        />
      ) : null}
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
            {participant.displayName} <span className="text-text-muted">· {participant.countryName}</span>
          </span>
          {!participant.isActive ? (
            <span
              className="shrink-0 rounded border border-accent-strong px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-accent-strong"
              title="No longer available — remove and pick a current contestant to save changes."
            >
              Replace
            </span>
          ) : null}

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
    $path = "src\components\prediction\YouVsTheWorld.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { CountryFlag } from "@/components/CountryFlag";
import { getEntryNoun } from "@/lib/events";
import { getEligiblePredictionsForComparison, type PredictionRecord } from "@/lib/predictions-db";
import { resolveParticipantsByIds } from "@/lib/participants";
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
  const eligible = await getEligiblePredictionsForComparison(event.slug, prediction.dataStatus);
  const comparison = computeComparison(prediction.rankedParticipantIds, eligible, prediction.id);
  const bucket = getSampleSizeBucket(comparison.population);
  const mode = getComparisonDisplayMode(comparison.population);
  const pluralNoun = getEntryNoun(event, true);

  // FOUCH 0.3B: resolves every participant id this section could
  // possibly render â€” the viewer's own winner pick AND whatever ids
  // appear in the community aggregate (sameWinner/boldestPick/
  // communityTop10) â€” regardless of current status. Any of those ids
  // could belong to someone else's prediction referencing a country
  // whose delegate has since become WITHDRAWN/REPLACED; this must
  // still resolve to a real name/country, never silently vanish.
  const idsToResolve = new Set<string>();
  if (comparison.sameWinner) idsToResolve.add(comparison.sameWinner.participantId);
  if (comparison.boldestPick) idsToResolve.add(comparison.boldestPick.participantId);
  for (const entry of comparison.communityTop10) idsToResolve.add(entry.participantId);

  const participantsById = await resolveParticipantsByIds(event.slug, Array.from(idsToResolve));

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
                {participantsById.get(comparison.sameWinner.participantId)?.displayName}{" "}
                <span className="text-text-muted">
                  · {participantsById.get(comparison.sameWinner.participantId)?.countryName}
                </span>{" "}
                —{" "}
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
                {participantsById.get(comparison.boldestPick.participantId)?.displayName}{" "}
                <span className="text-text-muted">
                  · {participantsById.get(comparison.boldestPick.participantId)?.countryName}
                </span>
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
                      <span className="flex-1 truncate text-sm text-text-primary">
                        {participant.displayName}{" "}
                        <span className="text-text-muted">· {participant.countryName}</span>
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
    $path = "src\components\scoring\FouchScore.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { getEntryNoun } from "@/lib/events";
import { resolveParticipantsByIds } from "@/lib/participants";
import { getPredictionScore } from "@/lib/scoring-service";
import { getOfficialResult } from "@/lib/results-db";
import { MIN_PERCENTILE_SAMPLE } from "@/lib/scoring";
import { siteUrl } from "@/lib/site";
import { CountryFlag } from "@/components/CountryFlag";
import type { PredictionRecord } from "@/lib/predictions-db";
import type { FouchEvent } from "@/types/event";
import type { ScoreBand } from "@/types/scoring";
import { FouchScoreTracker } from "./FouchScoreTracker";
import { ShareActions } from "@/components/prediction/ShareActions";
import { TrackedLink } from "@/components/TrackedLink";

const BAND_LABEL: Record<ScoreBand, string> = {
  MISSED_IT: "Missed it",
  FAIR: "Fair call",
  GOOD: "Good call",
  EXCELLENT: "Excellent call",
  ELITE: "Elite call",
};

/** "8.333..." -> "8.3", "25.0" -> "25" â€” one decimal, no trailing ".0". */
function formatPoints(value: number): string {
  const rounded = Math.round(value * 10) / 10;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}

/**
 * Renders nothing (returns null) when there's no official result yet â€”
 * the pre-result experience is unchanged, never a fabricated score.
 * Server Component: fetches + scores server-side, only the final
 * numbers reach the client (via the tracker's props, not raw data).
 *
 * Sprint 4.1: UI clarity only. Every number below comes straight from
 * the existing score engine's ScoreBreakdown â€” nothing here
 * recalculates or duplicates scoring logic.
 */
export async function FouchScore({
  prediction,
  event,
  publicId,
}: {
  prediction: PredictionRecord;
  event: FouchEvent;
  publicId: string;
}) {
  const result = await getPredictionScore(
    prediction.id,
    prediction.rankedParticipantIds,
    event.slug,
    prediction.dataStatus,
  );
  if (!result) return null;

  // Re-reads the same official-result row already used inside
  // getPredictionScore, purely to display who the actual winner was â€”
  // no scoring logic is duplicated, only a read.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);

  // FOUCH 0.3B: resolves regardless of current participant status â€”
  // both the user's own historical winner pick and the official
  // result's winner id must still render even if that country's
  // delegate has since become WITHDRAWN/REPLACED.
  const idsToResolve = new Set<string>();
  if (prediction.rankedParticipantIds[0]) idsToResolve.add(prediction.rankedParticipantIds[0]);
  if (official) idsToResolve.add(official.winner);

  const participantsById = await resolveParticipantsByIds(event.slug, Array.from(idsToResolve));
  const userWinnerPick = prediction.rankedParticipantIds[0]
    ? participantsById.get(prediction.rankedParticipantIds[0])
    : undefined;
  const actualWinner = official ? participantsById.get(official.winner) : undefined;
  const pluralNoun = getEntryNoun(event, true);
  const { breakdown, percentile } = result;
  const { winner, podium, top5, top10, ranking } = breakdown.components;

  return (
    <section className="mt-12 border-t border-border pt-10">
      <FouchScoreTracker
        eventSlug={event.slug}
        scoreBand={breakdown.band}
        percentileAvailable={percentile.percentile !== null}
        dataStatus={prediction.dataStatus}
      />

      <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">Fouch score</p>

      {prediction.dataStatus === "demo" ? (
        <p className="mt-2 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo result — not an official outcome
        </p>
      ) : null}

      <p className="mt-3 font-display text-7xl text-accent-strong">{breakdown.displayScore}</p>
      <p className="mt-1 font-display text-2xl uppercase tracking-tight text-text-primary">
        {BAND_LABEL[breakdown.band]}
      </p>

      {percentile.percentile !== null ? (
        <p className="mt-2 text-sm text-text-secondary">
          You beat {Math.round(percentile.percentile)}% of {pluralNoun === "picks" ? "predictions" : pluralNoun} for
          this event, based on {percentile.population} other predictions.
        </p>
      ) : (
        <p className="mt-2 text-xs text-text-muted">
          World ranking unlocks at {MIN_PERCENTILE_SAMPLE} predictions.
        </p>
      )}

      <dl className="mt-6 space-y-3 text-sm">
        <div className="border-b border-border pb-3">
          <dt className="flex items-center justify-between">
            <span className="text-text-secondary">Winner</span>
            <span className="text-text-muted">{formatPoints(winner.earned)} / {winner.max}</span>
          </dt>
          <dd className="mt-2">
            {winner.hit ? (
              <span className="inline-flex items-center gap-1.5 text-accent-strong">
                ✓
                {userWinnerPick ? (
                  <>
                    <CountryFlag countryCode={userWinnerPick.countryCode} />
                    {userWinnerPick.displayName}
                    <span className="text-text-muted">· {userWinnerPick.countryName}</span>
                  </>
                ) : (
                  "Correct"
                )}
              </span>
            ) : (
              <div className="space-y-1 text-text-primary">
                <p className="flex items-center gap-1.5">
                  <span className="text-text-muted">✗ Missed — your pick:</span>
                  {userWinnerPick ? (
                    <>
                      <CountryFlag countryCode={userWinnerPick.countryCode} />
                      {userWinnerPick.displayName}
                      <span className="text-text-muted">· {userWinnerPick.countryName}</span>
                    </>
                  ) : (
                    "—"
                  )}
                </p>
                {actualWinner ? (
                  <p className="flex items-center gap-1.5 text-text-secondary">
                    <span className="text-text-muted">Actual:</span>
                    <CountryFlag countryCode={actualWinner.countryCode} />
                    {actualWinner.displayName}
                    <span className="text-text-muted">· {actualWinner.countryName}</span>
                  </p>
                ) : null}
              </div>
            )}
          </dd>
        </div>

        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Podium</dt>
          <dd className="text-text-primary">
            {podium.hits} of {podium.total} · {formatPoints(podium.earned)} / {podium.max}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Top 5</dt>
          <dd className="text-text-primary">
            {top5.hits} of {top5.total} · {formatPoints(top5.earned)} / {top5.max}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Top 10</dt>
          <dd className="text-text-primary">
            {top10.hits} of {top10.total} · {formatPoints(top10.earned)} / {top10.max}
          </dd>
        </div>
        <div>
          <div className="flex items-center justify-between">
            <dt className="text-text-secondary">Ranking</dt>
            <dd className="text-text-primary">
              {formatPoints(ranking.earned)} / {ranking.max}
            </dd>
          </div>
          <p className="mt-1 text-xs text-text-muted">How close your picks were to the official finish.</p>
        </div>
      </dl>

      <div className="mt-8">
        <TrackedLink
          href={`/events/${event.slug}/leaderboard?from=${publicId}`}
          event="leaderboard_from_score_clicked"
          eventProperties={{ event_slug: event.slug }}
          className="inline-flex items-center justify-center rounded border border-border-strong px-6 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          See where you finished
        </TrackedLink>
      </div>

      <div className="mt-8">
        <p className="font-display text-lg text-text-primary">Share your result</p>
        <div className="mt-3">
          <ShareActions
            variant="result"
            eventSlug={event.slug}
            publicUrl={`${siteUrl}/p/${publicId}`}
            storyCardUrl={`/p/${publicId}/result-card/story`}
            postCardUrl={`/p/${publicId}/result-card/post`}
          />
        </div>
      </div>
    </section>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\FouchScore.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\FouchScore.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\FouchScore.tsx"
}

try {
    $path = "src\components\scoring\YourCrowdChanged.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { CountryFlag } from "@/components/CountryFlag";
import { resolveParticipantsByIds } from "@/lib/participants";
import { getConsensusChangeForPrediction } from "@/lib/consensus-change-service";
import { bucketSample } from "@/lib/consensus-change";
import type { PredictionRecord } from "@/lib/predictions-db";
import type { FouchEvent } from "@/types/event";
import { ConsensusChangeTracker } from "./ConsensusChangeTracker";

/**
 * Experiment 01 ("Your Crowd Changed") â€” FOUCH_EXPERIMENT_01.md.
 * Renders nothing whenever the movement isn't eligible (small sample,
 * or change under MIN_MOVEMENT_POINTS) â€” silence is the correct,
 * expected behavior, not a bug or a loading state.
 */
export async function YourCrowdChanged({
  prediction,
  event,
}: {
  prediction: PredictionRecord;
  event: FouchEvent;
}) {
  const winnerId = prediction.rankedParticipantIds[0];
  if (!winnerId) return null;

  const result = await getConsensusChangeForPrediction(
    prediction.id,
    prediction.submittedAt,
    winnerId,
    event.slug,
    prediction.dataStatus,
  );
  if (!result.eligible || !result.direction) return null;

  // FOUCH 0.3B: resolves regardless of current status â€” winnerId
  // comes from the community's aggregate winner picks and may
  // reference a participant who has since become
  // WITHDRAWN/REPLACED.
  const participantsById = await resolveParticipantsByIds(event.slug, [winnerId]);
  const winner = participantsById.get(winnerId);
  if (!winner) return null;

  const arrow = result.direction === "toward" ? "â†‘" : "â†“";
  const sign = result.changePoints > 0 ? "+" : "";
  const directionCopy =
    result.direction === "toward"
      ? "The crowd is moving toward your call."
      : "The crowd is moving away from your call.";

  return (
    <section className="mt-12 border-t border-border pt-10">
      <ConsensusChangeTracker
        eventSlug={event.slug}
        dataStatus={prediction.dataStatus}
        direction={result.direction}
        changePoints={result.changePoints}
        thenSampleBucket={bucketSample(result.thenSample)}
        nowSampleBucket={bucketSample(result.nowSample)}
      />

      <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">
        Your crowd changed
      </p>

      <div className="mt-3 flex items-center gap-2">
        <CountryFlag countryCode={winner.countryCode} className="text-2xl" />
        <span className="font-display text-xl text-text-primary">
          {winner.displayName} <span className="text-text-muted text-base">· {winner.countryName}</span>
        </span>
      </div>

      <p className="mt-2 font-display text-4xl text-accent-strong">
        {Math.round(result.thenSupport)}% â†’ {Math.round(result.nowSupport)}%
      </p>
      <p className="mt-1 text-sm text-text-secondary">
        {arrow} {sign}
        {Math.round(result.changePoints)} pts
      </p>

      <p className="mt-3 text-text-primary">{directionCopy}</p>
      <p className="mt-2 text-xs text-text-muted">Based on community predictions since your call.</p>
    </section>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\YourCrowdChanged.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\YourCrowdChanged.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\YourCrowdChanged.tsx"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 10 files written successfully." -ForegroundColor Green
}
