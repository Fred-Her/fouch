-- Sprint 0: minimal, category-agnostic schema.
-- Deliberately does NOT include predictions, prediction_items, scores,
-- leaderboards, profiles, shares, achievements, or leagues — those are
-- later sprints. The homepage currently reads from src/lib/events.ts
-- seed data, not from this table yet; this migration exists so the
-- schema is ready when that switch happens.

create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  category text not null check (category in ('pageant', 'awards', 'music', 'reality', 'talent', 'tv')),
  status text not null check (status in ('upcoming', 'open', 'live', 'completed')),
  event_date date not null,
  hero_asset text,
  is_featured boolean not null default false,
  subtitle text,
  created_at timestamptz not null default now()
);

comment on table events is 'Category-agnostic entertainment events (pageants, awards, music, etc).';
