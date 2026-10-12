import { describe, it, expect } from "vitest";
import { isDemoPredictionBlocked } from "./event-readiness";

describe("isDemoPredictionBlocked — never predict against placeholder data", () => {
  it("blocks a demo roster by default", () => {
    expect(isDemoPredictionBlocked("demo", false)).toBe(true);
  });
  it("never blocks a verified roster", () => {
    expect(isDemoPredictionBlocked("verified", false)).toBe(false);
    expect(isDemoPredictionBlocked("verified", true)).toBe(false);
  });
  it("local development can explicitly opt in", () => {
    expect(isDemoPredictionBlocked("demo", true)).toBe(false);
  });
  it("the default (no argument) reads ALLOW_DEMO_PREDICTIONS and is blocked when unset", () => {
    const original = process.env.ALLOW_DEMO_PREDICTIONS;
    delete process.env.ALLOW_DEMO_PREDICTIONS;
    expect(isDemoPredictionBlocked("demo")).toBe(true);
    process.env.ALLOW_DEMO_PREDICTIONS = "true";
    expect(isDemoPredictionBlocked("demo")).toBe(false);
    if (original === undefined) delete process.env.ALLOW_DEMO_PREDICTIONS;
    else process.env.ALLOW_DEMO_PREDICTIONS = original;
  });
});
