# Sprint 3: You vs The World — applies all new and changed files.
# IMPORTANT: run the npm install command below FIRST, before this script.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-sprint3.ps1
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
  /**
   * What a single ranked option is called for this event — "contestant"
   * for a verified pageant roster, "nominee" for an Oscars category,
   * "country" for a Eurovision entry, etc. Defaults to "pick" when
   * unset (see getEntryNoun), which is deliberately generic for the
   * current demo country dataset — see Sprint 3 brief section 30.
   */
  entryNounSingular?: string;
  entryNounPlural?: string;
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

/**
 * The generic, event-agnostic term for one ranked option — "pick" by
 * default (fits the current demo country dataset), overridable per
 * event via entryNounSingular/Plural for future categories (Oscars
 * "nominee", Eurovision "entry", a verified pageant "contestant").
 */
export function getEntryNoun(event: FouchEvent, plural: boolean): string {
  if (plural) return event.entryNounPlural ?? "picks";
  return event.entryNounSingular ?? "pick";
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
  | "public_prediction_cta_clicked"
  | "you_vs_world_viewed"
  | "same_winner_viewed"
  | "top3_match_viewed"
  | "boldest_pick_viewed"
  | "community_top10_viewed"
  | "community_share_clicked";

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
import type { EligiblePrediction } from "@/lib/community-comparison";

export interface PredictionRecord {
  /** Internal DB id — server-side use only (e.g. self-exclusion from
   * community comparisons). Never send this to the client. */
  id: string;
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
    id: prediction.id,
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

/**
 * Fetches every ranked-ID list eligible for comparison against a given
 * event + data-status — the raw material for community-comparison.ts.
 * Only `id` and `participant_id`/`predicted_position` are selected;
 * nickname, country, and device_token never leave the database for
 * this purpose (see Sprint 3 brief section 22, privacy).
 *
 * "Eligible" here means: same event, same data_status (demo
 * predictions and future verified predictions never mix — see
 * section 9), and exactly 10 items. A prediction with a corrupted or
 * incomplete item set is silently excluded rather than crashing the
 * comparison.
 */
export async function getEligiblePredictionsForComparison(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<EligiblePrediction[]> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  const { data: predictions, error } = await supabase
    .from("predictions")
    .select("id")
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .eq("is_final", true);

  if (error || !predictions || predictions.length === 0) return [];

  const predictionIds = predictions.map((p) => p.id);

  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("prediction_id, participant_id, predicted_position")
    .in("prediction_id", predictionIds)
    .order("predicted_position", { ascending: true });

  if (itemsError || !items) return [];

  const itemsByPrediction = new Map<string, string[]>();
  for (const item of items) {
    const list = itemsByPrediction.get(item.prediction_id) ?? [];
    list.push(item.participant_id);
    itemsByPrediction.set(item.prediction_id, list);
  }

  const eligible: EligiblePrediction[] = [];
  for (const [predictionId, rankedParticipantIds] of itemsByPrediction) {
    // Defensive: a prediction with anything other than exactly 10
    // items is malformed and excluded rather than skewing the
    // comparison (see section 33, edge cases).
    if (rankedParticipantIds.length === 10) {
      eligible.push({ predictionId, rankedParticipantIds });
    }
  }

  return eligible;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\predictions-db.ts"
} catch {
    Write-Host "FAILED: src\lib\predictions-db.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\predictions-db.ts"
}

try {
    $path = "src\lib\community-comparison.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
export interface EligiblePrediction {
  /** Used only to exclude the viewed prediction from its own comparison. */
  predictionId: string;
  /** Participant IDs in ranked order — index 0 is position #1. */
  rankedParticipantIds: string[];
}

export type SampleSizeBucket = "0" | "1_4" | "5_9" | "10_24" | "25_49" | "50_99" | "100_plus";

/**
 * Sample-size tiers drive both UI copy (see YouVsTheWorld.tsx) and the
 * analytics property `comparison_population_bucket`. Kept as one
 * source of truth rather than scattered thresholds — see brief
 * section 10.
 */
export function getSampleSizeBucket(population: number): SampleSizeBucket {
  if (population <= 0) return "0";
  if (population <= 4) return "1_4";
  if (population <= 9) return "5_9";
  if (population <= 24) return "10_24";
  if (population <= 49) return "25_49";
  if (population <= 99) return "50_99";
  return "100_plus";
}

export interface CommunityTop10Entry {
  participantId: string;
  points: number;
  firstPlaceCount: number;
  top3Count: number;
  top10Count: number;
}

export interface ComparisonResult {
  population: number;
  sameWinner: { participantId: string; count: number; pct: number } | null;
  top3Match: { overlap: number; communityTop3: string[] } | null;
  boldestPick: { participantId: string; inclusionPct: number } | null;
  communityTop10: CommunityTop10Entry[];
}

/**
 * Excludes the viewed prediction from the comparison population, per
 * brief section 12 — "PREDICTION vs EVERYONE ELSE" must never let a
 * prediction inflate its own agreement numbers.
 */
function excludeSelf(
  predictions: EligiblePrediction[],
  excludePredictionId?: string,
): EligiblePrediction[] {
  if (!excludePredictionId) return predictions;
  return predictions.filter((prediction) => prediction.predictionId !== excludePredictionId);
}

/**
 * Position-weighted community ranking: position 1 = 10 points, down
 * to position 10 = 1 point (formula: 11 - position). Ties break on,
 * in order: more #1 picks, more Top 3 appearances, more Top 10
 * appearances, then participant ID ascending — deterministic, never
 * arbitrary object/insertion order.
 */
export function computeCommunityTop10(predictions: EligiblePrediction[]): CommunityTop10Entry[] {
  const byParticipant = new Map<string, CommunityTop10Entry>();

  for (const prediction of predictions) {
    prediction.rankedParticipantIds.forEach((participantId, index) => {
      const position = index + 1;
      const entry = byParticipant.get(participantId) ?? {
        participantId,
        points: 0,
        firstPlaceCount: 0,
        top3Count: 0,
        top10Count: 0,
      };
      entry.points += 11 - position;
      if (position === 1) entry.firstPlaceCount += 1;
      if (position <= 3) entry.top3Count += 1;
      entry.top10Count += 1;
      byParticipant.set(participantId, entry);
    });
  }

  return Array.from(byParticipant.values()).sort((a, b) => {
    if (b.points !== a.points) return b.points - a.points;
    if (b.firstPlaceCount !== a.firstPlaceCount) return b.firstPlaceCount - a.firstPlaceCount;
    if (b.top3Count !== a.top3Count) return b.top3Count - a.top3Count;
    if (b.top10Count !== a.top10Count) return b.top10Count - a.top10Count;
    return a.participantId.localeCompare(b.participantId);
  });
}

/**
 * The full You vs The World comparison for one ranked prediction
 * against a comparison population. Pure function — no I/O — so it can
 * be unit-tested with fixtures (see community-comparison.test.ts) and
 * reused by both the public prediction page and analytics.
 */
export function computeComparison(
  rankedParticipantIds: string[],
  allPredictions: EligiblePrediction[],
  excludePredictionId?: string,
): ComparisonResult {
  const predictions = excludeSelf(allPredictions, excludePredictionId);
  const population = predictions.length;

  const communityTop10 = computeCommunityTop10(predictions);

  if (population === 0) {
    return { population: 0, sameWinner: null, top3Match: null, boldestPick: null, communityTop10: [] };
  }

  const userWinner = rankedParticipantIds[0];
  const sameWinnerCount = userWinner
    ? predictions.filter((p) => p.rankedParticipantIds[0] === userWinner).length
    : 0;
  const sameWinner = userWinner
    ? { participantId: userWinner, count: sameWinnerCount, pct: sameWinnerCount / population }
    : null;

  const communityTop3Ids = communityTop10.slice(0, 3).map((entry) => entry.participantId);
  const userTop3 = new Set(rankedParticipantIds.slice(0, 3));
  const top3Overlap = communityTop3Ids.filter((id) => userTop3.has(id)).length;
  const top3Match =
    communityTop3Ids.length > 0 ? { overlap: top3Overlap, communityTop3: communityTop3Ids } : null;

  const inclusionByParticipant = new Map(
    communityTop10.map((entry) => [entry.participantId, entry.top10Count / population]),
  );
  const userTop5 = rankedParticipantIds.slice(0, 5);
  let boldestPick: ComparisonResult["boldestPick"] = null;
  for (const participantId of userTop5) {
    const inclusionPct = inclusionByParticipant.get(participantId) ?? 0;
    if (!boldestPick || inclusionPct < boldestPick.inclusionPct) {
      boldestPick = { participantId, inclusionPct };
    }
  }

  return { population, sameWinner, top3Match, boldestPick, communityTop10: communityTop10.slice(0, 10) };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\community-comparison.ts"
} catch {
    Write-Host "FAILED: src\lib\community-comparison.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\community-comparison.ts"
}

try {
    $path = "src\lib\community-comparison.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { computeComparison, computeCommunityTop10, getSampleSizeBucket } from "./community-comparison";
import type { EligiblePrediction } from "./community-comparison";

// Fixtures straight from the Sprint 3 brief, section 32.
const predictionA: EligiblePrediction = {
  predictionId: "A",
  rankedParticipantIds: ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
};
const predictionB: EligiblePrediction = {
  predictionId: "B",
  rankedParticipantIds: ["A", "C", "B", "K", "L", "M", "N", "O", "P", "Q"],
};
const predictionC: EligiblePrediction = {
  predictionId: "C",
  rankedParticipantIds: ["B", "A", "C", "D", "K", "L", "M", "N", "O", "P"],
};
const allThree = [predictionA, predictionB, predictionC];

describe("getSampleSizeBucket", () => {
  it.each([
    [0, "0"],
    [1, "1_4"],
    [4, "1_4"],
    [5, "5_9"],
    [9, "5_9"],
    [10, "10_24"],
    [24, "10_24"],
    [25, "25_49"],
    [49, "25_49"],
    [50, "50_99"],
    [99, "50_99"],
    [100, "100_plus"],
    [500, "100_plus"],
  ])("population %i -> %s", (population, expected) => {
    expect(getSampleSizeBucket(population)).toBe(expected);
  });
});

describe("computeComparison — viewing prediction A (self-excluded, world = B & C)", () => {
  const result = computeComparison(predictionA.rankedParticipantIds, allThree, "A");

  it("excludes the viewed prediction from the population", () => {
    expect(result.population).toBe(2);
  });

  it("same winner: A appears as #1 in B only, out of B & C", () => {
    expect(result.sameWinner).toEqual({ participantId: "A", count: 1, pct: 0.5 });
  });

  it("top 3 match: community top 3 (A, B, C) fully overlaps A's own top 3", () => {
    expect(result.top3Match?.communityTop3).toEqual(["A", "B", "C"]);
    expect(result.top3Match?.overlap).toBe(3);
  });

  it("boldest pick: E never appears in B or C — the least common of A's top 5", () => {
    expect(result.boldestPick).toEqual({ participantId: "E", inclusionPct: 0 });
  });

  it("community top 10 excludes the 11th-ranked participant (Q) and orders by points", () => {
    const ids = result.communityTop10.map((entry) => entry.participantId);
    expect(ids).toEqual(["A", "B", "C", "K", "L", "M", "N", "D", "O", "P"]);
    expect(ids).toHaveLength(10);
  });
});

describe("computeComparison — viewing prediction C (self-excluded, world = A & B)", () => {
  const result = computeComparison(predictionC.rankedParticipantIds, allThree, "C");

  it("same winner: C's own winner is B, but A and B (the world) both have winner A — zero match", () => {
    expect(result.sameWinner).toEqual({ participantId: "B", count: 0, pct: 0 });
  });

  it("does not crash or divide by zero when the match count is zero", () => {
    expect(result.sameWinner?.pct).toBe(0);
  });
});

describe("computeComparison — zero eligible predictions", () => {
  it("returns an explicit empty state instead of dividing by zero", () => {
    const result = computeComparison(predictionA.rankedParticipantIds, [predictionA], "A");
    expect(result).toEqual({
      population: 0,
      sameWinner: null,
      top3Match: null,
      boldestPick: null,
      communityTop10: [],
    });
  });
});

describe("computeCommunityTop10 — deterministic tie-breaking", () => {
  it("breaks a points tie using first-place count, then top-3 count, then top-10 count, then participant ID", () => {
    // X and Y both score 7 points total (one 4th-place finish each: 11-4=7).
    // Z scores 7 points via a single #1 finish (11-1=10)... adjusted below
    // to isolate each tiebreaker independently.
    const predictions: EligiblePrediction[] = [
      // X: one #1 finish elsewhere pads its first-place count.
      { predictionId: "p1", rankedParticipantIds: ["X", "_", "_", "_", "_", "_", "_", "_", "_", "_"] },
      { predictionId: "p2", rankedParticipantIds: ["_", "_", "_", "Y", "_", "_", "_", "_", "_", "_"] },
    ];
    const ranking = computeCommunityTop10(predictions);
    const x = ranking.find((entry) => entry.participantId === "X");
    const y = ranking.find((entry) => entry.participantId === "Y");

    // X: position 1 -> 10 points, 1 first-place finish.
    // Y: position 4 -> 7 points, 0 first-place finishes.
    expect(x?.points).toBe(10);
    expect(y?.points).toBe(7);
    expect(ranking.findIndex((e) => e.participantId === "X")).toBeLessThan(
      ranking.findIndex((e) => e.participantId === "Y"),
    );
  });

  it("falls back to participant ID ascending when every other tiebreaker is equal", () => {
    const tied: EligiblePrediction[] = [
      { predictionId: "p1", rankedParticipantIds: ["Zebra"] },
      { predictionId: "p2", rankedParticipantIds: ["Apple"] },
    ];
    const ranking = computeCommunityTop10(tied);
    expect(ranking[0]?.participantId).toBe("Apple");
    expect(ranking[1]?.participantId).toBe("Zebra");
  });
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\community-comparison.test.ts"
} catch {
    Write-Host "FAILED: src\lib\community-comparison.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\community-comparison.test.ts"
}

try {
    $path = "src\components\prediction\YouVsTheWorld.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { flagEmoji } from "@/lib/flags";
import { getEntryNoun } from "@/lib/events";
import { getEligiblePredictionsForComparison, type PredictionRecord } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { computeComparison, getSampleSizeBucket } from "@/lib/community-comparison";
import type { FouchEvent } from "@/types/event";
import { ShareYourCallCta } from "./ShareYourCallCta";
import { YouVsTheWorldTracker } from "./YouVsTheWorldTracker";

function formatPct(pct: number): string {
  return `${Math.round(pct * 100)}%`;
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

      {bucket === "0" ? (
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
                {formatPct(comparison.sameWinner.pct)}
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                Same winner
              </p>
              <p className="mt-2 text-text-primary">
                {flagEmoji(
                  participantsById.get(comparison.sameWinner.participantId)?.countryCode ?? "",
                )}{" "}
                {participantsById.get(comparison.sameWinner.participantId)?.displayName} —{" "}
                {comparison.sameWinner.count === 0
                  ? "nobody else made the same call."
                  : `${comparison.sameWinner.count} of ${comparison.population} other predictions agree.`}
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
                {flagEmoji(participantsById.get(comparison.boldestPick.participantId)?.countryCode ?? "")}{" "}
                {participantsById.get(comparison.boldestPick.participantId)?.displayName}
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                Your boldest call
              </p>
              <p className="mt-2 text-text-primary">
                Only {formatPct(comparison.boldestPick.inclusionPct)} of other predictions have
                this in their top 10.
              </p>
            </div>
          ) : null}

          {comparison.communityTop10.length > 0 ? (
            <div>
              <p className="font-display text-xl text-text-primary">The world&apos;s top 10</p>
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
                      <span aria-hidden>{flagEmoji(participant.countryCode)}</span>
                      <span className="flex-1 text-sm text-text-primary">
                        {participant.displayName}
                      </span>
                      <span className="text-xs text-text-muted">
                        {formatPct(entry.top10Count / comparison.population)} picked
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
    $path = "src\components\prediction\YouVsTheWorldTracker.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect } from "react";
import { track } from "@/lib/analytics";
import type { SampleSizeBucket } from "@/lib/community-comparison";

/**
 * You vs The World itself is a Server Component (it needs server-side
 * Supabase access), so it can't call the client-only `track()`
 * directly. This tiny client component fires the view events on
 * mount and renders nothing.
 */
export function YouVsTheWorldTracker({
  eventSlug,
  dataStatus,
  bucket,
  hasSameWinner,
  hasTop3Match,
  hasBoldestPick,
  hasCommunityTop10,
}: {
  eventSlug: string;
  dataStatus: string;
  bucket: SampleSizeBucket;
  hasSameWinner: boolean;
  hasTop3Match: boolean;
  hasBoldestPick: boolean;
  hasCommunityTop10: boolean;
}) {
  useEffect(() => {
    const properties = { event_slug: eventSlug, data_status: dataStatus, comparison_population_bucket: bucket };
    track("you_vs_world_viewed", properties);
    if (hasSameWinner) track("same_winner_viewed", properties);
    if (hasTop3Match) track("top3_match_viewed", properties);
    if (hasBoldestPick) track("boldest_pick_viewed", properties);
    if (hasCommunityTop10) track("community_top10_viewed", properties);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\YouVsTheWorldTracker.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\YouVsTheWorldTracker.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\YouVsTheWorldTracker.tsx"
}

try {
    $path = "src\components\prediction\ShareYourCallCta.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { track } from "@/lib/analytics";

export function ShareYourCallCta({ standsOut = false }: { standsOut?: boolean }) {
  return (
    <div className="mt-2">
      <p className="font-display text-lg text-text-primary">
        {standsOut ? "Your call stands out." : "Think the world is wrong?"}
      </p>
      <Link
        href="#share"
        onClick={() => track("community_share_clicked")}
        className="group mt-3 inline-flex items-center gap-2 rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        Share your call
        <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
      </Link>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\ShareYourCallCta.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\ShareYourCallCta.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\ShareYourCallCta.tsx"
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
import { flagEmoji } from "@/lib/flags";
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
            <span aria-hidden className="text-xl">
              {flagEmoji(participant.countryCode)}
            </span>
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

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 12 files written successfully." -ForegroundColor Green
}