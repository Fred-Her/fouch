-- FOUCH 0.3B Event Resolution Fix — set the Home's featured event.
--
-- Plain data update, not a schema migration — no new column, no new
-- table. Run this in the SQL Editor once the code deploy that makes
-- `events` the source of truth for getEventBySlug/getFeaturedEvent is
-- live (otherwise the old hardcoded array would still be what the
-- Home reads, and this change would have no visible effect yet).
--
-- Does not touch prediction_lock_at, timezone, roster, or anything
-- else on either event row.

update events set is_featured = true where slug = 'miss-grand-international-2026';
update events set is_featured = false where slug = 'miss-universe-2026';

-- Verify exactly one event is featured afterward:
-- select slug, is_featured from events order by slug;
-- Expected: miss-grand-international-2026 = true, miss-universe-2026 = false.
