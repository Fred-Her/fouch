-- FOUCH — Miss Universe 2026: SAFE roster upsert.   *** PROPOSAL — NOT RUN, nothing applied yet ***
--
-- Goal: add newly verified delegates WITHOUT touching anything that already exists.
--
-- GUARANTEES (the script enforces them and aborts otherwise):
--   * Existing rows keep their participant id AND their contestant_name — this script never
--     renames anyone. A different name for an existing country is only REPORTED in Part 1.
--   * Only countries with no current (ACTIVE/PENDING) row get a new row (new uuid); the partial
--     unique index event_participants_one_current_slot_per_country is a second safety net.
--   * Saved predictions are never read-modified: a checksum of prediction_items must be
--     identical before and after, or the whole transaction rolls back.
--   * A genuine delegate change (same country, different person) is NOT automatic. It is done
--     explicitly, one country at a time, with the REPLACED + new-row pattern (see Part 3), so the
--     old id survives for saved predictions and the owners get the "no longer in the lineup" notice.
--   * No placeholder rows: a country with no named, verified delegate is simply not listed.
--
-- HOW TO USE: run PART 1 (read-only) and read it. If every row says what you expect, run PART 2.

-- ============================== PART 1 — DRY RUN (read-only) ==============================
begin;
create temp table roster_candidates (
  country_code     text primary key,
  country_name     text not null,
  contestant_name  text not null,
  source_url       text,
  notes            text
) on commit drop;

insert into roster_candidates (country_code, country_name, contestant_name, source_url, notes) values
  ('CO', 'Colombia', 'MARÍA ALEJANDRA LÓPEZ', 'https://www.portafolio.co/tendencias/sociales/ingeniera-industrial-y-reina-quien-es-maria-alejandra-lopez-la-nueva-miss-universe-colombia-504261', 'Full name María Alejandra López Pérez (Risaralda), crowned 10 Oct 2026. Also: El Colombiano, Claro Sports, Minuto60, Publimetro, Minuto30.'),
  ('HK', 'Hong Kong', 'JEN ZHOU', 'https://www.taiwannews.com.tw/en/news/6452043', 'Official Miss Universe Hong Kong release, 5 Oct 2026 (Media OutReach). Also listed as ''Jennifer Zhou'' by Conan Daily.');

select c.country_code,
       c.country_name,
       cur.contestant_name  as current_name,
       cur.status           as current_status,
       c.contestant_name    as proposed_name,
       case
         when cur.id is null and exists (
                select 1 from event_participants old
                where old.event_slug = 'miss-universe-2026' and old.country_code = c.country_code
              )                                               then 'INSERT_NEW (country has only withdrawn/replaced rows)'
         when cur.id is null                                  then 'INSERT_NEW'
         when lower(cur.contestant_name) = lower(c.contestant_name) then 'UNCHANGED (keep id and name; refresh check date only)'
         else 'DIFFERENT_NAME_REVIEW (NOT applied by this script)'
       end as action
from roster_candidates c
left join event_participants cur
  on cur.event_slug = 'miss-universe-2026'
 and cur.country_code = c.country_code
 and cur.status in ('ACTIVE', 'PENDING')
order by action, c.country_code;
rollback;

-- ============================== PART 2 — APPLY (new countries only) =======================
begin;
create temp table roster_candidates (
  country_code     text primary key,
  country_name     text not null,
  contestant_name  text not null,
  source_url       text,
  notes            text
) on commit drop;

insert into roster_candidates (country_code, country_name, contestant_name, source_url, notes) values
  ('CO', 'Colombia', 'MARÍA ALEJANDRA LÓPEZ', 'https://www.portafolio.co/tendencias/sociales/ingeniera-industrial-y-reina-quien-es-maria-alejandra-lopez-la-nueva-miss-universe-colombia-504261', 'Full name María Alejandra López Pérez (Risaralda), crowned 10 Oct 2026. Also: El Colombiano, Claro Sports, Minuto60, Publimetro, Minuto30.'),
  ('HK', 'Hong Kong', 'JEN ZHOU', 'https://www.taiwannews.com.tw/en/news/6452043', 'Official Miss Universe Hong Kong release, 5 Oct 2026 (Media OutReach). Also listed as ''Jennifer Zhou'' by Conan Daily.');

create temp table ids_before on commit drop as
  select id, country_code, contestant_name, status
  from event_participants where event_slug = 'miss-universe-2026';

create temp table items_before on commit drop as
  select count(*) as n,
         md5(coalesce(string_agg(id::text || participant_id || predicted_position::text, ',' order by id::text), '')) as checksum
  from prediction_items;

-- 2a. Insert only countries that have NO current delegate.
insert into event_participants
  (event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at, notes)
select 'miss-universe-2026', c.country_code, c.country_name, c.contestant_name, 'ACTIVE',
       c.source_url, now(), c.notes
from roster_candidates c
where not exists (
  select 1 from event_participants ep
  where ep.event_slug = 'miss-universe-2026'
    and ep.country_code = c.country_code
    and ep.status in ('ACTIVE', 'PENDING')
)
on conflict do nothing;

-- 2b. Re-confirmed, same person: refresh ONLY the check date (never name, id, or status).
update event_participants ep
set source_checked_at = now(), updated_at = now()
from roster_candidates c
where ep.event_slug = 'miss-universe-2026'
  and ep.country_code = c.country_code
  and ep.status = 'ACTIVE'
  and lower(ep.contestant_name) = lower(c.contestant_name);

-- 2c. Invariants — abort (roll back everything) if any existing row or prediction changed.
do $$
begin
  if exists (
    select 1 from ids_before b
    left join event_participants ep on ep.id = b.id
    where ep.id is null
       or ep.contestant_name is distinct from b.contestant_name
       or ep.country_code    is distinct from b.country_code
       or ep.status          is distinct from b.status
  ) then
    raise exception 'An existing participant row changed (id/name/country/status). Rolling back.';
  end if;

  if (select (n, checksum) from items_before) is distinct from
     (select (count(*), md5(coalesce(string_agg(id::text || participant_id || predicted_position::text, ',' order by id::text), '')))
        from prediction_items) then
    raise exception 'prediction_items changed. Rolling back.';
  end if;

  if exists (
    select 1 from event_participants
    where event_slug = 'miss-universe-2026' and status in ('ACTIVE','PENDING')
    group by country_code having count(*) > 1
  ) then
    raise exception 'More than one current delegate for a country. Rolling back.';
  end if;
end $$;

select count(*) filter (where status = 'ACTIVE') as active_delegates,
       count(*) as total_rows
from event_participants where event_slug = 'miss-universe-2026';
commit;

-- ============================== PART 3 — DELEGATE CHANGE (manual, one country at a time) ==
-- Only when a country's delegate genuinely changed and a reliable source says so. Example for
-- country XX (replace the placeholders). Never edit the old row's name in place:
--
-- update event_participants
--    set status = 'REPLACED', source_checked_at = now(), updated_at = now(),
--        notes = 'Superseded by a new delegate — see the new ACTIVE row.'
--  where event_slug = 'miss-universe-2026' and country_code = 'XX' and status = 'ACTIVE';
--
-- insert into event_participants
--   (event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at, notes)
-- values ('miss-universe-2026', 'XX', 'Country', 'NEW DELEGATE NAME', 'ACTIVE', 'https://…', now(), 'why/when/sources');
--
-- Then run miss-universe-2026-affected-predictions.sql to see which saved predictions include the
-- old delegate. They are not edited; their owners see the notice and replace the pick themselves.
