# FOUCH 0.3B â€” Event Participants Import & Update Workflow

No admin panel, no CMS, no scraper. This is a documented, founder/developer-run
SQL workflow against Supabase's SQL Editor â€” the same tool already used for
every migration in this project. Nothing here requires a Next.js deploy.

Status for Miss Grand International 2026 as of this sprint:
**PENDING OFFICIAL ROSTER IMPORT** â€” `missgrandinternational.com/contestants/`
blocked automated access during this sprint's investigation, and this sprint's
explicit instruction is to never substitute Wikipedia/fan-page data for the
production seed. The event row exists (migration 0011); zero
`event_participants` rows exist yet. Use the templates below once you have
the verified roster (e.g. by viewing the official site yourself in a normal
browser, which is not bot-blocked).

## 1. Add a new participant (country confirmed, delegate confirmed)

```sql
insert into event_participants
  (event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at, notes)
values
  ('miss-grand-international-2026', 'BR', 'Brazil', 'Jane Doe', 'ACTIVE',
   'https://missgrandinternational.com/contestants/', now(), null);
```

## 2. Add a country slot with no confirmed delegate yet (PENDING)

Never invent a name. Leave `contestant_name` null and `status` = `'PENDING'`.

```sql
insert into event_participants
  (event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at)
values
  ('miss-grand-international-2026', 'PY', 'Paraguay', null, 'PENDING',
   'https://missgrandinternational.com/contestants/', now());
```

## 3. Confirm a PENDING slot's delegate (PENDING â†’ ACTIVE)

```sql
update event_participants
set contestant_name = 'Jane Doe',
    status = 'ACTIVE',
    source_checked_at = now(),
    updated_at = now()
where event_slug = 'miss-grand-international-2026'
  and country_code = 'PY'
  and status = 'PENDING';
```

## 4. Mark a participant WITHDRAWN

Never delete the row â€” existing predictions may reference its `id`.

```sql
update event_participants
set status = 'WITHDRAWN',
    source_checked_at = now(),
    updated_at = now()
where event_slug = 'miss-grand-international-2026'
  and country_code = 'BR'
  and status = 'ACTIVE';
```

## 5. Replace a participant (delegate change for the same country)

Two steps â€” mark the old row REPLACED, then insert the new delegate as a
**separate row with its own new id**. Never edit the old row's name in place.

```sql
update event_participants
set status = 'REPLACED',
    source_checked_at = now(),
    updated_at = now(),
    notes = 'Superseded by a new delegate â€” see the new ACTIVE row for Brazil.'
where event_slug = 'miss-grand-international-2026'
  and country_code = 'BR'
  and status = 'ACTIVE';

insert into event_participants
  (event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at)
values
  ('miss-grand-international-2026', 'BR', 'Brazil', 'New Delegate Name', 'ACTIVE',
   'https://missgrandinternational.com/contestants/', now());
```

The unique index `event_participants_one_current_slot_per_country` guarantees
at most one ACTIVE-or-PENDING row per country at a time â€” running the insert
before withdrawing the old row will fail loudly (constraint violation)
instead of silently creating two current slots for the same country.

## 6. Sanity checks after any change

```sql
-- One current (ACTIVE/PENDING) slot per country, at most:
select event_slug, country_code, count(*)
from event_participants
where status in ('ACTIVE', 'PENDING')
group by event_slug, country_code
having count(*) > 1;
-- Must return zero rows.

-- Current roster snapshot:
select country_name, contestant_name, status, source_checked_at
from event_participants
where event_slug = 'miss-grand-international-2026'
order by country_name;
```

## What this workflow does NOT do

- Never deletes prediction history â€” `prediction_items.participant_id` is a
  plain text column with no foreign key to this table (by design, see
  migration 0010's comment), so nothing here can ever cascade into a
  prediction.
- Never changes a historical participant's `id` â€” REPLACED/WITHDRAWN rows are
  kept forever, exactly as saved predictions already reference them.
- Never requires rebuilding or redeploying the Next.js app â€” the builder and
  every rendering path read this table live on every request.
