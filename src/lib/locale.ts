/**
 * FOUCH i18n v1 — pure, edge-safe locale rules (no server-only, no
 * next/headers) so the middleware, server components, client
 * components and unit tests all share exactly one implementation.
 *
 * Strategy: ONE application, localized presentation only. English is
 * the default and lives at the unprefixed URL (/p/abc); Spanish lives
 * at /es/... which the middleware rewrites to the very same route
 * files — so /p/abc and /es/p/abc always resolve to the same
 * prediction, and no existing public URL changes.
 */
export const LOCALES = ["en", "es"] as const;
export type Locale = (typeof LOCALES)[number];
export const DEFAULT_LOCALE: Locale = "en";

export const LOCALE_HEADER = "x-fouch-locale";
export const PATH_HEADER = "x-fouch-pathname";
export const LOCALE_COOKIE = "fouch_locale";
export const LOCALE_COOKIE_MAX_AGE = 60 * 60 * 24 * 365;

export function isLocale(value: string | null | undefined): value is Locale {
  return value === "en" || value === "es";
}

/**
 * Browser-language detection ONLY (never IP geolocation — language is
 * not geography). Walks Accept-Language by priority (q-value, then
 * order) and picks the first SUPPORTED language: any es-* -> es, en-*
 * -> en. Everything unsupported is skipped; if nothing supported
 * remains the default (English) applies.
 */
export function detectLocaleFromAcceptLanguage(header: string | null | undefined): Locale {
  if (!header) return DEFAULT_LOCALE;

  const ranked = header
    .split(",")
    .map((part, index) => {
      const [tagRaw, ...params] = part.trim().split(";");
      const qParam = params.find((p) => p.trim().startsWith("q="));
      const q = qParam ? Number.parseFloat(qParam.trim().slice(2)) : 1;
      return { tag: (tagRaw ?? "").trim().toLowerCase(), q: Number.isNaN(q) ? 0 : q, index };
    })
    .filter((entry) => entry.tag && entry.tag !== "*" && entry.q > 0)
    .sort((a, b) => b.q - a.q || a.index - b.index);

  for (const { tag } of ranked) {
    const primary = tag.split("-")[0];
    if (primary === "es") return "es";
    if (primary === "en") return "en";
  }
  return DEFAULT_LOCALE;
}

export interface ResolvedRequestLocale {
  locale: Locale;
  /** The path with any /es prefix removed — what the app routes actually serve. */
  strippedPath: string;
  /** True when the locale came from an explicit /es URL (so the
   * middleware should persist it as the user's preference). */
  fromPath: boolean;
}

/** Locale resolution order: explicit /es URL > saved cookie > browser
 * language > English. */
export function resolveRequestLocale(params: {
  pathname: string;
  cookieValue?: string | null;
  acceptLanguage?: string | null;
}): ResolvedRequestLocale {
  const { pathname, cookieValue, acceptLanguage } = params;

  if (pathname === "/es" || pathname.startsWith("/es/")) {
    return { locale: "es", strippedPath: pathname.slice(3) || "/", fromPath: true };
  }

  if (isLocale(cookieValue)) {
    return { locale: cookieValue, strippedPath: pathname, fromPath: false };
  }

  return {
    locale: detectLocaleFromAcceptLanguage(acceptLanguage),
    strippedPath: pathname,
    fromPath: false,
  };
}

/** Public URL path for a given locale: English unprefixed, Spanish under /es. */
export function localizePath(path: string, locale: Locale): string {
  const clean = path.startsWith("/") ? path : `/${path}`;
  if (locale === "en") return clean;
  return clean === "/" ? "/es" : `/es${clean}`;
}

/** Removes a leading /es so the same logical page can be re-prefixed for another locale. */
export function stripLocalePrefix(path: string): string {
  if (path === "/es") return "/";
  if (path.startsWith("/es/")) return path.slice(3);
  return path;
}

/** Reads the middleware-provided locale header value (route handlers). */
export function localeFromHeaderValue(value: string | null | undefined): Locale {
  return isLocale(value) ? value : DEFAULT_LOCALE;
}
