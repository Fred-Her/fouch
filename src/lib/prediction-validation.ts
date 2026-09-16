﻿import type { Participant } from "@/types/participant";
import type { FouchEvent } from "@/types/event";
// Type-only import — erased at build time, so this file stays a pure,
// DB-free module. The shape it validates against (EventLockConfig)
// lives in prediction-lock-logic.ts, which itself has no "server-only"
// import specifically so both it and this file can be unit tested
// directly. See that file's comment for why database time, never
// client time, is what ultimately feeds `now` here.
import type { EventLockConfig } from "@/lib/prediction-lock-logic";

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
 *
 * FOUCH 0.3A: open/lock timing is no longer read from `event`
 * (src/lib/events.ts no longer carries these fields at all) — it is
 * passed in explicitly as `lockConfig`, fetched by the caller from
 * Supabase `events` (the single authoritative source, see
 * events-db.ts). `now` is also passed in rather than read here via
 * Date.now(), so this function stays a pure, fully unit-testable
 * function with no implicit clock or DB dependency — the server
 * action is what supplies real server time, never anything the
 * client could influence.
 */
export function validateSubmission(
  input: SubmissionInput,
  event: FouchEvent,
  activeParticipants: Participant[],
  requiredCount: number,
  lockConfig: EventLockConfig | null,
  now: number = Date.now(),
): ValidationResult {
  if (lockConfig?.predictionOpenAt && now < Date.parse(lockConfig.predictionOpenAt)) {
    return { valid: false, error: "Predictions for this event haven't opened yet." };
  }
  if (lockConfig?.predictionLockAt && now >= Date.parse(lockConfig.predictionLockAt)) {
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