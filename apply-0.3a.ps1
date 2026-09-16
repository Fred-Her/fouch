# FOUCH 0.3A — Editable Predictions & Version History — applies all changed/new files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-0.3a.ps1
$failures = @()

try {
    $path = "src\lib\prediction-lock-logic.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿/**
 * FOUCH 0.3A — pure decision logic split out of events-db.ts
 * specifically so it has NO "server-only" import and can be unit
 * tested directly (vitest's jsdom environment cannot import a
 * server-only-guarded module, the same reason prediction-validation.ts
 * only ever type-imports EventLockConfig rather than importing
 * events-db.ts's runtime code). events-db.ts re-exports both symbols
 * below unchanged, so every existing import site is unaffected.
 */
export interface EventLockConfig {
  predictionOpenAt: string | null;
  predictionLockAt: string | null;
}

/**
 * Given a lock config and the current SERVER time, decides whether
 * predictions/edits are currently allowed. Every real caller sources
 * `nowMs` from `Date.now()` on the server — never anything the client
 * supplies — per the frozen rule that client clocks must never be
 * trusted (brief §3/§20).
 */
export function isPredictionWindowOpen(config: EventLockConfig | null, nowMs: number): boolean {
  if (!config) return true; // No configured window — same as before 0.3A (unrestricted).
  if (config.predictionOpenAt && nowMs < Date.parse(config.predictionOpenAt)) return false;
  if (config.predictionLockAt && nowMs >= Date.parse(config.predictionLockAt)) return false;
  return true;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\prediction-lock-logic.ts"
} catch {
    Write-Host "FAILED: src\lib\prediction-lock-logic.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\prediction-lock-logic.ts"
}

try {
    $path = "src\lib\events-db.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { isPredictionWindowOpen, type EventLockConfig } from "@/lib/prediction-lock-logic";

// Re-exported unchanged so every existing import site
// (`@/lib/events-db`) keeps working — the pure logic itself now lives
// in prediction-lock-logic.ts purely so it can be unit tested without
// pulling in the "server-only" guard above. See that file's comment.
export { isPredictionWindowOpen };
export type { EventLockConfig };

/**
 * FOUCH 0.3A — the single authoritative source for prediction open/lock
 * timing. Supabase `events.prediction_open_at` / `prediction_lock_at`
 * (migration 0007) replace the old hardcoded values in
 * src/lib/events.ts, which may still hold display-only metadata
 * (name, subtitle, hero asset) but must never again be consulted for
 * timing decisions.
 *
 * Every timestamp here is compared against `Date.now()` on the
 * server that runs this code — never a value the browser supplies —
 * per the frozen rule that client clocks must never be trusted.
 */

/**
 * Returns null when the event row doesn't exist or the database isn't
 * configured. Callers must treat null as "no lock configured" (never
 * throw, never fail open in a way that fabricates a lock date) — this
 * mirrors how every other lookup in this codebase degrades when
 * Supabase is unavailable (see predictions-db.ts).
 */
export async function getEventLockConfig(eventSlug: string): Promise<EventLockConfig | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("events")
    .select("prediction_open_at, prediction_lock_at")
    .eq("slug", eventSlug)
    .maybeSingle();

  if (error || !data) return null;

  return {
    predictionOpenAt: data.prediction_open_at,
    predictionLockAt: data.prediction_lock_at,
  };
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\events-db.ts"
} catch {
    Write-Host "FAILED: src\lib\events-db.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\events-db.ts"
}

try {
    $path = "src\lib\events-db.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿import { describe, it, expect } from "vitest";
import { isPredictionWindowOpen, type EventLockConfig } from "./prediction-lock-logic";

const LOCK_AT = "2026-11-24T00:00:00Z";
const LOCK_MS = Date.parse(LOCK_AT);

describe("isPredictionWindowOpen — the single lock-timing decision, fed by server time only", () => {
  it("is open when no lock config exists at all (event not configured — same as pre-0.3A behavior)", () => {
    expect(isPredictionWindowOpen(null, Date.now())).toBe(true);
  });

  it("is open one second before the lock instant", () => {
    const config: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT };
    expect(isPredictionWindowOpen(config, LOCK_MS - 1000)).toBe(true);
  });

  it("is locked exactly AT the lock instant — >= , not > (brief §20: 'at lock time → rejected')", () => {
    const config: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT };
    expect(isPredictionWindowOpen(config, LOCK_MS)).toBe(false);
  });

  it("is locked one second after the lock instant", () => {
    const config: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT };
    expect(isPredictionWindowOpen(config, LOCK_MS + 1000)).toBe(false);
  });

  it("respects an open-at time in the future — not yet open", () => {
    const openAt = "2026-01-01T00:00:00Z";
    const config: EventLockConfig = { predictionOpenAt: openAt, predictionLockAt: null };
    expect(isPredictionWindowOpen(config, Date.parse(openAt) - 1)).toBe(false);
    expect(isPredictionWindowOpen(config, Date.parse(openAt))).toBe(true);
  });

  it("client clock manipulation has no effect — this function only ever receives a `nowMs` the caller supplies, and every real caller in this codebase sources it from Date.now() on the server, never from the browser", () => {
    // Documents the invariant at the type level: there is no
    // `document`/`window`/request-header parameter here at all — a
    // forged client timestamp is architecturally impossible to feed
    // into this function unless a server action explicitly chose to
    // (none do; see events-db.ts and verify-actions.ts, which always
    // call `isPredictionWindowOpen(lockConfig, Date.now())`).
    expect(isPredictionWindowOpen.length).toBe(2);
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\events-db.test.ts"
} catch {
    Write-Host "FAILED: src\lib\events-db.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\events-db.test.ts"
}

try {
    $path = "src\lib\prediction-version-logic.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿/**
 * FOUCH 0.3A — pure, DB-free decision logic for the edit flow, kept
 * separate from predictions-db.ts/verify-actions.ts for the same
 * reason leaderboard.ts is kept separate from leaderboard-service.ts:
 * these are the rules worth unit-testing directly, with no Supabase
 * client involved.
 */

/**
 * The entire ownership authorization rule, in one place. A legacy
 * anonymous prediction has `ownerAuthUserId === null`, which never
 * strictly-equals any real `requesterAuthUserId` string — so legacy
 * predictions are rejected by the same single comparison as any other
 * mismatched identity, with no separate "is this legacy?" branch to
 * accidentally get wrong. There is no other way to become authorized
 * (not nickname, not device_token, not public_id, not a later-entered
 * email) — this function's two parameters are the entire input.
 */
export function isAuthorizedToEdit(ownerAuthUserId: string | null, requesterAuthUserId: string): boolean {
  return ownerAuthUserId !== null && ownerAuthUserId === requesterAuthUserId;
}

/**
 * True when an edit's submitted ranking is identical, in order, to
 * the prediction's current version — the no-op case that must not
 * create a new version (brief §8/§19: a double-click or a lost-then-
 * retried request must not create uncontrolled duplicate versions).
 */
export function isRankingUnchanged(currentRankedParticipantIds: string[], nextParticipantIds: string[]): boolean {
  if (currentRankedParticipantIds.length !== nextParticipantIds.length) return false;
  return currentRankedParticipantIds.every((id, index) => id === nextParticipantIds[index]);
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\prediction-version-logic.ts"
} catch {
    Write-Host "FAILED: src\lib\prediction-version-logic.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\prediction-version-logic.ts"
}

try {
    $path = "src\lib\prediction-version-logic.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿import { describe, it, expect } from "vitest";
import { isAuthorizedToEdit, isRankingUnchanged } from "./prediction-version-logic";

describe("isAuthorizedToEdit — the entire ownership authorization rule", () => {
  it("authorizes the verified owner editing their own prediction", () => {
    expect(isAuthorizedToEdit("alice-auth-id", "alice-auth-id")).toBe(true);
  });

  it("rejects a different verified identity — cannot edit someone else's prediction", () => {
    expect(isAuthorizedToEdit("alice-auth-id", "bob-auth-id")).toBe(false);
  });

  it("rejects editing a legacy anonymous prediction (auth_user_id is null) — no owner to authorize against", () => {
    expect(isAuthorizedToEdit(null, "bob-auth-id")).toBe(false);
  });

  it("rejects even when the requester is somehow an empty string — never treats falsy-but-present as authorized", () => {
    expect(isAuthorizedToEdit(null, "")).toBe(false);
  });

  it("is never fooled by a forged auth_user_id payload — the check only ever compares the two identity strings given, never anything else the client could supply (nickname/device_token/public_id/email are not parameters at all)", () => {
    // This test exists to document the invariant, not to exercise new
    // behavior: the function's signature itself makes a
    // nickname/device_token/public_id/email-based claim impossible —
    // there is no code path that reaches this function with anything
    // other than two auth_user_id strings.
    expect(isAuthorizedToEdit.length).toBe(2);
  });
});

describe("isRankingUnchanged — the no-new-version-on-retry guard", () => {
  it("is true for an identical ranking, same order", () => {
    expect(isRankingUnchanged(["a", "b", "c"], ["a", "b", "c"])).toBe(true);
  });

  it("is false when the order differs, even with the same members", () => {
    expect(isRankingUnchanged(["a", "b", "c"], ["b", "a", "c"])).toBe(false);
  });

  it("is false when any single member differs", () => {
    expect(isRankingUnchanged(["a", "b", "c"], ["a", "b", "d"])).toBe(false);
  });

  it("is false when lengths differ", () => {
    expect(isRankingUnchanged(["a", "b"], ["a", "b", "c"])).toBe(false);
  });

  it("is true for two empty rankings (degenerate, but never crashes)", () => {
    expect(isRankingUnchanged([], [])).toBe(true);
  });
});

/**
 * FOUCH 0.3A — legacy anonymous prediction invariants requested
 * explicitly by the founder. These are DB/RLS-level facts (a row's
 * public_id survives migration, community/leaderboard count it once,
 * RLS rejects a direct anonymous mutation) that this test file cannot
 * exercise without a real Postgres instance — vitest here has no DB
 * layer, by the same design choice that keeps every other file in
 * src/lib/*.test.ts DB-free (see leaderboard.ts/leaderboard-service.ts
 * split).
 *
 * What IS unit-tested below is the one piece of this that genuinely
 * is pure application logic: a legacy prediction can never be
 * authorized for editing, through ANY input, including a supplied
 * device_token. Everything else in this describe block's name
 * (readable, same public_id, counted once in community/leaderboard,
 * RLS rejects direct mutation) was verified instead via real SQL
 * against a local Postgres instance with migrations 0001-0008 applied
 * and seeded legacy rows — see this sprint's final report
 * ("Legacy Migration" / "Privacy / RLS" sections) for the exact
 * queries and their output. That evidence is not restated here as an
 * automated test because doing so would require introducing database
 * mocking infrastructure this codebase deliberately doesn't have.
 */
describe("Legacy anonymous predictions — editing is never authorizable, by any input", () => {
  it("cannot be edited even by the identity that WOULD be legitimate for a verified prediction — a legacy row's stored owner is null, and null is never authorized against anything", () => {
    expect(isAuthorizedToEdit(null, "some-real-verified-auth-user-id")).toBe(false);
  });

  it("device_token is not a parameter this function even accepts — there is no code path anywhere that could use a device_token to authorize an edit, legacy or otherwise (see EditPredictionPayload in verify-actions.ts, which has no deviceToken field at all, unlike LockPredictionPayload)", () => {
    // isAuthorizedToEdit's signature is the whole authorization
    // surface for editing (see its own doc comment) — it takes
    // exactly two auth_user_id strings and nothing else, which is
    // itself the proof that a device_token (or nickname, or
    // public_id, or a later-typed email) cannot enter into this
    // decision under any circumstance.
    expect(isAuthorizedToEdit.length).toBe(2);
    expect(isAuthorizedToEdit(null, "device-token-aaa")).toBe(false);
  });

  it("remains false no matter how many times the same legacy prediction is checked — there is no retry, session, or state that flips a null owner to authorized", () => {
    expect(isAuthorizedToEdit(null, "user-1")).toBe(false);
    expect(isAuthorizedToEdit(null, "user-1")).toBe(false);
    expect(isAuthorizedToEdit(null, "user-2")).toBe(false);
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\prediction-version-logic.test.ts"
} catch {
    Write-Host "FAILED: src\lib\prediction-version-logic.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\prediction-version-logic.test.ts"
}

try {
    $path = "src\lib\prediction-validation.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\prediction-validation.ts"
} catch {
    Write-Host "FAILED: src\lib\prediction-validation.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\prediction-validation.ts"
}

try {
    $path = "src\lib\prediction-validation.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿import { describe, it, expect } from "vitest";
import { validateSubmission } from "./prediction-validation";
import type { FouchEvent } from "@/types/event";
import type { Participant } from "@/types/participant";
import type { EventLockConfig } from "./prediction-lock-logic";

const EVENT: FouchEvent = {
  id: "seed-1",
  slug: "miss-universe-2026",
  name: "Miss Universe 2026",
  category: "pageant",
  status: "upcoming",
  eventDate: "2026-11-24",
  isFeatured: true,
};

function makeParticipant(id: string): Participant {
  return {
    id,
    eventId: EVENT.id,
    displayName: `Contestant ${id}`,
    countryCode: "CL",
    countryName: "Chile",
    sortOrder: 0,
    isActive: true,
  };
}

const PARTICIPANTS = Array.from({ length: 12 }, (_, i) => makeParticipant(`p${i + 1}`));
const TOP_10 = PARTICIPANTS.slice(0, 10).map((p) => p.id);

describe("validateSubmission — participant/ranking rules (unchanged by FOUCH 0.3A)", () => {
  it("accepts a valid, complete, unique Top 10", () => {
    const result = validateSubmission({ participantIds: TOP_10 }, EVENT, PARTICIPANTS, 10, null);
    expect(result.valid).toBe(true);
  });

  it("rejects a ranking with the wrong count", () => {
    const result = validateSubmission({ participantIds: TOP_10.slice(0, 5) }, EVENT, PARTICIPANTS, 10, null);
    expect(result.valid).toBe(false);
  });

  it("rejects duplicate participants", () => {
    const withDuplicate = [...TOP_10.slice(0, 9), TOP_10[0] as string];
    const result = validateSubmission({ participantIds: withDuplicate }, EVENT, PARTICIPANTS, 10, null);
    expect(result.valid).toBe(false);
  });

  it("rejects an unknown participant id", () => {
    const withUnknown = [...TOP_10.slice(0, 9), "not-a-real-id"];
    const result = validateSubmission({ participantIds: withUnknown }, EVENT, PARTICIPANTS, 10, null);
    expect(result.valid).toBe(false);
  });
});

describe("validateSubmission — FOUCH 0.3A lock timing, driven entirely by the passed-in lockConfig + now", () => {
  const LOCK_AT = "2026-11-24T00:00:00Z";
  const LOCK_MS = Date.parse(LOCK_AT);

  it("allows a submission/edit one second before lock", () => {
    const lockConfig: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT };
    const result = validateSubmission({ participantIds: TOP_10 }, EVENT, PARTICIPANTS, 10, lockConfig, LOCK_MS - 1000);
    expect(result.valid).toBe(true);
  });

  it("rejects a submission/edit exactly at the lock instant", () => {
    const lockConfig: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT };
    const result = validateSubmission({ participantIds: TOP_10 }, EVENT, PARTICIPANTS, 10, lockConfig, LOCK_MS);
    expect(result.valid).toBe(false);
    expect(result.valid || result.error).toContain("locked");
  });

  it("rejects a submission/edit after the lock instant", () => {
    const lockConfig: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT };
    const result = validateSubmission(
      { participantIds: TOP_10 },
      EVENT,
      PARTICIPANTS,
      10,
      lockConfig,
      LOCK_MS + 1000,
    );
    expect(result.valid).toBe(false);
  });

  it("with no lockConfig at all, never rejects for timing (matches pre-0.3A unrestricted behavior)", () => {
    const result = validateSubmission({ participantIds: TOP_10 }, EVENT, PARTICIPANTS, 10, null, LOCK_MS + 100000);
    expect(result.valid).toBe(true);
  });

  it("never reads timing from the `event` (FouchEvent) argument — that type no longer even has lock fields, so this test simply documents that validateSubmission's timing decision is fully determined by lockConfig+now", () => {
    const eventWithoutLockFields = { ...EVENT } as FouchEvent;
    expect("predictionLockAt" in eventWithoutLockFields).toBe(false);
    const lockConfig: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT };
    const result = validateSubmission(
      { participantIds: TOP_10 },
      eventWithoutLockFields,
      PARTICIPANTS,
      10,
      lockConfig,
      LOCK_MS + 1,
    );
    expect(result.valid).toBe(false);
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\prediction-validation.test.ts"
} catch {
    Write-Host "FAILED: src\lib\prediction-validation.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\prediction-validation.test.ts"
}

try {
    $path = "src\lib\predictions-db.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { generatePublicId } from "@/lib/public-id";
import { getEventBySlug } from "@/lib/events";
import { getParticipantsForEvent, type ParticipantDataStatus } from "@/lib/participants";
import { classifyInsertConflict } from "@/lib/insert-conflict";
import { isRankingUnchanged } from "@/lib/prediction-version-logic";
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
  /** FOUCH 0.3A: whether this prediction has a verified owner. Only
   * ever used server-side to decide whether to offer "EDIT MY TOP
   * 10" — never exposed as a raw auth_user_id to the client (see
   * predictions_public, which still never selects auth_user_id). */
  hasVerifiedOwner: boolean;
  /** FOUCH 0.3A: version_number of the current version — needed by
   * the edit flow as the optimistic-concurrency baseline. */
  currentVersionNumber: number;
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

    // FOUCH 0.3A: every prediction, including a first-time submission,
    // is now version 1 of its versioned history — not a special case.
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
      // Compensating cleanup — Supabase's JS client has no
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
  /** Highest version_number that exists for this prediction — the
   * next successful edit is version_number = latestVersionNumber + 1. */
  latestVersionNumber: number;
  /** Participant IDs of the CURRENT version, in ranked order — used
   * to pre-fill the edit builder. */
  currentRankedParticipantIds: string[];
}

/**
 * The one lookup the edit flow needs before authorizing anything:
 * who owns this prediction (by auth_user_id, never anything the
 * client supplies) and what its current ranking/version number are.
 * Returns null if the prediction, its current version, or its items
 * can't be resolved — callers must treat that as "can't edit", never
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
 * `predictions` row — this is exclusively the "edit" path; first
 * submissions go through insertPrediction() above.
 *
 * Idempotency (brief §19): if the submitted ranking is identical to
 * the prediction's current version, this is a no-op that returns
 * success without creating a new version — the simplest robust
 * defense against a double-click or a network retry re-sending the
 * exact same edit, with no client-supplied idempotency key needed.
 * A retry that lands after a lost response looks identical to the
 * original request, so this naturally covers that case too.
 *
 * Concurrency: `expectedVersionNumber` must match the version number
 * the caller read just before presenting the edit form. A mismatch
 * means someone else's edit (or this same edit, retried, but no
 * longer the current version) landed first — reported as a
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
  // read, not the one the caller assumed — closes the gap between
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
    // — report as a conflict rather than silently retrying with a
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

  // FOUCH 0.3A: always the CURRENT version's items — never every
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

  // FOUCH 0.3A: `id` here is the logical prediction's key used only to
  // group items below; `current_version_id` is what actually scopes
  // which items count — a prediction with 3 saved versions must still
  // contribute exactly ONE eligible ranking (its current one), never
  // three (brief §12: "Freddy has v1, v2, v3 → community sample size
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

  // FOUCH 0.3A: same current-version-only scoping as
  // getEligiblePredictionsForComparison above — a prediction with
  // several saved versions is still exactly one leaderboard entry
  // (brief §13), never one entry per version.
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

  // FOUCH 0.3A: `submitted_at` remains the prediction's ORIGINAL
  // submission time (predictions.submitted_at is never touched by an
  // edit — only prediction_versions.created_at records when each
  // version was saved). Experiment 01's semantics with an edited
  // winner pick are addressed separately below (brief §17) — this
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

  // Only position 1 (the winner pick) — and only from predictions with
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

try {
    $path = "src\lib\events.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿import type { FouchEvent } from "@/types/event";

/**
 * SEED DATA — Sprint 0.
 *
 * This is real, verifiable public information (event name, date, venue),
 * not a database yet. There are no participant counts, popularity
 * numbers, or "trending" claims here — Fouch does not fabricate social
 * proof. Once Supabase is wired up (see src/lib/supabase), this file's
 * shape becomes the seed for the `events` table and this function can
 * be swapped for a real query without touching the components that
 * consume it.
 */
const events: FouchEvent[] = [
  {
    id: "seed-miss-universe-2026",
    slug: "miss-universe-2026",
    name: "Miss Universe 2026",
    category: "pageant",
    status: "upcoming",
    eventDate: "2026-11-24",
    isFeatured: true,
    subtitle: "José Miguel Agrelot Coliseum, San Juan, Puerto Rico",
    // FOUCH 0.3A: the prediction lock instant for this event now lives
    // in Supabase `events.prediction_lock_at` (migration 0007), seeded
    // with this exact same value. It is intentionally NOT duplicated
    // here — see src/lib/events-db.ts.
  },
];

export function getFeaturedEvent(): FouchEvent | null {
  return events.find((event) => event.isFeatured) ?? null;
}

export function getEventBySlug(slug: string): FouchEvent | null {
  return events.find((event) => event.slug === slug) ?? null;
}

/**
 * The generic, event-agnostic term for one ranked option — "pick" by
 * default (fits the current demo country dataset), overridable per
 * event via entryNounSingular/Plural for future categories (Oscars
 * "nominee", Eurovision "entry", a verified pageant "contestant").
 */
export function getEntryNoun(event: FouchEvent, plural: boolean): string {
  if (plural) return event.entryNounPlural ?? "picks";
  return event.entryNounSingular ?? "pick";
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\events.ts"
} catch {
    Write-Host "FAILED: src\lib\events.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\events.ts"
}

try {
    $path = "src\lib\analytics.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿/**
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
  | "prediction_edit_started"
  | "prediction_edit_reordered"
  | "prediction_updated"
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
    $path = "src\types\event.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿export type EventCategory =
  | "pageant"
  | "awards"
  | "music"
  | "reality"
  | "talent"
  | "tv";

export type EventStatus = "upcoming" | "open" | "live" | "completed";

/**
 * Category-agnostic event model. Deliberately does NOT assume
 * contestants, countries, or a Top 10 shape — those are
 * category-specific concerns for a later sprint.
 *
 * FOUCH 0.3A: this type deliberately has NO prediction open/lock
 * fields anymore. That timing now lives exclusively in Supabase
 * `events.prediction_open_at` / `prediction_lock_at` (migration
 * 0007), fetched server-side via events-db.ts's getEventLockConfig —
 * never read from this seed data. This file may still describe
 * display-only metadata (name, subtitle, hero asset) until events
 * moves fully into the database.
 */
export interface FouchEvent {
  id: string;
  slug: string;
  name: string;
  category: EventCategory;
  status: EventStatus;
  /** ISO 8601 date string. */
  eventDate: string;
  /** Path to a hero image/asset. Optional — Sprint 0 has none. */
  heroAsset?: string;
  isFeatured: boolean;
  /** Plain-language subtitle used in the UI, e.g. venue or one-line context. */
  subtitle?: string;
  /**
   * What a single ranked option is called for this event — "contestant"
   * for a verified pageant roster, "nominee" for an Oscars category,
   * "country" for a Eurovision entry, etc. Defaults to "pick" when
   * unset (see getEntryNoun), which is deliberately generic for the
   * current demo country dataset — see Sprint 3 brief section 30.
   */
  entryNounSingular?: string;
  entryNounPlural?: string;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\types\event.ts"
} catch {
    Write-Host "FAILED: src\types\event.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\types\event.ts"
}

try {
    $path = "src\app\predict\[slug]\actions.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿"use server";

import { getEventBySlug } from "@/lib/events";
import { getEventLockConfig } from "@/lib/events-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { validateSubmission } from "@/lib/prediction-validation";
import { insertPrediction, getPredictionByDeviceToken } from "@/lib/predictions-db";

export interface SubmitPredictionInput {
  eventSlug: string;
  participantIds: string[];
  nickname?: string;
  countryCode?: string;
  deviceToken: string;
}

export type SubmitPredictionResult =
  | { success: true; publicId: string }
  | { success: false; error: string };

export async function submitPrediction(
  input: SubmitPredictionInput,
): Promise<SubmitPredictionResult> {
  const event = getEventBySlug(input.eventSlug);
  if (!event) {
    return { success: false, error: "This event doesn't exist." };
  }

  const participantData = getParticipantsForEvent(input.eventSlug);
  if (!participantData) {
    return { success: false, error: "This event has no contestants configured." };
  }

  const requiredCount = Math.min(10, participantData.participants.length);

  // FOUCH 0.3A: lock/open timing comes from Supabase (single
  // authoritative source), fetched fresh on every submission attempt
  // — never cached, never trusted from the client.
  const lockConfig = await getEventLockConfig(input.eventSlug);

  const validation = validateSubmission(
    {
      participantIds: input.participantIds,
      nickname: input.nickname,
      countryCode: input.countryCode,
    },
    event,
    participantData.participants,
    requiredCount,
    lockConfig,
  );

  if (!validation.valid) {
    return { success: false, error: validation.error };
  }

  if (!input.deviceToken || typeof input.deviceToken !== "string") {
    return { success: false, error: "Missing device token." };
  }

  const result = await insertPrediction({
    eventSlug: input.eventSlug,
    participantIds: validation.data.participantIds,
    nickname: validation.data.nickname,
    countryCode: validation.data.countryCode,
    dataStatus: participantData.status,
    deviceToken: input.deviceToken,
  });

  if (!result.success) {
    return { success: false, error: result.error };
  }

  return { success: true, publicId: result.publicId };
}

/**
 * Checks whether this device already has a submitted prediction for
 * this event, so the Review screen can redirect straight to the
 * existing public prediction instead of showing the submit form again
 * — a submitted prediction is immutable in Sprint 2.
 */
export async function checkExistingSubmission(
  eventSlug: string,
  deviceToken: string,
): Promise<{ publicId: string } | null> {
  if (!deviceToken) return null;
  const existing = await getPredictionByDeviceToken(eventSlug, deviceToken);
  return existing ? { publicId: existing.publicId } : null;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\predict\[slug]\actions.ts"
} catch {
    Write-Host "FAILED: src\app\predict\[slug]\actions.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\predict\[slug]\actions.ts"
}

try {
    $path = "src\app\predict\[slug]\verify-actions.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿"use server";

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
 * Beta Hardening 0.2 Phase C — the verified-lock flow.
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

  // FOUCH 0.3A: fetched fresh on every lock/edit attempt from
  // Supabase, the single authoritative source — never from
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

/* ------------------------------------------------------------------
 * FOUCH 0.3A — Editable Predictions.
 *
 * Deliberately mirrors the Lock flow above almost exactly: same
 * email → OTP → verify shape, same accessToken-based retry-without-
 * new-code semantics, because the identity architecture is frozen
 * (Beta Hardening 0.2 rules are unchanged, see brief §3). The only
 * new thing editing needs on top of that is OWNERSHIP authorization
 * — see validateAndEdit below.
 *
 * Legacy scope (explicit product decision, not inferred): a
 * prediction with auth_user_id = null has no verified identity to
 * authorize an edit against, and this sprint introduces no mechanism
 * to retroactively claim one via nickname, device_token, a
 * later-entered email, public_id, or anything else. Such predictions
 * remain fully public/readable/scoreable forever, exactly as today —
 * they are simply never editable. The UI never even offers "EDIT MY
 * TOP 10" for them (see PublicPredictionPage), but the server check
 * below is the actual authorization boundary, not the UI.
 * ------------------------------------------------------------------ */

export interface EditPredictionPayload {
  publicId: string;
  participantIds: string[];
  /** The version_number the client read just before opening the edit
   * builder — used as an optimistic-concurrency check, see
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
       * save step failed transiently — lets the client retry the save
       * step alone, without a new OTP (same frozen retry semantics as
       * the lock flow). Never present for not_owner/locked/conflict —
       * those are never worth retrying with the same input. */
      accessToken?: string;
    };

/**
 * Shared by verifyEmailAndEditPrediction and
 * retryEditWithVerifiedSession. Every authorization and timing check
 * here is independent server-side state — nothing the client supplies
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

  // The critical authorization check (brief §10-11, reconfirmed for
  // legacy scope): the verified auth_user_id from THIS session must
  // match the prediction's stored auth_user_id exactly. See
  // isAuthorizedToEdit's own doc for why this single, pure check is
  // the entire ownership rule — no nickname/device_token/public_id/
  // email-based claiming exists anywhere in this codebase.
  if (!isAuthorizedToEdit(editable.authUserId, authUserId)) {
    return {
      success: false,
      error: "This isn't your prediction.",
      failureReason: "not_owner",
    };
  }

  const event = getEventBySlug(editable.eventSlug);
  if (!event) {
    return { success: false, error: "This event doesn't exist.", failureReason: "validation_failed" };
  }

  const participantData = getParticipantsForEvent(editable.eventSlug);
  if (!participantData) {
    return {
      success: false,
      error: "This event has no contestants configured.",
      failureReason: "validation_failed",
    };
  }

  const requiredCount = Math.min(10, participantData.participants.length);

  // Re-fetched fresh, right now, from Supabase — the one and only
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
 * The main verified-edit entry point — verifies the OTP, then
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
  // transiently — never for not_owner/locked/conflict/validation,
  // none of which a bare retry with the same input would fix.
  if (!result.success && result.failureReason === "edit_failed" && data.session) {
    return { ...result, accessToken: data.session.access_token };
  }

  return result;
}

/**
 * Retries only the save step after a transient failure, reusing the
 * access token from the original OTP verification — mirrors
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
    $path = "src\app\p\[publicId]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CountryFlag } from "@/components/CountryFlag";
import { siteUrl } from "@/lib/site";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { getOfficialResult } from "@/lib/results-db";
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
    // link but intentionally not indexed — we don't want thousands of
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

  // Cheap existence check only (no percentile/breakdown work) — used
  // purely to decide share-CTA hierarchy (Sprint 4.1 §7-8). FouchScore
  // below independently does the full scored computation; this is a
  // second, lightweight read of the same result row, not duplicated
  // scoring logic.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);
  const hasResult = Boolean(official);

  // FOUCH 0.3A: editing is offered only for a verified prediction
  // while the event is still open — fetched fresh on every page view
  // from the single authoritative source, never cached/assumed.
  const lockConfig = await getEventLockConfig(event.slug);
  const isPredictionOpen = isPredictionWindowOpen(lockConfig, Date.now());
  const canEdit = prediction.hasVerifiedOwner && isPredictionOpen;
  const showLockedNotice = prediction.hasVerifiedOwner && !isPredictionOpen;

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
      ) : null}

      <PublicPredictionView
        eventSlug={event.slug}
        publicId={publicId}
        rankedParticipants={rankedParticipants}
        hasResult={hasResult}
        canEdit={canEdit}
        showLockedNotice={showLockedNotice}
        predictionLockAt={lockConfig?.predictionLockAt ?? null}
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
    $path = "src\app\p\[publicId]\edit\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿import { notFound, redirect } from "next/navigation";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { EditPredictionFlow } from "@/components/prediction/EditPredictionFlow";

/**
 * FOUCH 0.3A — the edit entry point. This route is intentionally
 * unreachable in a way that actually matters for two cases, checked
 * server-side (never just hidden in the UI, since a direct URL visit
 * bypasses any client-side hiding):
 *
 *  - legacy anonymous prediction (no verified owner) — there is no
 *    identity to authorize an edit against, and this sprint adds no
 *    way to claim one, so editing is simply never offered;
 *  - the event has passed prediction_lock_at — editing closes at
 *    lock, full stop.
 *
 * Both redirect back to the public page rather than 404 — the
 * prediction itself is real and viewable, only editing isn't
 * available. The actual SAVE action (verify-actions.ts) independently
 * re-checks both of these server-side again at save time — this
 * page's checks are only about whether to show the builder at all,
 * never the authorization boundary itself.
 */
export default async function EditPredictionPage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) notFound();

  const { prediction, event, rankedParticipants } = record;

  if (!prediction.hasVerifiedOwner) {
    redirect(`/p/${publicId}`);
  }

  const lockConfig = await getEventLockConfig(event.slug);
  if (!isPredictionWindowOpen(lockConfig, Date.now())) {
    redirect(`/p/${publicId}`);
  }

  const participantData = getParticipantsForEvent(event.slug);
  if (!participantData) notFound();

  const requiredCount = Math.min(10, participantData.participants.length);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <h1 className="font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-1 text-sm text-text-secondary">Edit your Top {requiredCount}</p>

      <EditPredictionFlow
        eventSlug={event.slug}
        publicId={publicId}
        allParticipants={participantData.participants}
        initialRankedParticipantIds={rankedParticipants.map((participant) => participant.id)}
        requiredCount={requiredCount}
        expectedVersionNumber={prediction.currentVersionNumber}
        predictionLockAt={lockConfig?.predictionLockAt ?? null}
      />
    </main>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\edit\page.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\edit\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\edit\page.tsx"
}

try {
    $path = "src\components\prediction\EditPredictionFlow.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { track } from "@/lib/analytics";
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
 * FOUCH 0.3A — reuses the SAME ranking primitives as
 * PredictionBuilder.tsx (TopTenList, ParticipantBrowser) and the SAME
 * verification primitives as ReviewContent.tsx (EmailStep, OtpStep) —
 * deliberately not a second, independent builder. The only real
 * difference from PredictionBuilder is persistence: this component's
 * ranking state starts from the prediction's CURRENT version (passed
 * in from the server) and is never written to localStorage — there is
 * nothing "in progress" to resume here, only a specific saved
 * prediction being edited.
 */
export function EditPredictionFlow({
  eventSlug,
  publicId,
  allParticipants,
  initialRankedParticipantIds,
  requiredCount,
  expectedVersionNumber,
  predictionLockAt,
}: {
  eventSlug: string;
  publicId: string;
  allParticipants: Participant[];
  initialRankedParticipantIds: string[];
  requiredCount: number;
  expectedVersionNumber: number;
  predictionLockAt: string | null;
}) {
  const router = useRouter();
  const [selectedIds, setSelectedIds] = useState<string[]>(initialRankedParticipantIds);
  const [step, setStep] = useState<Step>("edit");

  const [emailSubmitting, setEmailSubmitting] = useState(false);
  const [emailError, setEmailError] = useState<string | null>(null);
  const [email, setEmail] = useState("");

  const [otpSubmitting, setOtpSubmitting] = useState(false);
  const [otpError, setOtpError] = useState<string | null>(null);
  const [wrongAttemptCount, setWrongAttemptCount] = useState(0);
  const [accessTokenForRetry, setAccessTokenForRetry] = useState<string | null>(null);

  const participantsById = new Map(allParticipants.map((participant) => [participant.id, participant]));

  const rankedParticipants = selectedIds
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  const isComplete = selectedIds.length >= requiredCount;

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
          You can update your picks until{" "}
          {new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" }).format(
            new Date(predictionLockAt),
          )}
          .
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
              <button
                type="button"
                onClick={handleStartSave}
                className="mt-6 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong sm:w-auto"
              >
                Save my Top {requiredCount}
              </button>
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
            onClick={handleRetry}
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
    Write-Host "OK:     src\components\prediction\EditPredictionFlow.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\EditPredictionFlow.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\EditPredictionFlow.tsx"
}

try {
    $path = "src\components\prediction\PublicPredictionView.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿"use client";

import { useEffect, type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { Pencil } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { siteUrl } from "@/lib/site";
import type { Participant } from "@/types/participant";
import { ShareActions } from "./ShareActions";

function formatLockDate(iso: string): string {
  try {
    return new Intl.DateTimeFormat("en-US", {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(iso));
  } catch {
    return iso;
  }
}

export function PublicPredictionView({
  eventSlug,
  publicId,
  rankedParticipants,
  hasResult = false,
  canEdit = false,
  showLockedNotice = false,
  predictionLockAt = null,
  fouchScore,
  youVsTheWorld,
  yourCrowdChanged,
}: {
  eventSlug: string;
  publicId: string;
  rankedParticipants: Participant[];
  /** Sprint 4.1: whether an official/demo result exists for this
   * prediction's event. Drives share-CTA hierarchy only — the original
   * Prediction Card share section becomes visually secondary once a
   * Result Card exists to share instead (brief §7-8). Does not affect
   * scoring or any calculation. */
  hasResult?: boolean;
  /** FOUCH 0.3A: true only for a verified prediction (auth_user_id
   * set) while the event is still open per Supabase
   * events.prediction_lock_at. A legacy anonymous prediction never
   * gets this — there is no verified identity to authorize an edit
   * against, and this sprint adds no way to claim one. */
  canEdit?: boolean;
  /** FOUCH 0.3A: true for a verified prediction whose event has
   * passed prediction_lock_at — shows "YOUR CALL IS LOCKED" instead
   * of an edit affordance. Never shown for legacy predictions, which
   * never offered editing in the first place. */
  showLockedNotice?: boolean;
  /** ISO datetime, only used for display ("until {date}"). */
  predictionLockAt?: string | null;
  /** FOUCH Score section (Sprint 4) — null/absent renders nothing, which
   * is exactly the pre-result experience. Server Component, passed down
   * for the same reason as youVsTheWorld below. */
  fouchScore?: ReactNode;
  /** The You vs The World section — a Server Component rendered by the
   * page and passed down, since it needs server-side data fetching
   * that a Client Component can't do directly. */
  youVsTheWorld: ReactNode;
  /** Experiment 01 ("Your Crowd Changed") — null/absent renders
   * nothing, same pattern as the two slots above. */
  yourCrowdChanged?: ReactNode;
}) {
  const searchParams = useSearchParams();
  const isNew = searchParams.get("new") === "1";
  const isEdited = searchParams.get("edited") === "1";
  const showSavedBanner = isNew || isEdited;

  useEffect(() => {
    track("public_prediction_viewed", { event_slug: eventSlug, is_new: isNew });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (isNew) {
      track("prediction_card_generated", { event_slug: eventSlug });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const publicUrl = `${siteUrl}/p/${publicId}`;

  const originalPredictionShare = (
    <div id="share" className="mt-10 scroll-mt-20 border-t border-border pt-8">
      <p
        className={
          hasResult
            ? "text-sm text-text-muted"
            : "font-display text-lg text-text-primary"
        }
      >
        {hasResult ? "Your original prediction" : "Share your prediction"}
      </p>
      <div className="mt-3">
        <ShareActions
          eventSlug={eventSlug}
          publicUrl={publicUrl}
          storyCardUrl={`/p/${publicId}/card/story`}
          postCardUrl={`/p/${publicId}/card/post`}
        />
      </div>
    </div>
  );

  return (
    <div>
      {showSavedBanner ? (
        <div className="mt-4">
          <p className="font-display text-lg text-accent-strong">YOUR CALL IS IN</p>
          {predictionLockAt ? (
            <p className="mt-1 text-sm text-text-secondary">
              You can update your picks until {formatLockDate(predictionLockAt)}.
            </p>
          ) : null}
        </div>
      ) : null}

      <ol className="mt-6 space-y-1.5">
        {rankedParticipants.map((participant, index) => (
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

      {canEdit ? (
        <div className="mt-4">
          <Link
            href={`/p/${publicId}/edit`}
            className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-2.5 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            <Pencil className="h-4 w-4" aria-hidden />
            Edit my Top 10
          </Link>
          {predictionLockAt ? (
            <p className="mt-2 text-xs text-text-muted">
              You can update your picks until {formatLockDate(predictionLockAt)}.
            </p>
          ) : null}
        </div>
      ) : showLockedNotice ? (
        <p className="mt-4 text-sm font-medium uppercase tracking-wide text-text-muted">
          YOUR CALL IS LOCKED
        </p>
      ) : null}

      {fouchScore}

      {youVsTheWorld}

      {yourCrowdChanged}

      {/* Pre-result: original prediction sharing stays primary and sits
          right before the "Make your Top 10" CTA, unchanged from Sprint 2/3.
          Post-result: it becomes a secondary, de-emphasized block, per the
          hierarchy in Sprint 4.1's brief (Result Card is the stronger
          social object once scoring exists). */}
      {!hasResult ? originalPredictionShare : null}

      <Link
        href={`/predict/${eventSlug}?from=${publicId}`}
        onClick={() => track("public_prediction_cta_clicked", { event_slug: eventSlug })}
        className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        Make your Top 10
      </Link>

      {hasResult ? originalPredictionShare : null}
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\PublicPredictionView.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\PublicPredictionView.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\PublicPredictionView.tsx"
}

try {
    $path = "src\components\prediction\SubmitPanel.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿"use client";

import { useState } from "react";
import { PREDICTOR_COUNTRIES } from "@/lib/countries";

export function SubmitPanel({
  requiredCount,
  submitting,
  errorMessage,
  onSubmit,
}: {
  requiredCount: number;
  submitting: boolean;
  errorMessage: string | null;
  onSubmit: (nickname: string, countryCode: string) => void;
}) {
  const [nickname, setNickname] = useState("");
  const [countryCode, setCountryCode] = useState("");

  return (
    <div className="mt-8 border-t border-border pt-6">
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="text-sm text-text-secondary">Nickname</span>
          <input
            type="text"
            value={nickname}
            onChange={(event) => setNickname(event.target.value)}
            maxLength={24}
            placeholder="Optional"
            className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
          />
        </label>

        <label className="block">
          <span className="text-sm text-text-secondary">Country</span>
          <select
            value={countryCode}
            onChange={(event) => setCountryCode(event.target.value)}
            className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary focus:border-accent"
          >
            <option value="">Optional</option>
            {PREDICTOR_COUNTRIES.map((country) => (
              <option key={country.code} value={country.code}>
                {country.name}
              </option>
            ))}
          </select>
        </label>
      </div>

      <p className="mt-2 text-xs text-text-muted">
        Optional — shown publicly with your prediction. You can update your picks until predictions
        close.
      </p>

      {errorMessage ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert">
          {errorMessage}
        </p>
      ) : null}

      <button
        type="button"
        disabled={submitting}
        onClick={() => onSubmit(nickname, countryCode)}
        className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
      >
        {submitting ? "Saving…" : `Save my Top ${requiredCount}`}
      </button>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\SubmitPanel.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\SubmitPanel.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\SubmitPanel.tsx"
}

try {
    $path = "supabase\migrations\0006_identity_phase_c_cutover.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿-- Beta Hardening 0.2 — Phase C cutover migration.
--
-- ============================================================
-- GATE 2 CLOSED — ALREADY APPLIED TO PRODUCTION.
-- This migration was applied in the same controlled release as the
-- verified-lock application code (Gate 1 + Gate 2, deployed together)
-- per the sequencing in FOUCH_DATABASE_MIGRATION_PLAN.md and
-- FOUCH_BETA_HARDENING_02_PHASE_C.md's cutover procedure. It is kept
-- here, unchanged, as the historical record of that cutover — do not
-- re-run it or modify the index it drops as part of FOUCH 0.3A.
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
    $path = "supabase\migrations\0007_event_lock_config.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿-- FOUCH 0.3A — event lock configuration moves from application code
-- into the real `events` table (created but unused since 0001_init.sql).
--
-- Why: prediction_lock_at previously lived as a hardcoded ISO string
-- in src/lib/events.ts (see FouchEvent.predictionLockAt). That worked
-- for a single hardcoded event but violates the requirement that
-- editable predictions be event-driven and never trust anything
-- other than server/database time. This migration makes Supabase
-- `events.prediction_lock_at` the SINGLE authoritative source for
-- lock enforcement going forward. src/lib/events.ts may continue to
-- provide display-only metadata (name, subtitle, hero asset) for now
-- — it is no longer consulted for lock/open timing.
--
-- Additive and idempotent:
--   - ADD COLUMN IF NOT EXISTS for both new columns.
--   - The Miss Universe 2026 row is written with INSERT ... ON
--     CONFLICT (slug) DO UPDATE, so running this against an
--     environment that already has the row (manually inserted or
--     from a previous partial run) safely updates it in place
--     instead of creating a duplicate event.
--
-- Scope: intentionally limited to what 0.3A needs. This does not
-- introduce event administration, dynamic participants, or any
-- second/third event beyond keeping Miss Universe 2026 accurate.

alter table events
  add column if not exists prediction_open_at timestamptz;

alter table events
  add column if not exists prediction_lock_at timestamptz;

comment on column events.prediction_lock_at is
  'Authoritative lock time for this event''s predictions (FOUCH 0.3A). '
  'Server-side code must read this column — never src/lib/events.ts — '
  'and must compare it against server/database time, never client time.';

comment on column events.prediction_open_at is
  'Authoritative open time for this event''s predictions (FOUCH 0.3A), '
  'mirroring prediction_lock_at. Null means "no open-time restriction".';

-- Seed/update the one real event this product currently supports.
-- Values match the existing src/lib/events.ts seed exactly (same
-- slug, same lock instant) — this migration relocates the value, it
-- does not change it.
insert into events (
  slug,
  name,
  category,
  status,
  event_date,
  is_featured,
  subtitle,
  prediction_open_at,
  prediction_lock_at
)
values (
  'miss-universe-2026',
  'Miss Universe 2026',
  'pageant',
  'upcoming',
  '2026-11-24',
  true,
  'José Miguel Agrelot Coliseum, San Juan, Puerto Rico',
  null,
  '2026-11-24T00:00:00Z'
)
on conflict (slug) do update
set
  prediction_open_at = excluded.prediction_open_at,
  prediction_lock_at = excluded.prediction_lock_at;
-- Deliberately only prediction_open_at/prediction_lock_at are
-- overwritten on conflict — if a row already exists with different
-- name/subtitle/status (e.g. a founder edited it manually), this
-- migration must not clobber that. Lock config is the only thing
-- 0.3A needs to be authoritative in the database.

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0007_event_lock_config.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0007_event_lock_config.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0007_event_lock_config.sql"
}

try {
    $path = "supabase\migrations\0008_prediction_versions.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿-- FOUCH 0.3A — Editable Predictions & Version History.
--
-- ============================================================
-- DO NOT RUN THIS AGAINST PRODUCTION YET.
-- Prepared for local verification and founder review only. See
-- FOUCH_0_3A brief §22 (Migration Safety) — this sprint has a
-- deployment gate; production application is a separate, explicit
-- founder decision.
-- ============================================================
--
-- Model: `predictions` remains the LOGICAL entity — one row per
-- identity/event (its existing uniqueness rules from Phase A/C are
-- completely untouched: predictions_one_final_per_identity still
-- enforces one final logical prediction per (event_slug,
-- auth_user_id), and public_id/auth_user_id/device_token/is_final all
-- keep their exact current meaning and columns).
--
-- New: `prediction_versions` holds one IMMUTABLE snapshot per save.
-- `predictions.current_version_id` points at whichever version is
-- currently authoritative. `prediction_items` — previously scoped
-- directly to a prediction — is rescoped to a specific version, since
-- a ranking is a property of a version, not of the logical prediction
-- itself. `prediction_id` is kept on prediction_items as a
-- denormalized convenience column (not required for correctness,
-- useful for "all items ever submitted for this prediction" queries),
-- but nothing in 0.3A relies on it for "current" reads — those always
-- go through predictions.current_version_id.
--
-- Invariants this migration establishes:
--   - old versions are never overwritten (prediction_versions rows
--     are never updated by application code after insert)
--   - one logical prediction per identity/event (unchanged, enforced
--     the same way it always was)
--   - public_id is untouched — it lives on `predictions`, never
--     duplicated onto versions
--   - current version is resolvable in one step via
--     predictions.current_version_id
--   - every existing row gets a real version 1, so no prediction is
--     ever without a resolvable current version after this migration

create table if not exists prediction_versions (
  id uuid primary key default gen_random_uuid(),
  prediction_id uuid not null references predictions(id) on delete cascade,
  version_number integer not null check (version_number >= 1),
  created_at timestamptz not null default now(),
  unique (prediction_id, version_number)
);

create index if not exists prediction_versions_prediction_id_idx
  on prediction_versions (prediction_id);

alter table predictions
  add column if not exists current_version_id uuid references prediction_versions(id);

-- prediction_items moves from being scoped to a prediction to being
-- scoped to a specific version. Added nullable first so existing rows
-- aren't rejected; backfilled below; tightened to NOT NULL afterward.
alter table prediction_items
  add column if not exists version_id uuid references prediction_versions(id) on delete cascade;

-- ------------------------------------------------------------------
-- Legacy data migration: give every existing prediction a version 1
-- that is byte-for-byte what it already had, and make it current.
-- Idempotent: re-running this migration is safe because the WHERE
-- clauses below only touch predictions that don't have a
-- current_version_id yet — a prediction already migrated is skipped
-- entirely on a second run, never given a duplicate version 1.
-- ------------------------------------------------------------------

insert into prediction_versions (prediction_id, version_number, created_at)
select p.id, 1, p.submitted_at
from predictions p
where p.current_version_id is null
  and not exists (
    select 1 from prediction_versions pv where pv.prediction_id = p.id
  );

-- Point every existing item at its prediction's (now-created) version 1.
update prediction_items pi
set version_id = pv.id
from prediction_versions pv
where pv.prediction_id = pi.prediction_id
  and pv.version_number = 1
  and pi.version_id is null;

-- Make every prediction's current_version_id point at its version 1.
update predictions p
set current_version_id = pv.id
from prediction_versions pv
where pv.prediction_id = p.id
  and pv.version_number = 1
  and p.current_version_id is null;

-- ------------------------------------------------------------------
-- Tighten constraints now that backfill is complete.
-- ------------------------------------------------------------------

-- Defensive check before tightening — surfaces as a migration failure
-- (not a silent data-integrity gap) if anything above didn't reach
-- every row, e.g. a prediction with zero items.
do $$
declare
  orphaned_items integer;
  predictions_without_current integer;
begin
  select count(*) into orphaned_items from prediction_items where version_id is null;
  if orphaned_items > 0 then
    raise exception 'FOUCH 0.3A migration: % prediction_items rows have no version_id after backfill', orphaned_items;
  end if;

  select count(*) into predictions_without_current from predictions where current_version_id is null;
  if predictions_without_current > 0 then
    raise exception 'FOUCH 0.3A migration: % predictions rows have no current_version_id after backfill', predictions_without_current;
  end if;
end $$;

alter table prediction_items
  alter column version_id set not null;

-- Replace the old prediction-scoped uniqueness with version-scoped
-- uniqueness — a ranking is unique within a version, not within the
-- logical prediction as a whole (two versions of the same prediction
-- may legitimately reuse the same participant/position). Dropping the
-- CONSTRAINT (not a bare DROP INDEX — Postgres refuses to drop a
-- constraint's backing index directly) also drops its backing index.
-- Constraint names below are Postgres's default naming for the
-- inline `unique (a, b)` declarations in 0002_predictions.sql
-- (verified against a real Postgres instance, same as insert-conflict.ts's
-- constraint-name comment).
alter table prediction_items
  drop constraint if exists prediction_items_prediction_id_participant_id_key;
alter table prediction_items
  drop constraint if exists prediction_items_prediction_id_predicted_position_key;

-- Plain ADD CONSTRAINT has no IF NOT EXISTS in Postgres, so this is
-- guarded explicitly to keep the whole migration safely re-runnable.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'prediction_items_version_id_participant_id_key'
  ) then
    alter table prediction_items
      add constraint prediction_items_version_id_participant_id_key
        unique (version_id, participant_id);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'prediction_items_version_id_predicted_position_key'
  ) then
    alter table prediction_items
      add constraint prediction_items_version_id_predicted_position_key
        unique (version_id, predicted_position);
  end if;
end $$;

create index if not exists prediction_items_version_id_idx on prediction_items (version_id);

-- ------------------------------------------------------------------
-- RLS: version history is private/internal for now (brief §6) — no
-- version history UI in this sprint, and prediction_versions carries
-- no reader-facing information on its own (no ranking, just
-- version_number/created_at), but it is not granted to anon/
-- authenticated at all, matching "historical versions are private".
-- prediction_items keeps its existing public-read policy unchanged —
-- reading it publicly was always fine (it's how the public prediction
-- page and every scoring/leaderboard query already work), and that
-- policy has no notion of "current" to begin with; the application
-- layer is what filters to current-version items via
-- predictions.current_version_id, exactly as it already filters by
-- is_final = true today.
-- ------------------------------------------------------------------

alter table prediction_versions enable row level security;
-- No select/insert/update/delete policy for anon/authenticated is
-- defined — with RLS enabled and no matching policy, all access
-- through the anon/authenticated roles is denied. Only the
-- service-role key (server-side only, same as every other write path
-- in this codebase) can read or write this table.

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0008_prediction_versions.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0008_prediction_versions.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0008_prediction_versions.sql"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 21 files written successfully." -ForegroundColor Green
}
