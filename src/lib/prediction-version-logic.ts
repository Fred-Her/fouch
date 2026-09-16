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
