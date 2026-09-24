import {
  AL,
  AM,
  AR,
  AU,
  BD,
  BE,
  BO,
  BR,
  CA,
  CH,
  CI,
  CL,
  CN,
  CO,
  CR,
  CU,
  CZ,
  DE,
  DO,
  EC,
  EG,
  ES,
  FR,
  GB,
  GE,
  GH,
  GT,
  GY,
  HK,
  HN,
  HT,
  ID,
  IN,
  IR,
  IT,
  JM,
  JP,
  KE,
  KR,
  KZ,
  LA,
  LB,
  LK,
  MA,
  MD,
  ME,
  MM,
  MN,
  MO,
  MT,
  MX,
  MY,
  NG,
  NI,
  NL,
  NO,
  NP,
  NZ,
  PA,
  PE,
  PH,
  PK,
  PR,
  PT,
  PY,
  RO,
  RU,
  SG,
  SK,
  SL,
  SS,
  SV,
  TH,
  TR,
  TW,
  TZ,
  US,
  UY,
  VE,
  VI,
  VN,
  XK,
  ZA,
  ZW,
} from "country-flag-icons/react/3x2";

type FlagComponent = typeof CL;

/**
 * Curated to exactly the country codes currently used across
 * src/lib/participants.ts, src/lib/countries.ts, and â€” as of FOUCH
 * 0.3B's Miss Grand International 2026 roster import â€” the
 * event_participants table, imported as named exports (not the whole
 * `country-flag-icons` set) so bundlers can tree-shake the ~220 flags
 * FOUCH doesn't use. Adding a new country to any of those sources
 * means adding one import + one entry here.
 */
const FLAGS: Record<string, FlagComponent> = {
  AL,
  AM,
  AR,
  AU,
  BD,
  BE,
  BO,
  BR,
  CA,
  CH,
  CI,
  CL,
  CN,
  CO,
  CR,
  CU,
  CZ,
  DE,
  DO,
  EC,
  EG,
  ES,
  FR,
  GB,
  GE,
  GH,
  GT,
  GY,
  HK,
  HN,
  HT,
  ID,
  IN,
  IR,
  IT,
  JM,
  JP,
  KE,
  KR,
  KZ,
  LA,
  LB,
  LK,
  MA,
  MD,
  ME,
  MM,
  MN,
  MO,
  MT,
  MX,
  MY,
  NG,
  NI,
  NL,
  NO,
  NP,
  NZ,
  PA,
  PE,
  PH,
  PK,
  PR,
  PT,
  PY,
  RO,
  RU,
  SG,
  SK,
  SL,
  SS,
  SV,
  TH,
  TR,
  TW,
  TZ,
  US,
  UY,
  VE,
  VI,
  VN,
  XK,
  ZA,
  ZW,
};

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