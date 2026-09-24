-- FOUCH 0.3A â€” event lock configuration moves from application code
-- into the real `events` table (created but unused since 0001_init.sql).
--
-- Why: prediction_lock_at previously lived as a hardcoded ISO string
-- in src/lib/events.ts (see FouchEvent.predictionLockAt). That worked
-- for a single hardcoded event but violates the requirement that
-- editable predictions be event-driven and never trust anything
-- other than server/database time. This migration makes Supabase
-- `events.prediction_lock_at` the SINGLE authoritative source for
-- lock enforcement going forward. src/lib/events.ts may continue to
-- provide display-only metadata (name, subtitle, hero asset) for now
-- â€” it is no longer consulted for lock/open timing.
--
-- Additive and idempotent:
--   - ADD COLUMN IF NOT EXISTS for both new columns.
--   - The Miss Universe 2026 row is written with INSERT ... ON
--     CONFLICT (slug) DO UPDATE, so running this against an
--     environment that already has the row (manually inserted or
--     from a previous partial run) safely updates it in place
--     instead of creating a duplicate event.
--
-- Scope: intentionally limited to what 0.3A needs. This does not
-- introduce event administration, dynamic participants, or any
-- second/third event beyond keeping Miss Universe 2026 accurate.

alter table events
  add column if not exists prediction_open_at timestamptz;

alter table events
  add column if not exists prediction_lock_at timestamptz;

comment on column events.prediction_lock_at is
  'Authoritative lock time for this event''s predictions (FOUCH 0.3A). '
  'Server-side code must read this column â€” never src/lib/events.ts â€” '
  'and must compare it against server/database time, never client time.';

comment on column events.prediction_open_at is
  'Authoritative open time for this event''s predictions (FOUCH 0.3A), '
  'mirroring prediction_lock_at. Null means "no open-time restriction".';

-- Seed/update the one real event this product currently supports.
-- Values match the existing src/lib/events.ts seed exactly (same
-- slug, same lock instant) â€” this migration relocates the value, it
-- does not change it.
insert into events (
  slug,
  name,
  category,
  status,
  event_date,
  is_featured,
  subtitle,
  prediction_open_at,
  prediction_lock_at
)
values (
  'miss-universe-2026',
  'Miss Universe 2026',
  'pageant',
  'upcoming',
  '2026-11-24',
  true,
  'JosÃ© Miguel Agrelot Coliseum, San Juan, Puerto Rico',
  null,
  '2026-11-24T00:00:00Z'
)
on conflict (slug) do update
set
  prediction_open_at = excluded.prediction_open_at,
  prediction_lock_at = excluded.prediction_lock_at;
-- Deliberately only prediction_open_at/prediction_lock_at are
-- overwritten on conflict â€” if a row already exists with different
-- name/subtitle/status (e.g. a founder edited it manually), this
-- migration must not clobber that. Lock config is the only thing
-- 0.3A needs to be authoritative in the database.
