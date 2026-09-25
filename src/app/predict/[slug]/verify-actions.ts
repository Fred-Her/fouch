"use server";

import { getEventBySlug } from "@/lib/events";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { validateSubmission } from "@/lib/prediction-validation";
import {
  insertPrediction,
  getDeviceTokenIdentity,
  getPredictionForEdit,
  createPredictionVersion,
  type InsertPredictionResult,
} from "@/lib/predictions-db";
import { isDeviceIdentityMismatch } from "@/lib/insert-conflict";
import { isAuthorizedToEdit } from "@/lib/prediction-version-logic";
import { normalizeEmail, isValidEmail } from "@/lib/email-validation";
import { getSupabaseAuthClient } from "@/lib/supabase/auth-client";

/**
 * Beta Hardening 0.2 Phase C â€” the verified-lock flow.
 *
 * GATE 1 + GATE 2 CLOSED: this file is wired into ReviewContent.tsx's
 * real Lock button, and the old `predictions_event_device_unique`
 * constraint has been dropped in production (migration 0006). See
 * FOUCH_BETA_HARDENING_02_PHASE_C.md for the completed cutover
 * procedure. device_token is now purely the soft, non-blocking signal
 * described in FOUCH_IDENTITY_ARCHITECTURE.md.
 */

export type StartVerificationResult = { success: true } | { success: false; error: string };

/**
 * Requests an OTP for the given email. Never reveals whether the
 * email already exists as a user, or already has a prediction for
 * this event â€” that check only happens AFTER verification succeeds
 * (see verifyEmailAndLockPrediction), specifically to avoid an
 * email-enumeration leak at this earlier, unauthenticated step.
 */
export async function startEmailVerification(email: string): Promise<StartVerificationResult> {
  const normalized = normalizeEmail(email);
  if (!isValidEmail(normalized)) {
    return { success: false, error: "That doesn't look like a valid email address." };
  }

  const supabase = getSupabaseAuthClient();
  if (!supabase) {
    return { success: false, error: "Verification isn't available right now — try again shortly." };
  }

  const { error } = await supabase.auth.signInWithOtp({
    email: normalized,
    options: { shouldCreateUser: true },
  });

  if (error) {
    // Supabase's own message here is already safe/generic (rate-limit,
    // transient failure) â€” never surface raw error internals, but no
    // need to further genericize what Supabase itself already returns
    // as a user-facing string.
    return { success: false, error: "We couldn't send a code — try again in a moment." };
  }

  return { success: true };
}

export interface LockPredictionPayload {
  eventSlug: string;
  participantIds: string[];
  nickname?: string;
  countryCode?: string;
  deviceToken: string;
}

export type VerifyAndLockFailureReason =
  | "invalid_code"
  | "expired_code"
  | "insert_failed"
  | "session_expired"
  | "validation_failed";

export type VerifyAndLockResult =
  | { success: true; publicId: string; duplicateDeviceSignal: boolean }
  | {
      success: false;
      error: string;
      failureReason: VerifyAndLockFailureReason;
      /** Present only when OTP verification itself succeeded but the
       * insert failed transiently â€” lets the client retry the lock
       * step alone, without a new OTP (frozen retry semantics). */
      accessToken?: string;
    };

/** Shared by verifyEmailAndLockPrediction and retryLockWithVerifiedSession
 * â€” re-validates the entire payload server-side (never weaker than the
 * existing anonymous submitPrediction() path) and attempts the insert
 * with the now-known auth_user_id. */
async function validateAndLock(
  authUserId: string,
  payload: LockPredictionPayload,
): Promise<VerifyAndLockResult> {
  const event = await getEventBySlug(payload.eventSlug);
  if (!event) {
    return { success: false, error: "This event doesn't exist.", failureReason: "validation_failed" };
  }

  const participantData = await getParticipantsForEvent(payload.eventSlug);
  if (!participantData) {
    return {
      success: false,
      error: "This event has no contestants configured.",
      failureReason: "validation_failed",
    };
  }

  const requiredCount = Math.min(10, participantData.participants.length);

  // FOUCH 0.3A: fetched fresh on every lock/edit attempt from
  // Supabase, the single authoritative source â€” never from
  // src/lib/events.ts, never from anything the client supplies.
  const lockConfig = await getEventLockConfig(payload.eventSlug);

  const validation = validateSubmission(
    { participantIds: payload.participantIds, nickname: payload.nickname, countryCode: payload.countryCode },
    event,
    participantData.participants,
    requiredCount,
    lockConfig,
  );

  if (!validation.valid) {
    return { success: false, error: validation.error, failureReason: "validation_failed" };
  }

  if (!payload.deviceToken || typeof payload.deviceToken !== "string") {
    return { success: false, error: "Missing device token.", failureReason: "validation_failed" };
  }

  // Soft signal only â€” computed BEFORE the insert (so it reflects
  // whoever already holds this device, if anyone), never blocks.
  const existingOnDevice = await getDeviceTokenIdentity(payload.eventSlug, payload.deviceToken);
  const duplicateDeviceSignal = isDeviceIdentityMismatch(existingOnDevice, {
    deviceToken: payload.deviceToken,
    authUserId,
  });

  let result: InsertPredictionResult;
  try {
    result = await insertPrediction({
      eventSlug: payload.eventSlug,
      participantIds: validation.data.participantIds,
      nickname: validation.data.nickname,
      countryCode: validation.data.countryCode,
      dataStatus: participantData.status,
      deviceToken: payload.deviceToken,
      authUserId,
    });
  } catch {
    return {
      success: false,
      error: "We couldn't lock your prediction. Your Top 10 is still saved — try again.",
      failureReason: "insert_failed",
    };
  }

  if (!result.success) {
    return { success: false, error: result.error, failureReason: "insert_failed" };
  }

  return { success: true, publicId: result.publicId, duplicateDeviceSignal };
}

/**
 * The main verified-lock entry point: verifies the OTP, then
 * immediately attempts the lock as the next step in the same
 * user-facing action â€” sequential, not one shared database
 * transaction (see FOUCH_IDENTITY_ARCHITECTURE.md).
 */
export async function verifyEmailAndLockPrediction(
  email: string,
  code: string,
  payload: LockPredictionPayload,
): Promise<VerifyAndLockResult> {
  const normalized = normalizeEmail(email);

  const supabase = getSupabaseAuthClient();
  if (!supabase) {
    return {
      success: false,
      error: "Verification isn't available right now — try again shortly.",
      failureReason: "invalid_code",
    };
  }

  const { data, error } = await supabase.auth.verifyOtp({
    email: normalized,
    token: code,
    type: "email",
  });

  if (error || !data.user) {
    const message = error?.message.toLowerCase() ?? "";
    const failureReason: VerifyAndLockFailureReason = message.includes("expired")
      ? "expired_code"
      : "invalid_code";
    const userMessage =
      failureReason === "expired_code"
        ? "That code expired."
        : "That code didn't match. Check your email and try again.";
    return { success: false, error: userMessage, failureReason };
  }

  const result = await validateAndLock(data.user.id, payload);

  // Only offer a no-new-OTP retry when verification itself succeeded
  // (we have a real session) but the LOCK step is what failed.
  if (!result.success && result.failureReason === "insert_failed" && data.session) {
    return { ...result, accessToken: data.session.access_token };
  }

  return result;
}

/**
 * Retries only the lock step after a transient insert failure,
 * reusing the access token obtained during the original OTP
 * verification â€” never requires a new code, per the frozen retry
 * semantics. Validates the token server-side via Supabase Auth itself
 * (getUser) rather than trusting anything the client asserts.
 */
export async function retryLockWithVerifiedSession(
  accessToken: string,
  payload: LockPredictionPayload,
): Promise<VerifyAndLockResult> {
  const supabase = getSupabaseAuthClient();
  if (!supabase) {
    return {
      success: false,
      error: "Verification isn't available right now — try again shortly.",
      failureReason: "session_expired",
    };
  }

  const { data, error } = await supabase.auth.getUser(accessToken);

  if (error || !data.user) {
    return {
      success: false,
      error: "Your verification expired — please request a new code.",
      failureReason: "session_expired",
    };
  }

  const result = await validateAndLock(data.user.id, payload);

  if (!result.success && result.failureReason === "insert_failed") {
    return { ...result, accessToken };
  }

  return result;
}

/* ------------------------------------------------------------------
 * FOUCH 0.3A â€” Editable Predictions.
 *
 * Deliberately mirrors the Lock flow above almost exactly: same
 * email â†’ OTP â†’ verify shape, same accessToken-based retry-without-
 * new-code semantics, because the identity architecture is frozen
 * (Beta Hardening 0.2 rules are unchanged, see brief Â§3). The only
 * new thing editing needs on top of that is OWNERSHIP authorization
 * â€” see validateAndEdit below.
 *
 * Legacy scope (explicit product decision, not inferred): a
 * prediction with auth_user_id = null has no verified identity to
 * authorize an edit against, and this sprint introduces no mechanism
 * to retroactively claim one via nickname, device_token, a
 * later-entered email, public_id, or anything else. Such predictions
 * remain fully public/readable/scoreable forever, exactly as today â€”
 * they are simply never editable. The UI never even offers "EDIT MY
 * TOP 10" for them (see PublicPredictionPage), but the server check
 * below is the actual authorization boundary, not the UI.
 * ------------------------------------------------------------------ */

export interface EditPredictionPayload {
  publicId: string;
  participantIds: string[];
  /** The version_number the client read just before opening the edit
   * builder â€” used as an optimistic-concurrency check, see
   * createPredictionVersion() in predictions-db.ts. */
  expectedVersionNumber: number;
}

export type VerifyAndEditFailureReason =
  | "invalid_code"
  | "expired_code"
  | "not_found"
  | "not_owner"
  | "locked"
  | "validation_failed"
  | "conflict"
  | "edit_failed"
  | "session_expired";

export type VerifyAndEditResult =
  | { success: true; publicId: string; versionNumber: number; unchanged: boolean }
  | {
      success: false;
      error: string;
      failureReason: VerifyAndEditFailureReason;
      /** Present only when OTP verification itself succeeded but the
       * save step failed transiently â€” lets the client retry the save
       * step alone, without a new OTP (same frozen retry semantics as
       * the lock flow). Never present for not_owner/locked/conflict â€”
       * those are never worth retrying with the same input. */
      accessToken?: string;
    };

/**
 * Shared by verifyEmailAndEditPrediction and
 * retryEditWithVerifiedSession. Every authorization and timing check
 * here is independent server-side state â€” nothing the client supplies
 * (publicId aside, which only selects WHICH prediction, never
 * authorizes anything on its own) is trusted for identity or timing.
 */
async function validateAndEdit(
  authUserId: string,
  payload: EditPredictionPayload,
): Promise<VerifyAndEditResult> {
  const editable = await getPredictionForEdit(payload.publicId);
  if (!editable) {
    return { success: false, error: "We couldn't find that prediction.", failureReason: "not_found" };
  }

  // The critical authorization check (brief Â§10-11, reconfirmed for
  // legacy scope): the verified auth_user_id from THIS session must
  // match the prediction's stored auth_user_id exactly. See
  // isAuthorizedToEdit's own doc for why this single, pure check is
  // the entire ownership rule â€” no nickname/device_token/public_id/
  // email-based claiming exists anywhere in this codebase.
  if (!isAuthorizedToEdit(editable.authUserId, authUserId)) {
    return {
      success: false,
      error: "This isn't your prediction.",
      failureReason: "not_owner",
    };
  }

  const event = await getEventBySlug(editable.eventSlug);
  if (!event) {
    return { success: false, error: "This event doesn't exist.", failureReason: "validation_failed" };
  }

  const participantData = await getParticipantsForEvent(editable.eventSlug);
  if (!participantData) {
    return {
      success: false,
      error: "This event has no contestants configured.",
      failureReason: "validation_failed",
    };
  }

  const requiredCount = Math.min(10, participantData.participants.length);

  // Re-fetched fresh, right now, from Supabase â€” the one and only
  // authoritative source. Never trust that the event was still open
  // when the edit page loaded; only whether it's open THIS instant.
  const lockConfig = await getEventLockConfig(editable.eventSlug);
  if (!isPredictionWindowOpen(lockConfig, Date.now())) {
    return {
      success: false,
      error: "Predictions for this event are locked.",
      failureReason: "locked",
    };
  }

  const validation = validateSubmission(
    { participantIds: payload.participantIds },
    event,
    participantData.participants,
    requiredCount,
    lockConfig,
  );

  if (!validation.valid) {
    return { success: false, error: validation.error, failureReason: "validation_failed" };
  }

  let result;
  try {
    result = await createPredictionVersion({
      predictionPublicId: editable.publicId,
      participantIds: validation.data.participantIds,
      expectedVersionNumber: payload.expectedVersionNumber,
      currentRankedParticipantIds: editable.currentRankedParticipantIds,
    });
  } catch {
    return {
      success: false,
      error: "We couldn't save your changes. Your Top 10 is still what it was — try again.",
      failureReason: "edit_failed",
    };
  }

  if (!result.success) {
    const failureReason: VerifyAndEditFailureReason = result.error.startsWith("Your prediction changed")
      ? "conflict"
      : "edit_failed";
    return { success: false, error: result.error, failureReason };
  }

  return {
    success: true,
    publicId: result.publicId,
    versionNumber: result.versionNumber,
    unchanged: result.unchanged,
  };
}

/**
 * The main verified-edit entry point â€” verifies the OTP, then
 * immediately attempts the edit as the next step in the same
 * user-facing action, exactly mirroring verifyEmailAndLockPrediction.
 */
export async function verifyEmailAndEditPrediction(
  email: string,
  code: string,
  payload: EditPredictionPayload,
): Promise<VerifyAndEditResult> {
  const normalized = normalizeEmail(email);

  const supabase = getSupabaseAuthClient();
  if (!supabase) {
    return {
      success: false,
      error: "Verification isn't available right now — try again shortly.",
      failureReason: "invalid_code",
    };
  }

  const { data, error } = await supabase.auth.verifyOtp({
    email: normalized,
    token: code,
    type: "email",
  });

  if (error || !data.user) {
    const message = error?.message.toLowerCase() ?? "";
    const failureReason: VerifyAndEditFailureReason = message.includes("expired")
      ? "expired_code"
      : "invalid_code";
    const userMessage =
      failureReason === "expired_code"
        ? "That code expired."
        : "That code didn't match. Check your email and try again.";
    return { success: false, error: userMessage, failureReason };
  }

  const result = await validateAndEdit(data.user.id, payload);

  // Only offer a no-new-OTP retry when verification itself succeeded
  // (we have a real session) but the SAVE step is what failed
  // transiently â€” never for not_owner/locked/conflict/validation,
  // none of which a bare retry with the same input would fix.
  if (!result.success && result.failureReason === "edit_failed" && data.session) {
    return { ...result, accessToken: data.session.access_token };
  }

  return result;
}

/**
 * Retries only the save step after a transient failure, reusing the
 * access token from the original OTP verification â€” mirrors
 * retryLockWithVerifiedSession exactly.
 */
export async function retryEditWithVerifiedSession(
  accessToken: string,
  payload: EditPredictionPayload,
): Promise<VerifyAndEditResult> {
  const supabase = getSupabaseAuthClient();
  if (!supabase) {
    return {
      success: false,
      error: "Verification isn't available right now — try again shortly.",
      failureReason: "session_expired",
    };
  }

  const { data, error } = await supabase.auth.getUser(accessToken);

  if (error || !data.user) {
    return {
      success: false,
      error: "Your verification expired — please request a new code.",
      failureReason: "session_expired",
    };
  }

  const result = await validateAndEdit(data.user.id, payload);

  if (!result.success && result.failureReason === "edit_failed") {
    return { ...result, accessToken };
  }

  return result;
}