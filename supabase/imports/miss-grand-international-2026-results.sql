-- FOUCH — Miss Grand International 2026: load the OFFICIAL result and close the event.
--
-- Run ONCE in the Supabase SQL Editor (production), after founder approval.
-- Plain data load, not a schema migration. It never touches predictions,
-- prediction versions, participants, scoring, or prediction_lock_at.
--
-- Official final (Grand Final, 10 Oct 2026, MGI Hall, Bangkok):
--   Winner ............ Tanzania        (TZ)
--   1st runner-up ..... Ecuador         (EC)
--   2nd runner-up ..... Netherlands     (NL)
--   3rd runner-up ..... Guatemala       (GT)  } stored as the unordered
--   4th runner-up ..... Vietnam         (VN)  } "Top 5 extras" (positions 4-5)
--   SIX equal 5th runners-up (a TIED Top 11 — no invented positions 6-11):
--     Côte d'Ivoire (CI), Cuba (CU), Mexico (MX), Puerto Rico (PR),
--     Thailand (TH), Venezuela (VE)
--
-- Participants are matched by country_code (never by name) against the
-- ACTIVE roster. The script ABORTS — inserting nothing — if any finalist
-- doesn't map to exactly one ACTIVE participant, or if a verified result
-- already exists (it never overwrites).

begin;

do $$
declare
  finalists text[] := array['TZ','EC','NL','GT','VN','CI','CU','MX','PR','TH','VE'];
  mapped int;
begin
  select count(*) into mapped
  from event_participants
  where event_slug = 'miss-grand-international-2026'
    and status = 'ACTIVE'
    and country_code = any (finalists);

  if mapped <> 11 then
    raise exception 'Expected 11 ACTIVE finalists to map, found %. Nothing was written.', mapped;
  end if;

  if (select count(distinct country_code) from event_participants
      where event_slug = 'miss-grand-international-2026' and status = 'ACTIVE'
        and country_code = any (finalists)) <> 11 then
    raise exception 'A finalist country maps to more than one ACTIVE participant. Nothing was written.';
  end if;

  if exists (
    select 1 from event_results
    where event_slug = 'miss-grand-international-2026' and data_status = 'verified'
  ) then
    raise exception 'A verified result already exists for this event — refusing to overwrite.';
  end if;

  if not exists (select 1 from events where slug = 'miss-grand-international-2026') then
    raise exception 'Event row miss-grand-international-2026 not found.';
  end if;
end $$;

insert into event_results (
  event_slug,
  data_status,
  winner_participant_id,
  first_runner_up_participant_id,
  second_runner_up_participant_id,
  top5_extra_participant_ids,
  top10_extra_participant_ids,
  source_note
)
select
  'miss-grand-international-2026',
  'verified',
  (select id::text from event_participants where event_slug = 'miss-grand-international-2026' and status = 'ACTIVE' and country_code = 'TZ'),
  (select id::text from event_participants where event_slug = 'miss-grand-international-2026' and status = 'ACTIVE' and country_code = 'EC'),
  (select id::text from event_participants where event_slug = 'miss-grand-international-2026' and status = 'ACTIVE' and country_code = 'NL'),
  array(select id::text from event_participants where event_slug = 'miss-grand-international-2026' and status = 'ACTIVE' and country_code in ('GT','VN') order by country_code),
  array(select id::text from event_participants where event_slug = 'miss-grand-international-2026' and status = 'ACTIVE' and country_code in ('CI','CU','MX','PR','TH','VE') order by country_code),
  'Official Grand Final result, 10 Oct 2026 (Bangkok): winner Tanzania; runners-up Ecuador, Netherlands, Guatemala, Vietnam; six equal 5th runners-up (tied Top 11): Cote d''Ivoire, Cuba, Mexico, Puerto Rico, Thailand, Venezuela. Tied finalists stored unordered.';

-- Close the event. Leaves is_featured for Miss Universe untouched; MGI simply
-- stops being featured/upcoming. prediction_lock_at is NOT modified.
update events
set status = 'completed',
    is_featured = false
where slug = 'miss-grand-international-2026';

-- Verification (read this output before trusting the load):
select
  r.event_slug,
  r.data_status,
  array_length(r.top5_extra_participant_ids, 1)  as top5_extras,
  array_length(r.top10_extra_participant_ids, 1) as tied_top11_extras,
  e.status,
  e.is_featured,
  e.prediction_lock_at
from event_results r
join events e on e.slug = r.event_slug
where r.event_slug = 'miss-grand-international-2026';

commit;
