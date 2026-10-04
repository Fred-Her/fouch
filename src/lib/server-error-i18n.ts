import type { Locale } from "@/lib/locale";

/**
 * i18n v1: server actions and DB helpers keep returning their original
 * English error strings (so server logic, logging and every existing
 * test are untouched). The UI localizes them at display time with this
 * pure lookup. Unknown messages fall back to the original English text
 * — never a raw backend/database error, because the server never
 * returns one.
 */
const EXACT_ES: Record<string, string> = {
  "This event doesn't exist.": "Este evento no existe.",
  "This event has no contestants configured.": "Este evento no tiene participantes configuradas.",
  "Missing device token.": "Falta el identificador del dispositivo. Recarga la página e inténtalo de nuevo.",
  "That doesn't look like a valid email address.": "Ese correo electrónico no parece válido.",
  "Verification isn't available right now — try again shortly.":
    "La verificación no está disponible en este momento — inténtalo de nuevo en unos minutos.",
  "We couldn't send a code — try again in a moment.":
    "No pudimos enviar el código — inténtalo de nuevo en un momento.",
  "We couldn't lock your prediction. Your Top 10 is still saved — try again.":
    "No pudimos guardar tu predicción. Tu Top 10 sigue guardado — inténtalo de nuevo.",
  "That code expired.": "Ese código expiró.",
  "That code didn't match. Check your email and try again.":
    "Ese código no coincide. Revisa tu correo e inténtalo de nuevo.",
  "Your verification expired — please request a new code.":
    "Tu verificación expiró — solicita un código nuevo.",
  "We couldn't find that prediction.": "No encontramos esa predicción.",
  "This isn't your prediction.": "Esta predicción no es tuya.",
  "Predictions for this event are locked.": "Las predicciones de este evento están cerradas.",
  "Predictions for this event haven't opened yet.":
    "Las predicciones de este evento todavía no han abierto.",
  "We couldn't save your changes. Your Top 10 is still what it was — try again.":
    "No pudimos guardar tus cambios. Tu Top 10 sigue igual — inténtalo de nuevo.",
  "Duplicate contestants aren't allowed.": "No se permiten participantes repetidas.",
  "One or more contestants are invalid for this event.":
    "Una o más participantes no son válidas para este evento.",
  "Invalid nickname.": "Apodo no válido.",
  "Invalid country.": "País no válido.",
  "Submissions aren't available yet — the database isn't configured.":
    "Aún no se pueden enviar predicciones.",
  "We couldn't save your prediction. Please try again.":
    "No pudimos guardar tu predicción. Inténtalo de nuevo.",
  "We couldn't generate a unique link. Please try again.":
    "No pudimos generar un enlace único. Inténtalo de nuevo.",
  "Editing isn't available right now — the database isn't configured.":
    "La edición no está disponible en este momento.",
  "We couldn't verify your prediction's current version.":
    "No pudimos verificar la versión actual de tu predicción.",
  "Your prediction changed elsewhere since you opened this — please reload and try again.":
    "Tu predicción cambió en otro lugar desde que abriste esta página — recarga e inténtalo de nuevo.",
  "We couldn't save your changes. Please try again.":
    "No pudimos guardar tus cambios. Inténtalo de nuevo.",
};

const PATTERNS_ES: Array<[RegExp, (match: RegExpMatchArray) => string]> = [
  [/^Exactly (\d+) contestants are required\.$/, (m) => `Se requieren exactamente ${m[1]} participantes.`],
  [/^Nickname must be (\d+) characters or fewer\.$/, (m) => `El apodo debe tener ${m[1]} caracteres o menos.`],
];

export function translateServerError(message: string | null, locale: Locale): string | null {
  if (!message || locale === "en") return message;

  const exact = EXACT_ES[message];
  if (exact) return exact;

  for (const [pattern, build] of PATTERNS_ES) {
    const match = message.match(pattern);
    if (match) return build(match);
  }
  return message;
}
