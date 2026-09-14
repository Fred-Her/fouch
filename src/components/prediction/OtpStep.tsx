"use client";

import { useEffect, useState } from "react";

/** Matches Supabase Auth's own default OTP resend cooldown, confirmed
 * in Phase B — never invent a different number here. */
const RESEND_COOLDOWN_SECONDS = 60;
/** Must match this project's actual configured "Email OTP length" in
 * Supabase (Authentication → Providers → Email) — confirmed as 8 in
 * this project, NOT the commonly-assumed 6. A mismatch here silently
 * truncates every real code and makes verification fail, misleadingly
 * reported as "expired" — a real bug found and fixed during Gate 1
 * manual testing, not a hypothetical. */
const OTP_LENGTH = 8;
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
          maxLength={OTP_LENGTH}
          value={code}
          onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, OTP_LENGTH))}
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
          disabled={submitting || code.length !== OTP_LENGTH}
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