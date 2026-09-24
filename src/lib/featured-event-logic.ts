/**
 * FOUCH 0.3B Event Resolution Fix — the entire "which event is
 * featured" decision, in one pure, DB-free place. Extracted
 * specifically so the tie-break behavior (more than one row with
 * is_featured = true, which must never happen by product intent but
 * is not enforced by a DB constraint — see this fix's report for why)
 * is deterministic and directly testable, without needing a live
 * Supabase client.
 *
 * The real DB query (getFeaturedEventFromDb in events-db.ts) mirrors
 * this exact tie-break by ordering on `slug` ascending before
 * limiting to 1 row, so this function's behavior and the live query's
 * behavior can never drift apart.
 */
export interface FeaturedCandidate {
  slug: string;
  isFeatured: boolean;
}

/**
 * Returns the slug of the featured event, or null if none is
 * currently featured. If more than one candidate has isFeatured
 * true — a data-entry mistake, not a supported state — picks the one
 * with the alphabetically first slug, deterministically, rather than
 * an arbitrary/unstable choice.
 */
export function pickFeaturedEventSlug(candidates: FeaturedCandidate[]): string | null {
  const featured = candidates.filter((c) => c.isFeatured);
  if (featured.length === 0) return null;
  const sorted = [...featured].sort((a, b) => a.slug.localeCompare(b.slug));
  return sorted[0]?.slug ?? null;
}
