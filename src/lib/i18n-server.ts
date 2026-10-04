import "server-only";
import { headers } from "next/headers";
import { DEFAULT_LOCALE, LOCALE_HEADER, PATH_HEADER, isLocale, type Locale } from "@/lib/locale";
import { getDictionary } from "@/lib/i18n";

/** The request locale, set by src/middleware.ts. Falls back to English
 * if the header is somehow absent (e.g. a build-time render). */
export async function getLocale(): Promise<Locale> {
  const value = (await headers()).get(LOCALE_HEADER);
  return isLocale(value) ? value : DEFAULT_LOCALE;
}

/** The original (locale-stripped) request path, e.g. "/p/abc". */
export async function getRequestPath(): Promise<string> {
  return (await headers()).get(PATH_HEADER) ?? "/";
}

export async function getI18n() {
  const locale = await getLocale();
  return { locale, dict: getDictionary(locale) };
}
