import { NextResponse, type NextRequest } from "next/server";
import {
  LOCALE_COOKIE,
  LOCALE_COOKIE_MAX_AGE,
  LOCALE_HEADER,
  PATH_HEADER,
  resolveRequestLocale,
} from "@/lib/locale";

/**
 * FOUCH i18n v1. Resolves the request's locale and exposes it to the
 * app via a request header (x-fouch-locale) — server components,
 * server actions and image routes all read that single header.
 *
 *  - /es/...  is REWRITTEN (not redirected) to the unprefixed route,
 *    so /es/p/abc and /p/abc are literally the same route handler and
 *    the same prediction. No existing URL changes or redirects.
 *  - Unprefixed URLs use the saved cookie, else Accept-Language.
 *  - Visiting an explicit /es URL saves the preference (cookie) so
 *    internal unprefixed links keep the language.
 */
export function middleware(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  const resolved = resolveRequestLocale({
    pathname,
    cookieValue: request.cookies.get(LOCALE_COOKIE)?.value,
    acceptLanguage: request.headers.get("accept-language"),
  });

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set(LOCALE_HEADER, resolved.locale);
  requestHeaders.set(PATH_HEADER, resolved.strippedPath);

  let response: NextResponse;
  if (resolved.fromPath) {
    const url = request.nextUrl.clone();
    url.pathname = resolved.strippedPath;
    url.search = search;
    response = NextResponse.rewrite(url, { request: { headers: requestHeaders } });
    response.cookies.set(LOCALE_COOKIE, resolved.locale, {
      path: "/",
      maxAge: LOCALE_COOKIE_MAX_AGE,
      sameSite: "lax",
    });
  } else {
    response = NextResponse.next({ request: { headers: requestHeaders } });
  }

  return response;
}

export const config = {
  // Everything except Next internals and static files (anything with a dot).
  matcher: ["/((?!_next/|api/|.*\\..*).*)"],
};
