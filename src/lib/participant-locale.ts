import type { Participant } from "@/types/participant";
import type { Locale } from "@/lib/locale";
import { getLocalizedCountryName } from "@/lib/countries";

/**
 * i18n v1 — presentation-only localization of a participant. The id,
 * official displayName, status, and country CODE are never touched;
 * only the human-readable country name changes. (Pure, so it is
 * directly unit-testable; participants.ts is server-only.)
 */
export function localizeParticipant(participant: Participant, locale: Locale): Participant {
  if (locale === "en") return participant;
  return {
    ...participant,
    countryName: getLocalizedCountryName(participant.countryCode, participant.countryName, locale),
  };
}

/**
 * The roster comes from the database in no guaranteed order, so the builder
 * list is sorted alphabetically by the country name IN THE VIEWER'S LANGUAGE
 * (then by contestant name as a stable tiebreak). Newly added delegates land
 * in their alphabetical place instead of at the end of the list. Pure and
 * non-mutating.
 */
export function sortParticipantsByCountry(participants: Participant[], locale: Locale): Participant[] {
  return [...participants].sort(
    (a, b) =>
      a.countryName.localeCompare(b.countryName, locale, { sensitivity: "base" }) ||
      a.displayName.localeCompare(b.displayName, locale, { sensitivity: "base" }),
  );
}
