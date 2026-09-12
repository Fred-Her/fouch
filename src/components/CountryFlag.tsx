import {
  AR,
  AU,
  BR,
  CA,
  CL,
  CO,
  DE,
  DO,
  EC,
  ES,
  FR,
  GB,
  ID,
  IN,
  IT,
  JM,
  JP,
  KE,
  KR,
  MX,
  NG,
  PA,
  PE,
  PH,
  PR,
  PT,
  PY,
  TH,
  US,
  UY,
  VE,
  VN,
  ZA,
} from "country-flag-icons/react/3x2";

type FlagComponent = typeof CL;

/**
 * Curated to exactly the country codes currently used across
 * src/lib/participants.ts and src/lib/countries.ts, imported as named
 * exports (not the whole `country-flag-icons` set) so bundlers can
 * tree-shake the ~220 flags FOUCH doesn't use. Adding a new country
 * to either seed file means adding one import + one entry here.
 */
const FLAGS: Record<string, FlagComponent> = {
  AR,
  AU,
  BR,
  CA,
  CL,
  CO,
  DE,
  DO,
  EC,
  ES,
  FR,
  GB,
  ID,
  IN,
  IT,
  JM,
  JP,
  KE,
  KR,
  MX,
  NG,
  PA,
  PE,
  PH,
  PR,
  PT,
  PY,
  TH,
  US,
  UY,
  VE,
  VN,
  ZA,
};

/**
 * Root cause this fixes: Unicode regional-indicator flag emoji (what
 * flagEmoji() in src/lib/flags.ts produces) render as actual flags on
 * iOS/Android/macOS, but Windows historically ships no color flag
 * emoji font — Chrome on Windows falls back to showing the two literal
 * regional-indicator letters ("CL" instead of 🇨🇱), which is exactly
 * what QA saw in production. SVG flags render identically everywhere.
 *
 * Decorative by default (aria-hidden) — every call site already shows
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