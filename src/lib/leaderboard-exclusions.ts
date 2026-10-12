/**
 * Explicit, per-event list of public_ids kept OFF the public
 * leaderboard (internal tests). Nothing is deleted or edited: an
 * excluded prediction keeps its public page, its score, its history
 * and its share cards — it simply isn't listed or ranked on the
 * public board. Empty until the founder confirms specific test IDs.
 */
export const LEADERBOARD_EXCLUDED_PUBLIC_IDS: Record<string, readonly string[]> = {};

export function applyLeaderboardExclusions<T extends { publicId: string }>(
  entries: T[],
  eventSlug: string,
  excluded: Record<string, readonly string[]> = LEADERBOARD_EXCLUDED_PUBLIC_IDS,
): T[] {
  const ids = excluded[eventSlug];
  if (!ids || ids.length === 0) return entries;
  const blocked = new Set(ids);
  return entries.filter((entry) => !blocked.has(entry.publicId));
}
