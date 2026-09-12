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