-- FOUCH — Miss Universe 2026: predictions affected by a roster change (READ-ONLY).
--
-- Lists every FINAL prediction whose CURRENT version contains a participant that is no longer
-- selectable (WITHDRAWN or REPLACED). It changes nothing: saved predictions are never edited or
-- remapped. Owners see a "No longer in the lineup" badge and a notice on their public page and
-- must replace the pick themselves (editing creates a new immutable version) before the lock.
--
-- Run it after any withdraw/replace so you know exactly who is affected and can reach out.

select p.public_id,
       p.nickname,
       i.predicted_position as position,
       ep.country_code,
       ep.contestant_name as pick_that_left,
       ep.status          as roster_status,
       (select ep2.contestant_name
          from event_participants ep2
         where ep2.event_slug = ep.event_slug
           and ep2.country_code = ep.country_code
           and ep2.status = 'ACTIVE') as current_delegate_for_that_country
from predictions p
join prediction_items i
  on i.version_id = p.current_version_id
join event_participants ep
  on ep.id::text = i.participant_id
 and ep.event_slug = p.event_slug
where p.event_slug = 'miss-universe-2026'
  and p.is_final = true
  and p.data_status = 'verified'
  and ep.status in ('WITHDRAWN', 'REPLACED')
order by p.public_id, i.predicted_position;
