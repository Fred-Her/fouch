-- FOUCH — Miss Universe 2026: load the VERIFIED launch roster, set the prediction lock, and open the event.
--
-- Run ONCE in the Supabase SQL Editor (production), AFTER the code deploy that makes the event
-- database-driven (until this runs, Miss Universe stays "Coming soon"). Plain data load, not a
-- schema migration. It never touches predictions, prediction versions, scoring, or Miss Grand.
--
-- ROSTER: 24 delegates, each named by El Nuevo Día's October 2026 candidate coverage AND by at
-- least one other independent, current source (see `notes`). Matched by country_code. The other
-- ~57 delegates cited only by Wikipedia (a pre-September snapshot) are added LATER, one verified
-- batch at a time, with the workflow in FOUCH_EVENT_PARTICIPANTS_IMPORT.md (e.g. Argentina had
-- already changed delegates since that snapshot). Thailand is HELD: its participation is disputed
-- inside the Miss Universe Organization (9 Oct 2026). No placeholders are inserted for any
-- missing country.
--
-- LOCK: the Grand Final is Tue 24 Nov 2026, 8:00 PM Puerto Rico time (America/Puerto_Rico, UTC-4;
-- official venue/ticketing page + Ticketera). The lock is one hour earlier — 7:00 PM AST =
-- 2026-11-24 23:00:00+00 — the same policy used for Miss Grand. It replaces the provisional value
-- 2026-11-24 00:00:00+00 and refuses to run if the lock was already changed by someone else.
-- prediction_open_at stays NULL (predictions open immediately).
--
-- The script ABORTS (writing nothing) if the event row is missing, if the event already has roster
-- rows, or if the lock is no longer the provisional value.

begin;

do $$
begin
  if not exists (select 1 from events where slug = 'miss-universe-2026') then
    raise exception 'Event row miss-universe-2026 not found. Nothing was written.';
  end if;

  if exists (select 1 from event_participants where event_slug = 'miss-universe-2026') then
    raise exception 'miss-universe-2026 already has roster rows — this is the INITIAL load only. Use the add/withdraw/replace workflow instead. Nothing was written.';
  end if;

  if not exists (
    select 1 from events
    where slug = 'miss-universe-2026' and prediction_lock_at = '2026-11-24 00:00:00+00'
  ) then
    raise exception 'prediction_lock_at is no longer the provisional 2026-11-24 00:00:00+00 — refusing to overwrite. Nothing was written.';
  end if;
end $$;

insert into event_participants
  (event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at, notes)
values
  ('miss-universe-2026', 'AR', 'Argentina', 'DAIANA PEREYRA', 'ACTIVE', 'https://www.hola.com/us/celebrities/20260921924564/miss-argentina-organization-replaces-tamara-rogouski-miss-universe-final/', '2026-10-12 00:00:00+00', 'Replaced Tamara Rogouski (withdrew 15-16 Sep 2026). Official Miss Universe Argentina communiqué; Telemundo, La Nación, Hola, Canal 12 Misiones.'),
  ('miss-universe-2026', 'AU', 'Australia', 'CAITLIN WORTHINGTON', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Gold Coast Magazine, 26 Aug 2026.'),
  ('miss-universe-2026', 'BZ', 'Belize', 'CALEIGH-ROSE WEST', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Breaking Belize News, 16 Aug 2026.'),
  ('miss-universe-2026', 'BO', 'Bolivia', 'VALERIA MENA', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Red Uno de Bolivia, 26 Jul 2026.'),
  ('miss-universe-2026', 'BR', 'Brazil', 'MARCELLA KOZINSKI', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: R7, 26 Jul 2026.'),
  ('miss-universe-2026', 'BG', 'Bulgaria', 'ANNA MARIA BABAU', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Town.bg, 21 Jul 2026.'),
  ('miss-universe-2026', 'CL', 'Chile', 'DOMINGA LÓPEZ', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: BioBioChile, 3 Aug 2026.'),
  ('miss-universe-2026', 'CR', 'Costa Rica', 'MARÍA ALEJANDRA ACOSTA', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Known as Mariale Acosta. Also: CRHoy; La Teja, 5 Jun 2026.'),
  ('miss-universe-2026', 'CU', 'Cuba', 'MIA DIO', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Legal name Mia Angelina Donadio Cancio. Also: El Nuevo Día (Miss Universe Cuba 2026).'),
  ('miss-universe-2026', 'CW', 'Curaçao', 'BIANTY GOMPERTS', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: NoticiaCla, 27 Jul 2026.'),
  ('miss-universe-2026', 'DO', 'Dominican Republic', 'MELISSA NÚÑEZ', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: El Nacional RD, 30 Jul 2026.'),
  ('miss-universe-2026', 'EC', 'Ecuador', 'DALIA BUCARAM', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Primicias, 15 Aug 2026.'),
  ('miss-universe-2026', 'EG', 'Egypt', 'SONIA GERGIS', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: CinemaBravo, 16 Aug 2026.'),
  ('miss-universe-2026', 'GT', 'Guatemala', 'MARÍA ADELINA CASTILLO', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Prensa Libre, 8 Aug 2026.'),
  ('miss-universe-2026', 'IN', 'India', 'KAZIAH LIZ MEJO', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: India TV, 24 Aug 2026.'),
  ('miss-universe-2026', 'KE', 'Kenya', 'JEAN OJIRO', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Kenya Times, 28 Jul 2026.'),
  ('miss-universe-2026', 'MX', 'Mexico', 'MARÍA VARGAS', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Hola, 30 Aug 2026 (crowned Miss Universe México 2026).'),
  ('miss-universe-2026', 'PY', 'Paraguay', 'GRETHA MATIAUDA', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: La Tribuna (PY), 26 Mar 2026.'),
  ('miss-universe-2026', 'PE', 'Peru', 'LUREN MÁRQUEZ', 'ACTIVE', 'https://www.hola.com/us-es/celebrities/20260817918486/luren-marquez-miss-universe-peru-recupera-titulo/', '2026-10-12 00:00:00+00', 'Dismissed 13 Aug 2026, reinstated 15 Aug 2026 (América TV, RPP, El Nuevo Día, Hola).'),
  ('miss-universe-2026', 'PH', 'Philippines', 'BEA MILLAN-WINDORSKI', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Listed by El Nuevo Día as Beatrice Millan-Windorski. Also: GMA News, 23 Jul 2026.'),
  ('miss-universe-2026', 'PR', 'Puerto Rico', 'JENNIFER BARRETO', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Hola, 9 Oct 2026.'),
  ('miss-universe-2026', 'ES', 'Spain', 'SUSANA MEDINA', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Listed by El Nuevo Día as Susana Lucía Medina. Also: Puerto de la Cruz, 19 Jul 2026.'),
  ('miss-universe-2026', 'US', 'United States', 'JUSTUS KELLEY', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: El Nuevo Día, 11 Oct 2026.'),
  ('miss-universe-2026', 'VE', 'Venezuela', 'CLARA VEGAS', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Hola, 7 Sep 2026.');

do $$
declare n int;
begin
  select count(*) into n from event_participants
  where event_slug = 'miss-universe-2026' and status = 'ACTIVE';
  if n <> 24 then
    raise exception 'Expected 24 ACTIVE delegates after the load, found %. Rolling back.', n;
  end if;
end $$;

update events
set prediction_lock_at = '2026-11-24 23:00:00+00',
    is_featured = true
where slug = 'miss-universe-2026';

-- Verification (read this output before trusting the load):
select slug, status, is_featured, prediction_open_at, prediction_lock_at, timezone
from events order by slug;

select count(*) filter (where status = 'ACTIVE') as active_delegates,
       count(*) filter (where status <> 'ACTIVE') as non_active_rows
from event_participants where event_slug = 'miss-universe-2026';

commit;
