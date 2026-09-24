import { describe, it, expect } from "vitest";
import { splitEventNameYear } from "./event-name-split";

describe("splitEventNameYear — generic, never a specific-event hardcode", () => {
  it("splits 'Miss Universe 2026' into 'Miss Universe' + '2026'", () => {
    expect(splitEventNameYear("Miss Universe 2026")).toEqual({ primary: "Miss Universe", year: "2026" });
  });

  it("splits 'Miss Grand International 2026' into 'Miss Grand International' + '2026' — same function, no per-event branch", () => {
    expect(splitEventNameYear("Miss Grand International 2026")).toEqual({
      primary: "Miss Grand International",
      year: "2026",
    });
  });

  it("falls back to the whole name with no year when there is no trailing 4-digit token", () => {
    expect(splitEventNameYear("The Oscars")).toEqual({ primary: "The Oscars", year: null });
  });

  it("does not split on a non-4-digit trailing number", () => {
    expect(splitEventNameYear("Top 10")).toEqual({ primary: "Top 10", year: null });
  });
});
