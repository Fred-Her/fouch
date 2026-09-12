import type { OfficialResultInput } from "@/types/scoring";
import type { Participant } from "@/types/participant";

export type OfficialResultValidation = { valid: true } | { valid: false; error: string };

/**
 * Validates an official result BEFORE it's accepted (research §24).
 * Rejects invalid structures outright — never silently corrects them.
 */
export function validateOfficialResult(
  result: OfficialResultInput,
  activeParticipants: Participant[],
): OfficialResultValidation {
  if (result.top5Extras.length !== 2) {
    return { valid: false, error: "top5Extras must contain exactly 2 participants." };
  }
  if (result.top10Extras.length !== 5) {
    return { valid: false, error: "top10Extras must contain exactly 5 participants." };
  }

  const allIds = [
    result.winner,
    result.firstRunnerUp,
    result.secondRunnerUp,
    ...result.top5Extras,
    ...result.top10Extras,
  ];

  if (new Set(allIds).size !== allIds.length) {
    return { valid: false, error: "Duplicate participant appears more than once in the result." };
  }

  const validIds = new Set(activeParticipants.map((p) => p.id));
  const unknown = allIds.filter((id) => !validIds.has(id));
  if (unknown.length > 0) {
    return { valid: false, error: `Unknown or inactive participant(s): ${unknown.join(", ")}` };
  }

  // Nested-stage consistency is implied by construction (winner/RU1/RU2 are
  // disjoint from top5Extras/top10Extras by the duplicate check above), but
  // stated explicitly per research §24's "podium belongs to Top5, Top5
  // belongs to Top10" requirement — true here by definition of the sets.

  return { valid: true };
}