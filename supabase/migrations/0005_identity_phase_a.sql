-- Beta Hardening 0.2 — Phase A: additive identity schema foundation.
--
-- This migration changes NOTHING about current product behavior. It
-- only prepares the schema for verified identity, per the frozen
-- architecture (FOUCH_IDENTITY_ARCHITECTURE.md,
-- FOUCH_DATABASE_MIGRATION_PLAN.md). Application code is not wired to
-- this column yet — that's Phase C.
--
-- Explicitly NOT touched here: the existing
-- `predictions_event_device_unique` index on (event_slug,
-- device_token) — the current anonymous submission flow still depends
-- on it for duplicate protection, and it is only dropped in Phase C,
-- alongside the new OTP application code, per the frozen cutover
-- sequence. Also not touched: `predictions_public` (the view added in
-- Beta Hardening 0.1) — it continues to expose exactly its current 8
-- columns; `auth_user_id` is never added to it.

alter table predictions
  add column if not exists auth_user_id uuid references auth.users(id);

-- No ON DELETE behavior is specified here — this is intentionally the
-- Postgres/Supabase default (effectively "NO ACTION"), not a chosen
-- CASCADE or SET NULL. That means: attempting to delete an auth.users
-- row that still has predictions referencing it will fail with a
-- foreign-key-violation error, rather than silently deleting or
-- modifying those predictions. This satisfies "deleting an auth user
-- must not silently destroy prediction rows" without deciding the
-- actual deletion model (e.g. null out auth_user_id first, or some
-- other flow) — that decision is explicitly deferred to a later
-- phase, not made here.

-- Every existing row gets auth_user_id = NULL automatically (no
-- backfill is performed, none is needed) — legacy anonymous
-- predictions remain exactly what they are.

create unique index if not exists predictions_one_final_per_identity
  on predictions (event_slug, auth_user_id)
  where auth_user_id is not null and is_final = true;