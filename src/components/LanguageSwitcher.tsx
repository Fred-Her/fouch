"use client";

import { track } from "@/lib/analytics";
import { useI18n } from "@/components/I18nProvider";
import { LOCALE_COOKIE, LOCALE_COOKIE_MAX_AGE, localizePath, stripLocalePrefix, type Locale } from "@/lib/locale";

/**
 * EN | ES — a plain, keyboard-accessible pair of links/buttons (no
 * flags: language is not country). Choosing a language persists it in
 * a cookie (read server-side by the middleware, so there is no
 * English-then-Spanish flash), fires language_changed, and does a full
 * navigation to the same logical page under the target locale's URL —
 * /p/abc <-> /es/p/abc — which is the same prediction either way.
 */
export function LanguageSwitcher({ eventSlug }: { eventSlug?: string }) {
  const { locale, dict } = useI18n();

  function choose(target: Locale) {
    if (target === locale) return;

    const currentPath = window.location.pathname;
    const logicalPath = stripLocalePrefix(currentPath);

    track("language_changed", {
      from_locale: locale,
      to_locale: target,
      page: logicalPath,
      ...(eventSlug ? { event_slug: eventSlug } : {}),
    });

    document.cookie = `${LOCALE_COOKIE}=${target}; path=/; max-age=${LOCALE_COOKIE_MAX_AGE}; samesite=lax`;
    window.location.assign(`${localizePath(logicalPath, target)}${window.location.search}${window.location.hash}`);
  }

  const options: Array<{ code: Locale; label: string }> = [
    { code: "en", label: "EN" },
    { code: "es", label: "ES" },
  ];

  return (
    <div role="group" aria-label={dict.nav.language} className="flex items-center gap-1 text-xs font-medium tracking-[0.15em]">
      {options.map((option, index) => (
        <span key={option.code} className="flex items-center gap-1">
          {index > 0 ? (
            <span aria-hidden className="text-border-strong">
              |
            </span>
          ) : null}
          <button
            type="button"
            onClick={() => choose(option.code)}
            aria-pressed={locale === option.code}
            lang={option.code}
            className={
              locale === option.code
                ? "rounded px-1 py-0.5 text-text-primary underline underline-offset-4"
                : "rounded px-1 py-0.5 text-text-muted transition-colors hover:text-text-secondary focus-visible:text-text-primary"
            }
          >
            {option.label}
          </button>
        </span>
      ))}
    </div>
  );
}
