-- FOUCH 0012 — demo predictions must not occupy the "one final prediction per verified identity
-- per event" slot.
--
-- Bug: Miss Universe 2026 launched as a demo event; the 8 demo predictions (data_status='demo',
-- some owned by a verified identity) kept holding the (event_slug, auth_user_id) slot. When their
-- owner saved a REAL prediction for the same event, the insert hit
-- predictions_one_final_per_identity and the app answered with the old demo prediction.
--
-- Fix: the uniqueness rule applies only to non-demo predictions. Nothing is deleted or edited;
-- existing rows are untouched. Safe to re-run.
begin;
drop index if exists predictions_one_final_per_identity;
create unique index predictions_one_final_per_identity
  on predictions (event_slug, auth_user_id)
  where auth_user_id is not null and is_final = true and data_status <> 'demo';
commit;