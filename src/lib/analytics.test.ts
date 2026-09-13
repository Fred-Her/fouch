import { describe, it, expect, vi, afterEach } from "vitest";

describe("track() — Beta Hardening 0.1: analytics must never break the product", () => {
  const originalKey = process.env.NEXT_PUBLIC_POSTHOG_KEY;

  afterEach(() => {
    if (originalKey === undefined) delete process.env.NEXT_PUBLIC_POSTHOG_KEY;
    else process.env.NEXT_PUBLIC_POSTHOG_KEY = originalKey;
    vi.resetModules();
    vi.restoreAllMocks();
  });

  it("does not throw when no PostHog key is configured (falls back silently)", async () => {
    delete process.env.NEXT_PUBLIC_POSTHOG_KEY;
    vi.resetModules();
    const { track } = await import("./analytics");
    const debugSpy = vi.spyOn(console, "debug").mockImplementation(() => {});

    expect(() => track("landing_view", { utm_source: "reddit" })).not.toThrow();
    expect(debugSpy).toHaveBeenCalledWith("[fouch:analytics]", "landing_view", { utm_source: "reddit" });
  });

  it("does not throw even if posthog.init itself throws", async () => {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    vi.doMock("posthog-js", () => ({
      default: {
        init: () => {
          throw new Error("network unavailable");
        },
        capture: vi.fn(),
      },
    }));
    const { track } = await import("./analytics");

    expect(() => track("prediction_submitted", { event_slug: "miss-universe-2026" })).not.toThrow();
  });

  it("does not throw even if posthog.capture itself throws (ad blocker, etc.)", async () => {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    vi.doMock("posthog-js", () => ({
      default: {
        init: vi.fn(),
        capture: () => {
          throw new Error("blocked by client");
        },
      },
    }));
    const { track } = await import("./analytics");

    expect(() => track("prediction_submitted", { event_slug: "miss-universe-2026" })).not.toThrow();
  });

  it("calls posthog.capture with the exact event name and properties when configured", async () => {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    const captureSpy = vi.fn();
    vi.doMock("posthog-js", () => ({
      default: { init: vi.fn(), capture: captureSpy },
    }));
    const { track } = await import("./analytics");

    track("score_viewed", { event_slug: "miss-universe-2026", score_band: "EXCELLENT" });

    expect(captureSpy).toHaveBeenCalledWith("score_viewed", {
      event_slug: "miss-universe-2026",
      score_band: "EXCELLENT",
    });
  });

  it("never calls posthog.identify — stays on anonymous distinct_id semantics", async () => {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    const identifySpy = vi.fn();
    vi.doMock("posthog-js", () => ({
      default: { init: vi.fn(), capture: vi.fn(), identify: identifySpy },
    }));
    const { track } = await import("./analytics");

    track("public_prediction_viewed", { event_slug: "miss-universe-2026" });

    expect(identifySpy).not.toHaveBeenCalled();
  });
});