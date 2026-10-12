# FOUCH — Predictor country-name consistency fix (presentation only).
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-predictor-country-fix.ps1
$failures = @()

try {
    $path = "src\lib\countries.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
export function getPredictorCountryName(code: string | null): string | null {
  if (!code) return null;
  return PREDICTOR_COUNTRIES.find((country) => country.code === code)?.name ?? null;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\countries.ts"
} catch {
    Write-Host "FAILED: src\lib\countries.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\countries.ts"
}

try {
    $path = "src\components\prediction\PredictionCardMarkup.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Participant } from "@/types/participant";
import { getPredictorCountryName } from "@/lib/countries";

export interface CardData {
  eventName: string;
  nickname: string | null;
  countryCode: string | null;
  isDemo: boolean;
  rankedParticipants: Participant[];
}

const INK = "#141318";
const SURFACE = "#232028";
const ACCENT = "#A6342E";
const ACCENT_STRONG = "#C44C42";
const TEXT_PRIMARY = "#F2EFE6";
const TEXT_MUTED = "#A39FB0";

/**
 * `next/og` (Satori under the hood) does not render Unicode flag
 * emoji reliably — confirmed by generating and visually inspecting
 * the actual output, which showed blank space where a flag should be.
 * Plain country-name text is the robust substitute: no emoji font
 * dependency, no network fetch, renders identically everywhere — and,
 * per Cohort 0 feedback, is what users actually asked for (a bare ISO
 * code like "VE" wasn't recognizable on its own). `maxWidth` + the
 * overflow/ellipsis trio keeps a long country name from breaking this
 * fixed-size image's layout.
 */
function CountryBadge({ name, fontSize, maxWidth }: { name: string; fontSize: number; maxWidth: number }) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "flex-end",
        fontSize,
        fontWeight: 700,
        color: TEXT_MUTED,
        maxWidth,
        overflow: "hidden",
        whiteSpace: "nowrap",
        textOverflow: "ellipsis",
      }}
    >
      {name}
    </div>
  );
}

/**
 * Shared visual system for both the Story (1080x1920) and Post
 * (1080x1350) formats — same tokens as the product UI (ink
 * background, oxblood accent) but bolder/bigger, per the approved
 * "energetic / shareable" direction for social cards. `height` also
 * drives a scale factor so the taller Story format fills its frame
 * instead of leaving a dead zone below a 10-item list.
 */
export function PredictionCardMarkup({
  data,
  width,
  height,
  siteDomain,
}: {
  data: CardData;
  width: number;
  height: number;
  siteDomain: string;
}) {
  const scale = Math.min(1.32, Math.max(1, height / 1350));
  const top3 = data.rankedParticipants.slice(0, 3);
  const rest = data.rankedParticipants.slice(3, 10);
  const predictorCountryName = getPredictorCountryName(data.countryCode);
  const whoBy = data.nickname
    ? `${data.nickname}${predictorCountryName ? ` · ${predictorCountryName}` : ""}`
    : predictorCountryName;

  return (
    <div
      style={{
        width,
        height,
        display: "flex",
        flexDirection: "column",
        backgroundColor: INK,
        fontFamily: "Georgia, serif",
        padding: `${64 * scale}px 56px`,
        color: TEXT_PRIMARY,
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", flexDirection: "column" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div style={{ display: "flex", fontSize: 28, letterSpacing: 4, color: TEXT_MUTED }}>
            FOUCH
          </div>
          {data.isDemo ? (
            <div
              style={{
                display: "flex",
                fontSize: 22,
                color: TEXT_MUTED,
                border: `1px solid ${TEXT_MUTED}`,
                borderRadius: 6,
                padding: "6px 14px",
              }}
            >
              DEMO
            </div>
          ) : null}
        </div>
        <div style={{ display: "flex", fontSize: 46 * scale, fontWeight: 700, marginTop: 18 }}>
          MAKE YOUR CALL.
        </div>
        <div style={{ display: "flex", fontSize: 30, color: TEXT_MUTED, marginTop: 8 }}>
          {data.eventName}
        </div>
        {whoBy ? (
          <div
            style={{
              display: "flex",
              fontSize: 28,
              color: ACCENT_STRONG,
              marginTop: 10,
              maxWidth: width - 112,
              overflow: "hidden",
              whiteSpace: "nowrap",
              textOverflow: "ellipsis",
            }}
          >
            {whoBy}
          </div>
        ) : null}
      </div>

      {/* Top 3 — big, energetic blocks */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: 44 * scale, gap: 18 * scale }}>
        {top3.map((participant, index) => (
          <div
            key={participant.id}
            style={{
              display: "flex",
              alignItems: "center",
              backgroundColor: index === 0 ? ACCENT : SURFACE,
              borderRadius: 20,
              padding: `${26 * scale}px 32px`,
            }}
          >
            <div style={{ display: "flex", fontSize: 64 * scale, fontWeight: 700, width: 110 }}>
              {index + 1}
            </div>
            <div style={{ display: "flex", fontSize: 40 * scale, fontWeight: 700, flex: 1 }}>
              {participant.displayName}
            </div>
            <CountryBadge name={participant.countryName} fontSize={26 * scale} maxWidth={230} />
          </div>
        ))}
      </div>

      {/* 4-10 — compact list */}
      {rest.length > 0 ? (
        <div style={{ display: "flex", flexDirection: "column", marginTop: 26 * scale, gap: 12 * scale }}>
          {rest.map((participant, index) => (
            <div key={participant.id} style={{ display: "flex", alignItems: "center", fontSize: 27 * scale }}>
              <div style={{ display: "flex", width: 60, color: TEXT_MUTED }}>{index + 4}</div>
              <div style={{ display: "flex", flex: 1, color: TEXT_PRIMARY }}>{participant.displayName}</div>
              <CountryBadge name={participant.countryName} fontSize={20} maxWidth={170} />
            </div>
          ))}
        </div>
      ) : null}

      {/* Footer */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: "auto" }}>
        <div style={{ display: "flex", fontSize: 34, fontWeight: 700 }}>WHO YOU GOT?</div>
        <div style={{ display: "flex", fontSize: 24, color: TEXT_MUTED, marginTop: 6 }}>
          {siteDomain}
        </div>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\PredictionCardMarkup.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\PredictionCardMarkup.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\PredictionCardMarkup.tsx"
}

try {
    $path = "src\components\scoring\ResultCardMarkup.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { ScoreBreakdown, ScoreBand } from "@/types/scoring";
import { getPredictorCountryName } from "@/lib/countries";

export interface ResultCardData {
  eventName: string;
  nickname: string | null;
  countryCode: string | null;
  isDemo: boolean;
  breakdown: ScoreBreakdown;
  percentile: number | null;
}

const INK = "#141318";
const SURFACE = "#232028";
const ACCENT = "#A6342E";
const ACCENT_STRONG = "#C44C42";
const TEXT_PRIMARY = "#F2EFE6";
const TEXT_MUTED = "#A39FB0";

const BAND_LABEL: Record<ScoreBand, string> = {
  MISSED_IT: "Missed it",
  FAIR: "Fair call",
  GOOD: "Good call",
  EXCELLENT: "Excellent call",
  ELITE: "Elite call",
};

/**
 * Same visual system as PredictionCardMarkup — same tokens, same
 * "no Unicode emoji, no photography" constraints (Satori can't render
 * flag emoji reliably; see PredictionCardMarkup.tsx's note). This is a
 * separate component (not a reskin of PredictionCardMarkup) because its
 * content is fundamentally different — a result, not a pick list — but
 * it deliberately reuses every token and spacing decision so it reads
 * as unmistakably the same product.
 */
export function ResultCardMarkup({
  data,
  width,
  height,
  siteDomain,
}: {
  data: ResultCardData;
  width: number;
  height: number;
  siteDomain: string;
}) {
  const scale = Math.min(1.32, Math.max(1, height / 1350));
  const predictorCountryName = getPredictorCountryName(data.countryCode);
  const whoBy = data.nickname
    ? `${data.nickname}${predictorCountryName ? ` · ${predictorCountryName}` : ""}`
    : predictorCountryName;
  const { breakdown } = data;

  return (
    <div
      style={{
        width,
        height,
        display: "flex",
        flexDirection: "column",
        backgroundColor: INK,
        fontFamily: "Georgia, serif",
        padding: `${64 * scale}px 56px`,
        color: TEXT_PRIMARY,
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div style={{ display: "flex", fontSize: 28, letterSpacing: 4, color: TEXT_MUTED }}>FOUCH</div>
        {data.isDemo ? (
          <div
            style={{
              display: "flex",
              fontSize: 22,
              color: TEXT_MUTED,
              border: `1px solid ${TEXT_MUTED}`,
              borderRadius: 6,
              padding: "6px 14px",
            }}
          >
            DEMO
          </div>
        ) : null}
      </div>

      <div style={{ display: "flex", fontSize: 30, color: TEXT_MUTED, marginTop: 24 }}>{data.eventName}</div>
      {whoBy ? (
        <div
          style={{
            display: "flex",
            fontSize: 26,
            color: ACCENT_STRONG,
            marginTop: 8,
            maxWidth: width - 112,
            overflow: "hidden",
            whiteSpace: "nowrap",
            textOverflow: "ellipsis",
          }}
        >
          {whoBy}
        </div>
      ) : null}

      {/* Score — the hero element */}
      <div
        style={{
          display: "flex",
          fontSize: 170 * scale,
          fontWeight: 700,
          marginTop: 20,
          lineHeight: 1,
          letterSpacing: 4,
        }}
      >
        {breakdown.displayScore}
      </div>
      <div style={{ display: "flex", fontSize: 46 * scale, fontWeight: 700, color: ACCENT, marginTop: 4 }}>
        {BAND_LABEL[breakdown.band].toUpperCase()}
      </div>

      {/* Breakdown */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: 64 * scale, gap: 28 * scale }}>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>Winner</div>
          <div style={{ display: "flex", color: breakdown.components.winner.hit ? ACCENT_STRONG : TEXT_MUTED }}>
            {breakdown.components.winner.hit ? "Correct" : "Missed"}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>Podium</div>
          <div style={{ display: "flex" }}>
            {breakdown.components.podium.hits} / {breakdown.components.podium.total}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>Top 5</div>
          <div style={{ display: "flex" }}>
            {breakdown.components.top5.hits} / {breakdown.components.top5.total}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>Top 10</div>
          <div style={{ display: "flex" }}>
            {breakdown.components.top10.hits} / {breakdown.components.top10.total}
          </div>
        </div>
      </div>

      {data.percentile !== null ? (
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            marginTop: 44 * scale,
            padding: "28px 32px",
            backgroundColor: SURFACE,
            borderRadius: 16,
          }}
        >
          <div style={{ display: "flex", fontSize: 30 * scale, color: TEXT_MUTED }}>TOP {100 - Math.round(data.percentile)}%</div>
          <div style={{ display: "flex", fontSize: 38 * scale, fontWeight: 700 }}>WORLDWIDE</div>
        </div>
      ) : null}

      {/* Footer */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: "auto" }}>
        <div style={{ display: "flex", fontSize: 34, fontWeight: 700 }}>THINK YOU COULD BEAT IT?</div>
        <div style={{ display: "flex", fontSize: 24, color: TEXT_MUTED, marginTop: 6 }}>{siteDomain}</div>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\ResultCardMarkup.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\ResultCardMarkup.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\ResultCardMarkup.tsx"
}

try {
    $path = "src\app\p\[publicId]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CountryFlag } from "@/components/CountryFlag";
import { siteUrl } from "@/lib/site";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { getOfficialResult } from "@/lib/results-db";
import { formatContestantListUpdated } from "@/lib/event-time-display";
import { getPredictorCountryName } from "@/lib/countries";
import { PublicPredictionView } from "@/components/prediction/PublicPredictionView";
import { YouVsTheWorld } from "@/components/prediction/YouVsTheWorld";
import { FouchScore } from "@/components/scoring/FouchScore";
import { YourCrowdChanged } from "@/components/scoring/YourCrowdChanged";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ publicId: string }>;
}): Promise<Metadata> {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) return {};

  const title = record.prediction.nickname
    ? `${record.prediction.nickname}'s Top 10 — ${record.event.name}`
    : `A Top 10 prediction — ${record.event.name}`;
  const description = "See the prediction, then make your own call.";

  return {
    title,
    description,
    // Sprint 2 decision: public prediction pages are reachable via
    // link but intentionally not indexed â€” we don't want thousands of
    // thin user-generated pages in search results. `follow` so the
    // "Make your Top 10" CTA is still crawlable back to the real
    // product pages.
    robots: { index: false, follow: true },
    openGraph: {
      title,
      description,
      url: `${siteUrl}/p/${publicId}`,
      images: [`${siteUrl}/p/${publicId}/opengraph-image`],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
    },
  };
}

export default async function PublicPredictionPage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) notFound();

  const { prediction, event, rankedParticipants } = record;
  const heading = prediction.nickname ? `${prediction.nickname}'s Top 10` : "Someone's Top 10";

  // Cheap existence check only (no percentile/breakdown work) â€” used
  // purely to decide share-CTA hierarchy (Sprint 4.1 Â§7-8). FouchScore
  // below independently does the full scored computation; this is a
  // second, lightweight read of the same result row, not duplicated
  // scoring logic.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);
  const hasResult = Boolean(official);

  // FOUCH 0.3A: editing is offered only for a verified prediction
  // while the event is still open â€” fetched fresh on every page view
  // from the single authoritative source, never cached/assumed.
  const lockConfig = await getEventLockConfig(event.slug);
  const isPredictionOpen = isPredictionWindowOpen(lockConfig, Date.now());
  const canEdit = prediction.hasVerifiedOwner && isPredictionOpen;
  const showLockedNotice = prediction.hasVerifiedOwner && !isPredictionOpen;

  // FOUCH 0.3B Â§13: "Contestant list updated {date}" for a real,
  // non-demo event with verified-roster provenance â€” never "Demo
  // prediction" for one of these. Null (no participant rows checked
  // yet, or a hardcoded/demo event) simply shows nothing extra here.
  const participantData = await getParticipantsForEvent(event.slug);
  const sourceCheckedAt = participantData?.sourceCheckedAt ?? null;

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>

      <h1 className="mt-6 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-2 font-display text-xl uppercase tracking-tight text-text-primary">
        {heading}
      </p>

      {prediction.countryCode ? (
        <p className="mt-1 flex items-center gap-1.5 text-sm text-text-muted">
          <CountryFlag countryCode={prediction.countryCode} />
          {getPredictorCountryName(prediction.countryCode)}
        </p>
      ) : null}

      {prediction.dataStatus === "demo" ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo prediction — not the official lineup
        </p>
      ) : sourceCheckedAt ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          {formatContestantListUpdated(sourceCheckedAt)}
        </p>
      ) : null}

      <PublicPredictionView
        eventSlug={event.slug}
        publicId={publicId}
        rankedParticipants={rankedParticipants}
        hasResult={hasResult}
        canEdit={canEdit}
        showLockedNotice={showLockedNotice}
        predictionLockAt={lockConfig?.predictionLockAt ?? null}
        predictionTimezone={lockConfig?.timezone ?? null}
        fouchScore={<FouchScore prediction={prediction} event={event} publicId={publicId} />}
        youVsTheWorld={<YouVsTheWorld prediction={prediction} event={event} />}
        yourCrowdChanged={<YourCrowdChanged prediction={prediction} event={event} />}
      />
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\page.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\page.tsx"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 4 files written successfully." -ForegroundColor Green
}
