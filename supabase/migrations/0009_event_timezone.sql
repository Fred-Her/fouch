﻿-- FOUCH 0.3A.1 — event timezone for unambiguous lock-time display.
--
-- Why: prediction_lock_at is correctly an absolute instant
-- (timestamptz), but displaying it as a naked local time ("9:00 PM")
-- is ambiguous for a worldwide audience — a viewer in Chile, Spain, or
-- Thailand would read it in their OWN browser's timezone, which has
-- nothing to do with when the actual event airs. This migration adds
-- the event's own canonical timezone so the UI can render the lock
-- instant in EVENT-local time with an unambiguous abbreviation,
-- instead of the viewer's local time.
--
-- This is presentational only. It does NOT change, reinterpret, or
-- widen prediction_lock_at itself — that column remains the sole
-- authoritative instant, compared against server time exactly as
-- before (see src/lib/prediction-lock-logic.ts, untouched by this
-- migration). See src/lib/event-time-display.ts for the pure,
-- separately-tested formatting function that consumes this column.
--
-- Additive and idempotent: ADD COLUMN IF NOT EXISTS, and the UPDATE
-- below only touches the one row this product currently has, by slug
-- — safe to re-run.

alter table events
  add column if not exists timezone text;

comment on column events.timezone is
  'IANA timezone identifier (e.g. "America/Puerto_Rico") for this '
  'event''s canonical local time — display-only. Never store an '
  'abbreviation ("AST") or fixed offset ("GMT-4") here; those are '
  'derived at render time via Intl.DateTimeFormat. Null means the UI '
  'falls back to an unambiguous UTC-labeled display.';

update events
set timezone = 'America/Puerto_Rico'
where slug = 'miss-universe-2026';
