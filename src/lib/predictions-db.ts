import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { generatePublicId } from "@/lib/public-id";
import { getEventBySlug } from "@/lib/events";
import { resolveParticipantsByIds, type ParticipantDataStatus } from "@/lib/participants";
import { classifyInsertConflict } from "@/lib/insert-conflict";
import { isRankingUnchanged } from "@/lib/prediction-version-logic";
import type { FouchEvent } from "@/types/event";
import type { Participant } from "@/types/participant";
import type { EligiblePrediction } from "@/lib/community-comparison";

export interface PredictionRecord {
  /** Internal DB id â€” server-side use only (e.g. self-exclusion from
   * community comparisons). Never send this to the client. */
  id: string;
  publicId: string;
  eventSlug: string;
  nickname: string | null;
  countryCode: string | null;
  dataStatus: ParticipantDataStatus;
  submittedAt: string;
  /** FOUCH 0.3A: whether this prediction has a verified owner. Only
   * ever used server-side to decide whether to offer "EDIT MY TOP
   * 10" â€” never exposed as a raw auth_user_id to the client (see
   * predictions_public, which still never selects auth_user_id). */
  hasVerifiedOwner: boolean;
  /** FOUCH 0.3A: version_number of the current version â€” needed by
   * the edit flow as the optimistic-concurrency baseline. */
  currentVersionNumber: number;
  /** Participant IDs in ranked order â€” index 0 is position #1. */
  rankedParticipantIds: string[];
}

interface InsertPredictionParams {
  eventSlug: string;
  participantIds: string[];
  nickname: string | null;
  countryCode: string | null;
  dataStatus: ParticipantDataStatus;
  deviceToken: string;
  /** Beta Hardening 0.2 Phase C â€” set only by the new verified-lock
   * path. Undefined/omitted preserves the exact pre-Phase-C anonymous
   * insert behavior (legacy predictions are never retroactively
   * touched â€” see FOUCH_IDENTITY_ARCHITECTURE.md). */
  authUserId?: string;
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
        ...(params.authUserId ? { auth_user_id: params.authUserId } : {}),
      })
      .select("id, public_id")
      .single();

    if (insertError) {
      // A public_id collision is astronomically unlikely (46 bits of
      // entropy) but retrying costs nothing. A conflict on the
      // identity index (Phase C) or the legacy device index both mean
      // "this identity/device already has a prediction for this
      // event" â€” treat either as success and hand back the existing
      // one, so a double-tap, a race, or a retry never looks like a
      // hard failure. See insert-conflict.ts for why the message is
      // classified rather than just checked for "public_id" â€” Phase C
      // adds a second possible unique constraint to distinguish.
      if (insertError.code === UNIQUE_VIOLATION) {
        const conflict = classifyInsertConflict(insertError.message);

        if (conflict === "public_id") continue;

        if (conflict === "identity" && params.authUserId) {
          const existing = await getPredictionByAuthUserId(params.eventSlug, params.authUserId);
          if (existing) {
            return { success: true, publicId: existing.publicId, alreadyExisted: true };
          }
        }

        if (conflict === "device" || conflict === "unknown") {
          const existing = await getPredictionByDeviceToken(params.eventSlug, params.deviceToken);
          if (existing) {
            return { success: true, publicId: existing.publicId, alreadyExisted: true };
          }
        }
      }
      return { success: false, error: "We couldn't save your prediction. Please try again." };
    }

    // FOUCH 0.3A: every prediction, including a first-time submission,
    // is now version 1 of its versioned history â€” not a special case.
    // See createPredictionVersion() below for the same shape used by
    // every later edit.
    const { data: version, error: versionError } = await supabase
      .from("prediction_versions")
      .insert({ prediction_id: prediction.id, version_number: 1 })
      .select("id")
      .single();

    if (versionError || !version) {
      await supabase.from("predictions").delete().eq("id", prediction.id);
      return { success: false, error: "We couldn't save your prediction. Please try again." };
    }

    const items = params.participantIds.map((participantId, index) => ({
      prediction_id: prediction.id,
      version_id: version.id,
      participant_id: participantId,
      predicted_position: index + 1,
    }));

    const { error: itemsError } = await supabase.from("prediction_items").insert(items);

    if (itemsError) {
      // Compensating cleanup â€” Supabase's JS client has no
      // multi-statement transaction here, so we manually undo the
      // parent rows rather than leave an incomplete prediction behind.
      // Deleting `predictions` cascades to `prediction_versions`
      // (on delete cascade), which in turn cascades to any
      // `prediction_items` already inserted for it.
      await supabase.from("predictions").delete().eq("id", prediction.id);
      return { success: false, error: "We couldn't save your prediction. Please try again." };
    }

    const { error: currentVersionError } = await supabase
      .from("predictions")
      .update({ current_version_id: version.id })
      .eq("id", prediction.id);

    if (currentVersionError) {
      await supabase.from("predictions").delete().eq("id", prediction.id);
      return { success: false, error: "We couldn't save your prediction. Please try again." };
    }

    return { success: true, publicId: prediction.public_id, alreadyExisted: false };
  }

  return { success: false, error: "We couldn't generate a unique link. Please try again." };
}

export interface EditablePrediction {
  publicId: string;
  eventSlug: string;
  authUserId: string | null;
  /** Highest version_number that exists for this prediction â€” the
   * next successful edit is version_number = latestVersionNumber + 1. */
  latestVersionNumber: number;
  /** Participant IDs of the CURRENT version, in ranked order â€” used
   * to pre-fill the edit builder. */
  currentRankedParticipantIds: string[];
}

/**
 * The one lookup the edit flow needs before authorizing anything:
 * who owns this prediction (by auth_user_id, never anything the
 * client supplies) and what its current ranking/version number are.
 * Returns null if the prediction, its current version, or its items
 * can't be resolved â€” callers must treat that as "can't edit", never
 * as "treat as new".
 */
export async function getPredictionForEdit(publicId: string): Promise<EditablePrediction | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data: prediction, error } = await supabase
    .from("predictions")
    .select("id, public_id, event_slug, auth_user_id, current_version_id")
    .eq("public_id", publicId)
    .single();

  if (error || !prediction || !prediction.current_version_id) return null;

  const { data: currentVersion, error: versionError } = await supabase
    .from("prediction_versions")
    .select("version_number")
    .eq("id", prediction.current_version_id)
    .single();

  if (versionError || !currentVersion) return null;

  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("participant_id, predicted_position")
    .eq("version_id", prediction.current_version_id)
    .order("predicted_position", { ascending: true });

  if (itemsError || !items) return null;

  return {
    publicId: prediction.public_id,
    eventSlug: prediction.event_slug,
    authUserId: prediction.auth_user_id,
    latestVersionNumber: currentVersion.version_number,
    currentRankedParticipantIds: items.map((item) => item.participant_id),
  };
}

export type CreateVersionResult =
  | { success: true; publicId: string; versionNumber: number; unchanged: boolean }
  | { success: false; error: string };

/**
 * Creates a new immutable version for an EXISTING logical prediction
 * and makes it current. Never touches public_id, never creates a new
 * `predictions` row â€” this is exclusively the "edit" path; first
 * submissions go through insertPrediction() above.
 *
 * Idempotency (brief Â§19): if the submitted ranking is identical to
 * the prediction's current version, this is a no-op that returns
 * success without creating a new version â€” the simplest robust
 * defense against a double-click or a network retry re-sending the
 * exact same edit, with no client-supplied idempotency key needed.
 * A retry that lands after a lost response looks identical to the
 * original request, so this naturally covers that case too.
 *
 * Concurrency: `expectedVersionNumber` must match the version number
 * the caller read just before presenting the edit form. A mismatch
 * means someone else's edit (or this same edit, retried, but no
 * longer the current version) landed first â€” reported as a
 * conflict rather than silently overwritten, satisfying "a retry
 * must not accidentally create uncontrolled duplicate versions" from
 * the other direction (never silently stack two edits based on a
 * stale read either).
 */
export async function createPredictionVersion(params: {
  predictionPublicId: string;
  participantIds: string[];
  expectedVersionNumber: number;
  currentRankedParticipantIds: string[];
}): Promise<CreateVersionResult> {
  const supabase = getSupabaseServerClient();
  if (!supabase) {
    return { success: false, error: "Editing isn't available right now — the database isn't configured." };
  }

  const isUnchanged = isRankingUnchanged(params.currentRankedParticipantIds, params.participantIds);

  if (isUnchanged) {
    return {
      success: true,
      publicId: params.predictionPublicId,
      versionNumber: params.expectedVersionNumber,
      unchanged: true,
    };
  }

  const { data: prediction, error: predictionError } = await supabase
    .from("predictions")
    .select("id, current_version_id")
    .eq("public_id", params.predictionPublicId)
    .single();

  if (predictionError || !prediction) {
    return { success: false, error: "We couldn't find that prediction." };
  }

  // Re-check the expected version number against the DB row we just
  // read, not the one the caller assumed â€” closes the gap between
  // "the page loaded the current ranking" and "the save request
  // actually landed", per the concurrency note above.
  const { data: currentVersionRow, error: currentVersionRowError } = await supabase
    .from("prediction_versions")
    .select("version_number")
    .eq("id", prediction.current_version_id)
    .single();

  if (currentVersionRowError || !currentVersionRow) {
    return { success: false, error: "We couldn't verify your prediction's current version." };
  }

  if (currentVersionRow.version_number !== params.expectedVersionNumber) {
    return {
      success: false,
      error: "Your prediction changed elsewhere since you opened this — please reload and try again.",
    };
  }

  const nextVersionNumber = currentVersionRow.version_number + 1;

  const { data: newVersion, error: versionError } = await supabase
    .from("prediction_versions")
    .insert({ prediction_id: prediction.id, version_number: nextVersionNumber })
    .select("id")
    .single();

  if (versionError || !newVersion) {
    // A unique-violation on (prediction_id, version_number) here means
    // a concurrent edit already claimed this exact next version number
    // â€” report as a conflict rather than silently retrying with a
    // higher number, which could race indefinitely under contention.
    return {
      success: false,
      error: "Your prediction changed elsewhere since you opened this — please reload and try again.",
    };
  }

  const items = params.participantIds.map((participantId, index) => ({
    prediction_id: prediction.id,
    version_id: newVersion.id,
    participant_id: participantId,
    predicted_position: index + 1,
  }));

  const { error: itemsError } = await supabase.from("prediction_items").insert(items);

  if (itemsError) {
    // Compensating cleanup, same pattern as insertPrediction(): undo
    // the orphaned version row rather than leave a version with no
    // items behind. current_version_id was never pointed at it, so
    // no reader ever saw this partial state.
    await supabase.from("prediction_versions").delete().eq("id", newVersion.id);
    return { success: false, error: "We couldn't save your changes. Please try again." };
  }

  const { error: updateError } = await supabase
    .from("predictions")
    .update({ current_version_id: newVersion.id })
    .eq("id", prediction.id);

  if (updateError) {
    await supabase.from("prediction_versions").delete().eq("id", newVersion.id);
    return { success: false, error: "We couldn't save your changes. Please try again." };
  }

  return {
    success: true,
    publicId: params.predictionPublicId,
    versionNumber: nextVersionNumber,
    unchanged: false,
  };
}

export async function getPredictionByPublicId(publicId: string): Promise<PredictionRecord | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data: prediction, error } = await supabase
    .from("predictions")
    .select(
      "public_id, event_slug, nickname, country_code, data_status, submitted_at, id, current_version_id, auth_user_id",
    )
    .eq("public_id", publicId)
    .single();

  if (error || !prediction || !prediction.current_version_id) return null;

  const { data: currentVersion, error: currentVersionError } = await supabase
    .from("prediction_versions")
    .select("version_number")
    .eq("id", prediction.current_version_id)
    .single();

  if (currentVersionError || !currentVersion) return null;

  // FOUCH 0.3A: always the CURRENT version's items â€” never every
  // version ever saved. This is the one place every public-facing
  // read of "this prediction's ranking" ultimately goes through.
  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("participant_id, predicted_position")
    .eq("version_id", prediction.current_version_id)
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
    hasVerifiedOwner: prediction.auth_user_id !== null,
    currentVersionNumber: currentVersion.version_number,
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
 * Beta Hardening 0.2 Phase C â€” looks up an existing FINAL prediction
 * by verified identity, the same shape as getPredictionByDeviceToken
 * above, used for the identity unique-constraint conflict path.
 */
export async function getPredictionByAuthUserId(
  eventSlug: string,
  authUserId: string,
): Promise<PredictionRecord | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data: prediction, error } = await supabase
    .from("predictions")
    .select("public_id")
    .eq("event_slug", eventSlug)
    .eq("auth_user_id", authUserId)
    .eq("is_final", true)
    .maybeSingle();

  if (error || !prediction) return null;

  return getPredictionByPublicId(prediction.public_id);
}

/**
 * Beta Hardening 0.2 Phase C â€” feeds the soft, non-blocking
 * same-device/different-identity signal (see insert-conflict.ts's
 * isDeviceIdentityMismatch). Returns only the two fields that
 * function needs â€” never a full PredictionRecord, since this is
 * purely an internal analytics signal, not a user-facing lookup.
 */
export async function getDeviceTokenIdentity(
  eventSlug: string,
  deviceToken: string,
): Promise<{ deviceToken: string; authUserId: string | null } | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("predictions")
    .select("device_token, auth_user_id")
    .eq("event_slug", eventSlug)
    .eq("device_token", deviceToken)
    .eq("is_final", true)
    .maybeSingle();

  if (error || !data) return null;

  return { deviceToken: data.device_token, authUserId: data.auth_user_id };
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

  const event = await getEventBySlug(prediction.eventSlug);
  if (!event) return null;

  // FOUCH 0.3B: resolves by id regardless of current status â€” a
  // participant who has since become WITHDRAWN/REPLACED must still
  // render here with their real name/country. Using the active-only
  // getParticipantsForEvent here would silently drop such an entry
  // (or, worse, fail the length check below and 404 the whole public
  // prediction) the moment their status changed after the fact.
  const participantsById = await resolveParticipantsByIds(prediction.eventSlug, prediction.rankedParticipantIds);

  const rankedParticipants = prediction.rankedParticipantIds
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  if (rankedParticipants.length !== prediction.rankedParticipantIds.length) return null;

  return { prediction, event, rankedParticipants };
}

/**
 * Fetches every ranked-ID list eligible for comparison against a given
 * event + data-status â€” the raw material for community-comparison.ts.
 * Only `id` and `participant_id`/`predicted_position` are selected;
 * nickname, country, and device_token never leave the database for
 * this purpose (see Sprint 3 brief section 22, privacy).
 *
 * "Eligible" here means: same event, same data_status (demo
 * predictions and future verified predictions never mix â€” see
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

  // FOUCH 0.3A: `id` here is the logical prediction's key used only to
  // group items below; `current_version_id` is what actually scopes
  // which items count â€” a prediction with 3 saved versions must still
  // contribute exactly ONE eligible ranking (its current one), never
  // three (brief Â§12: "Freddy has v1, v2, v3 â†’ community sample size
  // is 1 prediction, not 3").
  const { data: predictions, error } = await supabase
    .from("predictions")
    .select("id, current_version_id")
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .eq("is_final", true)
    .not("current_version_id", "is", null);

  if (error || !predictions || predictions.length === 0) return [];

  const versionIds = predictions.map((p) => p.current_version_id as string);

  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("prediction_id, version_id, participant_id, predicted_position")
    .in("version_id", versionIds)
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

export interface LeaderboardRawEntry {
  predictionId: string;
  publicId: string;
  nickname: string | null;
  countryCode: string | null;
  rankedParticipantIds: string[];
}

/**
 * Same eligibility filters as getEligiblePredictionsForComparison
 * (event + data_status + is_final=true + exactly 10 items) â€” kept as a
 * near-identical second query, deliberately, rather than reusing that
 * function directly: that function's contract explicitly promises to
 * never select nickname/country (see its comment) so it stays safe to
 * reuse anywhere privacy matters. The leaderboard's whole purpose is
 * to show nickname/country publicly, so it needs its own query rather
 * than weakening that guarantee.
 */
export async function getLeaderboardRawEntries(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<LeaderboardRawEntry[]> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  // FOUCH 0.3A: same current-version-only scoping as
  // getEligiblePredictionsForComparison above â€” a prediction with
  // several saved versions is still exactly one leaderboard entry
  // (brief Â§13), never one entry per version.
  const { data: predictions, error } = await supabase
    .from("predictions")
    .select("id, public_id, nickname, country_code, current_version_id")
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .eq("is_final", true)
    .not("current_version_id", "is", null);

  if (error || !predictions || predictions.length === 0) return [];

  const versionIds = predictions.map((p) => p.current_version_id as string);

  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("prediction_id, version_id, participant_id, predicted_position")
    .in("version_id", versionIds)
    .order("predicted_position", { ascending: true });

  if (itemsError || !items) return [];

  const itemsByPrediction = new Map<string, string[]>();
  for (const item of items) {
    const list = itemsByPrediction.get(item.prediction_id) ?? [];
    list.push(item.participant_id);
    itemsByPrediction.set(item.prediction_id, list);
  }

  const entries: LeaderboardRawEntry[] = [];
  for (const prediction of predictions) {
    const rankedParticipantIds = itemsByPrediction.get(prediction.id) ?? [];
    if (rankedParticipantIds.length === 10) {
      entries.push({
        predictionId: prediction.id,
        publicId: prediction.public_id,
        nickname: prediction.nickname,
        countryCode: prediction.country_code,
        rankedParticipantIds,
      });
    }
  }

  return entries;
}

/**
 * Experiment 01 ("Your Crowd Changed") â€” the leanest possible query for
 * this experiment: only each eligible prediction's submission time and
 * #1 (winner) pick, never the full 10-item ranking. Deliberately a
 * separate query rather than reusing getEligiblePredictionsForComparison
 * or getLeaderboardRawEntries â€” those fetch every item of every
 * prediction, which this experiment doesn't need at all.
 *
 * Eligibility mirrors both of those functions exactly: same event_slug,
 * same data_status, is_final = true, and (checked via the items query)
 * exactly 10 items â€” never a different population definition for the
 * same underlying concept of "an eligible prediction."
 */
export async function getWinnerPicksForConsensusChange(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<Array<{ predictionId: string; submittedAt: string; winnerParticipantId: string }>> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  // FOUCH 0.3A: `submitted_at` remains the prediction's ORIGINAL
  // submission time (predictions.submitted_at is never touched by an
  // edit â€” only prediction_versions.created_at records when each
  // version was saved). Experiment 01's semantics with an edited
  // winner pick are addressed separately below (brief Â§17) â€” this
  // function's contract (submission time + CURRENT winner pick) is
  // unchanged here on purpose.
  const { data: predictions, error } = await supabase
    .from("predictions")
    .select("id, submitted_at, current_version_id")
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .eq("is_final", true)
    .not("current_version_id", "is", null);

  if (error || !predictions || predictions.length === 0) return [];

  const versionIds = predictions.map((p) => p.current_version_id as string);

  // Only position 1 (the winner pick) â€” and only from predictions with
  // exactly 10 items, so a malformed/partial prediction never counts as
  // an eligible "winner pick" here either.
  const { data: allItems, error: itemsError } = await supabase
    .from("prediction_items")
    .select("prediction_id, version_id, participant_id, predicted_position")
    .in("version_id", versionIds);

  if (itemsError || !allItems) return [];

  const itemCountByPrediction = new Map<string, number>();
  const winnerByPrediction = new Map<string, string>();
  for (const item of allItems) {
    itemCountByPrediction.set(item.prediction_id, (itemCountByPrediction.get(item.prediction_id) ?? 0) + 1);
    if (item.predicted_position === 1) {
      winnerByPrediction.set(item.prediction_id, item.participant_id);
    }
  }

  const results: Array<{ predictionId: string; submittedAt: string; winnerParticipantId: string }> = [];
  for (const prediction of predictions) {
    const winner = winnerByPrediction.get(prediction.id);
    const itemCount = itemCountByPrediction.get(prediction.id) ?? 0;
    if (winner && itemCount === 10 && prediction.submitted_at) {
      results.push({
        predictionId: prediction.id,
        submittedAt: prediction.submitted_at,
        winnerParticipantId: winner,
      });
    }
  }

  return results;
}