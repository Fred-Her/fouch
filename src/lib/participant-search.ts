/**
 * Contestant/country search that ignores accents and case, so "peru" finds
 * "Perú", "maria" finds "MARÍA", "curacao" finds "Curaçao" and "turkiye"
 * finds "Türkiye". A few letters don't decompose under Unicode NFD, so they
 * are folded explicitly.
 */
const FOLD: Record<string, string> = { ı: "i", ł: "l", ø: "o", đ: "d", ß: "ss", æ: "ae", œ: "oe" };

export function normalizeForSearch(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/[ıłøđßæœ]/g, (char) => FOLD[char] ?? char)
    .trim();
}

export function matchesParticipantSearch(
  participant: { displayName: string; countryName: string },
  query: string,
): boolean {
  const needle = normalizeForSearch(query);
  if (!needle) return true;
  return (
    normalizeForSearch(participant.displayName).includes(needle) ||
    normalizeForSearch(participant.countryName).includes(needle)
  );
}
