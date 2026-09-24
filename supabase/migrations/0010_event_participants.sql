-- FOUCH 0.3B â€” Dynamic Participants & Miss Grand International 2026.
--
-- ============================================================
-- DO NOT RUN THIS AGAINST PRODUCTION YET.
-- Prepared for local verification and founder review only.
-- ============================================================
--
-- Why a new table instead of touching prediction_items: this
-- codebase's prediction_items.participant_id is (and remains) a
-- plain TEXT column with NO foreign key â€” it never enforced
-- referential integrity against any participant table, for either
-- event. That means Miss Universe 2026's existing hardcoded
-- `demo-<code>` IDs (src/lib/participants.ts) need ZERO migration:
-- they keep working exactly as before, completely untouched by this
-- sprint. This migration only adds a NEW, separate source for events
-- that want database-driven participants â€” starting with Miss Grand
-- International 2026 â€” without retrofitting or risking Miss
-- Universe's already-live predictions.
--
-- Stable identity (brief Â§6): `id` is a server-generated uuid,
-- never derived from name/position/status/country text. A country
-- whose delegate changes gets a NEW row (new id) for the replacement
-- â€” the original row is kept, marked REPLACED, never mutated in
-- place and never deleted. This is exactly what makes historical
-- prediction_items.participant_id values (which reference a specific
-- id, stored as opaque text) stay resolvable forever, regardless of
-- what happens to that country's delegate later.

create table if not exists event_participants (
  id uuid primary key default gen_random_uuid(),
  event_slug text not null references events(slug),
  country_code text not null,
  country_name text not null,
  -- Null exactly when the official source lists the country/slot but
  -- has not yet named a confirmed delegate (status must be PENDING
  -- whenever this is null â€” enforced below).
  contestant_name text,
  status text not null check (status in ('ACTIVE', 'PENDING', 'WITHDRAWN', 'REPLACED')),
  source_url text,
  source_checked_at timestamptz,
  -- Optional short provenance note (brief Â§12) â€” e.g. "confirmed via
  -- official site country page" or "superseded by <id> on withdrawal".
  -- Free text, never parsed by application code.
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- The one real rule: a name may be absent ONLY while PENDING. Once
-- ACTIVE/WITHDRAWN/REPLACED, a contestant_name is required â€” the
-- import workflow can set a provisional name on a PENDING row before
-- flipping it to ACTIVE if it wants to, but never invents a name.
-- Plain ADD CONSTRAINT has no IF NOT EXISTS in Postgres, so this is
-- guarded explicitly to keep the whole migration safely re-runnable
-- (same pattern as migration 0008).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'event_participants_name_required_unless_pending'
  ) then
    alter table event_participants
      add constraint event_participants_name_required_unless_pending
      check (contestant_name is not null or status = 'PENDING');
  end if;
end $$;

-- Only one CURRENT (selectable-or-pending) slot per country per
-- event â€” WITHDRAWN/REPLACED rows are historical and explicitly
-- excluded from this constraint, so a country can accumulate any
-- number of past delegates over time without ever colliding.
create unique index if not exists event_participants_one_current_slot_per_country
  on event_participants (event_slug, country_code)
  where status in ('ACTIVE', 'PENDING');

create index if not exists event_participants_event_slug_idx
  on event_participants (event_slug);

-- ------------------------------------------------------------------
-- RLS: publicly readable (a historical prediction referencing a
-- WITHDRAWN/REPLACED participant must still resolve its name/country
-- for any visitor viewing that public prediction â€” see brief Â§7),
-- but never writable by anon/authenticated. Participant maintenance
-- is a trusted, server-side-only workflow (brief Â§11/Â§20) â€” same
-- pattern as every other write path in this codebase (service-role
-- key only, never a client-side privileged write).
-- ------------------------------------------------------------------

alter table event_participants enable row level security;

drop policy if exists "event participants are publicly readable" on event_participants;
create policy "event participants are publicly readable"
  on event_participants for select
  using (true);

-- No insert/update/delete policy for anon/authenticated â€” with RLS
-- enabled and no matching policy, those operations are denied by
-- default, exactly like predictions/prediction_items/prediction_versions.
