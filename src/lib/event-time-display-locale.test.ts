import { describe, it, expect } from "vitest";
import { formatEventLocalLockTime, formatEventDayMonth, formatContestantListUpdated } from "./event-time-display";

const BANGKOK_LOCK = "2026-10-09T17:00:00Z"; // Oct 10 00:00 in Bangkok (GMT+7)

describe("event time display — locale-aware presentation, same instant", () => {
  it("English output is unchanged (default locale)", () => {
    expect(formatEventLocalLockTime(BANGKOK_LOCK, "Asia/Bangkok")).toBe(
      formatEventLocalLockTime(BANGKOK_LOCK, "Asia/Bangkok", "en"),
    );
    expect(formatEventLocalLockTime(BANGKOK_LOCK, "Asia/Bangkok", "en")).toContain("Oct 10 at 12:00 AM");
  });

  it("Spanish uses Spanish month/day-period and keeps the timezone", () => {
    const es = formatEventLocalLockTime(BANGKOK_LOCK, "Asia/Bangkok", "es");
    expect(es).toMatch(/10 oct/i);
    expect(es).toMatch(/GMT\+7/);
    expect(es).not.toMatch(/\bAM\b/);
  });

  it("CRITICAL: localizing never changes the underlying instant", () => {
    const before = new Date(BANGKOK_LOCK).getTime();
    formatEventLocalLockTime(BANGKOK_LOCK, "Asia/Bangkok", "es");
    formatEventLocalLockTime(BANGKOK_LOCK, "Asia/Bangkok", "en");
    expect(new Date(BANGKOK_LOCK).getTime()).toBe(before);
  });

  it("day/month label: English unchanged, Spanish day-first", () => {
    expect(formatEventDayMonth("2026-10-10", "en")).toBe("OCT 10");
    expect(formatEventDayMonth("2026-10-10", "es")).toMatch(/^10 OCT/);
  });

  it("roster-updated note uses the localized template and date", () => {
    expect(formatContestantListUpdated("2026-09-22T00:00:00Z", "Updated {date}", "en")).toMatch(/^Updated Sep 22, 2026/);
    expect(formatContestantListUpdated("2026-09-22T00:00:00Z", "Actualizada el {date}", "es")).toMatch(/^Actualizada el 22 sept/i);
  });
});
