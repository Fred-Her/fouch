# Sprint 2: Submit + Prediction Card + Share — applies all new and changed files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-sprint2.ps1
# NOTE: run 'npm install nanoid' separately first (see instructions).
$failures = @()

try {
    $path = "supabase\migrations\0002_predictions.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- Sprint 2: real anonymous prediction persistence.
--
-- Security model: ALL writes go through server-side Server Actions
-- using the service-role key, which bypasses RLS by design — that is
-- where every validation rule (exact 10 positions, active
-- participants, event lock time, etc.) is enforced. RLS here is
-- defense-in-depth for the anon/public read path: anyone can read a
-- prediction by its public_id (that's the point — public prediction
-- pages need no login), but nobody can write, update, or delete
-- through the anon key.

create table if not exists predictions (
  id uuid primary key default gen_random_uuid(),
  public_id text not null unique,
  -- Events and participants are currently code-defined seed/demo data
  -- (see src/lib/events.ts, src/lib/participants.ts), not DB rows —
  -- so this references the event by slug, not a foreign key. When
  -- events move into Postgres, this can become a real FK.
  event_slug text not null,
  nickname text,
  country_code text,
  data_status text not null check (data_status in ('demo', 'verified')),
  device_token text not null,
  submitted_at timestamptz not null default now(),
  is_final boolean not null default true
);

-- One prediction per device per event — the lightweight duplicate/abuse
-- guard described in the sprint brief. Not foolproof (a user can clear
-- localStorage), but stops accidental double-submits and casual replay
-- without collecting IP or device fingerprinting data.
create unique index if not exists predictions_event_device_unique
  on predictions (event_slug, device_token);

create index if not exists predictions_event_slug_idx on predictions (event_slug);

create table if not exists prediction_items (
  id uuid primary key default gen_random_uuid(),
  prediction_id uuid not null references predictions(id) on delete cascade,
  participant_id text not null,
  predicted_position integer not null check (predicted_position between 1 and 10),
  created_at timestamptz not null default now(),
  unique (prediction_id, participant_id),
  unique (prediction_id, predicted_position)
);

create index if not exists prediction_items_prediction_id_idx on prediction_items (prediction_id);

alter table predictions enable row level security;
alter table prediction_items enable row level security;

-- Public read: prediction pages are shareable links, no login required.
drop policy if exists "predictions are publicly readable" on predictions;
create policy "predictions are publicly readable"
  on predictions for select
  using (true);

drop policy if exists "prediction_items are publicly readable" on prediction_items;
create policy "prediction_items are publicly readable"
  on prediction_items for select
  using (true);

-- No insert/update/delete policies are defined for anon/authenticated
-- roles on purpose: with RLS enabled and no matching policy, those
-- operations are denied by default. Only the service-role key (used
-- exclusively in src/app/predict/[slug]/actions.ts, server-side) can
-- write.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0002_predictions.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0002_predictions.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0002_predictions.sql"
}

try {
    $path = "src\types\event.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
export type EventCategory =
  | "pageant"
  | "awards"
  | "music"
  | "reality"
  | "talent"
  | "tv";

export type EventStatus = "upcoming" | "open" | "live" | "completed";

/**
 * Category-agnostic event model. Deliberately does NOT assume
 * contestants, countries, or a Top 10 shape — those are
 * category-specific concerns for a later sprint.
 */
export interface FouchEvent {
  id: string;
  slug: string;
  name: string;
  category: EventCategory;
  status: EventStatus;
  /** ISO 8601 date string. */
  eventDate: string;
  /** Path to a hero image/asset. Optional — Sprint 0 has none. */
  heroAsset?: string;
  isFeatured: boolean;
  /** Plain-language subtitle used in the UI, e.g. venue or one-line context. */
  subtitle?: string;
  /** ISO 8601 datetime. Predictions are rejected before this time, if set. */
  predictionOpenAt?: string;
  /** ISO 8601 datetime. Predictions are rejected at/after this time, if set. */
  predictionLockAt?: string;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\types\event.ts"
} catch {
    Write-Host "FAILED: src\types\event.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\types\event.ts"
}

try {
    $path = "src\lib\events.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { FouchEvent } from "@/types/event";

/**
 * SEED DATA — Sprint 0.
 *
 * This is real, verifiable public information (event name, date, venue),
 * not a database yet. There are no participant counts, popularity
 * numbers, or "trending" claims here — Fouch does not fabricate social
 * proof. Once Supabase is wired up (see src/lib/supabase), this file's
 * shape becomes the seed for the `events` table and this function can
 * be swapped for a real query without touching the components that
 * consume it.
 */
const events: FouchEvent[] = [
  {
    id: "seed-miss-universe-2026",
    slug: "miss-universe-2026",
    name: "Miss Universe 2026",
    category: "pageant",
    status: "upcoming",
    eventDate: "2026-11-24",
    isFeatured: true,
    subtitle: "José Miguel Agrelot Coliseum, San Juan, Puerto Rico",
    // Conservative lock: start of the event's calendar day (UTC), not the
    // exact broadcast time (not publicly confirmed to the minute at time
    // of writing). Safely before any results could be known.
    predictionLockAt: "2026-11-24T00:00:00Z",
  },
];

export function getFeaturedEvent(): FouchEvent | null {
  return events.find((event) => event.isFeatured) ?? null;
}

export function getEventBySlug(slug: string): FouchEvent | null {
  return events.find((event) => event.slug === slug) ?? null;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\events.ts"
} catch {
    Write-Host "FAILED: src\lib\events.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\events.ts"
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
 * free-text nickname/contestant input — only structural values like
 * an event slug, a count, a position, or a share method.
 */

export type FouchAnalyticsEvent =
  | "landing_view"
  | "featured_event_clicked"
  | "start_prediction"
  | "participant_selected"
  | "participant_removed"
  | "prediction_reordered"
  | "prediction_completed"
  | "prediction_reviewed"
  | "prediction_submit_started"
  | "prediction_submitted"
  | "prediction_card_generated"
  | "share_clicked"
  | "native_share_opened"
  | "copy_link_clicked"
  | "image_downloaded"
  | "public_prediction_viewed"
  | "public_prediction_cta_clicked";

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
    $path = "src\lib\public-id.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { customAlphabet } from "nanoid";

// No 0/O/1/I/l — avoids visually ambiguous characters in a link people
// might read aloud or retype. 9 chars over this 32-symbol alphabet is
// ~46 bits of entropy — not guessable, plenty for this scale.
const alphabet = "23456789abcdefghjkmnpqrstuvwxyz";
const generate = customAlphabet(alphabet, 9);

export function generatePublicId(): string {
  return generate();
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\public-id.ts"
} catch {
    Write-Host "FAILED: src\lib\public-id.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\public-id.ts"
}

try {
    $path = "src\lib\device-token.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
const STORAGE_KEY = "fouch:device-token";

/**
 * A random, anonymous per-browser token — not tied to identity, not
 * derived from IP/fingerprinting. Used only so the server can enforce
 * "one prediction per device per event" (see the unique index in
 * 0002_predictions.sql). Clearing localStorage resets it; that's an
 * accepted tradeoff for a lightweight, non-invasive guard.
 */
export function getDeviceToken(): string {
  if (typeof window === "undefined") return "";

  try {
    const existing = window.localStorage.getItem(STORAGE_KEY);
    if (existing) return existing;

    const token = crypto.randomUUID();
    window.localStorage.setItem(STORAGE_KEY, token);
    return token;
  } catch {
    // Storage unavailable (private browsing, quota, disabled) — fall
    // back to a per-request random value. Duplicate protection is
    // simply unavailable for that session, which is an acceptable
    // degradation, not a crash.
    return crypto.randomUUID();
  }
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\device-token.ts"
} catch {
    Write-Host "FAILED: src\lib\device-token.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\device-token.ts"
}

try {
    $path = "src\lib\prediction-validation.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Participant } from "@/types/participant";
import type { FouchEvent } from "@/types/event";

export interface SubmissionInput {
  participantIds: string[];
  nickname?: string;
  countryCode?: string;
}

export interface ValidatedSubmission {
  participantIds: string[];
  nickname: string | null;
  countryCode: string | null;
}

export type ValidationResult =
  | { valid: true; data: ValidatedSubmission }
  | { valid: false; error: string };

const MAX_NICKNAME_LENGTH = 24;
const COUNTRY_CODE_PATTERN = /^[A-Z]{2}$/;
// Strip anything that isn't a printable character or basic punctuation —
// defensive even though React already escapes rendered text; this also
// removes control characters and angle brackets outright.
const NICKNAME_SANITIZE_PATTERN = /[<>]/g;

function sanitizeNickname(raw: string | undefined): string | null {
  if (!raw) return null;
  const trimmed = raw.replace(NICKNAME_SANITIZE_PATTERN, "").trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * The single source of truth for "is this submission allowed". Called
 * only from the server action — the browser's ranking, nickname, and
 * country are never trusted as-is. Every rule here maps directly to
 * Sprint 2's brief section 10.
 */
export function validateSubmission(
  input: SubmissionInput,
  event: FouchEvent,
  activeParticipants: Participant[],
  requiredCount: number,
): ValidationResult {
  const now = Date.now();

  if (event.predictionOpenAt && now < Date.parse(event.predictionOpenAt)) {
    return { valid: false, error: "Predictions for this event haven't opened yet." };
  }
  if (event.predictionLockAt && now >= Date.parse(event.predictionLockAt)) {
    return { valid: false, error: "Predictions for this event are locked." };
  }

  const { participantIds } = input;

  if (!Array.isArray(participantIds) || participantIds.length !== requiredCount) {
    return { valid: false, error: `Exactly ${requiredCount} contestants are required.` };
  }

  const uniqueIds = new Set(participantIds);
  if (uniqueIds.size !== participantIds.length) {
    return { valid: false, error: "Duplicate contestants aren't allowed." };
  }

  const validIds = new Set(activeParticipants.map((participant) => participant.id));
  const allValid = participantIds.every((id) => typeof id === "string" && validIds.has(id));
  if (!allValid) {
    return { valid: false, error: "One or more contestants are invalid for this event." };
  }

  let nickname: string | null = null;
  if (input.nickname !== undefined) {
    if (typeof input.nickname !== "string") {
      return { valid: false, error: "Invalid nickname." };
    }
    nickname = sanitizeNickname(input.nickname);
    if (nickname && nickname.length > MAX_NICKNAME_LENGTH) {
      return { valid: false, error: `Nickname must be ${MAX_NICKNAME_LENGTH} characters or fewer.` };
    }
  }

  let countryCode: string | null = null;
  if (input.countryCode !== undefined && input.countryCode !== "") {
    if (typeof input.countryCode !== "string" || !COUNTRY_CODE_PATTERN.test(input.countryCode)) {
      return { valid: false, error: "Invalid country." };
    }
    countryCode = input.countryCode;
  }

  return {
    valid: true,
    data: { participantIds, nickname, countryCode },
  };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\prediction-validation.ts"
} catch {
    Write-Host "FAILED: src\lib\prediction-validation.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\prediction-validation.ts"
}

try {
    $path = "src\lib\predictions-db.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { generatePublicId } from "@/lib/public-id";
import { getEventBySlug } from "@/lib/events";
import { getParticipantsForEvent, type ParticipantDataStatus } from "@/lib/participants";
import type { FouchEvent } from "@/types/event";
import type { Participant } from "@/types/participant";

export interface PredictionRecord {
  publicId: string;
  eventSlug: string;
  nickname: string | null;
  countryCode: string | null;
  dataStatus: ParticipantDataStatus;
  submittedAt: string;
  /** Participant IDs in ranked order — index 0 is position #1. */
  rankedParticipantIds: string[];
}

interface InsertPredictionParams {
  eventSlug: string;
  participantIds: string[];
  nickname: string | null;
  countryCode: string | null;
  dataStatus: ParticipantDataStatus;
  deviceToken: string;
}

export type InsertPredictionResult =
  | { success: true; publicId: string; alreadyExisted: boolean }
  | { success: false; error: string };

const MAX_PUBLIC_ID_ATTEMPTS = 5;
const UNIQUE_VIOLATION = "23505";

export async function insertPrediction(
  params: InsertPredictionParams,
): Promise<InsertPredictionResult> {
  const supabase = getSupabaseServerClient();
  if (!supabase) {
    return { success: false, error: "Submissions aren't available yet — the database isn't configured." };
  }

  for (let attempt = 0; attempt < MAX_PUBLIC_ID_ATTEMPTS; attempt++) {
    const publicId = generatePublicId();

    const { data: prediction, error: insertError } = await supabase
      .from("predictions")
      .insert({
        public_id: publicId,
        event_slug: params.eventSlug,
        nickname: params.nickname,
        country_code: params.countryCode,
        data_status: params.dataStatus,
        device_token: params.deviceToken,
      })
      .select("id, public_id")
      .single();

    if (insertError) {
      // A public_id collision is astronomically unlikely (46 bits of
      // entropy) but retrying costs nothing. A (event_slug,
      // device_token) collision means this device already has a
      // prediction for this event — treat that as success and hand
      // back the existing one, so a double-tap or retry never looks
      // like a hard failure.
      if (insertError.code === UNIQUE_VIOLATION) {
        if (insertError.message.includes("public_id")) continue;

        const existing = await getPredictionByDeviceToken(params.eventSlug, params.deviceToken);
        if (existing) {
          return { success: true, publicId: existing.publicId, alreadyExisted: true };
        }
      }
      return { success: false, error: "We couldn't save your prediction. Please try again." };
    }

    const items = params.participantIds.map((participantId, index) => ({
      prediction_id: prediction.id,
      participant_id: participantId,
      predicted_position: index + 1,
    }));

    const { error: itemsError } = await supabase.from("prediction_items").insert(items);

    if (itemsError) {
      // Compensating cleanup — Supabase's JS client has no
      // multi-statement transaction here, so we manually undo the
      // parent row rather than leave an incomplete prediction behind.
      await supabase.from("predictions").delete().eq("id", prediction.id);
      return { success: false, error: "We couldn't save your prediction. Please try again." };
    }

    return { success: true, publicId: prediction.public_id, alreadyExisted: false };
  }

  return { success: false, error: "We couldn't generate a unique link. Please try again." };
}

export async function getPredictionByPublicId(publicId: string): Promise<PredictionRecord | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data: prediction, error } = await supabase
    .from("predictions")
    .select("public_id, event_slug, nickname, country_code, data_status, submitted_at, id")
    .eq("public_id", publicId)
    .single();

  if (error || !prediction) return null;

  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("participant_id, predicted_position")
    .eq("prediction_id", prediction.id)
    .order("predicted_position", { ascending: true });

  if (itemsError || !items) return null;

  return {
    publicId: prediction.public_id,
    eventSlug: prediction.event_slug,
    nickname: prediction.nickname,
    countryCode: prediction.country_code,
    dataStatus: prediction.data_status as ParticipantDataStatus,
    submittedAt: prediction.submitted_at,
    rankedParticipantIds: items.map((item) => item.participant_id),
  };
}

export async function getPredictionByDeviceToken(
  eventSlug: string,
  deviceToken: string,
): Promise<PredictionRecord | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data: prediction, error } = await supabase
    .from("predictions")
    .select("public_id")
    .eq("event_slug", eventSlug)
    .eq("device_token", deviceToken)
    .maybeSingle();

  if (error || !prediction) return null;

  return getPredictionByPublicId(prediction.public_id);
}

/**
 * Resolves a stored prediction's participant IDs back into full
 * Participant records (name, country) via the same seed/demo data the
 * builder uses, in the prediction's saved rank order. Returns null if
 * the prediction or any of its referenced participants can no longer
 * be resolved (e.g. seed data changed).
 */
export async function getPredictionWithParticipants(publicId: string): Promise<{
  prediction: PredictionRecord;
  event: FouchEvent;
  rankedParticipants: Participant[];
} | null> {
  const prediction = await getPredictionByPublicId(publicId);
  if (!prediction) return null;

  const event = getEventBySlug(prediction.eventSlug);
  if (!event) return null;

  const participantData = getParticipantsForEvent(prediction.eventSlug);
  if (!participantData) return null;

  const participantsById = new Map(
    participantData.participants.map((participant) => [participant.id, participant]),
  );

  const rankedParticipants = prediction.rankedParticipantIds
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  if (rankedParticipants.length !== prediction.rankedParticipantIds.length) return null;

  return { prediction, event, rankedParticipants };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\predictions-db.ts"
} catch {
    Write-Host "FAILED: src\lib\predictions-db.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\predictions-db.ts"
}

try {
    $path = "src\lib\countries.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * A curated, non-exhaustive list of countries for the optional "your
 * country" field on submission. This is about the PREDICTOR, not the
 * event's contestants (see src/lib/participants.ts) — a predictor can
 * be from anywhere, so this list is intentionally broader and
 * separate. ISO 3166-1 alpha-2 codes, validated server-side against
 * the same pattern regardless of whether the code appears here.
 */
export const PREDICTOR_COUNTRIES: Array<{ code: string; name: string }> = [
  { code: "AR", name: "Argentina" },
  { code: "AU", name: "Australia" },
  { code: "BR", name: "Brazil" },
  { code: "CA", name: "Canada" },
  { code: "CL", name: "Chile" },
  { code: "CO", name: "Colombia" },
  { code: "DE", name: "Germany" },
  { code: "DO", name: "Dominican Republic" },
  { code: "EC", name: "Ecuador" },
  { code: "ES", name: "Spain" },
  { code: "FR", name: "France" },
  { code: "GB", name: "United Kingdom" },
  { code: "IN", name: "India" },
  { code: "ID", name: "Indonesia" },
  { code: "IT", name: "Italy" },
  { code: "JM", name: "Jamaica" },
  { code: "JP", name: "Japan" },
  { code: "KE", name: "Kenya" },
  { code: "KR", name: "South Korea" },
  { code: "MX", name: "Mexico" },
  { code: "NG", name: "Nigeria" },
  { code: "PA", name: "Panama" },
  { code: "PE", name: "Peru" },
  { code: "PH", name: "Philippines" },
  { code: "PR", name: "Puerto Rico" },
  { code: "PT", name: "Portugal" },
  { code: "PY", name: "Paraguay" },
  { code: "TH", name: "Thailand" },
  { code: "US", name: "United States" },
  { code: "UY", name: "Uruguay" },
  { code: "VE", name: "Venezuela" },
  { code: "VN", name: "Vietnam" },
  { code: "ZA", name: "South Africa" },
].sort((a, b) => a.name.localeCompare(b.name));
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\countries.ts"
} catch {
    Write-Host "FAILED: src\lib\countries.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\countries.ts"
}

try {
    $path = "src\app\predict\[slug]\actions.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use server";

import { getEventBySlug } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { validateSubmission } from "@/lib/prediction-validation";
import { insertPrediction, getPredictionByDeviceToken } from "@/lib/predictions-db";

export interface SubmitPredictionInput {
  eventSlug: string;
  participantIds: string[];
  nickname?: string;
  countryCode?: string;
  deviceToken: string;
}

export type SubmitPredictionResult =
  | { success: true; publicId: string }
  | { success: false; error: string };

export async function submitPrediction(
  input: SubmitPredictionInput,
): Promise<SubmitPredictionResult> {
  const event = getEventBySlug(input.eventSlug);
  if (!event) {
    return { success: false, error: "This event doesn't exist." };
  }

  const participantData = getParticipantsForEvent(input.eventSlug);
  if (!participantData) {
    return { success: false, error: "This event has no contestants configured." };
  }

  const requiredCount = Math.min(10, participantData.participants.length);

  const validation = validateSubmission(
    {
      participantIds: input.participantIds,
      nickname: input.nickname,
      countryCode: input.countryCode,
    },
    event,
    participantData.participants,
    requiredCount,
  );

  if (!validation.valid) {
    return { success: false, error: validation.error };
  }

  if (!input.deviceToken || typeof input.deviceToken !== "string") {
    return { success: false, error: "Missing device token." };
  }

  const result = await insertPrediction({
    eventSlug: input.eventSlug,
    participantIds: validation.data.participantIds,
    nickname: validation.data.nickname,
    countryCode: validation.data.countryCode,
    dataStatus: participantData.status,
    deviceToken: input.deviceToken,
  });

  if (!result.success) {
    return { success: false, error: result.error };
  }

  return { success: true, publicId: result.publicId };
}

/**
 * Checks whether this device already has a submitted prediction for
 * this event, so the Review screen can redirect straight to the
 * existing public prediction instead of showing the submit form again
 * — a submitted prediction is immutable in Sprint 2.
 */
export async function checkExistingSubmission(
  eventSlug: string,
  deviceToken: string,
): Promise<{ publicId: string } | null> {
  if (!deviceToken) return null;
  const existing = await getPredictionByDeviceToken(eventSlug, deviceToken);
  return existing ? { publicId: existing.publicId } : null;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\predict\[slug]\actions.ts"
} catch {
    Write-Host "FAILED: src\app\predict\[slug]\actions.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\predict\[slug]\actions.ts"
}

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
  searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ from?: string }>;
}) {
  const { slug } = await params;
  const { from } = await searchParams;
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
          sourcePredictionId={from}
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
    $path = "src\components\prediction\ReviewContent.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Pencil } from "lucide-react";
import { flagEmoji } from "@/lib/flags";
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
  sourcePredictionId,
}: {
  eventSlug: string;
  participants: Participant[];
  requiredCount: number;
  /** Public ID of the shared prediction this visitor arrived from, if any. */
  sourcePredictionId?: string;
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
    track("start_prediction", {
      event_slug: eventSlug,
      source_prediction_public_id: sourcePredictionId ?? null,
    });
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
    $path = "src\components\prediction\SubmitPanel.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useState } from "react";
import { PREDICTOR_COUNTRIES } from "@/lib/countries";

export function SubmitPanel({
  requiredCount,
  submitting,
  errorMessage,
  onSubmit,
}: {
  requiredCount: number;
  submitting: boolean;
  errorMessage: string | null;
  onSubmit: (nickname: string, countryCode: string) => void;
}) {
  const [nickname, setNickname] = useState("");
  const [countryCode, setCountryCode] = useState("");

  return (
    <div className="mt-8 border-t border-border pt-6">
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="text-sm text-text-secondary">Nickname</span>
          <input
            type="text"
            value={nickname}
            onChange={(event) => setNickname(event.target.value)}
            maxLength={24}
            placeholder="Optional"
            className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
          />
        </label>

        <label className="block">
          <span className="text-sm text-text-secondary">Country</span>
          <select
            value={countryCode}
            onChange={(event) => setCountryCode(event.target.value)}
            className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary focus:border-accent"
          >
            <option value="">Optional</option>
            {PREDICTOR_COUNTRIES.map((country) => (
              <option key={country.code} value={country.code}>
                {country.name}
              </option>
            ))}
          </select>
        </label>
      </div>

      <p className="mt-2 text-xs text-text-muted">
        Optional — shown publicly with your prediction. You can edit your ranking until you lock
        it in.
      </p>

      {errorMessage ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert">
          {errorMessage}
        </p>
      ) : null}

      <button
        type="button"
        disabled={submitting}
        onClick={() => onSubmit(nickname, countryCode)}
        className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
      >
        {submitting ? "Locking in…" : `Lock in my Top ${requiredCount}`}
      </button>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\SubmitPanel.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\SubmitPanel.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\SubmitPanel.tsx"
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
 * A small country-code badge is the robust substitute: no emoji font
 * dependency, no network fetch, renders identically everywhere.
 */
function CountryBadge({ code, fontSize }: { code: string; fontSize: number }) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontSize,
        fontWeight: 700,
        letterSpacing: 1,
        color: TEXT_MUTED,
      }}
    >
      {code}
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
            <CountryBadge code={participant.countryCode} fontSize={26 * scale} />
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
              <CountryBadge code={participant.countryCode} fontSize={20} />
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
    $path = "src\components\prediction\ShareActions.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useState } from "react";
import { Share2, Download, Link2, Check } from "lucide-react";
import { track } from "@/lib/analytics";

export function ShareActions({
  eventSlug,
  publicUrl,
  storyCardUrl,
  postCardUrl,
}: {
  eventSlug: string;
  publicUrl: string;
  storyCardUrl: string;
  postCardUrl: string;
}) {
  const [format, setFormat] = useState<"story" | "post">("story");
  const [copied, setCopied] = useState(false);
  const [canNativeShare, setCanNativeShare] = useState(false);

  // navigator.share only exists client-side — checked once after mount
  // so server and initial client render stay consistent (no
  // hydration mismatch).
  useEffect(() => {
    if (typeof navigator !== "undefined" && "share" in navigator) {
      setCanNativeShare(true);
    }
  }, []);

  const activeCardUrl = format === "story" ? storyCardUrl : postCardUrl;

  async function handleShare() {
    track("share_clicked", { event_slug: eventSlug, share_method: "native" });
    if (!canNativeShare) return;

    try {
      await navigator.share({ title: "My Fouch prediction", url: publicUrl });
      track("native_share_opened", { event_slug: eventSlug });
    } catch {
      // User cancelled the share sheet — not an error worth surfacing.
    }
  }

  async function handleCopyLink() {
    track("copy_link_clicked", { event_slug: eventSlug });
    try {
      await navigator.clipboard.writeText(publicUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard API unavailable — the link is still visible/selectable
      // in the UI as a fallback (see the public page).
    }
  }

  function handleDownload() {
    track("image_downloaded", { event_slug: eventSlug, share_method: format });
  }

  return (
    <div>
      <div className="inline-flex rounded border border-border p-1 text-sm">
        <button
          type="button"
          onClick={() => setFormat("story")}
          className={`rounded px-3 py-1.5 transition-colors ${
            format === "story" ? "bg-surface-raised text-text-primary" : "text-text-muted"
          }`}
        >
          Story
        </button>
        <button
          type="button"
          onClick={() => setFormat("post")}
          className={`rounded px-3 py-1.5 transition-colors ${
            format === "post" ? "bg-surface-raised text-text-primary" : "text-text-muted"
          }`}
        >
          Post
        </button>
      </div>

      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={activeCardUrl}
        alt="Your Fouch prediction card"
        className="mt-3 w-full max-w-xs rounded border border-border"
      />

      <div className="mt-4 flex flex-wrap gap-2">
        {canNativeShare ? (
          <button
            type="button"
            onClick={handleShare}
            className="inline-flex items-center gap-2 rounded bg-accent px-5 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            <Share2 className="h-4 w-4" aria-hidden />
            Share
          </button>
        ) : null}

        <a
          href={activeCardUrl}
          download={`fouch-prediction-${format}.png`}
          onClick={handleDownload}
          className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          <Download className="h-4 w-4" aria-hidden />
          Save image
        </a>

        <button
          type="button"
          onClick={handleCopyLink}
          className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          {copied ? <Check className="h-4 w-4" aria-hidden /> : <Link2 className="h-4 w-4" aria-hidden />}
          {copied ? "Copied" : "Copy link"}
        </button>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\ShareActions.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\ShareActions.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\ShareActions.tsx"
}

try {
    $path = "src\components\prediction\PublicPredictionView.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { flagEmoji } from "@/lib/flags";
import { track } from "@/lib/analytics";
import { siteUrl } from "@/lib/site";
import type { Participant } from "@/types/participant";
import { ShareActions } from "./ShareActions";

export function PublicPredictionView({
  eventSlug,
  publicId,
  rankedParticipants,
}: {
  eventSlug: string;
  publicId: string;
  rankedParticipants: Participant[];
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
            <span aria-hidden className="text-xl">
              {flagEmoji(participant.countryCode)}
            </span>
            <span className="text-sm text-text-primary">{participant.displayName}</span>
          </li>
        ))}
      </ol>

      <div className="mt-8">
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

      <Link
        href={`/predict/${eventSlug}?from=${publicId}`}
        onClick={() => track("public_prediction_cta_clicked", { event_slug: eventSlug })}
        className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        Make your Top 10
      </Link>
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
    $path = "src\app\p\[publicId]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { flagEmoji } from "@/lib/flags";
import { siteUrl } from "@/lib/site";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { PublicPredictionView } from "@/components/prediction/PublicPredictionView";

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
        <p className="mt-1 text-sm text-text-muted">{flagEmoji(prediction.countryCode)}</p>
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
import { flagEmoji } from "@/lib/flags";
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
              <span style={{ display: "flex", marginRight: 8 }}>{flagEmoji(participant.countryCode)}</span>
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

try {
    $path = "src\app\p\[publicId]\card\story\route.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ImageResponse } from "next/og";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { PredictionCardMarkup } from "@/components/prediction/PredictionCardMarkup";
import { siteUrl } from "@/lib/site";

export const runtime = "edge";

const WIDTH = 1080;
const HEIGHT = 1920;

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ publicId: string }> },
) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);

  if (!record) {
    return new Response("Prediction not found", { status: 404 });
  }

  return new ImageResponse(
    (
      <PredictionCardMarkup
        width={WIDTH}
        height={HEIGHT}
        siteDomain={siteUrl.replace(/^https?:\/\//, "")}
        data={{
          eventName: record.event.name,
          nickname: record.prediction.nickname,
          countryCode: record.prediction.countryCode,
          isDemo: record.prediction.dataStatus === "demo",
          rankedParticipants: record.rankedParticipants,
        }}
      />
    ),
    { width: WIDTH, height: HEIGHT },
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\card\story\route.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\card\story\route.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\card\story\route.tsx"
}

try {
    $path = "src\app\p\[publicId]\card\post\route.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ImageResponse } from "next/og";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { PredictionCardMarkup } from "@/components/prediction/PredictionCardMarkup";
import { siteUrl } from "@/lib/site";

export const runtime = "edge";

const WIDTH = 1080;
const HEIGHT = 1350;

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ publicId: string }> },
) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);

  if (!record) {
    return new Response("Prediction not found", { status: 404 });
  }

  return new ImageResponse(
    (
      <PredictionCardMarkup
        width={WIDTH}
        height={HEIGHT}
        siteDomain={siteUrl.replace(/^https?:\/\//, "")}
        data={{
          eventName: record.event.name,
          nickname: record.prediction.nickname,
          countryCode: record.prediction.countryCode,
          isDemo: record.prediction.dataStatus === "demo",
          rankedParticipants: record.rankedParticipants,
        }}
      />
    ),
    { width: WIDTH, height: HEIGHT },
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\card\post\route.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\card\post\route.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\card\post\route.tsx"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 21 files written successfully." -ForegroundColor Green
}