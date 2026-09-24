/**
 * FOUCH 0.3B â€” the entire participant status model, in one small,
 * pure, DB-free place. Every rule about which statuses are
 * selectable for a NEW prediction lives here â€” nowhere else decides
 * this independently, so builder/validation/tests all agree by
 * construction.
 */
export type EventParticipantStatus = "ACTIVE" | "PENDING" | "WITHDRAWN" | "REPLACED";

/**
 * Only ACTIVE participants may be chosen for a new Top 10 (or a new
 * version of an edited one). PENDING (identity not yet confirmed),
 * WITHDRAWN, and REPLACED are all excluded â€” the same one boolean
 * check the whole system relies on to keep "is this a valid pick"
 * uniform everywhere.
 */
export function isSelectableStatus(status: EventParticipantStatus): boolean {
  return status === "ACTIVE";
}
