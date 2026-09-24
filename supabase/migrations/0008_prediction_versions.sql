-- FOUCH 0.3A â€” Editable Predictions & Version History.
--
-- ============================================================
-- DO NOT RUN THIS AGAINST PRODUCTION YET.
-- Prepared for local verification and founder review only. See
-- FOUCH_0_3A brief Â§22 (Migration Safety) â€” this sprint has a
-- deployment gate; production application is a separate, explicit
-- founder decision.
-- ============================================================
--
-- Model: `predictions` remains the LOGICAL entity â€” one row per
-- identity/event (its existing uniqueness rules from Phase A/C are
-- completely untouched: predictions_one_final_per_identity still
-- enforces one final logical prediction per (event_slug,
-- auth_user_id), and public_id/auth_user_id/device_token/is_final all
-- keep their exact current meaning and columns).
--
-- New: `prediction_versions` holds one IMMUTABLE snapshot per save.
-- `predictions.current_version_id` points at whichever version is
-- currently authoritative. `prediction_items` â€” previously scoped
-- directly to a prediction â€” is rescoped to a specific version, since
-- a ranking is a property of a version, not of the logical prediction
-- itself. `prediction_id` is kept on prediction_items as a
-- denormalized convenience column (not required for correctness,
-- useful for "all items ever submitted for this prediction" queries),
-- but nothing in 0.3A relies on it for "current" reads â€” those always
-- go through predictions.current_version_id.
--
-- Invariants this migration establishes:
--   - old versions are never overwritten (prediction_versions rows
--     are never updated by application code after insert)
--   - one logical prediction per identity/event (unchanged, enforced
--     the same way it always was)
--   - public_id is untouched â€” it lives on `predictions`, never
--     duplicated onto versions
--   - current version is resolvable in one step via
--     predictions.current_version_id
--   - every existing row gets a real version 1, so no prediction is
--     ever without a resolvable current version after this migration

create table if not exists prediction_versions (
  id uuid primary key default gen_random_uuid(),
  prediction_id uuid not null references predictions(id) on delete cascade,
  version_number integer not null check (version_number >= 1),
  created_at timestamptz not null default now(),
  unique (prediction_id, version_number)
);

create index if not exists prediction_versions_prediction_id_idx
  on prediction_versions (prediction_id);

alter table predictions
  add column if not exists current_version_id uuid references prediction_versions(id);

-- prediction_items moves from being scoped to a prediction to being
-- scoped to a specific version. Added nullable first so existing rows
-- aren't rejected; backfilled below; tightened to NOT NULL afterward.
alter table prediction_items
  add column if not exists version_id uuid references prediction_versions(id) on delete cascade;

-- ------------------------------------------------------------------
-- Legacy data migration: give every existing prediction a version 1
-- that is byte-for-byte what it already had, and make it current.
-- Idempotent: re-running this migration is safe because the WHERE
-- clauses below only touch predictions that don't have a
-- current_version_id yet â€” a prediction already migrated is skipped
-- entirely on a second run, never given a duplicate version 1.
-- ------------------------------------------------------------------

insert into prediction_versions (prediction_id, version_number, created_at)
select p.id, 1, p.submitted_at
from predictions p
where p.current_version_id is null
  and not exists (
    select 1 from prediction_versions pv where pv.prediction_id = p.id
  );

-- Point every existing item at its prediction's (now-created) version 1.
update prediction_items pi
set version_id = pv.id
from prediction_versions pv
where pv.prediction_id = pi.prediction_id
  and pv.version_number = 1
  and pi.version_id is null;

-- Make every prediction's current_version_id point at its version 1.
update predictions p
set current_version_id = pv.id
from prediction_versions pv
where pv.prediction_id = p.id
  and pv.version_number = 1
  and p.current_version_id is null;

-- ------------------------------------------------------------------
-- Tighten constraints now that backfill is complete.
-- ------------------------------------------------------------------

-- Defensive check before tightening â€” surfaces as a migration failure
-- (not a silent data-integrity gap) if anything above didn't reach
-- every row, e.g. a prediction with zero items.
do $$
declare
  orphaned_items integer;
  predictions_without_current integer;
begin
  select count(*) into orphaned_items from prediction_items where version_id is null;
  if orphaned_items > 0 then
    raise exception 'FOUCH 0.3A migration: % prediction_items rows have no version_id after backfill', orphaned_items;
  end if;

  select count(*) into predictions_without_current from predictions where current_version_id is null;
  if predictions_without_current > 0 then
    raise exception 'FOUCH 0.3A migration: % predictions rows have no current_version_id after backfill', predictions_without_current;
  end if;
end $$;

alter table prediction_items
  alter column version_id set not null;

-- Replace the old prediction-scoped uniqueness with version-scoped
-- uniqueness â€” a ranking is unique within a version, not within the
-- logical prediction as a whole (two versions of the same prediction
-- may legitimately reuse the same participant/position). Dropping the
-- CONSTRAINT (not a bare DROP INDEX â€” Postgres refuses to drop a
-- constraint's backing index directly) also drops its backing index.
-- Constraint names below are Postgres's default naming for the
-- inline `unique (a, b)` declarations in 0002_predictions.sql
-- (verified against a real Postgres instance, same as insert-conflict.ts's
-- constraint-name comment).
alter table prediction_items
  drop constraint if exists prediction_items_prediction_id_participant_id_key;
alter table prediction_items
  drop constraint if exists prediction_items_prediction_id_predicted_position_key;

-- Plain ADD CONSTRAINT has no IF NOT EXISTS in Postgres, so this is
-- guarded explicitly to keep the whole migration safely re-runnable.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'prediction_items_version_id_participant_id_key'
  ) then
    alter table prediction_items
      add constraint prediction_items_version_id_participant_id_key
        unique (version_id, participant_id);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'prediction_items_version_id_predicted_position_key'
  ) then
    alter table prediction_items
      add constraint prediction_items_version_id_predicted_position_key
        unique (version_id, predicted_position);
  end if;
end $$;

create index if not exists prediction_items_version_id_idx on prediction_items (version_id);

-- ------------------------------------------------------------------
-- RLS: version history is private/internal for now (brief Â§6) â€” no
-- version history UI in this sprint, and prediction_versions carries
-- no reader-facing information on its own (no ranking, just
-- version_number/created_at), but it is not granted to anon/
-- authenticated at all, matching "historical versions are private".
-- prediction_items keeps its existing public-read policy unchanged â€”
-- reading it publicly was always fine (it's how the public prediction
-- page and every scoring/leaderboard query already work), and that
-- policy has no notion of "current" to begin with; the application
-- layer is what filters to current-version items via
-- predictions.current_version_id, exactly as it already filters by
-- is_final = true today.
-- ------------------------------------------------------------------

alter table prediction_versions enable row level security;
-- No select/insert/update/delete policy for anon/authenticated is
-- defined â€” with RLS enabled and no matching policy, all access
-- through the anon/authenticated roles is denied. Only the
-- service-role key (server-side only, same as every other write path
-- in this codebase) can read or write this table.
