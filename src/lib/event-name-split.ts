/**
 * FOUCH 0.3B Home Multi-Event Rendering Fix — the FeaturedEvent card's
 * two-line typography ("MISS UNIVERSE" / "2026") used to be two
 * literal hardcoded strings, which meant every event rendered as
 * "Miss Universe 2026" regardless of which event was actually
 * featured. This is the generic, event-agnostic replacement: split
 * any event.name into a "primary" line and a trailing "year" line
 * purely by pattern (a trailing 4-digit token), never by matching a
 * specific event's name. The next event added to the `events` table
 * needs zero changes here.
 */
export function splitEventNameYear(name: string): { primary: string; year: string | null } {
  const match = name.trim().match(/^(.*\S)\s+(\d{4})$/);
  if (!match) return { primary: name.trim(), year: null };
  const primary = match[1] ?? name.trim();
  const year = match[2] ?? null;
  return { primary, year };
}

/**
 * Compact label for tight spots (e.g. the Home results link):
 * "Miss Grand International 2026" -> "MGI 2026". Only abbreviates
 * names of three or more words; shorter names ("Miss Universe 2026")
 * are returned in full. Pure and generic — never keyed to one event.
 */
export function getEventShortLabel(name: string): string {
  const { primary, year } = splitEventNameYear(name);
  const words = primary.split(/\s+/).filter(Boolean);
  if (words.length < 3) return name.trim();
  const initials = words.map((word) => word.charAt(0).toUpperCase()).join("");
  return year ? `${initials} ${year}` : initials;
}
