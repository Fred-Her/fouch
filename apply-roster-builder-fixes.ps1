# FOUCH — Builder roster fixes: alphabetical order by localized country + accent-insensitive search (+ natural ES name for Hong Kong).
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-roster-builder-fixes.ps1
$failures = @()

try {
    $path = "src\components\prediction\ParticipantBrowser.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useMemo, useState } from "react";
import { Search } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import type { Participant } from "@/types/participant";
import { useI18n } from "@/components/I18nProvider";
import { fmt } from "@/lib/i18n";
import { matchesParticipantSearch } from "@/lib/participant-search";

export function ParticipantBrowser({
  participants,
  selectedIds,
  atMax,
  onToggle,
}: {
  participants: Participant[];
  selectedIds: Set<string>;
  atMax: boolean;
  onToggle: (id: string) => void;
}) {
  const [query, setQuery] = useState("");

  const { dict } = useI18n();
  const t = dict.builder;

  const filtered = useMemo(() => {
    if (!query.trim()) return participants;

    return participants.filter((participant) => matchesParticipantSearch(participant, query));
  }, [participants, query]);

  return (
    <div>
      <div className="relative">
        <Search
          className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted"
          aria-hidden
        />
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder={t.searchPlaceholder}
          aria-label={t.searchAria}
          className="w-full rounded border border-border bg-surface py-2.5 pl-10 pr-3 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
        />
      </div>

      {filtered.length === 0 ? (
        <p className="mt-6 text-sm text-text-muted">{fmt(t.noMatch, { query })}</p>
      ) : (
        <ul className="mt-4 divide-y divide-border">
          {filtered.map((participant) => {
            const selected = selectedIds.has(participant.id);
            const disabled = atMax && !selected;

            return (
              <li key={participant.id}>
                <button
                  type="button"
                  onClick={() => onToggle(participant.id)}
                  disabled={disabled}
                  aria-pressed={selected}
                  className={`flex w-full items-center gap-3 py-3 text-left transition-colors disabled:cursor-not-allowed disabled:opacity-40 ${
                    selected ? "text-accent-strong" : "text-text-primary hover:text-accent-strong"
                  }`}
                >
                  <CountryFlag countryCode={participant.countryCode} className="text-lg" />
                  <span className="flex-1 truncate text-sm">
                    {participant.displayName} <span className="text-text-muted">· {participant.countryName}</span>
                  </span>
                  {selected ? (
                    <span className="text-xs font-medium uppercase tracking-wide">{t.selected}</span>
                  ) : null}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\ParticipantBrowser.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\ParticipantBrowser.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\ParticipantBrowser.tsx"
}

try {
    $path = "src\lib\countries.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Locale } from "@/lib/locale";

/**
 * FOUCH Country Selector Globalization — the canonical, global list
 * of countries for user-identity metadata (the optional "your
 * country" field on a prediction). This is about the PREDICTOR, not
 * an event's contestants (see src/lib/participants.ts /
 * event-participants-db.ts for those) — a predictor can be from
 * anywhere in the world, so this list is deliberately complete and
 * entirely independent of any event's roster.
 *
 * Generated from the same country-flag-icons package FOUCH already
 * depends on for flag rendering (CountryFlag.tsx), using each code's
 * standard English display name (Intl.DisplayNames), with a small,
 * explicit set of uninhabited/non-country/testing entries excluded
 * (Antarctica, Bouvet Island, the "European Union" pseudo-region,
 * ICU's "Pseudo-Accents" test locale, and similar). Every other
 * ISO 3166-1 code the flag package recognizes is included — the full
 * worldwide set, not a curated subset — so a predictor's country is
 * never missing here regardless of nationality.
 *
 * ISO 3166-1 alpha-2 codes, validated server-side against the same
 * pattern regardless of whether the code appears here.
 */
export const PREDICTOR_COUNTRIES: Array<{ code: string; name: string }> = [
  { code: "AF", name: "Afghanistan" },
  { code: "AX", name: "Åland Islands" },
  { code: "AL", name: "Albania" },
  { code: "DZ", name: "Algeria" },
  { code: "AS", name: "American Samoa" },
  { code: "AD", name: "Andorra" },
  { code: "AO", name: "Angola" },
  { code: "AI", name: "Anguilla" },
  { code: "AG", name: "Antigua & Barbuda" },
  { code: "AR", name: "Argentina" },
  { code: "AM", name: "Armenia" },
  { code: "AW", name: "Aruba" },
  { code: "AC", name: "Ascension Island" },
  { code: "AU", name: "Australia" },
  { code: "AT", name: "Austria" },
  { code: "AZ", name: "Azerbaijan" },
  { code: "BS", name: "Bahamas" },
  { code: "BH", name: "Bahrain" },
  { code: "BD", name: "Bangladesh" },
  { code: "BB", name: "Barbados" },
  { code: "BY", name: "Belarus" },
  { code: "BE", name: "Belgium" },
  { code: "BZ", name: "Belize" },
  { code: "BJ", name: "Benin" },
  { code: "BM", name: "Bermuda" },
  { code: "BT", name: "Bhutan" },
  { code: "BO", name: "Bolivia" },
  { code: "BA", name: "Bosnia & Herzegovina" },
  { code: "BW", name: "Botswana" },
  { code: "BR", name: "Brazil" },
  { code: "VG", name: "British Virgin Islands" },
  { code: "BN", name: "Brunei" },
  { code: "BG", name: "Bulgaria" },
  { code: "BF", name: "Burkina Faso" },
  { code: "BI", name: "Burundi" },
  { code: "KH", name: "Cambodia" },
  { code: "CM", name: "Cameroon" },
  { code: "CA", name: "Canada" },
  { code: "IC", name: "Canary Islands" },
  { code: "CV", name: "Cape Verde" },
  { code: "BQ", name: "Caribbean Netherlands" },
  { code: "KY", name: "Cayman Islands" },
  { code: "CF", name: "Central African Republic" },
  { code: "TD", name: "Chad" },
  { code: "CL", name: "Chile" },
  { code: "CN", name: "China" },
  { code: "CO", name: "Colombia" },
  { code: "KM", name: "Comoros" },
  { code: "CG", name: "Congo - Brazzaville" },
  { code: "CD", name: "Congo - Kinshasa" },
  { code: "CK", name: "Cook Islands" },
  { code: "CR", name: "Costa Rica" },
  { code: "CI", name: "Côte d’Ivoire" },
  { code: "HR", name: "Croatia" },
  { code: "CU", name: "Cuba" },
  { code: "CW", name: "Curaçao" },
  { code: "CY", name: "Cyprus" },
  { code: "CZ", name: "Czechia" },
  { code: "DK", name: "Denmark" },
  { code: "DJ", name: "Djibouti" },
  { code: "DM", name: "Dominica" },
  { code: "DO", name: "Dominican Republic" },
  { code: "EC", name: "Ecuador" },
  { code: "EG", name: "Egypt" },
  { code: "SV", name: "El Salvador" },
  { code: "GQ", name: "Equatorial Guinea" },
  { code: "ER", name: "Eritrea" },
  { code: "EE", name: "Estonia" },
  { code: "SZ", name: "Eswatini" },
  { code: "ET", name: "Ethiopia" },
  { code: "FK", name: "Falkland Islands" },
  { code: "FO", name: "Faroe Islands" },
  { code: "FJ", name: "Fiji" },
  { code: "FI", name: "Finland" },
  { code: "FR", name: "France" },
  { code: "GF", name: "French Guiana" },
  { code: "PF", name: "French Polynesia" },
  { code: "GA", name: "Gabon" },
  { code: "GM", name: "Gambia" },
  { code: "GE", name: "Georgia" },
  { code: "DE", name: "Germany" },
  { code: "GH", name: "Ghana" },
  { code: "GI", name: "Gibraltar" },
  { code: "GR", name: "Greece" },
  { code: "GL", name: "Greenland" },
  { code: "GD", name: "Grenada" },
  { code: "GP", name: "Guadeloupe" },
  { code: "GU", name: "Guam" },
  { code: "GT", name: "Guatemala" },
  { code: "GG", name: "Guernsey" },
  { code: "GN", name: "Guinea" },
  { code: "GW", name: "Guinea-Bissau" },
  { code: "GY", name: "Guyana" },
  { code: "HT", name: "Haiti" },
  { code: "HN", name: "Honduras" },
  { code: "HK", name: "Hong Kong SAR China" },
  { code: "HU", name: "Hungary" },
  { code: "IS", name: "Iceland" },
  { code: "IN", name: "India" },
  { code: "ID", name: "Indonesia" },
  { code: "IR", name: "Iran" },
  { code: "IQ", name: "Iraq" },
  { code: "IE", name: "Ireland" },
  { code: "IM", name: "Isle of Man" },
  { code: "IL", name: "Israel" },
  { code: "IT", name: "Italy" },
  { code: "JM", name: "Jamaica" },
  { code: "JP", name: "Japan" },
  { code: "JE", name: "Jersey" },
  { code: "JO", name: "Jordan" },
  { code: "KZ", name: "Kazakhstan" },
  { code: "KE", name: "Kenya" },
  { code: "KI", name: "Kiribati" },
  { code: "XK", name: "Kosovo" },
  { code: "KW", name: "Kuwait" },
  { code: "KG", name: "Kyrgyzstan" },
  { code: "LA", name: "Laos" },
  { code: "LV", name: "Latvia" },
  { code: "LB", name: "Lebanon" },
  { code: "LS", name: "Lesotho" },
  { code: "LR", name: "Liberia" },
  { code: "LY", name: "Libya" },
  { code: "LI", name: "Liechtenstein" },
  { code: "LT", name: "Lithuania" },
  { code: "LU", name: "Luxembourg" },
  { code: "MO", name: "Macao SAR China" },
  { code: "MG", name: "Madagascar" },
  { code: "MW", name: "Malawi" },
  { code: "MY", name: "Malaysia" },
  { code: "MV", name: "Maldives" },
  { code: "ML", name: "Mali" },
  { code: "MT", name: "Malta" },
  { code: "MH", name: "Marshall Islands" },
  { code: "MQ", name: "Martinique" },
  { code: "MR", name: "Mauritania" },
  { code: "MU", name: "Mauritius" },
  { code: "YT", name: "Mayotte" },
  { code: "MX", name: "Mexico" },
  { code: "FM", name: "Micronesia" },
  { code: "MD", name: "Moldova" },
  { code: "MC", name: "Monaco" },
  { code: "MN", name: "Mongolia" },
  { code: "ME", name: "Montenegro" },
  { code: "MS", name: "Montserrat" },
  { code: "MA", name: "Morocco" },
  { code: "MZ", name: "Mozambique" },
  { code: "MM", name: "Myanmar (Burma)" },
  { code: "NA", name: "Namibia" },
  { code: "NR", name: "Nauru" },
  { code: "NP", name: "Nepal" },
  { code: "NL", name: "Netherlands" },
  { code: "NC", name: "New Caledonia" },
  { code: "NZ", name: "New Zealand" },
  { code: "NI", name: "Nicaragua" },
  { code: "NE", name: "Niger" },
  { code: "NG", name: "Nigeria" },
  { code: "NU", name: "Niue" },
  { code: "KP", name: "North Korea" },
  { code: "MK", name: "North Macedonia" },
  { code: "MP", name: "Northern Mariana Islands" },
  { code: "NO", name: "Norway" },
  { code: "OM", name: "Oman" },
  { code: "PK", name: "Pakistan" },
  { code: "PW", name: "Palau" },
  { code: "PS", name: "Palestinian Territories" },
  { code: "PA", name: "Panama" },
  { code: "PG", name: "Papua New Guinea" },
  { code: "PY", name: "Paraguay" },
  { code: "PE", name: "Peru" },
  { code: "PH", name: "Philippines" },
  { code: "PL", name: "Poland" },
  { code: "PT", name: "Portugal" },
  { code: "PR", name: "Puerto Rico" },
  { code: "QA", name: "Qatar" },
  { code: "RE", name: "Réunion" },
  { code: "RO", name: "Romania" },
  { code: "RU", name: "Russia" },
  { code: "RW", name: "Rwanda" },
  { code: "WS", name: "Samoa" },
  { code: "SM", name: "San Marino" },
  { code: "ST", name: "São Tomé & Príncipe" },
  { code: "SA", name: "Saudi Arabia" },
  { code: "SN", name: "Senegal" },
  { code: "RS", name: "Serbia" },
  { code: "SC", name: "Seychelles" },
  { code: "SL", name: "Sierra Leone" },
  { code: "SG", name: "Singapore" },
  { code: "SX", name: "Sint Maarten" },
  { code: "SK", name: "Slovakia" },
  { code: "SI", name: "Slovenia" },
  { code: "SB", name: "Solomon Islands" },
  { code: "SO", name: "Somalia" },
  { code: "ZA", name: "South Africa" },
  { code: "KR", name: "South Korea" },
  { code: "SS", name: "South Sudan" },
  { code: "ES", name: "Spain" },
  { code: "LK", name: "Sri Lanka" },
  { code: "BL", name: "St. Barthélemy" },
  { code: "SH", name: "St. Helena" },
  { code: "KN", name: "St. Kitts & Nevis" },
  { code: "LC", name: "St. Lucia" },
  { code: "MF", name: "St. Martin" },
  { code: "PM", name: "St. Pierre & Miquelon" },
  { code: "VC", name: "St. Vincent & Grenadines" },
  { code: "SD", name: "Sudan" },
  { code: "SR", name: "Suriname" },
  { code: "SE", name: "Sweden" },
  { code: "CH", name: "Switzerland" },
  { code: "SY", name: "Syria" },
  { code: "TW", name: "Taiwan" },
  { code: "TJ", name: "Tajikistan" },
  { code: "TZ", name: "Tanzania" },
  { code: "TH", name: "Thailand" },
  { code: "TL", name: "Timor-Leste" },
  { code: "TG", name: "Togo" },
  { code: "TK", name: "Tokelau" },
  { code: "TO", name: "Tonga" },
  { code: "TT", name: "Trinidad & Tobago" },
  { code: "TN", name: "Tunisia" },
  { code: "TR", name: "Türkiye" },
  { code: "TM", name: "Turkmenistan" },
  { code: "TC", name: "Turks & Caicos Islands" },
  { code: "TV", name: "Tuvalu" },
  { code: "VI", name: "U.S. Virgin Islands" },
  { code: "UG", name: "Uganda" },
  { code: "UA", name: "Ukraine" },
  { code: "AE", name: "United Arab Emirates" },
  { code: "GB", name: "United Kingdom" },
  { code: "US", name: "United States" },
  { code: "UY", name: "Uruguay" },
  { code: "UZ", name: "Uzbekistan" },
  { code: "VU", name: "Vanuatu" },
  { code: "VA", name: "Vatican City" },
  { code: "VE", name: "Venezuela" },
  { code: "VN", name: "Vietnam" },
  { code: "WF", name: "Wallis & Futuna" },
  { code: "EH", name: "Western Sahara" },
  { code: "YE", name: "Yemen" },
  { code: "ZM", name: "Zambia" },
  { code: "ZW", name: "Zimbabwe" },
].sort((a, b) => a.name.localeCompare(b.name));

/**
 * FOUCH Country Recognition consistency fix — the single lookup every
 * predictor-country display surface (Share Cards, public prediction
 * header) uses to resolve a stored ISO code to its human-readable
 * name. Reuses PREDICTOR_COUNTRIES — the same list the country
 * selector itself is built from — so there is only ever one
 * code-to-name mapping in the app, never a second one. Returns null
 * for a code that isn't in the list (never fabricates a name).
 */
export function getPredictorCountryName(code: string | null, locale: Locale = "en"): string | null {
  if (!code) return null;
  const englishName = PREDICTOR_COUNTRIES.find((country) => country.code === code)?.name ?? null;
  if (!englishName) return null;
  return getLocalizedCountryName(code, englishName, locale);
}

/**
 * i18n v1: the human-readable country name in the viewer's language.
 * English returns the existing English name untouched (so every
 * current English surface — including DB roster names like "Czech
 * Republic" — is byte-for-byte unchanged). Other locales use the
 * platform's Intl.DisplayNames (CLDR data) and fall back to the
 * English name whenever Intl has nothing useful (unknown/unofficial
 * codes such as XK, or a runtime without that locale) — never a raw
 * ISO code. No second country dataset is introduced.
 */
/**
 * CLDR's long Spanish names for a few regions are administrative and awkward on a
 * contestant card ("RAE de Hong Kong (China)", "Territorios Palestinos"). For those
 * only, the CLDR short form ("Hong Kong", "Palestina") reads naturally. Every other
 * country keeps its long name — notably "Estados Unidos", where the short form would
 * be the abbreviation "EE. UU.".
 */
const PREFER_SHORT_NAME = new Set(["HK", "MO", "PS"]);

export function getLocalizedCountryName(code: string, englishName: string, locale: Locale): string {
  if (locale === "en") return englishName;
  try {
    const localized = new Intl.DisplayNames([locale], {
      type: "region",
      style: PREFER_SHORT_NAME.has(code) ? "short" : "long",
    }).of(code);
    if (localized && localized !== code) return localized;
  } catch {
    // Unsupported locale/code in this runtime — fall through to English.
  }
  return englishName;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\countries.ts"
} catch {
    Write-Host "FAILED: src\lib\countries.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\countries.ts"
}

try {
    $path = "src\lib\country-locale.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { PREDICTOR_COUNTRIES, getLocalizedCountryName, getPredictorCountryName } from "./countries";
import { localizeParticipant, sortParticipantsByCountry } from "./participant-locale";
import type { Participant } from "@/types/participant";

describe("country names render in the viewer's locale", () => {
  it("English returns the existing English name untouched (incl. roster names Intl would rename)", () => {
    expect(getLocalizedCountryName("PH", "Philippines", "en")).toBe("Philippines");
    expect(getLocalizedCountryName("CZ", "Czech Republic", "en")).toBe("Czech Republic");
  });

  it("Spanish uses natural Spanish names", () => {
    expect(getLocalizedCountryName("PH", "Philippines", "es")).toBe("Filipinas");
    expect(getLocalizedCountryName("US", "United States", "es")).toBe("Estados Unidos");
    expect(getLocalizedCountryName("VE", "Venezuela", "es")).toBe("Venezuela");
    expect(getLocalizedCountryName("CL", "Chile", "es")).toBe("Chile");
  });

  it("regions with an awkward CLDR long name use the natural short form in Spanish, nothing else changes", () => {
    expect(getLocalizedCountryName("HK", "Hong Kong", "es")).toBe("Hong Kong");
    expect(getLocalizedCountryName("PS", "Palestine", "es")).toBe("Palestina");
    expect(getLocalizedCountryName("US", "United States", "es")).toBe("Estados Unidos");
  });

  it("never exposes a raw ISO code — falls back to the English name when Intl has nothing", () => {
    const xk = getLocalizedCountryName("XK", "Kosovo", "es");
    expect(xk).not.toBe("XK");
    expect(xk.length).toBeGreaterThan(2);
  });

  it("every selectable predictor country resolves to a real name in Spanish (not a bare code)", () => {
    for (const country of PREDICTOR_COUNTRIES) {
      const name = getLocalizedCountryName(country.code, country.name, "es");
      expect(name, country.code).not.toBe(country.code);
      expect(name.length, country.code).toBeGreaterThan(2);
    }
  });

  it("predictor country lookup is locale-aware and still null-safe", () => {
    expect(getPredictorCountryName("PH", "es")).toBe("Filipinas");
    expect(getPredictorCountryName("PH")).toBe("Philippines");
    expect(getPredictorCountryName(null, "es")).toBeNull();
    expect(getPredictorCountryName("ZZ", "es")).toBeNull();
  });
});

describe("localizeParticipant — presentation only, identity untouched", () => {
  const participant: Participant = {
    id: "uuid-1",
    eventId: "evt",
    displayName: "HANA DĚDKOVÁ",
    countryCode: "PH",
    countryName: "Philippines",
    sortOrder: 4,
    isActive: true,
  };

  it("only countryName changes; id, official name, code, status, order are identical", () => {
    const es = localizeParticipant(participant, "es");
    expect(es.countryName).toBe("Filipinas");
    expect({ ...es, countryName: "x" }).toEqual({ ...participant, countryName: "x" });
    expect(es.displayName).toBe("HANA DĚDKOVÁ");
  });

  it("English returns the very same object", () => {
    expect(localizeParticipant(participant, "en")).toBe(participant);
  });
});

describe("sortParticipantsByCountry — new delegates land in their alphabetical place", () => {
  const make = (id: string, name: string, code: string, country: string): Participant => ({
    id, eventId: "e", displayName: name, countryCode: code, countryName: country, sortOrder: 0, isActive: true,
  });
  const roster = [
    make("1", "VENEZUELAN", "VE", "Venezuela"),
    make("2", "COLOMBIAN", "CO", "Colombia"),
    make("3", "ARGENTINE", "AR", "Argentina"),
    make("4", "HONG KONG", "HK", "Hong Kong"),
  ];

  it("sorts by country name, so a delegate added later (Colombia, Hong Kong) is not appended at the end", () => {
    expect(sortParticipantsByCountry(roster, "en").map((x) => x.countryName)).toEqual([
      "Argentina", "Colombia", "Hong Kong", "Venezuela",
    ]);
  });

  it("sorts by the country name in the viewer's language", () => {
    const es = roster.map((x) => localizeParticipant(x, "es"));
    expect(sortParticipantsByCountry(es, "es").map((x) => x.countryName)).toEqual([
      "Argentina", "Colombia", "Hong Kong", "Venezuela",
    ]);
  });

  it("accents don't break the order (Perú sorts with P, not after Z)", () => {
    const list = [make("1", "A", "ZA", "Zambia"), make("2", "B", "PE", "Perú"), make("3", "C", "PA", "Panamá")];
    expect(sortParticipantsByCountry(list, "es").map((x) => x.countryName)).toEqual(["Panamá", "Perú", "Zambia"]);
  });

  it("is stable on ties (same country -> contestant name) and never mutates its input", () => {
    const tie = [make("1", "BETA", "XX", "Same"), make("2", "ALPHA", "XX", "Same")];
    const before = JSON.stringify(tie);
    expect(sortParticipantsByCountry(tie, "en").map((x) => x.displayName)).toEqual(["ALPHA", "BETA"]);
    expect(JSON.stringify(tie)).toBe(before);
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\country-locale.test.ts"
} catch {
    Write-Host "FAILED: src\lib\country-locale.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\country-locale.test.ts"
}

try {
    $path = "src\lib\participant-locale.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\participant-locale.ts"
} catch {
    Write-Host "FAILED: src\lib\participant-locale.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\participant-locale.ts"
}

try {
    $path = "src\lib\participants.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import type { Participant } from "@/types/participant";
import { isSelectableStatus } from "@/lib/participant-status";
import { localizeParticipant as localize, sortParticipantsByCountry } from "@/lib/participant-locale";
import { chooseRosterSource, demoParticipantsForIds } from "@/lib/participant-sources";
import type { Locale } from "@/lib/locale";
import { getAllEventParticipantRows, type EventParticipantRow } from "@/lib/event-participants-db";

/**
 * DEMO / DEVELOPMENT DATA â€” NOT the official Miss Universe 2026 lineup.
 *
 * The full, verified list of national delegates for Miss Universe 2026
 * is not yet finalized/confirmed by the organization at the time of
 * writing. Rather than invent an official-looking roster, this is a
 * clearly-marked demo set of real countries, used only to test the
 * Top 10 mechanic. See `getParticipantsForEvent`'s returned `status`
 * field â€” the UI must surface "Demo participant data" whenever it is
 * "demo", and this must never be presented as the official lineup.
 */
const demoCountries: Array<{ code: string; name: string }> = [
  { code: "AR", name: "Argentina" },
  { code: "AU", name: "Australia" },
  { code: "BR", name: "Brazil" },
  { code: "CA", name: "Canada" },
  { code: "CL", name: "Chile" },
  { code: "CO", name: "Colombia" },
  { code: "DO", name: "Dominican Republic" },
  { code: "ES", name: "Spain" },
  { code: "FR", name: "France" },
  { code: "IN", name: "India" },
  { code: "ID", name: "Indonesia" },
  { code: "IT", name: "Italy" },
  { code: "JM", name: "Jamaica" },
  { code: "JP", name: "Japan" },
  { code: "KE", name: "Kenya" },
  { code: "KR", name: "South Korea" },
  { code: "MX", name: "Mexico" },
  { code: "NG", name: "Nigeria" },
  { code: "PE", name: "Peru" },
  { code: "PH", name: "Philippines" },
  { code: "PR", name: "Puerto Rico" },
  { code: "TH", name: "Thailand" },
  { code: "VE", name: "Venezuela" },
  { code: "VN", name: "Vietnam" },
  { code: "ZA", name: "South Africa" },
].sort((a, b) => a.name.localeCompare(b.name));

const missUniverse2026Participants: Participant[] = demoCountries.map((country, index) => ({
  id: `demo-${country.code.toLowerCase()}`,
  eventId: "seed-miss-universe-2026",
  displayName: country.name,
  countryCode: country.code,
  countryName: country.name,
  sortOrder: index,
  isActive: true,
}));

const participantsByEventSlug: Record<string, Participant[]> = {
  "miss-universe-2026": missUniverse2026Participants,
};

export type ParticipantDataStatus = "demo" | "verified";

export interface ParticipantsForEvent {
  status: ParticipantDataStatus;
  participants: Participant[];
  /** FOUCH 0.3B Â§13: the most recent `source_checked_at` across this
   * event's ACTIVE participants, for the "Contestant list updated
   * {date}" copy â€” never used for a "demo" event (always null there;
   * Miss Universe's hardcoded seed has no provenance concept at all).
   * Null for a verified event with no source-checked participants
   * yet (e.g. Miss Grand before its roster import â€” see
   * FOUCH_EVENT_PARTICIPANTS_IMPORT.md). */
  sourceCheckedAt: string | null;
}

function toParticipant(row: EventParticipantRow): Participant {
  return {
    // Stable identity (0.3B Â§6): the DB row's own uuid, never derived
    // from name/position/status/country â€” see migration 0010.
    id: row.id,
    eventId: row.eventSlug,
    // A PENDING row has no confirmed contestant_name yet â€” never
    // invented here; fall back to the country name itself so the UI
    // has something displayable without fabricating a person's name.
    displayName: row.contestantName ?? row.countryName,
    countryCode: row.countryCode,
    countryName: row.countryName,
    sortOrder: 0,
    isActive: isSelectableStatus(row.status),
  };
}

/**
 * The active/selectable roster for building a NEW Top 10 (or a new
 * version of an edited one) â€” exactly the same contract this function
 * has always had: only ever returns participants a person may
 * currently choose. Every existing caller (builder, review,
 * validateSubmission's activeParticipants, edit's requiredCount) can
 * keep assuming that, unchanged â€” the only difference from before
 * 0.3B is that resolving a database-driven event's roster requires an
 * await now.
 *
 * PENDING/WITHDRAWN/REPLACED participants are deliberately excluded
 * here â€” see resolveParticipantsByIds below for the separate,
 * status-blind lookup that historical rendering needs instead.
 */
export async function getParticipantsForEvent(slug: string, locale: Locale = "en"): Promise<ParticipantsForEvent | null> {
  const hardcoded = participantsByEventSlug[slug];
  const rows = await getAllEventParticipantRows(slug);

  // Database first: an event with real roster rows ALWAYS uses them. The
  // hardcoded demo list only applies while an event has no rows at all.
  const source = chooseRosterSource(rows.length, Boolean(hardcoded));
  if (source === "demo" && hardcoded) {
    return {
      status: "demo",
      participants: sortParticipantsByCountry(
        hardcoded.filter((participant) => participant.isActive).map((p) => localize(p, locale)),
        locale,
      ),
      sourceCheckedAt: null,
    };
  }
  if (source === "none") return null;

  const active = rows.filter((row) => isSelectableStatus(row.status));
  const sourceCheckedAt = active.reduce<string | null>((latest, row) => {
    if (!row.sourceCheckedAt) return latest;
    if (!latest || row.sourceCheckedAt > latest) return row.sourceCheckedAt;
    return latest;
  }, null);

  return {
    status: "verified",
    participants: sortParticipantsByCountry(
      active.map((row) => localize(toParticipant(row), locale)),
      locale,
    ),
    sourceCheckedAt,
  };
}

/**
 * Resolves a specific set of participant IDs to display info
 * REGARDLESS of current status â€” the one place historical rendering
 * (a saved prediction's ranking, its share card, its winner pick for
 * scoring/consensus) must go through instead of
 * getParticipantsForEvent above. A WITHDRAWN or REPLACED participant
 * still resolves here with its real name/country (isActive: false),
 * exactly so an existing prediction never silently loses an entry
 * just because that country's delegate later changed (brief Â§7).
 *
 * For Miss Universe's hardcoded roster this is equivalent to the
 * active-only lookup (every hardcoded entry is always active), so
 * behavior there is unchanged.
 */
export async function resolveParticipantsByIds(
  eventSlug: string,
  participantIds: string[],
  locale: Locale = "en",
): Promise<Map<string, Participant>> {
  const idSet = new Set(participantIds);
  const rows = await getAllEventParticipantRows(eventSlug);
  const map = new Map<string, Participant>();
  for (const row of rows) {
    if (idSet.has(row.id)) map.set(row.id, localize(toParticipant(row), locale));
  }

  // Historical demo predictions (ids "demo-xx") must keep rendering after
  // the event moved to its real roster. Resolve-only: never selectable.
  for (const demo of demoParticipantsForIds(participantIds, participantsByEventSlug[eventSlug])) {
    if (!map.has(demo.id)) map.set(demo.id, localize(demo, locale));
  }
  return map;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\participants.ts"
} catch {
    Write-Host "FAILED: src\lib\participants.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\participants.ts"
}

try {
    $path = "src\lib\participant-search.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { matchesParticipantSearch, normalizeForSearch } from "./participant-search";

const p = (displayName: string, countryName: string) => ({ displayName, countryName });

describe("participant search ignores accents and case", () => {
  it("normalizes accents, case and special letters", () => {
    expect(normalizeForSearch("MARÍA")).toBe("maria");
    expect(normalizeForSearch("Curaçao")).toBe("curacao");
    expect(normalizeForSearch("Türkiye")).toBe("turkiye");
    expect(normalizeForSearch("Alara Erıç")).toBe("alara eric");
    expect(normalizeForSearch("Nguyễn")).toBe("nguyen");
    expect(normalizeForSearch("Đ")).toBe("d");
  });

  it("Spanish users typing without accents still find the country", () => {
    expect(matchesParticipantSearch(p("LUREN MÁRQUEZ", "Perú"), "peru")).toBe(true);
    expect(matchesParticipantSearch(p("MARÍA VARGAS", "México"), "mexico")).toBe(true);
    expect(matchesParticipantSearch(p("GABRIELA GONZÁLEZ", "Panamá"), "panama")).toBe(true);
    expect(matchesParticipantSearch(p("BIANTY GOMPERTS", "Curazao"), "curacao")).toBe(false); // different word, no false positive
  });

  it("finds by contestant name without accents", () => {
    expect(matchesParticipantSearch(p("MARÍA ADELINA CASTILLO", "Guatemala"), "maria")).toBe(true);
    expect(matchesParticipantSearch(p("DOMINGA LÓPEZ", "Chile"), "lopez")).toBe(true);
  });

  it("typing WITH accents works too", () => {
    expect(matchesParticipantSearch(p("LUREN MÁRQUEZ", "Perú"), "perú")).toBe(true);
    expect(matchesParticipantSearch(p("LUREN MÁRQUEZ", "Perú"), "MÁRQUEZ")).toBe(true);
  });

  it("an empty query matches everyone; a non-matching one matches nobody", () => {
    expect(matchesParticipantSearch(p("A", "B"), "")).toBe(true);
    expect(matchesParticipantSearch(p("A", "B"), "   ")).toBe(true);
    expect(matchesParticipantSearch(p("LUREN MÁRQUEZ", "Perú"), "zzz")).toBe(false);
  });

  it("substring search keeps working (country search behavior unchanged)", () => {
    expect(matchesParticipantSearch(p("CLARA VEGAS", "Venezuela"), "venez")).toBe(true);
    expect(matchesParticipantSearch(p("CLARA VEGAS", "Venezuela"), "veg")).toBe(true);
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\participant-search.test.ts"
} catch {
    Write-Host "FAILED: src\lib\participant-search.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\participant-search.test.ts"
}

try {
    $path = "src\lib\participant-search.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Contestant/country search that ignores accents and case, so "peru" finds
 * "Perú", "maria" finds "MARÍA", "curacao" finds "Curaçao" and "turkiye"
 * finds "Türkiye". A few letters don't decompose under Unicode NFD, so they
 * are folded explicitly.
 */
const FOLD: Record<string, string> = { ı: "i", ł: "l", ø: "o", đ: "d", ß: "ss", æ: "ae", œ: "oe" };

export function normalizeForSearch(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/[ıłøđßæœ]/g, (char) => FOLD[char] ?? char)
    .trim();
}

export function matchesParticipantSearch(
  participant: { displayName: string; countryName: string },
  query: string,
): boolean {
  const needle = normalizeForSearch(query);
  if (!needle) return true;
  return (
    normalizeForSearch(participant.displayName).includes(needle) ||
    normalizeForSearch(participant.countryName).includes(needle)
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\participant-search.ts"
} catch {
    Write-Host "FAILED: src\lib\participant-search.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\participant-search.ts"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 7 files written successfully." -ForegroundColor Green
}