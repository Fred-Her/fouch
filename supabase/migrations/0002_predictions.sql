-- Sprint 2: real anonymous prediction persistence.
--
-- Security model: ALL writes go through server-side Server Actions
-- using the service-role key, which bypasses RLS by design — that is
-- where every validation rule (exact 10 positions, active
-- participants, event lock time, etc.) is enforced. RLS here is
-- defense-in-depth for the anon/public read path: anyone can read a
-- prediction by its public_id (that's the point — public prediction
-- pages need no login), but nobody can write, update, or delete
-- through the anon key.

create table if not exists predictions (
  id uuid primary key default gen_random_uuid(),
  public_id text not null unique,
  -- Events and participants are currently code-defined seed/demo data
  -- (see src/lib/events.ts, src/lib/participants.ts), not DB rows —
  -- so this references the event by slug, not a foreign key. When
  -- events move into Postgres, this can become a real FK.
  event_slug text not null,
  nickname text,
  country_code text,
  data_status text not null check (data_status in ('demo', 'verified')),
  device_token text not null,
  submitted_at timestamptz not null default now(),
  is_final boolean not null default true
);

-- One prediction per device per event — the lightweight duplicate/abuse
-- guard described in the sprint brief. Not foolproof (a user can clear
-- localStorage), but stops accidental double-submits and casual replay
-- without collecting IP or device fingerprinting data.
create unique index if not exists predictions_event_device_unique
  on predictions (event_slug, device_token);

create index if not exists predictions_event_slug_idx on predictions (event_slug);

create table if not exists prediction_items (
  id uuid primary key default gen_random_uuid(),
  prediction_id uuid not null references predictions(id) on delete cascade,
  participant_id text not null,
  predicted_position integer not null check (predicted_position between 1 and 10),
  created_at timestamptz not null default now(),
  unique (prediction_id, participant_id),
  unique (prediction_id, predicted_position)
);

create index if not exists prediction_items_prediction_id_idx on prediction_items (prediction_id);

alter table predictions enable row level security;
alter table prediction_items enable row level security;

-- Public read: prediction pages are shareable links, no login required.
drop policy if exists "predictions are publicly readable" on predictions;
create policy "predictions are publicly readable"
  on predictions for select
  using (true);

drop policy if exists "prediction_items are publicly readable" on prediction_items;
create policy "prediction_items are publicly readable"
  on prediction_items for select
  using (true);

-- No insert/update/delete policies are defined for anon/authenticated
-- roles on purpose: with RLS enabled and no matching policy, those
-- operations are denied by default. Only the service-role key (used
-- exclusively in src/app/predict/[slug]/actions.ts, server-side) can
-- write.