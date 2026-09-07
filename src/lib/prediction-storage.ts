const STORAGE_PREFIX = "fouch:prediction:";

interface StoredPrediction {
  eventSlug: string;
  /** Participant IDs, in ranked order â€” index 0 is position #1. */
  participantIds: string[];
}

function storageKey(eventSlug: string): string {
  return `${STORAGE_PREFIX}${eventSlug}`;
}

/**
 * Reads and validates a stored in-progress prediction for an event.
 * Never throws: a missing key, malformed JSON, or a shape that
 * doesn't match `StoredPrediction` all just return null so the caller
 * can fail safely and start fresh â€” this is browser-only scratch
 * state, not a database record.
 *
 * `validParticipantIds` lets the caller drop any stored ID that no
 * longer corresponds to an active participant (e.g. the seed data
 * changed), rather than restoring a broken prediction.
 */
export function loadPrediction(
  eventSlug: string,
  validParticipantIds: Set<string>,
): string[] {
  if (typeof window === "undefined") return [];

  try {
    const raw = window.localStorage.getItem(storageKey(eventSlug));
    if (!raw) return [];

    const parsed: unknown = JSON.parse(raw);
    if (
      typeof parsed !== "object" ||
      parsed === null ||
      !("eventSlug" in parsed) ||
      !("participantIds" in parsed)
    ) {
      return [];
    }

    const stored = parsed as StoredPrediction;
    if (stored.eventSlug !== eventSlug || !Array.isArray(stored.participantIds)) {
      return [];
    }

    return stored.participantIds.filter(
      (id): id is string => typeof id === "string" && validParticipantIds.has(id),
    );
  } catch {
    return [];
  }
}

export function savePrediction(eventSlug: string, participantIds: string[]): void {
  if (typeof window === "undefined") return;

  try {
    const payload: StoredPrediction = { eventSlug, participantIds };
    window.localStorage.setItem(storageKey(eventSlug), JSON.stringify(payload));
  } catch {
    // Storage can fail (private browsing, quota, disabled). The
    // prediction still works for the current session either way â€”
    // this is a convenience, not a requirement.
  }
}

export function clearPrediction(eventSlug: string): void {
  if (typeof window === "undefined") return;

  try {
    window.localStorage.removeItem(storageKey(eventSlug));
  } catch {
    // See savePrediction.
  }
}