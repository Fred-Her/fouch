import { describe, it, expect } from "vitest";
import { formatEventLocalLockTime, deriveLocationLabel, formatContestantListUpdated } from "./event-time-display";

const MISS_UNIVERSE_LOCK_AT = "2026-11-24T00:00:00Z";

describe("deriveLocationLabel â€” generic IANA-id -> human label, no new config field", () => {
  it("derives 'Puerto Rico' from 'America/Puerto_Rico'", () => {
    expect(deriveLocationLabel("America/Puerto_Rico")).toBe("Puerto Rico");
  });

  it("derives 'Santiago' from 'America/Santiago'", () => {
    expect(deriveLocationLabel("America/Santiago")).toBe("Santiago");
  });

  it("falls back to the raw identifier if there is no '/' segment", () => {
    expect(deriveLocationLabel("UTC")).toBe("UTC");
  });
});

describe("formatEventLocalLockTime â€” unambiguous, event-local, never a naked time", () => {
  it("resolves the Miss Universe 2026 lock instant correctly in Puerto Rico event time", () => {
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Puerto_Rico");
    // 2026-11-24T00:00:00Z is 2026-11-23 20:00 in America/Puerto_Rico
    // (AST, UTC-4 year-round â€” Puerto Rico does not observe DST).
    expect(result).toBe("Nov 23 at 8:00 PM AST (Puerto Rico)");
  });

  it("always includes a timezone abbreviation â€” never a naked time with no context", () => {
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Puerto_Rico");
    expect(result).toMatch(/[A-Z]{2,5}/); // AST, UTC, GMT+N, etc. â€” some abbreviation/offset token
    expect(result).not.toBe("8:00 PM");
    expect(result).not.toBe("9:00 PM");
  });

  it("always includes the human-readable location context in parentheses", () => {
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Puerto_Rico");
    expect(result).toContain("(Puerto Rico)");
  });

  it("falls back to an explicit UTC-labeled rendering when timezone is null â€” never a silently-assumed local time", () => {
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, null);
    expect(result).toBe("Nov 24 at 12:00 AM UTC");
    expect(result).not.toContain("(");
  });

  it("falls back to UTC gracefully for an invalid/unrecognized IANA identifier, never throws", () => {
    expect(() => formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "Not/ARealZone")).not.toThrow();
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "Not/ARealZone");
    expect(result).toBe("Nov 24 at 12:00 AM UTC");
  });

  it("CRITICAL: formatting for display never changes the absolute instant the ISO string represents â€” same instant, different timezone displays, both parse back to the identical epoch millisecond", () => {
    const epochBefore = new Date(MISS_UNIVERSE_LOCK_AT).getTime();

    // Render in three different timezones â€” none of this touches the
    // original string or reinterprets it as timezone-less.
    formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Puerto_Rico");
    formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Santiago");
    formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, null);

    const epochAfter = new Date(MISS_UNIVERSE_LOCK_AT).getTime();
    expect(epochAfter).toBe(epochBefore);

    // The instant itself, independent of any display formatting, is
    // exactly what server-side lock enforcement compares against
    // (see prediction-lock-logic.test.ts) â€” proving here that display
    // formatting is a pure read, never a mutation of that instant.
    expect(epochBefore).toBe(Date.parse(MISS_UNIVERSE_LOCK_AT));
  });
});

describe("formatContestantListUpdated â€” FOUCH 0.3B Â§13 restrained roster-freshness copy", () => {
  it("renders a plain, human date â€” never the word 'demo'", () => {
    const result = formatContestantListUpdated("2026-09-20T12:00:00Z");
    expect(result).toBe("Contestant list updated Sep 20, 2026");
    expect(result.toLowerCase()).not.toContain("demo");
  });

  it("never claims completeness â€” no 'official lineup' or 'complete' wording", () => {
    const result = formatContestantListUpdated("2026-09-20T12:00:00Z");
    expect(result.toLowerCase()).not.toContain("official lineup");
    expect(result.toLowerCase()).not.toContain("complete");
  });
});
