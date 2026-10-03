/**
 * FOUCH — Instagram Story Sharing UX. The entire decision logic for
 * "what should clicking Instagram Story actually do" lives here, pure
 * and DB/DOM-free, so it's directly unit-testable without mocking
 * `navigator` or the DOM — the same pattern this codebase already
 * uses everywhere else (see prediction-version-logic.ts,
 * event-name-split.ts). `ShareActions.tsx` calls these functions but
 * contains none of the decision logic itself.
 */

export type DeviceType = "mobile" | "desktop";
export type InstagramShareMethod = "native_share" | "download_fallback" | "desktop_download";

/**
 * Standard UA-based mobile heuristic — good enough for an analytics
 * property and for choosing fallback copy, never used to gate
 * functionality (the actual capability check is always
 * navigator.canShare({ files }), not this).
 */
export function getDeviceType(userAgent: string): DeviceType {
  return /Android|iPhone|iPad|iPod|Mobile/i.test(userAgent) ? "mobile" : "desktop";
}

/**
 * The one decision this whole feature makes: given whether the
 * browser can actually share the generated Story image as a file, and
 * what kind of device this is, which path did the user just take?
 * Never assumes Instagram specifically will appear in the share sheet
 * — "native_share" only means the OS share sheet opened with the file
 * attached, not that Instagram was chosen.
 */
export function resolveInstagramShareMethod(
  canShareFile: boolean,
  deviceType: DeviceType,
): InstagramShareMethod {
  if (canShareFile) return "native_share";
  return deviceType === "mobile" ? "download_fallback" : "desktop_download";
}

/**
 * The exact, minimal property set sent to PostHog for
 * instagram_story_clicked — never anything beyond event_slug,
 * prediction_public_id (already public — it's the URL slug), device
 * type, and the resolved share method. No email, no auth_user_id, no
 * device_token, no internal numeric prediction id.
 */
export interface InstagramStoryShareProperties {
  event_slug: string;
  prediction_public_id: string;
  device_type: DeviceType;
  share_method: InstagramShareMethod;
}

export function buildInstagramStoryShareProperties(params: {
  eventSlug: string;
  predictionPublicId: string;
  deviceType: DeviceType;
  shareMethod: InstagramShareMethod;
}): InstagramStoryShareProperties {
  return {
    event_slug: params.eventSlug,
    prediction_public_id: params.predictionPublicId,
    device_type: params.deviceType,
    share_method: params.shareMethod,
  };
}
