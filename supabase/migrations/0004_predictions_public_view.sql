-- Beta Hardening 0.1 — device_token confidentiality fix.
--
-- Root cause (found in the beta readiness audit): the `predictions`
-- table's public-read RLS policy was `using (true)` — row-level, which
-- Postgres RLS always is. It does not, and cannot, restrict which
-- COLUMNS are visible. That meant `device_token` (meant to be a
-- private anti-abuse signal, never a public field) was technically
-- readable by anyone holding the anon key, even though no current
-- application code takes that path (all real reads go through
-- server-side functions using the service-role key, which bypasses
-- RLS entirely and only ever forwards safe fields to the client — see
-- PredictionRecord in src/lib/predictions-db.ts, which has no
-- device_token field at all).
--
-- Fix: remove anon's SELECT policy on the base table, and replace it
-- with a column-restricted view containing only the fields the
-- product actually needs to be public. This doesn't change any
-- current behavior (nothing today queries the base table via the anon
-- key) — it closes the gap for good, structurally, rather than
-- relying on "nothing happens to import the browser client."
--
-- Mechanism: a Postgres view without `security_invoker` runs with its
-- OWNER's privileges when queried, not the querying role's — so this
-- view can still read the base table (RLS is bypassed for the view's
-- own internal query) while anon/authenticated are granted SELECT on
-- the view itself via a normal object-privilege grant, not RLS. Anon
-- querying the base table directly now gets nothing (no policy left);
-- anon querying predictions_public gets exactly the 8 safe columns
-- below, never device_token.

drop policy if exists "predictions are publicly readable" on predictions;

create or replace view predictions_public
as
select
  id,
  public_id,
  event_slug,
  nickname,
  country_code,
  data_status,
  submitted_at,
  is_final
from predictions;

grant select on predictions_public to anon, authenticated;

-- prediction_items and event_results were also reviewed: neither
-- contains anything sensitive (participant IDs, positions, published
-- result data), so their existing `using (true)` public-read policies
-- are correct as-is and are not changed here.