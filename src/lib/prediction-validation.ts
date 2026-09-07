import type { Participant } from "@/types/participant";
import type { FouchEvent } from "@/types/event";

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
 */
export function validateSubmission(
  input: SubmissionInput,
  event: FouchEvent,
  activeParticipants: Participant[],
  requiredCount: number,
): ValidationResult {
  const now = Date.now();

  if (event.predictionOpenAt && now < Date.parse(event.predictionOpenAt)) {
    return { valid: false, error: "Predictions for this event haven't opened yet." };
  }
  if (event.predictionLockAt && now >= Date.parse(event.predictionLockAt)) {
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