import { describe, it, expect } from "vitest";
import { getShortLocation } from "./event-location";

describe("getShortLocation — generic comma-structure transform, never event-specific", () => {
  it("shortens a 3-part venue subtitle to city + region", () => {
    expect(getShortLocation("José Miguel Agrelot Coliseum, San Juan, Puerto Rico")).toBe(
      "San Juan, Puerto Rico",
    );
  });

  it("leaves a 2-part subtitle unchanged", () => {
    expect(getShortLocation("Bangkok, Thailand")).toBe("Bangkok, Thailand");
  });

  it("leaves a single-part subtitle unchanged", () => {
    expect(getShortLocation("Bangkok")).toBe("Bangkok");
  });
});
