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