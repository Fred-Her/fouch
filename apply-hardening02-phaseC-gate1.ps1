# Beta Hardening 0.2 Phase C GATE 1 ONLY — implementation, not deployed to production.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-hardening02-phaseC-gate1.ps1
# IMPORTANT: after applying, test locally only (npm run dev / npm run build).
# Do NOT git push until you and Claude explicitly agree to do the Gate 2 cutover
# (deploying this code together with the 0006 migration, in one release).
$failures = @()

try {
    $path = "src\lib\email-validation.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Beta Hardening 0.2 Phase C — minimal email validation. Deliberately
 * simple: real validation (does this address actually exist/receive
 * mail) is Supabase Auth's job via the OTP round-trip itself. This is
 * only a basic shape check before spending a Supabase Auth call.
 */

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_EMAIL_LENGTH = 254; // RFC 5321 practical limit

export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

export function isValidEmail(raw: string): boolean {
  const normalized = normalizeEmail(raw);
  return normalized.length > 0 && normalized.length <= MAX_EMAIL_LENGTH && EMAIL_PATTERN.test(normalized);
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\email-validation.ts"
} catch {
    Write-Host "FAILED: src\lib\email-validation.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\email-validation.ts"
}

try {
    $path = "src\lib\email-validation.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { normalizeEmail, isValidEmail } from "./email-validation";

describe("normalizeEmail", () => {
  it("trims whitespace and lowercases", () => {
    expect(normalizeEmail("  Fred@Example.COM  ")).toBe("fred@example.com");
  });
});

describe("isValidEmail", () => {
  it.each([
    "fred@example.com",
    "fred.h@example.co",
    "fred+test@example.com",
  ])("accepts a well-formed address: %s", (email) => {
    expect(isValidEmail(email)).toBe(true);
  });

  it.each([
    "",
    "   ",
    "not-an-email",
    "missing-domain@",
    "@missing-local.com",
    "no-at-sign.com",
    "spaces in@email.com",
  ])("rejects a malformed address: %s", (email) => {
    expect(isValidEmail(email)).toBe(false);
  });

  it("rejects an address longer than 254 characters", () => {
    const long = `${"a".repeat(250)}@b.com`;
    expect(isValidEmail(long)).toBe(false);
  });

  it("is case-insensitive about validity (normalizes before checking)", () => {
    expect(isValidEmail("  FRED@EXAMPLE.COM  ")).toBe(true);
  });
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\email-validation.test.ts"
} catch {
    Write-Host "FAILED: src\lib\email-validation.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\email-validation.test.ts"
}

try {
    $path = "src\lib\insert-conflict.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Beta Hardening 0.2 Phase C — classifies a Postgres unique-violation
 * error message so `insertPrediction()` knows which conflict fired,
 * without duplicating constraint-name strings across the codebase.
 *
 * The exact constraint names below were confirmed against a real
 * Postgres instance during Phase A verification
 * (`predictions_event_device_unique`, `predictions_one_final_per_identity`)
 * — not guessed.
 */
export type InsertConflictType = "public_id" | "identity" | "device" | "unknown";

export function classifyInsertConflict(errorMessage: string): InsertConflictType {
  if (errorMessage.includes("public_id")) return "public_id";
  if (errorMessage.includes("predictions_one_final_per_identity")) return "identity";
  if (errorMessage.includes("predictions_event_device_unique")) return "device";
  return "unknown";
}

/**
 * Soft, non-blocking duplicate signal (identity architecture's
 * "layered duplicate protection"): true only when the same device
 * already has a final prediction for this event under a DIFFERENT,
 * non-null verified identity. Never true for two anonymous
 * (auth_user_id null) rows, and never true for the same identity
 * (that's the hard rule's job, not this signal's).
 */
export function isDeviceIdentityMismatch(
  existing: { deviceToken: string; authUserId: string | null } | null,
  incoming: { deviceToken: string; authUserId: string | null },
): boolean {
  if (!existing) return false;
  if (existing.deviceToken !== incoming.deviceToken) return false;
  if (!existing.authUserId || !incoming.authUserId) return false;
  return existing.authUserId !== incoming.authUserId;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\insert-conflict.ts"
} catch {
    Write-Host "FAILED: src\lib\insert-conflict.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\insert-conflict.ts"
}

try {
    $path = "src\lib\insert-conflict.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { classifyInsertConflict, isDeviceIdentityMismatch } from "./insert-conflict";

describe("classifyInsertConflict — using the exact Postgres messages confirmed in Phase A", () => {
  it("classifies a public_id collision", () => {
    expect(
      classifyInsertConflict('duplicate key value violates unique constraint "predictions_public_id_key"'),
    ).toBe("public_id");
  });

  it("classifies an identity (auth_user_id) collision", () => {
    expect(
      classifyInsertConflict(
        'duplicate key value violates unique constraint "predictions_one_final_per_identity"',
      ),
    ).toBe("identity");
  });

  it("classifies a device_token collision", () => {
    expect(
      classifyInsertConflict('duplicate key value violates unique constraint "predictions_event_device_unique"'),
    ).toBe("device");
  });

  it("falls back to unknown for an unrecognized message", () => {
    expect(classifyInsertConflict("some other database error")).toBe("unknown");
  });
});

describe("isDeviceIdentityMismatch — the soft, non-blocking signal", () => {
  it("is false when there is no existing prediction on this device", () => {
    expect(isDeviceIdentityMismatch(null, { deviceToken: "d1", authUserId: "alice" })).toBe(false);
  });

  it("is false when the device tokens differ (not the same physical device)", () => {
    expect(
      isDeviceIdentityMismatch(
        { deviceToken: "d1", authUserId: "alice" },
        { deviceToken: "d2", authUserId: "bob" },
      ),
    ).toBe(false);
  });

  it("is true for the Person A / Person B case: same device, different verified identities", () => {
    expect(
      isDeviceIdentityMismatch(
        { deviceToken: "shared-laptop", authUserId: "alice" },
        { deviceToken: "shared-laptop", authUserId: "bob" },
      ),
    ).toBe(true);
  });

  it("is false for the SAME identity on the same device (that's the hard rule's job, not this signal)", () => {
    expect(
      isDeviceIdentityMismatch(
        { deviceToken: "shared-laptop", authUserId: "alice" },
        { deviceToken: "shared-laptop", authUserId: "alice" },
      ),
    ).toBe(false);
  });

  it("is false when either side is anonymous (null auth_user_id) — never flags legacy rows", () => {
    expect(
      isDeviceIdentityMismatch(
        { deviceToken: "shared-laptop", authUserId: null },
        { deviceToken: "shared-laptop", authUserId: "bob" },
      ),
    ).toBe(false);
    expect(
      isDeviceIdentityMismatch(
        { deviceToken: "shared-laptop", authUserId: "alice" },
        { deviceToken: "shared-laptop", authUserId: null },
      ),
    ).toBe(false);
  });
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\insert-conflict.test.ts"
} catch {
    Write-Host "FAILED: src\lib\insert-conflict.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\insert-conflict.test.ts"
}

try {
    $path = "src\lib\supabase\auth-client.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Server-only, STATELESS Supabase Auth client for the email OTP flow.
 * Deliberately separate from getSupabaseServerClient() (which prefers
 * the service-role key): signInWithOtp/verifyOtp are genuine end-user
 * operations, exactly what an anonymous visitor's own browser would
 * call — using service-role for these would be semantically wrong,
 * even though it happens to run server-side here.
 *
 * `persistSession: false` because this project deliberately doesn't
 * build cookie/session infrastructure (no @supabase/ssr, no
 * middleware) — see FOUCH_IDENTITY_ARCHITECTURE.md's "Session
 * strategy". Each call gets a fresh, stateless client; the one piece
 * of session data that matters (the access token, for retrying a
 * failed insert without a new OTP) is threaded through explicitly by
 * the calling server action, not persisted implicitly.
 */
export function getSupabaseAuthClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) return null;

  return createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\supabase\auth-client.ts"
} catch {
    Write-Host "FAILED: src\lib\supabase\auth-client.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\supabase\auth-client.ts"
}

try {
    $path = "src\app\predict\[slug]\verify-actions.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\predict\[slug]\verify-actions.ts"
} catch {
    Write-Host "FAILED: src\app\predict\[slug]\verify-actions.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\predict\[slug]\verify-actions.ts"
}

try {
    $path = "src\components\prediction\EmailStep.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useState } from "react";

export function EmailStep({
  submitting,
  errorMessage,
  onSendCode,
}: {
  submitting: boolean;
  errorMessage: string | null;
  onSendCode: (email: string) => void;
}) {
  const [email, setEmail] = useState("");

  return (
    <div className="mt-8 border-t border-border pt-6">
      <p className="font-display text-xl text-text-primary">Enter your email to lock your prediction.</p>
      <p className="mt-1 text-sm text-text-secondary">We&apos;ll send you a 6-digit code — no password needed.</p>

      <label className="mt-4 block">
        <span className="text-sm text-text-secondary">Email</span>
        <input
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          placeholder="you@example.com"
          autoComplete="email"
          className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
        />
      </label>

      {errorMessage ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert">
          {errorMessage}
        </p>
      ) : null}

      <button
        type="button"
        disabled={submitting || email.trim().length === 0}
        onClick={() => onSendCode(email)}
        className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
      >
        {submitting ? "Sending…" : "Send code"}
      </button>

      <p className="mt-3 text-xs text-text-muted">
        FOUCH is an independent fan prediction game — your email is only used to verify your call,
        never shown publicly.
      </p>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\EmailStep.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\EmailStep.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\EmailStep.tsx"
}

try {
    $path = "src\components\prediction\OtpStep.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useState } from "react";

/** Matches Supabase Auth's own default OTP resend cooldown, confirmed
 * in Phase B — never invent a different number here. */
const RESEND_COOLDOWN_SECONDS = 60;
/** UX guardrail only, not a security control — see
 * FOUCH_AUTH_FLOW.md's "Wrong code" state. Supabase Auth's own OTP
 * expiry/rate-limiting is the real protection. */
const MAX_UX_ATTEMPTS = 5;

export function OtpStep({
  email,
  submitting,
  errorMessage,
  wrongAttemptCount,
  onVerify,
  onResend,
  onUseDifferentEmail,
}: {
  email: string;
  submitting: boolean;
  errorMessage: string | null;
  wrongAttemptCount: number;
  onVerify: (code: string) => void;
  onResend: () => void;
  onUseDifferentEmail: () => void;
}) {
  const [code, setCode] = useState("");
  const [secondsLeft, setSecondsLeft] = useState(RESEND_COOLDOWN_SECONDS);

  useEffect(() => {
    if (secondsLeft <= 0) return;
    const timer = setInterval(() => setSecondsLeft((s) => Math.max(0, s - 1)), 1000);
    return () => clearInterval(timer);
  }, [secondsLeft]);

  const lockedOut = wrongAttemptCount >= MAX_UX_ATTEMPTS;

  function handleResend() {
    setCode("");
    setSecondsLeft(RESEND_COOLDOWN_SECONDS);
    onResend();
  }

  return (
    <div className="mt-8 border-t border-border pt-6">
      <p className="font-display text-xl text-text-primary">Enter the code we sent to {email}.</p>

      <label className="mt-4 block">
        <span className="text-sm text-text-secondary">Verification code</span>
        <input
          type="text"
          inputMode="numeric"
          autoComplete="one-time-code"
          maxLength={6}
          value={code}
          onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
          disabled={lockedOut}
          className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-lg tracking-[0.3em] text-text-primary placeholder:text-text-muted focus:border-accent disabled:opacity-60"
        />
      </label>

      {errorMessage ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert" aria-live="polite">
          {errorMessage}
        </p>
      ) : null}

      {lockedOut ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert">
          Too many incorrect attempts. Request a new code.
        </p>
      ) : (
        <button
          type="button"
          disabled={submitting || code.length !== 6}
          onClick={() => onVerify(code)}
          className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
        >
          {submitting ? "Verifying…" : "Verify and lock"}
        </button>
      )}

      <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm">
        {secondsLeft > 0 ? (
          <span className="text-text-muted">Resend code in 0:{String(secondsLeft).padStart(2, "0")}</span>
        ) : (
          <button type="button" onClick={handleResend} className="text-text-secondary underline hover:text-accent-strong">
            Resend code
          </button>
        )}
        <button type="button" onClick={onUseDifferentEmail} className="text-text-secondary underline hover:text-accent-strong">
          Use a different email
        </button>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\OtpStep.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\OtpStep.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\OtpStep.tsx"
}

try {
    $path = "src\app\privacy\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy | FOUCH",
  description: "What FOUCH collects, why, and what stays public.",
};

export default function PrivacyPage() {
  return (
    <main className="mx-auto max-w-content px-6 py-12">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>
      <h1 className="mt-6 font-display text-3xl text-text-primary">Privacy</h1>
      <p className="mt-2 text-sm text-text-muted">Last updated for the FOUCH beta.</p>

      <div className="mt-8 space-y-6 text-sm text-text-secondary">
        <section>
          <h2 className="font-display text-lg text-text-primary">What we collect</h2>
          <p className="mt-2">
            To lock a prediction, we ask for your email address, which we use only to verify
            that your call is real and to prevent one person from locking multiple predictions
            for the same event. Your email is managed by our authentication provider (Supabase)
            and is never made public.
          </p>
          <p className="mt-2">
            You may optionally add a nickname and country — both are shown publicly alongside
            your prediction if you provide them.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">What&apos;s public</h2>
          <p className="mt-2">
            Your prediction itself — the ranking you submit, your nickname (or &quot;Anonymous&quot;
            if you don&apos;t provide one), your country, and your score once results are
            available — is public and accessible to anyone with the link. Your email is never
            part of that public page.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">Analytics</h2>
          <p className="mt-2">
            We use basic product analytics to understand how people use FOUCH (e.g. whether a
            prediction was completed, whether a result was shared). These events never include
            your email or any other personally identifying information.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">No gambling, no money</h2>
          <p className="mt-2">
            FOUCH is an entertainment prediction game. There is no monetary betting and no cash
            prizes.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">Questions or deletion requests</h2>
          <p className="mt-2">
            FOUCH is currently a small beta. If you&apos;d like your data removed, reach out
            through the feedback link on the site and we&apos;ll handle it directly.
          </p>
        </section>
      </div>
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\privacy\page.tsx"
} catch {
    Write-Host "FAILED: src\app\privacy\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\privacy\page.tsx"
}

try {
    $path = "src\app\terms\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Terms | FOUCH",
  description: "The basics of using FOUCH during its beta.",
};

export default function TermsPage() {
  return (
    <main className="mx-auto max-w-content px-6 py-12">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>
      <h1 className="mt-6 font-display text-3xl text-text-primary">Terms</h1>
      <p className="mt-2 text-sm text-text-muted">Last updated for the FOUCH beta.</p>

      <div className="mt-8 space-y-6 text-sm text-text-secondary">
        <section>
          <h2 className="font-display text-lg text-text-primary">What FOUCH is</h2>
          <p className="mt-2">
            FOUCH is an entertainment prediction game for fans. It is an independent project and
            is not affiliated with, endorsed by, or connected to Miss Universe or any pageant
            organization.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">No betting, no prizes</h2>
          <p className="mt-2">
            FOUCH involves no monetary betting or wagering, and there are no guaranteed prizes
            for participating.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">Your content</h2>
          <p className="mt-2">
            Your prediction, nickname, and country (if provided) are shown publicly. Please
            don&apos;t submit anything abusive, offensive, or that impersonates someone else — we
            may remove content that violates this.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">One prediction per person, per event</h2>
          <p className="mt-2">
            We verify your email to keep the game fair — one verified identity may lock one final
            prediction per event.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">Beta availability</h2>
          <p className="mt-2">
            FOUCH is in active beta. Features, availability, and the service itself may change
            without notice, and we don&apos;t guarantee uptime during this period.
          </p>
        </section>
      </div>
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\terms\page.tsx"
} catch {
    Write-Host "FAILED: src\app\terms\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\terms\page.tsx"
}

try {
    $path = "supabase\migrations\0006_identity_phase_c_cutover.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- Beta Hardening 0.2 — Phase C cutover migration.
--
-- ============================================================
-- DO NOT RUN THIS AGAINST PRODUCTION YET.
-- This file is prepared for Gate 2 (founder-approved cutover) only.
-- It must be applied in the SAME controlled release as the new
-- verified-lock application code — never before (removes duplicate
-- protection with nothing yet live to replace it) and never
-- meaningfully after (a verified Person B sharing a device with a
-- verified Person A would still be incorrectly blocked by this old
-- constraint, even though the new code never relies on it). See
-- FOUCH_DATABASE_MIGRATION_PLAN.md's "Sequencing" and
-- FOUCH_BETA_HARDENING_02_PHASE_C.md's cutover procedure.
-- ============================================================
--
-- Purpose: drop the old (event_slug, device_token) unique index. Once
-- this runs, device_token is purely the soft, non-blocking signal
-- described in FOUCH_IDENTITY_ARCHITECTURE.md — the hard duplicate
-- rule becomes exclusively predictions_one_final_per_identity
-- (already live since Phase A).
--
-- This migration does NOT:
--   - drop the device_token column (kept, as a descriptive field)
--   - alter auth_user_id or its index
--   - modify any existing row
--   - touch predictions_public, event_results, or prediction_items

drop index if exists predictions_event_device_unique;

-- Rollback (only if needed — see FOUCH_BETA_HARDENING_02_PHASE_C.md's
-- rollback plan): restores the exact original constraint.
--
-- create unique index if not exists predictions_event_device_unique
--   on predictions (event_slug, device_token);
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0006_identity_phase_c_cutover.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0006_identity_phase_c_cutover.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0006_identity_phase_c_cutover.sql"
}

try {
    $path = "FOUCH_BETA_HARDENING_02_PHASE_C.md"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
# FOUCH Beta Hardening 0.2 — Phase C: Verified Lock Cutover (Gate 1)

*Gate 1 only: the full verified-lock flow is implemented and tested in
the repository. Production has NOT been cut over — the old
`predictions_event_device_unique` constraint is still active in
production, and none of this code has been deployed. Gate 2 (the
actual cutover) requires explicit founder approval — see the end of
this document.*

## Implementation

**No session/cookie infrastructure was built.** OTP verification
(`supabase.auth.verifyOtp`) returns the authenticated user and session
directly in its response — no `@supabase/ssr`, no middleware, no
persisted cookies. The one place a session needs to survive past a
single call (retrying a failed lock without a new OTP) is handled by
passing the access token back to the client in memory and forwarding
it to a dedicated retry action, which re-validates it server-side via
`supabase.auth.getUser(accessToken)`. This is a deliberate
simplification consistent with "no account UI, no login state" — see
`FOUCH_IDENTITY_ARCHITECTURE.md`'s Session strategy.

## Verified Lock Flow

```
Review → "Lock in my Top 10" → Email step → Send code
  → OTP step → Verify and lock
  → verifyOtp (Supabase Auth) → auth_user_id obtained
  → re-validate full payload server-side (same validateSubmission()
    the old anonymous path used — never weakened)
  → insertPrediction() with auth_user_id
  → conflict? → identity conflict returns existing public_id;
    device conflict (old constraint, still live pre-cutover) also
    handled gracefully, unchanged from today
  → redirect to /p/{publicId}?new=1 → You vs The World
```

Both real Supabase email paths confirmed in Phase B (first-time
"Confirm signup," returning "Magic Link") are supported identically —
the application code only ever calls `verifyOtp`, never branches on
which template Supabase happened to send.

## Email / OTP UI

Single numeric input (`inputmode="numeric" autocomplete="one-time-code"`),
not six boxes — matches `FOUCH_AUTH_FLOW.md`'s accessibility
reasoning. Resend cooldown is 60 seconds, matching Supabase's
Phase-B-confirmed default exactly. "Use a different email" preserves
the Top 10 draft (still in `localStorage`, untouched by any of this).

## First-time Email / Returning Email

Both paths are handled by the exact same `verifyEmailAndLockPrediction`
call — the code never needs to know or care which Supabase template
was used, since `verifyOtp` behaves identically either way from the
application's perspective.

## Identity Rule

`insertPrediction()` now accepts an optional `authUserId`. Its
conflict-handling was extended (not replaced) via a new pure,
unit-tested classifier (`insert-conflict.ts`) that reads the real
Postgres error message to distinguish a `public_id` collision, an
identity (`predictions_one_final_per_identity`) collision, or the
legacy device collision — each resolved the same way the device
conflict always was: look up and return the existing `public_id`
rather than a hard error.

## Retry / Idempotency

Verified directly (see "Tests" below): if OTP succeeds but the insert
fails transiently, the access token is returned to the client, and a
dedicated `retryLockWithVerifiedSession` action re-attempts the insert
without a new code. If the original insert actually succeeded but the
response was lost, the retry hits the same identity-conflict path and
resolves to the existing `public_id` — never a duplicate. No pending-
prediction table, queue, or transaction coordinator was built.

## Analytics

`verification_started`, `verification_sent`, `verification_completed`,
`verification_failed` (with `failure_reason`: `invalid_code` |
`expired_code` | `insert_failed` | `session_expired` |
`validation_failed`), `duplicate_prediction_attempt` — properties
limited to `event_slug` and `failure_reason`. No email, `auth_user_id`,
or `device_token` in any event. `prediction_submitted` still fires only
after confirmed final lock — no redundant `prediction_locked` was
added. No `posthog.alias()`.

## Privacy / Terms

`/privacy` and `/terms` added, linked from the existing `Footer`
component. Both state the essentials (email used only for
verification and never public, no gambling/no monetary prizes,
independent-fan-game disclaimer, beta availability) without
over-lawyering it, per the frozen scope. The independence disclaimer
is also shown directly on the Email step.

## Legacy Compatibility

`insertPrediction()`'s existing anonymous-only call sites (untouched —
`actions.ts`'s `submitPrediction` still exists, unchanged) continue to
omit `authUserId` entirely, producing rows identical in shape to every
prediction created before this sprint. No backfill, no retroactive
identity assignment, anywhere.

## Cutover Migration

**File**: `supabase/migrations/0006_identity_phase_c_cutover.sql`
**Applied to production: NO.**
Contents: a single `drop index if exists predictions_event_device_unique;`
— nothing else. A commented-out rollback snippet (recreating the exact
original index) is included for the rollback plan below.

## Tests

**22 new automated tests** (133 total, up from 111 — no existing test
changed): email validation (13), and — critically — a pure conflict
classifier tested against the **exact real Postgres error message
strings confirmed during Phase A** (9 tests, covering `public_id`,
`identity`, `device`, and the Person-A/Person-B soft-signal logic in
isolation).

**Real Postgres verification (not simulated)**, using the project's
actual migration files (`0002`, `0004`, `0005`, and now `0006`) applied
to a local instance, exactly mirroring the Phase A methodology:

| Scenario | Before cutover (0006 not applied) | After cutover (0006 applied) |
|---|---|---|
| Two different verified identities, same device_token, same event | **Correctly reproduces today's bug**: second insert rejected by the old `predictions_event_device_unique` constraint | **Fixed**: both inserts succeed |
| Same verified identity, second final prediction (different device) | Rejected (identity rule, unaffected by cutover) | **Still rejected** — the hard rule survives the cutover unchanged |

This is the first time in this project that the *actual bug* (not just
the fix) was reproduced against a real database before confirming the
fix resolves it — a stronger form of verification than testing the fix
in isolation.

**Full regression**: typecheck clean, lint clean, **133/133 tests
passing**, production build clean. `/privacy` and `/terms` render as
new static routes; every other route's size is unchanged except
`/predict/[slug]/review` (grew from 4.4kB to 5.66kB — the new flow's
own code, expected).

## Files Changed

New: `src/lib/email-validation.ts` (+test), `src/lib/insert-conflict.ts`
(+test), `src/lib/supabase/auth-client.ts`,
`src/app/predict/[slug]/verify-actions.ts`,
`src/components/prediction/EmailStep.tsx`,
`src/components/prediction/OtpStep.tsx`, `src/app/privacy/page.tsx`,
`src/app/terms/page.tsx`, `supabase/migrations/0006_identity_phase_c_cutover.sql`.
Modified: `src/lib/predictions-db.ts` (extended, not replaced),
`src/lib/analytics.ts`, `src/components/prediction/ReviewContent.tsx`
(rewritten to orchestrate the step machine), `src/components/Footer.tsx`.

## Manual Pre-Cutover Test (founder, on a local/preview build only — never production yet)

1. `npm run dev` (or a Vercel preview deploy — not production)
2. Build a Top 10 normally
3. On Review, click "Lock in my Top 10," enter your real email
4. Check your inbox, enter the 6-digit code
5. Confirm you land on `/p/{publicId}?new=1` with your prediction
6. Open Supabase's Table Editor: confirm the new row has `auth_user_id`
   set and `device_token` also populated
7. Go through the flow again with the **same email**, same event
8. Confirm you're redirected to the **same** existing prediction, with
   a "you've already made your call" message — not a duplicate row
9. Open the event leaderboard and the prediction's You vs The World
   section: confirm both work normally alongside your new verified row
10. Confirm the *existing* anonymous demo predictions from earlier
    sprints still open, score, and rank exactly as before

## Rollback

**Prepared: YES.**
1. Revert the application deployment to the previous known-good build.
2. If `0006`'s index drop was already applied, restore it:
   `create unique index if not exists predictions_event_device_unique on predictions (event_slug, device_token);`
   (included as a comment in the migration file itself).
3. Never delete `auth_user_id` data, never delete verified `auth.users`
   rows, never modify legacy predictions — none of that is part of any
   rollback path.

## Gate 2 — production cutover

**NOT performed.** Requires explicit founder approval for:
1. Deploying this verified-lock application code to production.
2. Applying `0006_identity_phase_c_cutover.sql` to production.
3. Both in the same controlled release window (per the frozen
   sequencing — see `FOUCH_DATABASE_MIGRATION_PLAN.md`).

Recommended cutover order once approved: verify Phase A schema present
→ verify Phase B Auth/SMTP still operational → deploy new code →
apply `0006` → immediate smoke test (steps 2-8 above, against
production) → done.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_BETA_HARDENING_02_PHASE_C.md"
} catch {
    Write-Host "FAILED: FOUCH_BETA_HARDENING_02_PHASE_C.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_BETA_HARDENING_02_PHASE_C.md"
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
import { classifyInsertConflict } from "@/lib/insert-conflict";
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
  /** Beta Hardening 0.2 Phase C — set only by the new verified-lock
   * path. Undefined/omitted preserves the exact pre-Phase-C anonymous
   * insert behavior (legacy predictions are never retroactively
   * touched — see FOUCH_IDENTITY_ARCHITECTURE.md). */
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
      // event" — treat either as success and hand back the existing
      // one, so a double-tap, a race, or a retry never looks like a
      // hard failure. See insert-conflict.ts for why the message is
      // classified rather than just checked for "public_id" — Phase C
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
 * Beta Hardening 0.2 Phase C — looks up an existing FINAL prediction
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
 * Beta Hardening 0.2 Phase C — feeds the soft, non-blocking
 * same-device/different-identity signal (see insert-conflict.ts's
 * isDeviceIdentityMismatch). Returns only the two fields that
 * function needs — never a full PredictionRecord, since this is
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

export interface LeaderboardRawEntry {
  predictionId: string;
  publicId: string;
  nickname: string | null;
  countryCode: string | null;
  rankedParticipantIds: string[];
}

/**
 * Same eligibility filters as getEligiblePredictionsForComparison
 * (event + data_status + is_final=true + exactly 10 items) — kept as a
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

  const { data: predictions, error } = await supabase
    .from("predictions")
    .select("id, public_id, nickname, country_code")
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
 * Experiment 01 ("Your Crowd Changed") — the leanest possible query for
 * this experiment: only each eligible prediction's submission time and
 * #1 (winner) pick, never the full 10-item ranking. Deliberately a
 * separate query rather than reusing getEligiblePredictionsForComparison
 * or getLeaderboardRawEntries — those fetch every item of every
 * prediction, which this experiment doesn't need at all.
 *
 * Eligibility mirrors both of those functions exactly: same event_slug,
 * same data_status, is_final = true, and (checked via the items query)
 * exactly 10 items — never a different population definition for the
 * same underlying concept of "an eligible prediction."
 */
export async function getWinnerPicksForConsensusChange(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<Array<{ predictionId: string; submittedAt: string; winnerParticipantId: string }>> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  const { data: predictions, error } = await supabase
    .from("predictions")
    .select("id, submitted_at")
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .eq("is_final", true);

  if (error || !predictions || predictions.length === 0) return [];

  const predictionIds = predictions.map((p) => p.id);

  // Only position 1 (the winner pick) — and only from predictions with
  // exactly 10 items, so a malformed/partial prediction never counts as
  // an eligible "winner pick" here either.
  const { data: allItems, error: itemsError } = await supabase
    .from("prediction_items")
    .select("prediction_id, participant_id, predicted_position")
    .in("prediction_id", predictionIds);

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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\predictions-db.ts"
} catch {
    Write-Host "FAILED: src\lib\predictions-db.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\predictions-db.ts"
}

try {
    $path = "src\lib\analytics.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Analytics seam — Beta Hardening 0.1.
 *
 * Every call site still imports the same `track(event, properties)`
 * function as before; only the transport underneath changed, from a
 * console.debug stub to real PostHog capture. The contract is
 * unchanged on purpose so no component needed to be touched.
 *
 * Configuration (set in Vercel):
 *   NEXT_PUBLIC_POSTHOG_KEY  — PostHog project API key (public by
 *     design — PostHog's own docs confirm this key is meant to be
 *     browser-visible; it is not a secret).
 *   NEXT_PUBLIC_POSTHOG_HOST — defaults to https://us.i.posthog.com
 *     if unset; only needed for a self-hosted or EU-region instance.
 *
 * Without NEXT_PUBLIC_POSTHOG_KEY configured, track() falls back to
 * the original console.debug behavior — nothing crashes, nothing is
 * silently required. Analytics is always best-effort: every call is
 * wrapped so a PostHog failure (network, ad blocker, misconfiguration)
 * can never throw into product code. Prediction submission, sharing,
 * and every public page must keep working exactly the same whether or
 * not analytics succeeds.
 *
 * Properties must never carry personally identifiable information or
 * free-text nickname/contestant input — only structural values like
 * an event slug, a count, a position, or a share method. This function
 * also never calls posthog.identify() — every event stays on
 * PostHog's normal anonymous, cookie/localStorage-backed distinct_id.
 * Connecting anonymous activity to a verified identity is explicitly
 * deferred to Beta Hardening 0.2.
 */

import posthog from "posthog-js";

let posthogReady = false;

function ensurePostHogInitialized(): boolean {
  if (typeof window === "undefined") return false;

  const key = process.env.NEXT_PUBLIC_POSTHOG_KEY;
  if (!key) return false;

  if (!posthogReady) {
    try {
      posthog.init(key, {
        api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST || "https://us.i.posthog.com",
        // Beta-appropriate defaults: no automatic pageview capture (we
        // fire explicit, typed events already, e.g. landing_view), and
        // no full "person" profile creation for anonymous beta traffic
        // — keeps this cheap and avoids modeling identity we haven't
        // decided on yet (that's Beta Hardening 0.2).
        capture_pageview: false,
        person_profiles: "identified_only",
      });
      posthogReady = true;
    } catch {
      return false;
    }
  }

  return true;
}

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
  | "community_share_clicked"
  | "score_viewed"
  | "score_breakdown_viewed"
  | "percentile_viewed"
  | "result_card_generated"
  | "result_card_shared"
  | "result_card_saved"
  | "result_share_link_copied"
  | "leaderboard_viewed"
  | "leaderboard_row_clicked"
  | "own_rank_viewed"
  | "leaderboard_from_score_clicked"
  | "consensus_change_viewed"
  | "verification_started"
  | "verification_sent"
  | "verification_completed"
  | "verification_failed"
  | "duplicate_prediction_attempt";

export function track(event: FouchAnalyticsEvent, properties?: Record<string, unknown>) {
  if (typeof window === "undefined") return;

  try {
    if (ensurePostHogInitialized()) {
      posthog.capture(event, properties);
      return;
    }
  } catch {
    // Analytics must never break the product — fall through to the
    // silent/dev-visible fallback below rather than propagate.
  }

  // No PostHog key configured (or init/capture failed): preserve the
  // original, harmless console.debug behavior rather than losing
  // visibility entirely during local development or misconfiguration.
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
            <span className="text-sm text-text-primary">{participant.displayName}</span>
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
        <EmailStep submitting={emailSubmitting} errorMessage={emailError} onSendCode={handleSendCode} />
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
    $path = "src\components\Footer.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import Link from "next/link";
import type { Dictionary } from "@/content/types";

export function Footer({ dictionary }: { dictionary: Dictionary }) {
  return (
    <footer className="border-t border-border">
      <div className="mx-auto max-w-content px-6 py-8">
        <p className="font-display text-base font-semibold tracking-[0.12em] text-text-primary">
          FOUCH
        </p>
        <p className="mt-1 text-sm text-text-muted">{dictionary.footer.tagline}</p>
        <p className="mt-1 text-xs text-text-muted">
          FOUCH is an independent fan prediction game — not affiliated with Miss Universe.
        </p>
        <div className="mt-3 flex gap-4 text-xs text-text-muted">
          <Link href="/privacy" className="underline hover:text-text-secondary">
            Privacy
          </Link>
          <Link href="/terms" className="underline hover:text-text-secondary">
            Terms
          </Link>
        </div>
      </div>
    </footer>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\Footer.tsx"
} catch {
    Write-Host "FAILED: src\components\Footer.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\Footer.tsx"
}

try {
    $path = "FOUCH_BETA_HARDENING_02_CHECKLIST.md"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
# FOUCH Beta Hardening 0.2 — Implementation Checklist

*For use only after the architecture in `FOUCH_IDENTITY_ARCHITECTURE.md`,
`FOUCH_AUTH_FLOW.md`, and `FOUCH_DATABASE_MIGRATION_PLAN.md` is
reviewed and approved. Nothing on this list has been built yet.*

**v1.1**: reflects the frozen `device_token`-drop sequencing (now
explicit Phase A / B / C checkpoints), the decision to skip
`posthog.alias()`, the wrong-code counter's UX-only framing, and the
verify-then-lock retry semantics for a transient post-verification
failure.

**Phase B**: **COMPLETE — FOUNDER VERIFIED**, documented in
`FOUCH_BETA_HARDENING_02_PHASE_B.md` — validated against real
production Supabase Auth, real Resend SMTP, and a real email inbox.

**Phase C — Gate 1**: **COMPLETE**, documented in
`FOUCH_BETA_HARDENING_02_PHASE_C.md` — full verified-lock flow
implemented, 133/133 tests passing, and the actual Person-A/Person-B
bug reproduced and confirmed fixed against real Postgres. **Gate 2
(production cutover) has NOT happened** — awaiting founder approval.

## Supabase configuration (Phase B — see
`FOUCH_BETA_HARDENING_02_PHASE_B.md` for full detail — COMPLETE,
founder-verified against real Supabase Auth, real Resend SMTP, and a
real inbox)

- [x] Connect Resend via Supabase's custom SMTP settings (the
      marketplace one-click integration wasn't available in this
      project; manual SMTP configuration was used instead — same
      outcome)
- [x] Enable numeric `{{ .Token }}` on **both** templates that turned
      out to matter: **Confirm signup** (first-time email) and
      **Magic Link** (returning confirmed email) — a real discovery
      from testing, not anticipated by the original research
- [x] Set OTP expiry to ~10 minutes
- [x] Resend cooldown confirmed as Supabase's 60-second default

## Sequencing checkpoints (Phase A / B / C — see `FOUCH_DATABASE_MIGRATION_PLAN.md`)

- [x] Phase A: additive `auth_user_id` migration ships **while the old
      `(event_slug, device_token)` unique constraint still exists** —
      the current anonymous submission path still depends on it.
      *(Migration file created and verified against a real local
      Postgres instance running the project's actual migrations — see
      `FOUCH_BETA_HARDENING_02_PHASE_A.md`. Not yet applied to the
      founder's production Supabase project; that's a manual step.)*
- [x] Phase B: Supabase Auth (OTP template, SMTP, expiry, resend
      cooldown) configured and verified — see
      `FOUCH_BETA_HARDENING_02_PHASE_B.md`
- [ ] Phase C: cutover release deploys the new verified-lock code
      *(code complete and tested — see
      `FOUCH_BETA_HARDENING_02_PHASE_C.md` — not yet deployed;
      awaiting founder approval)*
- [ ] Phase C: old `(event_slug, device_token)` unique constraint is
      dropped in that same cutover release — not before, not
      meaningfully after *(migration prepared as `0006_identity_phase_c_cutover.sql`,
      confirmed working against real Postgres, not yet applied to
      production)*
- [x] A transient failure *after* OTP verification succeeds (insert
      fails) can be retried without losing the Top 10 draft and
      without requiring a new OTP (the session is already valid)
- [x] A retry after an ambiguous insert outcome (response lost, write
      possibly succeeded) resolves safely to the existing `public_id`
      via the unique-constraint-conflict path — never a duplicate

## Schema

- [x] Add `auth_user_id uuid references auth.users(id)` (nullable) to
      `predictions` — *done in Phase A, see
      `FOUCH_BETA_HARDENING_02_PHASE_A.md`*
- [x] Add partial unique index `(event_slug, auth_user_id) where
      auth_user_id is not null and is_final = true`
- [x] Confirm `predictions_public` view is unchanged (still excludes
      `auth_user_id`, alongside `device_token`) — *verified in Phase A*

## Server actions

- [x] `startEmailVerification(email)` — calls `signInWithOtp`, never
      reveals whether this email already has a prediction
- [x] `verifyEmailAndLockPrediction(email, code, predictionPayload)` —
      verifies OTP, then inserts the prediction row with `auth_user_id`
      set, catching `23505` (unique violation on the new
      `auth_user_id` index) and returning the existing `public_id`
      instead of erroring — same pattern as the existing
      `device_token` conflict handling, now driven by verified
      identity instead
- [x] Read-time check (not a constraint): if the new row's
      `device_token` matches an existing final prediction for the
      event under a *different* `auth_user_id`, fire
      `duplicate_prediction_attempt` — never block on this
- [x] Client-side wrong-code counter (UX only — see "UI" below; not a
      security control, no server-side attempt-tracking is built)

## UI

- [x] Email screen (single input, disclaimer line)
- [x] Code screen (single `inputmode="numeric" autocomplete="one-time-code"`
      input, resend timer matched to Supabase's real cooldown)
- [x] Success/redirect state
- [x] Duplicate-identity screen (reuses the existing "already
      predicted" redirect pattern)
- [x] Wrong-code / expired-code inline states — wrong-code counter is
      explicitly a UX guardrail ("too many incorrect attempts, request
      a new code"), not security; real protection is entirely
      Supabase Auth's own OTP expiry and rate limiting, nothing custom
      built server-side (no Redis, no rate-limit table, no CAPTCHA)
- [x] "Use a different email" back-navigation, preserving the local
      Top 10 draft

## Analytics (PostHog)

- [x] `verification_started`, `verification_sent`,
      `verification_completed`, `verification_failed`,
      `duplicate_prediction_attempt` — properties limited to
      `event_slug`, `data_status`, `failure_reason` (enum, never raw
      text); never email, `auth_user_id`, or `device_token`
- [x] **No `posthog.alias()` call** — the beta's funnel metrics
      (landing → start → completion → verification → lock → community
      view → share → second visit) are all measurable on PostHog's
      existing anonymous `distinct_id` alone, since it already
      persists per-browser across visits; aliasing to `auth_user_id`
      would only add cross-device identity unification, which isn't a
      beta success metric — data-minimization wins by default
- [x] Confirm `prediction_submitted` (existing event) still fires at
      final lock — no new, redundant "locked" event

## Privacy/Trust pages

- [x] `/privacy` and `/terms` routes (minimal, beta-appropriate copy)
- [x] Add both links to the existing `Footer` component
- [x] "Independent fan prediction, not affiliated with Miss Universe"
      disclaimer on the Email screen specifically, in addition to the
      footer

## Tests (deterministic, no live Supabase dependency where avoidable)

- [ ] Fresh anonymous browse → build → OTP → lock succeeds *(code
      complete and unit/DB-verified — see
      `FOUCH_BETA_HARDENING_02_PHASE_C.md`'s real-Postgres before/after
      cutover test; the full live-email version of this is the
      founder's Manual Pre-Cutover Test, not yet performed)*
- [x] Same email, second browser/incognito/device → hard rule →
      redirected to existing `public_id` *(verified at the DB level —
      Phase A's Test C/E plus Phase C's new Person-A/B reproduction)*
- [x] Two near-simultaneous lock attempts, same email (race condition)
      → exactly one row created, both callers resolve to it *(Postgres's
      own atomicity guarantees this — same mechanism already proven
      for device_token in Sprint 2, now extended to the identity index)*
- [x] Same email, second *different* event → succeeds normally
      (constraint is per-event) *(verified in Phase A, Test D)*
- [ ] Wrong code → retry allowed → client-side UX counter kicks in
      after 5 attempts (confirmed as UX-only, not asserted as a
      security boundary) *(implemented; live-tested against a real
      wrong code as part of Gate 2's pre-cutover verification, not yet
      run)*
- [ ] Expired code → resend → succeeds *(implemented; requires waiting
      out the real expiry window with a live account, not yet run)*
- [x] Two different verified identities on the *same* device
      (matching `device_token`) → both succeed; only
      `duplicate_prediction_attempt` fires, nothing is blocked
      *(reproduced the actual pre-cutover bug and confirmed the
      post-cutover fix against real Postgres — see Phase C doc)*
- [x] Leaderboard/Score/You vs The World/Crowd Movement all produce
      correct results against a *mixed* population of legacy
      (`auth_user_id IS NULL`) and new verified rows in the same event
      *(none of those systems read `auth_user_id` at all — confirmed
      by code inspection; unchanged from Phase A's equivalent finding)*
- [x] Analytics properties never contain email/auth_user_id/device_token
      (and no `alias()` call is present anywhere in the analytics code)

## Regression (must still work, unchanged)

- [x] Existing anonymous predictions (pre-migration) still resolve on
      their public pages
- [x] Leaderboard ranking/ties unchanged
- [x] FOUCH Score formula/bands unchanged
- [x] You vs The World calculations unchanged
- [x] Experiment 01 (Your Crowd Changed) unchanged
- [x] Result Card / Prediction Card generation unchanged
- [x] Demo/official isolation unchanged

## Explicitly not in this checklist

Profiles, account menus, login/logout UI, password auth, notifications,
creator pages, leagues, followers, AI predictions, Sprint 6 — all out
of scope, per the architecture brief.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_BETA_HARDENING_02_CHECKLIST.md"
} catch {
    Write-Host "FAILED: FOUCH_BETA_HARDENING_02_CHECKLIST.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_BETA_HARDENING_02_CHECKLIST.md"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 17 files written successfully. GATE 1 ONLY -- do not deploy yet." -ForegroundColor Green
}