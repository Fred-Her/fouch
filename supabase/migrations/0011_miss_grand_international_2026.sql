-- FOUCH 0.3B â€” seed the Miss Grand International 2026 event row.
--
-- ============================================================
-- DO NOT RUN THIS AGAINST PRODUCTION YET.
-- ============================================================
--
-- Deliberately does NOT insert any event_participants rows. Per
-- explicit founder instruction, the official roster is NOT scraped,
-- guessed, or backfilled from secondary sources (Wikipedia, fan
-- pages) in this sprint â€” missgrandinternational.com/contestants/
-- blocked automated access during this sprint's investigation.
-- Participant rows are added later via the documented import
-- workflow (see FOUCH_EVENT_PARTICIPANTS_IMPORT.md) once the founder
-- supplies the verified roster. Status: PENDING OFFICIAL ROSTER
-- IMPORT.
--
-- prediction_lock_at: the confirmed final date is 10 October 2026 in
-- Bangkok, Thailand (multiple corroborating sources), but no
-- authoritative exact start TIME for the final show was verified
-- during this sprint. Per this sprint's own instruction ("choose a
-- safe temporary configuration clearly marked as requiring founder
-- confirmation... never silently invent a competition start time"),
-- this uses the conservative placeholder of the START of the event's
-- own calendar day in Asia/Bangkok (2026-10-10T00:00:00 local =
-- 2026-10-09T17:00:00Z) â€” safely before any results could exist,
-- exactly the same reasoning already used for Miss Universe 2026's
-- seed. This MUST be reviewed and confirmed/corrected by the founder
-- once an authoritative start time is available â€” see notes column.

insert into events (
  slug,
  name,
  category,
  status,
  event_date,
  is_featured,
  subtitle,
  timezone,
  prediction_open_at,
  prediction_lock_at
)
values (
  'miss-grand-international-2026',
  'Miss Grand International 2026',
  'pageant',
  'upcoming',
  '2026-10-10',
  true,
  'Bangkok, Thailand',
  'Asia/Bangkok',
  null,
  '2026-10-09T17:00:00Z' -- PLACEHOLDER â€” start of event-local calendar day; confirm exact final start time.
)
on conflict (slug) do update
set
  timezone = excluded.timezone;
-- Only `timezone` is overwritten on conflict, same conservative
-- pattern as 0007 â€” if this event row already exists with a founder-
-- reviewed prediction_lock_at, this migration must never clobber it.
