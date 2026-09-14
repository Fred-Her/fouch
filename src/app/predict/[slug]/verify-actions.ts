"use server";

import { getEventBySlug } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { validateSubmission } from "@/lib/prediction-validation";
import {
  insertPrediction,
  getDeviceTokenIdentity,
  type InsertPredictionResult,
} from "@/lib/predictions-db";
import { isDeviceIdentityMismatch } from "@/lib/insert-conflict";
import { normalizeEmail, isValidEmail } from "@/lib/email-validation";
import { getSupabaseAuthClient } from "@/lib/supabase/auth-client";

/**
 * Beta Hardening 0.2 Phase C — the verified-lock flow.
 *
 * GATE 1 ONLY: this file is fully implemented and ready, but nothing
 * calls it from the live product yet, and the old
 * `predictions_event_device_unique` constraint has NOT been dropped
 * in production. Wiring this into ReviewContent.tsx's real Lock
 * button and dropping that old constraint are Gate 2 (founder-approved
 * cutover, deployed together) — see FOUCH_BETA_HARDENING_02_PHASE_C.md.
 */

export type StartVerificationResult = { success: true } | { success: false; error: string };

/**
 * Requests an OTP for the given email. Never reveals whether the
 * email already exists as a user, or already has a prediction for
 * this event — that check only happens AFTER verification succeeds
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
    // transient failure) — never surface raw error internals, but no
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
       * insert failed transiently — lets the client retry the lock
       * step alone, without a new OTP (frozen retry semantics). */
      accessToken?: string;
    };

/** Shared by verifyEmailAndLockPrediction and retryLockWithVerifiedSession
 * — re-validates the entire payload server-side (never weaker than the
 * existing anonymous submitPrediction() path) and attempts the insert
 * with the now-known auth_user_id. */
async function validateAndLock(
  authUserId: string,
  payload: LockPredictionPayload,
): Promise<VerifyAndLockResult> {
  const event = getEventBySlug(payload.eventSlug);
  if (!event) {
    return { success: false, error: "This event doesn't exist.", failureReason: "validation_failed" };
  }

  const participantData = getParticipantsForEvent(payload.eventSlug);
  if (!participantData) {
    return {
      success: false,
      error: "This event has no contestants configured.",
      failureReason: "validation_failed",
    };
  }

  const requiredCount = Math.min(10, participantData.participants.length);

  const validation = validateSubmission(
    { participantIds: payload.participantIds, nickname: payload.nickname, countryCode: payload.countryCode },
    event,
    participantData.participants,
    requiredCount,
  );

  if (!validation.valid) {
    return { success: false, error: validation.error, failureReason: "validation_failed" };
  }

  if (!payload.deviceToken || typeof payload.deviceToken !== "string") {
    return { success: false, error: "Missing device token.", failureReason: "validation_failed" };
  }

  // Soft signal only — computed BEFORE the insert (so it reflects
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
 * user-facing action — sequential, not one shared database
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
 * verification — never requires a new code, per the frozen retry
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