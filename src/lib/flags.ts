const REGIONAL_INDICATOR_OFFSET = 127397;

/**
 * Converts an ISO 3166-1 alpha-2 code (e.g. "TH") to its Unicode flag
 * emoji. No image assets, no flag library â€” just two regional
 * indicator symbols. Reliable on modern iOS/Android/desktop browsers,
 * which is Fouch's whole audience.
 */
export function flagEmoji(countryCode: string): string {
  return countryCode
    .toUpperCase()
    .replace(/./g, (char) =>
      String.fromCodePoint(char.charCodeAt(0) + REGIONAL_INDICATOR_OFFSET),
    );
}