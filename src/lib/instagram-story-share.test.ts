import { describe, it, expect } from "vitest";
import {
  getDeviceType,
  resolveInstagramShareMethod,
  buildInstagramStoryShareProperties,
} from "./instagram-story-share";

describe("getDeviceType — UA heuristic, display/analytics only, never a capability gate", () => {
  it("detects common mobile user agents", () => {
    expect(getDeviceType("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)")).toBe("mobile");
    expect(getDeviceType("Mozilla/5.0 (Linux; Android 14; Pixel 8)")).toBe("mobile");
    expect(getDeviceType("Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X)")).toBe("mobile");
  });

  it("detects common desktop user agents", () => {
    expect(getDeviceType("Mozilla/5.0 (Windows NT 10.0; Win64; x64)")).toBe("desktop");
    expect(getDeviceType("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")).toBe("desktop");
  });
});

describe("resolveInstagramShareMethod — the one decision this feature makes", () => {
  it("mobile Web Share path: file sharing supported -> native_share", () => {
    expect(resolveInstagramShareMethod(true, "mobile")).toBe("native_share");
  });

  it("desktop with file sharing somehow supported -> still native_share (capability, not device, decides)", () => {
    expect(resolveInstagramShareMethod(true, "desktop")).toBe("native_share");
  });

  it("fallback: mobile without file-share support -> download_fallback", () => {
    expect(resolveInstagramShareMethod(false, "mobile")).toBe("download_fallback");
  });

  it("desktop behavior: no file-share support -> desktop_download, never the generic OS share sheet", () => {
    expect(resolveInstagramShareMethod(false, "desktop")).toBe("desktop_download");
  });
});

describe("buildInstagramStoryShareProperties — privacy: only the allowed keys, ever", () => {
  it("returns exactly the four allowed properties, nothing else", () => {
    const props = buildInstagramStoryShareProperties({
      eventSlug: "miss-grand-international-2026",
      predictionPublicId: "vksp2sfqu",
      deviceType: "mobile",
      shareMethod: "native_share",
    });
    expect(Object.keys(props).sort()).toEqual(
      ["device_type", "event_slug", "prediction_public_id", "share_method"].sort(),
    );
    expect(props).toEqual({
      event_slug: "miss-grand-international-2026",
      prediction_public_id: "vksp2sfqu",
      device_type: "mobile",
      share_method: "native_share",
    });
  });

  it("never contains email, auth_user_id, or device_token keys — the type itself makes this impossible", () => {
    const props = buildInstagramStoryShareProperties({
      eventSlug: "e",
      predictionPublicId: "p",
      deviceType: "desktop",
      shareMethod: "desktop_download",
    });
    const keys = Object.keys(props);
    expect(keys).not.toContain("email");
    expect(keys).not.toContain("auth_user_id");
    expect(keys).not.toContain("device_token");
  });
});
