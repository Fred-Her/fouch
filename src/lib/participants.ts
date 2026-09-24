import "server-only";
import type { Participant } from "@/types/participant";
import { isSelectableStatus } from "@/lib/participant-status";
import { getAllEventParticipantRows, type EventParticipantRow } from "@/lib/event-participants-db";

/**
 * DEMO / DEVELOPMENT DATA â€” NOT the official Miss Universe 2026 lineup.
 *
 * The full, verified list of national delegates for Miss Universe 2026
 * is not yet finalized/confirmed by the organization at the time of
 * writing. Rather than invent an official-looking roster, this is a
 * clearly-marked demo set of real countries, used only to test the
 * Top 10 mechanic. See `getParticipantsForEvent`'s returned `status`
 * field â€” the UI must surface "Demo participant data" whenever it is
 * "demo", and this must never be presented as the official lineup.
 */
const demoCountries: Array<{ code: string; name: string }> = [
  { code: "AR", name: "Argentina" },
  { code: "AU", name: "Australia" },
  { code: "BR", name: "Brazil" },
  { code: "CA", name: "Canada" },
  { code: "CL", name: "Chile" },
  { code: "CO", name: "Colombia" },
  { code: "DO", name: "Dominican Republic" },
  { code: "ES", name: "Spain" },
  { code: "FR", name: "France" },
  { code: "IN", name: "India" },
  { code: "ID", name: "Indonesia" },
  { code: "IT", name: "Italy" },
  { code: "JM", name: "Jamaica" },
  { code: "JP", name: "Japan" },
  { code: "KE", name: "Kenya" },
  { code: "KR", name: "South Korea" },
  { code: "MX", name: "Mexico" },
  { code: "NG", name: "Nigeria" },
  { code: "PE", name: "Peru" },
  { code: "PH", name: "Philippines" },
  { code: "PR", name: "Puerto Rico" },
  { code: "TH", name: "Thailand" },
  { code: "VE", name: "Venezuela" },
  { code: "VN", name: "Vietnam" },
  { code: "ZA", name: "South Africa" },
].sort((a, b) => a.name.localeCompare(b.name));

const missUniverse2026Participants: Participant[] = demoCountries.map((country, index) => ({
  id: `demo-${country.code.toLowerCase()}`,
  eventId: "seed-miss-universe-2026",
  displayName: country.name,
  countryCode: country.code,
  countryName: country.name,
  sortOrder: index,
  isActive: true,
}));

const participantsByEventSlug: Record<string, Participant[]> = {
  "miss-universe-2026": missUniverse2026Participants,
};

export type ParticipantDataStatus = "demo" | "verified";

export interface ParticipantsForEvent {
  status: ParticipantDataStatus;
  participants: Participant[];
  /** FOUCH 0.3B Â§13: the most recent `source_checked_at` across this
   * event's ACTIVE participants, for the "Contestant list updated
   * {date}" copy â€” never used for a "demo" event (always null there;
   * Miss Universe's hardcoded seed has no provenance concept at all).
   * Null for a verified event with no source-checked participants
   * yet (e.g. Miss Grand before its roster import â€” see
   * FOUCH_EVENT_PARTICIPANTS_IMPORT.md). */
  sourceCheckedAt: string | null;
}

function toParticipant(row: EventParticipantRow): Participant {
  return {
    // Stable identity (0.3B Â§6): the DB row's own uuid, never derived
    // from name/position/status/country â€” see migration 0010.
    id: row.id,
    eventId: row.eventSlug,
    // A PENDING row has no confirmed contestant_name yet â€” never
    // invented here; fall back to the country name itself so the UI
    // has something displayable without fabricating a person's name.
    displayName: row.contestantName ?? row.countryName,
    countryCode: row.countryCode,
    countryName: row.countryName,
    sortOrder: 0,
    isActive: isSelectableStatus(row.status),
  };
}

/**
 * The active/selectable roster for building a NEW Top 10 (or a new
 * version of an edited one) â€” exactly the same contract this function
 * has always had: only ever returns participants a person may
 * currently choose. Every existing caller (builder, review,
 * validateSubmission's activeParticipants, edit's requiredCount) can
 * keep assuming that, unchanged â€” the only difference from before
 * 0.3B is that resolving a database-driven event's roster requires an
 * await now.
 *
 * PENDING/WITHDRAWN/REPLACED participants are deliberately excluded
 * here â€” see resolveParticipantsByIds below for the separate,
 * status-blind lookup that historical rendering needs instead.
 */
export async function getParticipantsForEvent(slug: string): Promise<ParticipantsForEvent | null> {
  const hardcoded = participantsByEventSlug[slug];
  if (hardcoded) {
    return {
      status: "demo",
      participants: hardcoded.filter((participant) => participant.isActive),
      sourceCheckedAt: null,
    };
  }

  const rows = await getAllEventParticipantRows(slug);
  if (rows.length === 0) return null;

  const active = rows.filter((row) => isSelectableStatus(row.status));
  const sourceCheckedAt = active.reduce<string | null>((latest, row) => {
    if (!row.sourceCheckedAt) return latest;
    if (!latest || row.sourceCheckedAt > latest) return row.sourceCheckedAt;
    return latest;
  }, null);

  return {
    status: "verified",
    participants: active.map(toParticipant),
    sourceCheckedAt,
  };
}

/**
 * Resolves a specific set of participant IDs to display info
 * REGARDLESS of current status â€” the one place historical rendering
 * (a saved prediction's ranking, its share card, its winner pick for
 * scoring/consensus) must go through instead of
 * getParticipantsForEvent above. A WITHDRAWN or REPLACED participant
 * still resolves here with its real name/country (isActive: false),
 * exactly so an existing prediction never silently loses an entry
 * just because that country's delegate later changed (brief Â§7).
 *
 * For Miss Universe's hardcoded roster this is equivalent to the
 * active-only lookup (every hardcoded entry is always active), so
 * behavior there is unchanged.
 */
export async function resolveParticipantsByIds(
  eventSlug: string,
  participantIds: string[],
): Promise<Map<string, Participant>> {
  const idSet = new Set(participantIds);
  const hardcoded = participantsByEventSlug[eventSlug];

  if (hardcoded) {
    const map = new Map<string, Participant>();
    for (const participant of hardcoded) {
      if (idSet.has(participant.id)) map.set(participant.id, participant);
    }
    return map;
  }

  const rows = await getAllEventParticipantRows(eventSlug);
  const map = new Map<string, Participant>();
  for (const row of rows) {
    if (idSet.has(row.id)) map.set(row.id, toParticipant(row));
  }
  return map;
}