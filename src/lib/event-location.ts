/**
 * FOUCH Home v1.1 — a generic, structural transform of an event's
 * subtitle ("<venue>, <city>, <region>") into a short "<city>,
 * <region>" location for compact presentations (Up Next). Derived
 * purely from comma structure, never from a specific event's
 * identity — the full subtitle (with venue) remains available
 * wherever a section chooses to show it (Now Predicting keeps the
 * full string).
 */
export function getShortLocation(subtitle: string): string {
  const parts = subtitle
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
  if (parts.length <= 2) return parts.join(", ");
  return parts.slice(-2).join(", ");
}
