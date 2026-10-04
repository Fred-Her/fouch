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
