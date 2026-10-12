# FOUCH User-Visible UTF-8 Fix — em dashes, middots and apostrophes in visible text/strings (comments left untouched).
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-utf8-fix.ps1
$failures = @()

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
            {participant.displayName}
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
    $path = "src\components\prediction\EditPredictionFlow.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { track } from "@/lib/analytics";
import { formatEventLocalLockTime } from "@/lib/event-time-display";
import {
  startEmailVerification,
  verifyEmailAndEditPrediction,
  retryEditWithVerifiedSession,
  type VerifyAndEditResult,
} from "@/app/predict/[slug]/verify-actions";
import type { Participant } from "@/types/participant";
import { TopTenList } from "./TopTenList";
import { ParticipantBrowser } from "./ParticipantBrowser";
import { EmailStep } from "./EmailStep";
import { OtpStep } from "./OtpStep";

type Step = "edit" | "email" | "otp";

/**
 * FOUCH 0.3A â€” reuses the SAME ranking primitives as
 * PredictionBuilder.tsx (TopTenList, ParticipantBrowser) and the SAME
 * verification primitives as ReviewContent.tsx (EmailStep, OtpStep) â€”
 * deliberately not a second, independent builder. The only real
 * difference from PredictionBuilder is persistence: this component's
 * ranking state starts from the prediction's CURRENT version (passed
 * in from the server) and is never written to localStorage â€” there is
 * nothing "in progress" to resume here, only a specific saved
 * prediction being edited.
 */
export function EditPredictionFlow({
  eventSlug,
  publicId,
  allParticipants,
  initialRankedParticipants,
  requiredCount,
  expectedVersionNumber,
  predictionLockAt,
  predictionTimezone,
}: {
  eventSlug: string;
  publicId: string;
  /** Only currently-selectable (ACTIVE) contestants â€” what
   * ParticipantBrowser offers to pick from. */
  allParticipants: Participant[];
  /** FOUCH 0.3B: the CURRENT ranking resolved regardless of status â€”
   * may include a WITHDRAWN/REPLACED entry (isActive: false), which
   * must still display with its real name so it can be seen and
   * explicitly swapped out, never silently dropped from the list. */
  initialRankedParticipants: Participant[];
  requiredCount: number;
  expectedVersionNumber: number;
  predictionLockAt: string | null;
  /** FOUCH 0.3A.1 â€” IANA timezone identifier for the event, used only
   * for unambiguous display of predictionLockAt (see
   * event-time-display.ts). */
  predictionTimezone: string | null;
}) {
  const router = useRouter();
  const [selectedIds, setSelectedIds] = useState<string[]>(
    initialRankedParticipants.map((participant) => participant.id),
  );
  const [step, setStep] = useState<Step>("edit");

  const [emailSubmitting, setEmailSubmitting] = useState(false);
  const [emailError, setEmailError] = useState<string | null>(null);
  const [email, setEmail] = useState("");

  const [otpSubmitting, setOtpSubmitting] = useState(false);
  const [otpError, setOtpError] = useState<string | null>(null);
  const [wrongAttemptCount, setWrongAttemptCount] = useState(0);
  const [accessTokenForRetry, setAccessTokenForRetry] = useState<string | null>(null);

  // FOUCH 0.3B: merges the selectable roster with whatever the
  // current ranking already contains â€” this is what lets a
  // WITHDRAWN/REPLACED entry the user hasn't removed yet keep
  // resolving to its real name (isActive: false) instead of vanishing
  // from the Top N the moment its status changed. ParticipantBrowser
  // below still only ever offers `allParticipants` (active-only) to
  // pick from, so a removed inactive entry can only be replaced by a
  // currently-active contestant â€” never re-added.
  const participantsById = new Map(
    [...allParticipants, ...initialRankedParticipants].map((participant) => [participant.id, participant]),
  );

  const rankedParticipants = selectedIds
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  const isComplete = selectedIds.length >= requiredCount;
  // FOUCH 0.3B Â§7: a saved version can never include a participant
  // who is no longer ACTIVE â€” checked client-side here purely to
  // give an immediate, clear message instead of a round-trip to the
  // server; validateSubmission enforces the same rule authoritatively
  // regardless of this check (see verify-actions.ts's edit flow).
  const hasUnavailableSelection = rankedParticipants.some((participant) => !participant.isActive);
  const canSave = isComplete && !hasUnavailableSelection;

  function handleToggle(id: string) {
    setSelectedIds((current) => {
      if (current.includes(id)) {
        return current.filter((selectedId) => selectedId !== id);
      }
      if (current.length >= requiredCount) return current;
      return [...current, id];
    });
  }

  function handleRemove(id: string) {
    setSelectedIds((current) => current.filter((selectedId) => selectedId !== id));
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
      track("prediction_edit_reordered", { event_slug: eventSlug });
      return swap(current, index - 1, index);
    });
  }

  function handleMoveDown(index: number) {
    setSelectedIds((current) => {
      if (index === current.length - 1) return current;
      track("prediction_edit_reordered", { event_slug: eventSlug });
      return swap(current, index, index + 1);
    });
  }

  function handleStartSave() {
    track("prediction_edit_started", { event_slug: eventSlug });
    setStep("email");
  }

  async function handleSendCode(targetEmail: string) {
    if (emailSubmitting) return;
    setEmailSubmitting(true);
    setEmailError(null);

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

    setEmail(targetEmail);
    setOtpError(null);
    setWrongAttemptCount(0);
    setAccessTokenForRetry(null);
    setStep("otp");
  }

  function handleEditResult(result: VerifyAndEditResult) {
    if (result.success) {
      track("prediction_updated", {
        event_slug: eventSlug,
        version_number: result.versionNumber,
        unchanged: result.unchanged,
      });
      router.push(`/p/${publicId}?edited=1`);
      return;
    }

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

    let result: VerifyAndEditResult;
    try {
      result = await verifyEmailAndEditPrediction(email, code, {
        publicId,
        participantIds: selectedIds,
        expectedVersionNumber,
      });
    } catch {
      setOtpSubmitting(false);
      setOtpError("We couldn't verify your code — try again.");
      return;
    }

    setOtpSubmitting(false);
    handleEditResult(result);
  }

  async function handleRetry() {
    if (otpSubmitting || !accessTokenForRetry) return;
    setOtpSubmitting(true);
    setOtpError(null);

    let result: VerifyAndEditResult;
    try {
      result = await retryEditWithVerifiedSession(accessTokenForRetry, {
        publicId,
        participantIds: selectedIds,
        expectedVersionNumber,
      });
    } catch {
      setOtpSubmitting(false);
      setOtpError("We couldn't save your changes. Try again.");
      return;
    }

    setOtpSubmitting(false);
    handleEditResult(result);
  }

  function handleUseDifferentEmail() {
    setStep("email");
    setEmail("");
    setOtpError(null);
    setEmailError(null);
    setWrongAttemptCount(0);
    setAccessTokenForRetry(null);
  }

  return (
    <div className="mt-6">
      {predictionLockAt ? (
        <p className="mb-4 text-xs text-text-muted">
          You can update your picks until {formatEventLocalLockTime(predictionLockAt, predictionTimezone)}.
        </p>
      ) : null}

      {step === "edit" ? (
        <div className="lg:grid lg:grid-cols-[380px_1fr] lg:gap-10">
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
              <>
                <button
                  type="button"
                  onClick={handleStartSave}
                  disabled={!canSave}
                  className="mt-6 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
                >
                  Save my Top {requiredCount}
                </button>
                {hasUnavailableSelection ? (
                  <p className="mt-2 text-xs text-text-muted">
                    Replace the contestant marked &quot;Replace&quot; with a current one to save your changes.
                  </p>
                ) : null}
              </>
            ) : null}
          </section>

          <section aria-label="All contestants" className="mt-10 lg:mt-0">
            <h2 className="font-display text-lg text-text-primary">All contestants</h2>
            <div className="mt-3">
              <ParticipantBrowser
                participants={allParticipants}
                selectedIds={new Set(selectedIds)}
                atMax={isComplete}
                onToggle={handleToggle}
              />
            </div>
          </section>
        </div>
      ) : null}

      {step === "email" ? (
        <EmailStep mode="edit" submitting={emailSubmitting} errorMessage={emailError} onSendCode={handleSendCode} />
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
            onClick={handleRetry}
            className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
          >
            {otpSubmitting ? "Trying againâ€¦" : "Try again"}
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
    Write-Host "OK:     src\components\prediction\EditPredictionFlow.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\EditPredictionFlow.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\EditPredictionFlow.tsx"
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
                {participantsById.get(comparison.sameWinner.participantId)?.displayName} —{" "}
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
                {participantsById.get(comparison.boldestPick.participantId)?.displayName}
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
                      <span className="flex-1 text-sm text-text-primary">
                        {participant.displayName}
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
                âœ“
                {userWinnerPick ? (
                  <>
                    <CountryFlag countryCode={userWinnerPick.countryCode} />
                    {userWinnerPick.displayName}
                  </>
                ) : (
                  "Correct"
                )}
              </span>
            ) : (
              <div className="space-y-1 text-text-primary">
                <p className="flex items-center gap-1.5">
                  <span className="text-text-muted">âœ— Missed — your pick:</span>
                  {userWinnerPick ? (
                    <>
                      <CountryFlag countryCode={userWinnerPick.countryCode} />
                      {userWinnerPick.displayName}
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
    $path = "src\app\events\[slug]\leaderboard\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getEventBySlug, getEntryNoun } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { getEventLeaderboard } from "@/lib/leaderboard-service";
import { MIN_PERCENTILE_SAMPLE } from "@/lib/scoring";
import { LeaderboardRow } from "@/components/scoring/LeaderboardRow";
import { LeaderboardTracker } from "@/components/scoring/LeaderboardTracker";

// Sprint 5.1: this route reads Supabase state that changes independently
// of any URL parameter (a new prediction being scored, a result being
// entered) â€” force fresh server execution on every request rather than
// risk this being treated as a cacheable static/ISR route.
export const dynamic = "force-dynamic";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = await getEventBySlug(slug);
  if (!event) return {};

  const participantData = await getParticipantsForEvent(slug);
  const isDemo = participantData?.status === "demo";

  return {
    title: `${event.name} Predictions Leaderboard | FOUCH`,
    description: isDemo
      ? "A demo FOUCH predictions leaderboard — not an official result."
      : "See how FOUCH predictions ranked after the result.",
    // Demo leaderboards should never be indexed as if they were real â€”
    // same non-indexing posture as public prediction pages (Sprint 2).
    robots: isDemo ? { index: false, follow: true } : undefined,
  };
}

export default async function EventLeaderboardPage({
  params,
  searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ from?: string }>;
}) {
  const { slug } = await params;
  const { from } = await searchParams;

  const event = await getEventBySlug(slug);
  if (!event) notFound();

  const participantData = await getParticipantsForEvent(slug);
  if (!participantData) notFound();

  const leaderboard = await getEventLeaderboard(slug, participantData.status, from);
  const pluralNoun = getEntryNoun(event, true);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>

      <h1 className="mt-6 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-1 font-display text-xl uppercase tracking-tight text-text-primary">
        Event leaderboard
      </p>
      <p className="mt-2 text-sm text-text-secondary">See who called it best.</p>

      {participantData.status === "demo" ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo leaderboard — not an official outcome
        </p>
      ) : null}

      {leaderboard.status === "no_result" ? (
        <div className="mt-10 rounded border border-border bg-surface p-6">
          <p className="font-display text-xl text-text-primary">Leaderboard locked</p>
          <p className="mt-2 text-sm text-text-secondary">
            Results will appear here once {event.name} has been scored.
          </p>
          <Link
            href={`/predict/${slug}`}
            className="mt-5 inline-flex items-center justify-center rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            Make your call
          </Link>
        </div>
      ) : (
        <div className="mt-8">
          <LeaderboardTracker
            eventSlug={slug}
            dataStatus={leaderboard.dataStatus}
            leaderboardSize={leaderboard.totalCount}
            ownRank={leaderboard.viewer?.entry.rank}
            ownScoreBand={leaderboard.viewer?.entry.band}
          />

          {leaderboard.totalCount === 0 ? (
            <p className="text-sm text-text-muted">No scored predictions yet.</p>
          ) : leaderboard.totalCount === 1 ? (
            <p className="text-sm text-text-muted">First call on the board.</p>
          ) : leaderboard.totalCount <= 4 ? (
            <p className="text-sm text-text-muted">The leaderboard is just getting started.</p>
          ) : null}

          {leaderboard.viewer ? (
            <div className="mt-6 rounded border border-accent/40 bg-accent/10 p-5">
              <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-secondary">
                Your finish
              </p>
              <p className="mt-2 font-display text-4xl text-accent-strong">
                #{leaderboard.viewer.entry.rank} of {leaderboard.totalCount}
              </p>
              <p className="mt-1 text-sm text-text-secondary">
                Fouch score {leaderboard.viewer.entry.score}
                {leaderboard.viewer.percentile.percentile !== null
                  ? ` · Top ${Math.max(1, Math.round(100 - leaderboard.viewer.percentile.percentile))}%`
                  : ""}
              </p>
              {leaderboard.viewer.percentile.percentile === null ? (
                <p className="mt-1 text-xs text-text-muted">
                  World ranking unlocks at {MIN_PERCENTILE_SAMPLE} predictions.
                </p>
              ) : null}
            </div>
          ) : null}

          {leaderboard.topEntries.length > 0 ? (
            <ol className="mt-8 space-y-2">
              {leaderboard.topEntries.map((entry) => (
                <li key={entry.publicId}>
                  <LeaderboardRow
                    entry={entry}
                    eventSlug={slug}
                    isViewer={entry.publicId === from}
                    prominent={entry.rank <= 3}
                  />
                </li>
              ))}
            </ol>
          ) : null}

          {leaderboard.viewer && leaderboard.viewer.neighbors.length > 0 ? (
            <div className="mt-8 border-t border-border pt-6">
              <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">
                Your neighborhood
              </p>
              <ol className="mt-3 space-y-2">
                {leaderboard.viewer.neighbors.map((entry) => (
                  <li key={entry.publicId}>
                    <LeaderboardRow
                      entry={entry}
                      eventSlug={slug}
                      isViewer={entry.publicId === from}
                      prominent={false}
                    />
                  </li>
                ))}
              </ol>
            </div>
          ) : null}

          <p className="mt-6 text-xs text-text-muted">
            Showing the top {Math.min(50, leaderboard.totalCount)} {pluralNoun === "picks" ? "predictions" : pluralNoun}
            {leaderboard.totalCount > 50 ? ` of ${leaderboard.totalCount}` : ""}.
          </p>
        </div>
      )}
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\events\[slug]\leaderboard\page.tsx"
} catch {
    Write-Host "FAILED: src\app\events\[slug]\leaderboard\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\events\[slug]\leaderboard\page.tsx"
}

try {
    $path = "src\app\p\[publicId]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CountryFlag } from "@/components/CountryFlag";
import { siteUrl } from "@/lib/site";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { getOfficialResult } from "@/lib/results-db";
import { formatContestantListUpdated } from "@/lib/event-time-display";
import { PublicPredictionView } from "@/components/prediction/PublicPredictionView";
import { YouVsTheWorld } from "@/components/prediction/YouVsTheWorld";
import { FouchScore } from "@/components/scoring/FouchScore";
import { YourCrowdChanged } from "@/components/scoring/YourCrowdChanged";

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
    // link but intentionally not indexed â€” we don't want thousands of
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

  // Cheap existence check only (no percentile/breakdown work) â€” used
  // purely to decide share-CTA hierarchy (Sprint 4.1 Â§7-8). FouchScore
  // below independently does the full scored computation; this is a
  // second, lightweight read of the same result row, not duplicated
  // scoring logic.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);
  const hasResult = Boolean(official);

  // FOUCH 0.3A: editing is offered only for a verified prediction
  // while the event is still open â€” fetched fresh on every page view
  // from the single authoritative source, never cached/assumed.
  const lockConfig = await getEventLockConfig(event.slug);
  const isPredictionOpen = isPredictionWindowOpen(lockConfig, Date.now());
  const canEdit = prediction.hasVerifiedOwner && isPredictionOpen;
  const showLockedNotice = prediction.hasVerifiedOwner && !isPredictionOpen;

  // FOUCH 0.3B Â§13: "Contestant list updated {date}" for a real,
  // non-demo event with verified-roster provenance â€” never "Demo
  // prediction" for one of these. Null (no participant rows checked
  // yet, or a hardcoded/demo event) simply shows nothing extra here.
  const participantData = await getParticipantsForEvent(event.slug);
  const sourceCheckedAt = participantData?.sourceCheckedAt ?? null;

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
        <p className="mt-1 text-sm text-text-muted"><CountryFlag countryCode={prediction.countryCode} /></p>
      ) : null}

      {prediction.dataStatus === "demo" ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo prediction — not the official lineup
        </p>
      ) : sourceCheckedAt ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          {formatContestantListUpdated(sourceCheckedAt)}
        </p>
      ) : null}

      <PublicPredictionView
        eventSlug={event.slug}
        publicId={publicId}
        rankedParticipants={rankedParticipants}
        hasResult={hasResult}
        canEdit={canEdit}
        showLockedNotice={showLockedNotice}
        predictionLockAt={lockConfig?.predictionLockAt ?? null}
        predictionTimezone={lockConfig?.timezone ?? null}
        fouchScore={<FouchScore prediction={prediction} event={event} publicId={publicId} />}
        youVsTheWorld={<YouVsTheWorld prediction={prediction} event={event} />}
        yourCrowdChanged={<YourCrowdChanged prediction={prediction} event={event} />}
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
    $path = "src\app\predict\[slug]\review\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getEventBySlug } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { ReviewContent } from "@/components/prediction/ReviewContent";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = await getEventBySlug(slug);
  if (!event) return {};

  return { title: `Your Top 10 — ${event.name}` };
}

const REQUIRED_SELECTIONS = 10;

export default async function ReviewPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const event = await getEventBySlug(slug);
  if (!event) notFound();

  const participantData = await getParticipantsForEvent(slug);
  if (!participantData || participantData.participants.length === 0) notFound();

  const requiredCount = Math.min(REQUIRED_SELECTIONS, participantData.participants.length);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link
        href={`/predict/${slug}`}
        className="inline-flex items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary"
      >
        <ArrowLeft className="h-4 w-4" aria-hidden />
        Back to builder
      </Link>

      <p className="mt-6 font-display text-sm tracking-[0.2em] text-text-muted">FOUCH</p>
      <h1 className="mt-1 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-3 font-display text-xl uppercase tracking-tight text-text-primary">
        Your Top {requiredCount}
      </p>

      <div className="mt-8">
        <ReviewContent
          eventSlug={slug}
          participants={participantData.participants}
          requiredCount={requiredCount}
        />
      </div>
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\predict\[slug]\review\page.tsx"
} catch {
    Write-Host "FAILED: src\app\predict\[slug]\review\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\predict\[slug]\review\page.tsx"
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
import { formatContestantListUpdated } from "@/lib/event-time-display";
import { PredictionBuilder } from "@/components/prediction/PredictionBuilder";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = await getEventBySlug(slug);
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
  const event = await getEventBySlug(slug);
  if (!event) notFound();

  const participantData = await getParticipantsForEvent(slug);
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

  const { status, participants, sourceCheckedAt } = participantData;
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
        ) : sourceCheckedAt ? (
          <p className="mt-4 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
            {formatContestantListUpdated(sourceCheckedAt)}
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
    $path = "src\app\predict\[slug]\verify-actions.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\predict\[slug]\verify-actions.ts"
} catch {
    Write-Host "FAILED: src\app\predict\[slug]\verify-actions.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\predict\[slug]\verify-actions.ts"
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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\predictions-db.ts"
} catch {
    Write-Host "FAILED: src\lib\predictions-db.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\predictions-db.ts"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 10 files written successfully." -ForegroundColor Green
}
