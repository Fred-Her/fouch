import * as CountryFlagIcons from "country-flag-icons/react/3x2";

type FlagComponent = typeof CountryFlagIcons.US;

/**
 * FOUCH Country Selector Globalization — every ISO 3166-1 code the
 * `country-flag-icons` package supports is now available here (all
 * ~265), imported as one namespace instead of a hand-maintained list
 * of individual named imports. This replaced a curated subset because
 * the predictor-country selector (src/lib/countries.ts) now offers
 * the full worldwide country set, not a short list — hand-adding one
 * import per country every time that list grows was exactly the kind
 * of per-addition maintenance this fix was meant to eliminate. Event
 * participant flags (src/lib/event-participants-db.ts /
 * src/lib/participants.ts) benefit the same way: a future event's
 * roster never needs a CountryFlag.tsx change either.
 */
const FLAGS: Record<string, FlagComponent | undefined> = CountryFlagIcons as unknown as Record<
  string,
  FlagComponent | undefined
>;

/**
 * Root cause this fixes: Unicode regional-indicator flag emoji (what
 * flagEmoji() in src/lib/flags.ts produces) render as actual flags on
 * iOS/Android/macOS, but Windows historically ships no color flag
 * emoji font â€” Chrome on Windows falls back to showing the two literal
 * regional-indicator letters ("CL" instead of ðŸ‡¨ðŸ‡±), which is exactly
 * what QA saw in production. SVG flags render identically everywhere.
 *
 * Decorative by default (aria-hidden) â€” every call site already shows
 * the country name as visible text right next to this, so a flag
 * doesn't need its own screen-reader announcement (that would read as
 * redundant "Chile flag, Chile").
 */
export function CountryFlag({
  countryCode,
  className = "",
}: {
  countryCode?: string | null;
  className?: string;
}) {
  const code = countryCode?.toUpperCase();
  const Flag = code ? FLAGS[code] : undefined;

  if (!Flag) {
    return (
      <span
        aria-hidden
        className={`inline-flex h-[1em] items-center justify-center rounded-sm bg-surface-raised px-1 text-[0.55em] font-bold leading-none text-text-muted ${className}`}
      >
        {code || "XX"}
      </span>
    );
  }

  return (
    <Flag
      aria-hidden
      className={`inline-block h-[1em] w-[1.5em] rounded-[2px] align-middle ${className}`}
    />
  );
}