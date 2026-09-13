import { describe, it, expect, beforeEach } from "vitest";
import { captureUtmSource } from "./attribution";

function setUrl(search: string) {
  window.history.pushState({}, "", `/${search}`);
}

describe("captureUtmSource", () => {
  beforeEach(() => {
    window.sessionStorage.clear();
    setUrl("");
  });

  it("captures a simple source (reddit)", () => {
    setUrl("?utm_source=reddit");
    expect(captureUtmSource()).toBe("reddit");
  });

  it("captures another simple source (instagram)", () => {
    setUrl("?utm_source=instagram");
    expect(captureUtmSource()).toBe("instagram");
  });

  it("returns null with no utm_source and nothing previously captured", () => {
    setUrl("");
    expect(captureUtmSource()).toBeNull();
  });

  it("persists across calls within the same session even after the param is gone", () => {
    setUrl("?utm_source=missosology");
    expect(captureUtmSource()).toBe("missosology");
    setUrl(""); // simulate navigating to a page with no query string
    expect(captureUtmSource()).toBe("missosology");
  });

  it("sanitizes an overly long source by truncating", () => {
    const long = "a".repeat(200);
    setUrl(`?utm_source=${long}`);
    const result = captureUtmSource();
    expect(result).not.toBeNull();
    expect(result!.length).toBeLessThanOrEqual(50);
  });

  it("sanitizes malformed characters out of the source", () => {
    setUrl(`?utm_source=${encodeURIComponent("<script>alert(1)</script>")}`);
    const result = captureUtmSource();
    expect(result).not.toContain("<");
    expect(result).not.toContain(">");
  });

  it("a new utm_source overwrites a previously captured one", () => {
    setUrl("?utm_source=reddit");
    captureUtmSource();
    setUrl("?utm_source=creator");
    expect(captureUtmSource()).toBe("creator");
  });
});