import { describe, it, expect } from "vitest";
import { chooseRosterSource, demoParticipantsForIds, DEMO_ID_PREFIX } from "./participant-sources";
import type { Participant } from "@/types/participant";

const demo = (code: string): Participant => ({
  id: `demo-${code}`,
  eventId: "seed",
  displayName: code,
  countryCode: code.toUpperCase(),
  countryName: code,
  sortOrder: 0,
  isActive: true,
});
const demoList = [demo("ar"), demo("cl"), demo("ve")];

describe("chooseRosterSource — the database always wins", () => {
  it("an event with roster rows uses the database, even when a demo list exists (Miss Universe after the roster load)", () => {
    expect(chooseRosterSource(24, true)).toBe("db");
  });
  it("an event with NO rows falls back to the demo list only if one exists (Miss Universe before the roster load -> Coming soon)", () => {
    expect(chooseRosterSource(0, true)).toBe("demo");
  });
  it("an event with no rows and no demo list has no roster at all", () => {
    expect(chooseRosterSource(0, false)).toBe("none");
  });
  it("a single row is enough to switch to the database (no placeholder padding)", () => {
    expect(chooseRosterSource(1, true)).toBe("db");
  });
});

describe("demoParticipantsForIds — historical demo predictions keep rendering", () => {
  it("resolves only the demo ids a saved prediction references", () => {
    const found = demoParticipantsForIds(["demo-ar", "demo-ve", "demo-zz"], demoList);
    expect(found.map((p) => p.id)).toEqual(["demo-ar", "demo-ve"]);
  });
  it("never resolves a real (uuid) participant id from the demo list", () => {
    expect(demoParticipantsForIds(["e2a5991c-cafd-4a42-a5a4-e46b6719a914"], demoList)).toEqual([]);
  });
  it("an event with no demo list resolves nothing", () => {
    expect(demoParticipantsForIds(["demo-ar"], undefined)).toEqual([]);
  });
  it("uses the documented demo id prefix", () => {
    expect(DEMO_ID_PREFIX).toBe("demo-");
  });
});
