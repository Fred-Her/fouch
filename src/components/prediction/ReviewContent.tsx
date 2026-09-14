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