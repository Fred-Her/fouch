# FOUCH Beta Hardening 0.2 — Phase A Implementation Note

*Additive database foundation only. No application behavior changed.
Verified against a real local Postgres instance running the actual,
unmodified project migrations — not just read for syntax.*

## Migration

**File**: `supabase/migrations/0005_identity_phase_a.sql`

**Changes**:
1. `alter table predictions add column if not exists auth_user_id uuid
   references auth.users(id);` — nullable, no default, no backfill.
2. `create unique index if not exists predictions_one_final_per_identity
   on predictions (event_slug, auth_user_id) where auth_user_id is not
   null and is_final = true;`

Nothing else. No other column, table, or view was touched.

## Identity Constraint

Exact rule, confirmed working against real Postgres:
`UNIQUE (event_slug, auth_user_id) WHERE auth_user_id IS NOT NULL AND
is_final = true`.

## Device Token Constraint

**Status: unchanged, confirmed active.** The existing
`predictions_event_device_unique` index on `(event_slug, device_token)`
— found to exactly match its documented definition, no discrepancy —
was not dropped, altered, renamed, or weakened. Verified directly: a
duplicate `(event_slug, device_token)` insert was rejected by this
exact constraint during testing, unchanged.

## Foreign Key Behavior

`auth_user_id` references `auth.users(id)` with Postgres/Supabase's
plain default (no `ON DELETE` clause specified — not `CASCADE`, not
`SET NULL`). **Verified directly**: attempting to delete an
`auth.users` row that still has predictions referencing it fails with
a foreign-key-violation error, and the referencing predictions remain
completely untouched. This satisfies "deleting an auth user must not
silently destroy prediction rows" without deciding the actual
deletion-model behavior (e.g. null the column first) — that decision
is deferred, not made here.

## Public View

**Status: unchanged.** `predictions_public` was not recreated (no
change was required). Confirmed by direct inspection of
`information_schema.columns`: exactly 8 columns — `id, public_id,
event_slug, nickname, country_code, data_status, submitted_at,
is_final`. Neither `auth_user_id` nor `device_token` is present.

## Legacy Predictions

**Status: unaffected, no backfill.** Every row inserted without an
explicit `auth_user_id` gets `NULL` automatically. Multiple `NULL`
rows for the same event coexist freely (the partial index's `WHERE
auth_user_id IS NOT NULL` clause means it never evaluates them).

## Tests

All of the following were run as real SQL against a local PostgreSQL
16 instance, using the project's actual, unmodified migration files
(`0002_predictions.sql`, `0004_predictions_public_view.sql`,
`0005_identity_phase_a.sql`) applied in sequence, plus a minimal
`auth.users` stub table (matching Supabase's own always-present `auth`
schema) — not a syntax read, not a mock:

| Case | Result |
|---|---|
| A. Legacy row, no `auth_user_id` | Inserted fine, `auth_user_id` is `NULL`, `is_final = true` |
| B. Duplicate `device_token` for the same event | **Rejected** by `predictions_event_device_unique` (unchanged, still active) |
| C. Same `auth_user_id`, same event, second final prediction | **Rejected** by `predictions_one_final_per_identity` |
| D. Same `auth_user_id`, different event | **Allowed** |
| E. Two different verified identities, same event, sharing a device (the Person A/Person B case) | **Both allowed** — the exact scenario the identity architecture was designed to fix |
| F. Multiple `NULL`-identity rows, same event | **Allowed** (3 confirmed coexisting) |
| G. `predictions_public` column list | Exactly the pre-existing 8 safe columns; `auth_user_id`/`device_token` absent |
| FK deletion safety | Deleting a referenced `auth.users` row **fails loudly**; predictions untouched |

**Full project regression suite**: typecheck clean, lint clean,
**111/111 tests passing** (identical count to before this migration —
no application code was touched, so no test count change was
expected), production build clean with an unchanged route list.

## Files Changed

- `supabase/migrations/0005_identity_phase_a.sql` (new)
- `FOUCH_BETA_HARDENING_02_PHASE_A.md` (this file, new)
- `FOUCH_BETA_HARDENING_02_CHECKLIST.md` (Phase A items marked complete only)

No application source file was modified.

## Manual Founder Steps

1. Open `supabase/migrations/0005_identity_phase_a.sql`, copy its
   contents.
2. Run it in Supabase's SQL Editor (same process as every previous
   migration).
3. Confirm the column exists: in the SQL Editor, `select
   column_name from information_schema.columns where table_name =
   'predictions' and column_name = 'auth_user_id';` should return one row.
4. Confirm the new index exists: `select indexname from pg_indexes
   where tablename = 'predictions' and indexname =
   'predictions_one_final_per_identity';` should return one row.
5. Confirm the old index is still there too: same query with
   `indexname = 'predictions_event_device_unique'` should also return
   one row.
6. Make one normal prediction through the existing, completely
   unchanged Lock flow — it should work exactly as it does today.

## Implementation Status

PHASE A: COMPLETE. Migration file created and verified against a real
Postgres instance running the project's actual migrations — not yet
applied to the founder's production Supabase project (that's manual
step 1-2 above).