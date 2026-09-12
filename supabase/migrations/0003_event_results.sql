-- Sprint 4: official result storage for FOUCH SCORE v1.0 (STAGE_RANKING).
--
-- Deliberately minimal: one row per (event_slug, data_status). Winner /
-- 1st RU / 2nd RU are exact single participant IDs; top5_extras and
-- top10_extras are unordered arrays — the schema itself makes it
-- impossible to store an invented exact position for an unordered
-- stage member, matching FOUCH_SCORING_RESEARCH.md §3/§5.
--
-- No separate "result status" state machine: a NULL/missing row means
-- "no official result yet" (existing pre-result experience, unchanged),
-- and a row's mere existence means "sufficient result to score" because
-- validate_official_result() (application-side, see
-- src/lib/official-result-validation.ts) is required before any insert.
-- This is a deliberate simplicity choice, documented in
-- FOUCH_SCORE_IMPLEMENTATION.md, appropriate for the project's current
-- scale.

create table if not exists event_results (
  id uuid primary key default gen_random_uuid(),
  event_slug text not null,
  data_status text not null check (data_status in ('demo', 'verified')),
  winner_participant_id text not null,
  first_runner_up_participant_id text not null,
  second_runner_up_participant_id text not null,
  -- Exactly 2 — enforced application-side (validateOfficialResult) since
  -- Postgres array-length CHECK constraints on a nullable array are
  -- fragile; the app is the single write path (service-role only, see
  -- RLS below), so this is sufficient defense-in-depth.
  top5_extra_participant_ids text[] not null,
  top10_extra_participant_ids text[] not null,
  source_note text,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_slug, data_status)
);

create index if not exists event_results_event_slug_idx on event_results (event_slug);

alter table event_results enable row level security;

-- Public read: the whole point is that anyone with a prediction link can
-- see whether/how it scored.
drop policy if exists "event_results are publicly readable" on event_results;
create policy "event_results are publicly readable"
  on event_results for select
  using (true);

-- No insert/update/delete policy for anon/authenticated — with RLS
-- enabled and no matching policy, those are denied by default. Only the
-- service-role key (used exclusively by scripts/set-official-result.ts,
-- server-side) can write. See FOUCH_SCORE_IMPLEMENTATION.md for how to
-- enter a result.