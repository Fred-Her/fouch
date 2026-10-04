import { describe, it, expect, vi, afterEach } from "vitest";

describe("analytics — locale property on every event (i18n v1)", () => {
  const originalKey = process.env.NEXT_PUBLIC_POSTHOG_KEY;
  afterEach(() => {
    if (originalKey === undefined) delete process.env.NEXT_PUBLIC_POSTHOG_KEY;
    else process.env.NEXT_PUBLIC_POSTHOG_KEY = originalKey;
    vi.resetModules();
    vi.restoreAllMocks();
  });

  async function setup() {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    const captureSpy = vi.fn();
    vi.doMock("posthog-js", () => ({ default: { init: vi.fn(), capture: captureSpy } }));
    const analytics = await import("./analytics");
    return { ...analytics, captureSpy };
  }

  it("attaches locale to the funnel events once the UI language is known", async () => {
    const { track, setAnalyticsLocale, captureSpy } = await setup();
    setAnalyticsLocale("es");
    for (const event of [
      "landing_view",
      "start_prediction",
      "prediction_completed",
      "verification_sent",
      "prediction_submitted",
      "you_vs_world_viewed",
      "share_clicked",
      "instagram_story_clicked",
    ] as const) {
      track(event, { event_slug: "miss-grand-international-2026" });
      expect(captureSpy).toHaveBeenLastCalledWith(event, {
        locale: "es",
        event_slug: "miss-grand-international-2026",
      });
    }
  });

  it("existing event names are unchanged and still fire with their original properties plus locale", async () => {
    const { track, setAnalyticsLocale, captureSpy } = await setup();
    setAnalyticsLocale("en");
    track("prediction_submitted", { event_slug: "e", utm_source: "whatsapp" });
    expect(captureSpy).toHaveBeenCalledWith("prediction_submitted", {
      locale: "en",
      event_slug: "e",
      utm_source: "whatsapp",
    });
  });

  it("language_changed carries from_locale, to_locale, page and event_slug", async () => {
    const { track, setAnalyticsLocale, captureSpy } = await setup();
    setAnalyticsLocale("en");
    track("language_changed", {
      from_locale: "en",
      to_locale: "es",
      page: "/predict/miss-grand-international-2026",
      event_slug: "miss-grand-international-2026",
    });
    expect(captureSpy).toHaveBeenCalledWith("language_changed", {
      locale: "en",
      from_locale: "en",
      to_locale: "es",
      page: "/predict/miss-grand-international-2026",
      event_slug: "miss-grand-international-2026",
    });
  });

  it("no locale property is added before a locale is set (existing behavior untouched)", async () => {
    const { track, captureSpy } = await setup();
    track("landing_view", { utm_source: "x" });
    expect(captureSpy).toHaveBeenCalledWith("landing_view", { utm_source: "x" });
  });

  it("an explicit locale in the call's own properties wins", async () => {
    const { track, setAnalyticsLocale, captureSpy } = await setup();
    setAnalyticsLocale("es");
    track("landing_view", { locale: "en" });
    expect(captureSpy).toHaveBeenCalledWith("landing_view", { locale: "en" });
  });

  it("still never sends private identifiers (locale is the only addition)", async () => {
    const { track, setAnalyticsLocale, captureSpy } = await setup();
    setAnalyticsLocale("es");
    track("instagram_story_clicked", {
      event_slug: "e",
      prediction_public_id: "abc123",
      device_type: "mobile",
      share_method: "native_share",
    });
    const props = captureSpy.mock.calls[0]?.[1] as Record<string, unknown>;
    expect(Object.keys(props).sort()).toEqual(
      ["device_type", "event_slug", "locale", "prediction_public_id", "share_method"].sort(),
    );
  });
});
