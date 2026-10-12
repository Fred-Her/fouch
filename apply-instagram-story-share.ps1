# FOUCH — Instagram Story Sharing UX.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-instagram-story-share.ps1
$failures = @()

try {
    $path = "src\lib\analytics.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Analytics seam — Beta Hardening 0.1.
 *
 * Every call site still imports the same `track(event, properties)`
 * function as before; only the transport underneath changed, from a
 * console.debug stub to real PostHog capture. The contract is
 * unchanged on purpose so no component needed to be touched.
 *
 * Configuration (set in Vercel):
 *   NEXT_PUBLIC_POSTHOG_KEY  — PostHog project API key (public by
 *     design — PostHog's own docs confirm this key is meant to be
 *     browser-visible; it is not a secret).
 *   NEXT_PUBLIC_POSTHOG_HOST — defaults to https://us.i.posthog.com
 *     if unset; only needed for a self-hosted or EU-region instance.
 *
 * Without NEXT_PUBLIC_POSTHOG_KEY configured, track() falls back to
 * the original console.debug behavior — nothing crashes, nothing is
 * silently required. Analytics is always best-effort: every call is
 * wrapped so a PostHog failure (network, ad blocker, misconfiguration)
 * can never throw into product code. Prediction submission, sharing,
 * and every public page must keep working exactly the same whether or
 * not analytics succeeds.
 *
 * Properties must never carry personally identifiable information or
 * free-text nickname/contestant input — only structural values like
 * an event slug, a count, a position, or a share method. This function
 * also never calls posthog.identify() — every event stays on
 * PostHog's normal anonymous, cookie/localStorage-backed distinct_id.
 * Connecting anonymous activity to a verified identity is explicitly
 * deferred to Beta Hardening 0.2.
 */

import posthog from "posthog-js";

let posthogReady = false;

function ensurePostHogInitialized(): boolean {
  if (typeof window === "undefined") return false;

  const key = process.env.NEXT_PUBLIC_POSTHOG_KEY;
  if (!key) return false;

  if (!posthogReady) {
    try {
      posthog.init(key, {
        api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST || "https://us.i.posthog.com",
        // Beta-appropriate defaults: no automatic pageview capture (we
        // fire explicit, typed events already, e.g. landing_view), and
        // no full "person" profile creation for anonymous beta traffic
        // — keeps this cheap and avoids modeling identity we haven't
        // decided on yet (that's Beta Hardening 0.2).
        capture_pageview: false,
        person_profiles: "identified_only",
      });
      posthogReady = true;
    } catch {
      return false;
    }
  }

  return true;
}

export type FouchAnalyticsEvent =
  | "landing_view"
  | "featured_event_clicked"
  | "start_prediction"
  | "participant_selected"
  | "participant_removed"
  | "prediction_reordered"
  | "prediction_completed"
  | "prediction_reviewed"
  | "prediction_submit_started"
  | "prediction_submitted"
  | "prediction_card_generated"
  | "share_clicked"
  | "instagram_story_clicked"
  | "native_share_opened"
  | "copy_link_clicked"
  | "image_downloaded"
  | "public_prediction_viewed"
  | "public_prediction_cta_clicked"
  | "prediction_edit_started"
  | "prediction_edit_reordered"
  | "prediction_updated"
  | "you_vs_world_viewed"
  | "same_winner_viewed"
  | "top3_match_viewed"
  | "boldest_pick_viewed"
  | "community_top10_viewed"
  | "community_share_clicked"
  | "score_viewed"
  | "score_breakdown_viewed"
  | "percentile_viewed"
  | "result_card_generated"
  | "result_card_shared"
  | "result_card_saved"
  | "result_share_link_copied"
  | "leaderboard_viewed"
  | "leaderboard_row_clicked"
  | "own_rank_viewed"
  | "leaderboard_from_score_clicked"
  | "consensus_change_viewed"
  | "verification_started"
  | "verification_sent"
  | "verification_completed"
  | "verification_failed"
  | "duplicate_prediction_attempt";

export function track(event: FouchAnalyticsEvent, properties?: Record<string, unknown>) {
  if (typeof window === "undefined") return;

  try {
    if (ensurePostHogInitialized()) {
      posthog.capture(event, properties);
      return;
    }
  } catch {
    // Analytics must never break the product — fall through to the
    // silent/dev-visible fallback below rather than propagate.
  }

  // No PostHog key configured (or init/capture failed): preserve the
  // original, harmless console.debug behavior rather than losing
  // visibility entirely during local development or misconfiguration.
  console.debug("[fouch:analytics]", event, properties ?? {});
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\analytics.ts"
} catch {
    Write-Host "FAILED: src\lib\analytics.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\analytics.ts"
}

try {
    $path = "src\lib\instagram-story-share.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\instagram-story-share.ts"
} catch {
    Write-Host "FAILED: src\lib\instagram-story-share.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\instagram-story-share.ts"
}

try {
    $path = "src\lib\instagram-story-share.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\instagram-story-share.test.ts"
} catch {
    Write-Host "FAILED: src\lib\instagram-story-share.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\instagram-story-share.test.ts"
}

try {
    $path = "src\components\prediction\ShareActions.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useState } from "react";
import { Share2, Download, Link2, Check, Camera } from "lucide-react";
import { track } from "@/lib/analytics";
import type { FouchAnalyticsEvent } from "@/lib/analytics";
import {
  getDeviceType,
  resolveInstagramShareMethod,
  buildInstagramStoryShareProperties,
} from "@/lib/instagram-story-share";

interface ShareEventNames {
  share: FouchAnalyticsEvent;
  nativeOpened: FouchAnalyticsEvent | null;
  download: FouchAnalyticsEvent;
  copyLink: FouchAnalyticsEvent;
}

const EVENT_NAMES: Record<"prediction" | "result", ShareEventNames> = {
  prediction: {
    share: "share_clicked",
    nativeOpened: "native_share_opened",
    download: "image_downloaded",
    copyLink: "copy_link_clicked",
  },
  result: {
    share: "result_card_shared",
    nativeOpened: null,
    download: "result_card_saved",
    copyLink: "result_share_link_copied",
  },
};

/** Triggers a browser download of a Blob without navigating away —
 * the same mechanism the browser's own download attribute uses, just
 * invoked programmatically since Instagram Story's file comes from a
 * fetch(), not a plain <a href> the user clicked. */
function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

export function ShareActions({
  eventSlug,
  publicId,
  publicUrl,
  storyCardUrl,
  postCardUrl,
  variant = "prediction",
}: {
  eventSlug: string;
  /** The prediction's public_id — already public (it's the URL slug)
   * — used only as an analytics property, never a private/internal id. */
  publicId: string;
  publicUrl: string;
  storyCardUrl: string;
  postCardUrl: string;
  /** Defaults to "prediction" — the existing, unchanged behavior. Pass
   * "result" to reuse this exact component for the post-result Result
   * Card, firing the distinct result_* analytics events instead. */
  variant?: "prediction" | "result";
}) {
  const [format, setFormat] = useState<"story" | "post">("story");
  const [copied, setCopied] = useState(false);
  const [canNativeShare, setCanNativeShare] = useState(false);
  const [instagramState, setInstagramState] = useState<"idle" | "generating" | "ready">("idle");
  const [instagramDeviceType, setInstagramDeviceType] = useState<"mobile" | "desktop">("desktop");
  const events = EVENT_NAMES[variant];

  // navigator.share only exists client-side — checked once after mount
  // so server and initial client render stay consistent (no
  // hydration mismatch).
  useEffect(() => {
    if (typeof navigator !== "undefined" && "share" in navigator) {
      setCanNativeShare(true);
    }
  }, []);

  const activeCardUrl = format === "story" ? storyCardUrl : postCardUrl;

  async function handleShare() {
    track(events.share, { event_slug: eventSlug, share_method: "native" });
    if (!canNativeShare) return;

    try {
      await navigator.share({ title: "My Fouch prediction", url: publicUrl });
      if (events.nativeOpened) track(events.nativeOpened, { event_slug: eventSlug });
    } catch {
      // User cancelled the share sheet — not an error worth surfacing.
    }
  }

  async function handleCopyLink() {
    track(events.copyLink, { event_slug: eventSlug });
    try {
      await navigator.clipboard.writeText(publicUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard API unavailable — the link is still visible/selectable
      // in the UI as a fallback (see the public page).
    }
  }

  function handleDownload() {
    track(events.download, { event_slug: eventSlug, share_method: format });
  }

  /**
   * Instagram Story is deliberately NOT the generic handleShare above.
   * It always targets the 9:16 Story image regardless of the
   * Story/Post toggle above, and never opens the generic OS share
   * sheet without the image file attached — see brief §1/§3/§4. We
   * never claim Instagram specifically will appear; the OS decides
   * what shows up in its own share sheet.
   */
  async function handleInstagramStory() {
    const deviceType = getDeviceType(typeof navigator !== "undefined" ? navigator.userAgent : "");
    setInstagramDeviceType(deviceType);
    setInstagramState("generating");

    let blob: Blob;
    try {
      const response = await fetch(storyCardUrl);
      blob = await response.blob();
    } catch {
      setInstagramState("idle");
      return;
    }

    const file = new File([blob], "fouch-story.png", { type: "image/png" });
    const canShareFile =
      typeof navigator !== "undefined" &&
      "share" in navigator &&
      "canShare" in navigator &&
      navigator.canShare({ files: [file] });

    const shareMethod = resolveInstagramShareMethod(canShareFile, deviceType);
    const properties = buildInstagramStoryShareProperties({
      eventSlug,
      predictionPublicId: publicId,
      deviceType,
      shareMethod,
    });

    if (shareMethod === "native_share") {
      try {
        await navigator.share({ files: [file], url: publicUrl, title: "My Fouch prediction" });
        track("instagram_story_clicked", { ...properties });
        // Brief §6: Instagram Story always fires the literal
        // share_clicked signal (never events.share, which for the
        // "result" variant is result_card_shared) — this is a
        // dedicated, variant-independent share-intent signal.
        track("share_clicked", { event_slug: eventSlug, share_channel: "instagram_story" });
      } catch {
        // User cancelled the native share sheet — not an error.
      }
      setInstagramState("idle");
      return;
    }

    downloadBlob(blob, "fouch-story.png");
    track("instagram_story_clicked", { ...properties });
    track("share_clicked", { event_slug: eventSlug, share_channel: "instagram_story" });
    setInstagramState("ready");
  }

  return (
    <div>
      <div className="inline-flex rounded border border-border p-1 text-sm">
        <button
          type="button"
          onClick={() => setFormat("story")}
          className={`rounded px-3 py-1.5 transition-colors ${
            format === "story" ? "bg-surface-raised text-text-primary" : "text-text-muted"
          }`}
        >
          Story
        </button>
        <button
          type="button"
          onClick={() => setFormat("post")}
          className={`rounded px-3 py-1.5 transition-colors ${
            format === "post" ? "bg-surface-raised text-text-primary" : "text-text-muted"
          }`}
        >
          Post
        </button>
      </div>

      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={activeCardUrl}
        alt={variant === "result" ? "Your Fouch result card" : "Your Fouch prediction card"}
        className="mt-3 w-full max-w-xs rounded border border-border"
      />

      {instagramState === "ready" ? (
        <div className="mt-4 rounded border border-border-strong p-4">
          <p className="text-sm font-medium uppercase tracking-wide text-text-primary">
            Your Story is ready
          </p>
          <p className="mt-2 text-sm text-text-secondary">
            {instagramDeviceType === "mobile"
              ? "Image saved. Open Instagram → Story → choose the image."
              : "Open Instagram on your phone and add the saved image to your Story."}
          </p>
          <button
            type="button"
            onClick={handleCopyLink}
            className="mt-3 inline-flex items-center gap-2 rounded border border-border-strong px-4 py-2.5 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            {copied ? <Check className="h-4 w-4" aria-hidden /> : <Link2 className="h-4 w-4" aria-hidden />}
            {copied ? "Copied" : "Copy prediction link"}
          </button>
        </div>
      ) : (
        <div className="mt-4 flex flex-wrap gap-2">
          <button
            type="button"
            onClick={handleInstagramStory}
            disabled={instagramState === "generating"}
            className="inline-flex items-center gap-2 rounded bg-accent px-5 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60"
          >
            <Camera className="h-4 w-4" aria-hidden />
            {instagramState === "generating" ? "Preparing…" : "Instagram Story"}
          </button>

          {canNativeShare ? (
            <button
              type="button"
              onClick={handleShare}
              className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
            >
              <Share2 className="h-4 w-4" aria-hidden />
              Share
            </button>
          ) : null}

          <a
            href={activeCardUrl}
            download={`fouch-${variant}-${format}.png`}
            onClick={handleDownload}
            className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            <Download className="h-4 w-4" aria-hidden />
            Save image
          </a>

          <button
            type="button"
            onClick={handleCopyLink}
            className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            {copied ? <Check className="h-4 w-4" aria-hidden /> : <Link2 className="h-4 w-4" aria-hidden />}
            {copied ? "Copied" : "Copy link"}
          </button>
        </div>
      )}
    </div>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\ShareActions.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\ShareActions.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\ShareActions.tsx"
}

try {
    $path = "src\components\prediction\PublicPredictionView.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { Pencil } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { siteUrl } from "@/lib/site";
import { formatEventLocalLockTime } from "@/lib/event-time-display";
import type { Participant } from "@/types/participant";
import { ShareActions } from "./ShareActions";

export function PublicPredictionView({
  eventSlug,
  publicId,
  rankedParticipants,
  hasResult = false,
  canEdit = false,
  showLockedNotice = false,
  predictionLockAt = null,
  predictionTimezone = null,
  fouchScore,
  youVsTheWorld,
  yourCrowdChanged,
}: {
  eventSlug: string;
  publicId: string;
  rankedParticipants: Participant[];
  /** Sprint 4.1: whether an official/demo result exists for this
   * prediction's event. Drives share-CTA hierarchy only — the original
   * Prediction Card share section becomes visually secondary once a
   * Result Card exists to share instead (brief §7-8). Does not affect
   * scoring or any calculation. */
  hasResult?: boolean;
  /** FOUCH 0.3A: true only for a verified prediction (auth_user_id
   * set) while the event is still open per Supabase
   * events.prediction_lock_at. A legacy anonymous prediction never
   * gets this — there is no verified identity to authorize an edit
   * against, and this sprint adds no way to claim one. */
  canEdit?: boolean;
  /** FOUCH 0.3A: true for a verified prediction whose event has
   * passed prediction_lock_at — shows "YOUR CALL IS LOCKED" instead
   * of an edit affordance. Never shown for legacy predictions, which
   * never offered editing in the first place. */
  showLockedNotice?: boolean;
  /** ISO datetime, only used for display ("until {date}"). */
  predictionLockAt?: string | null;
  /** FOUCH 0.3A.1 — IANA timezone identifier for the event (e.g.
   * "America/Puerto_Rico"), used ONLY to render predictionLockAt
   * unambiguously in event-local time (see event-time-display.ts).
   * Null falls back to an explicit UTC-labeled rendering — never the
   * viewer's browser timezone. */
  predictionTimezone?: string | null;
  /** FOUCH Score section (Sprint 4) — null/absent renders nothing, which
   * is exactly the pre-result experience. Server Component, passed down
   * for the same reason as youVsTheWorld below. */
  fouchScore?: ReactNode;
  /** The You vs The World section — a Server Component rendered by the
   * page and passed down, since it needs server-side data fetching
   * that a Client Component can't do directly. */
  youVsTheWorld: ReactNode;
  /** Experiment 01 ("Your Crowd Changed") — null/absent renders
   * nothing, same pattern as the two slots above. */
  yourCrowdChanged?: ReactNode;
}) {
  const searchParams = useSearchParams();
  const isNew = searchParams.get("new") === "1";
  const isEdited = searchParams.get("edited") === "1";
  const showSavedBanner = isNew || isEdited;

  useEffect(() => {
    track("public_prediction_viewed", { event_slug: eventSlug, is_new: isNew });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (isNew) {
      track("prediction_card_generated", { event_slug: eventSlug });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const publicUrl = `${siteUrl}/p/${publicId}`;

  const originalPredictionShare = (
    <div id="share" className="mt-10 scroll-mt-20 border-t border-border pt-8">
      <p
        className={
          hasResult
            ? "text-sm text-text-muted"
            : "font-display text-lg text-text-primary"
        }
      >
        {hasResult ? "Your original prediction" : "Share your call"}
      </p>
      <div className="mt-3">
        <ShareActions
          eventSlug={eventSlug}
          publicId={publicId}
          publicUrl={publicUrl}
          storyCardUrl={`/p/${publicId}/card/story`}
          postCardUrl={`/p/${publicId}/card/post`}
        />
      </div>
    </div>
  );

  return (
    <div>
      {showSavedBanner ? (
        <div className="mt-4">
          <p className="font-display text-lg text-accent-strong">YOUR CALL IS IN</p>
          {predictionLockAt ? (
            <p className="mt-1 text-sm text-text-secondary">
              You can update your picks until {formatEventLocalLockTime(predictionLockAt, predictionTimezone)}.
            </p>
          ) : null}
        </div>
      ) : null}

      <ol className="mt-6 space-y-1.5">
        {rankedParticipants.map((participant, index) => (
          <li
            key={participant.id}
            className="flex items-center gap-3 rounded border border-border bg-surface px-4 py-3"
          >
            <span className="font-display w-7 shrink-0 text-base text-accent-strong">
              {String(index + 1).padStart(2, "0")}
            </span>
            <CountryFlag countryCode={participant.countryCode} className="text-xl" />
            <span className="truncate text-sm text-text-primary">
              {participant.displayName} <span className="text-text-muted">· {participant.countryName}</span>
            </span>
          </li>
        ))}
      </ol>

      {canEdit ? (
        <div className="mt-4">
          <Link
            href={`/p/${publicId}/edit`}
            className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-2.5 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            <Pencil className="h-4 w-4" aria-hidden />
            Edit my Top 10
          </Link>
          {predictionLockAt ? (
            <p className="mt-2 text-xs text-text-muted">
              You can update your picks until {formatEventLocalLockTime(predictionLockAt, predictionTimezone)}.
            </p>
          ) : null}
        </div>
      ) : showLockedNotice ? (
        <p className="mt-4 text-sm font-medium uppercase tracking-wide text-text-muted">
          YOUR CALL IS LOCKED
        </p>
      ) : null}

      {fouchScore}

      {youVsTheWorld}

      {yourCrowdChanged}

      {/* Pre-result: original prediction sharing stays primary and sits
          right before the "Make your Top 10" CTA, unchanged from Sprint 2/3.
          Post-result: it becomes a secondary, de-emphasized block, per the
          hierarchy in Sprint 4.1's brief (Result Card is the stronger
          social object once scoring exists). */}
      {!hasResult ? originalPredictionShare : null}

      <Link
        href={`/predict/${eventSlug}?from=${publicId}`}
        onClick={() => track("public_prediction_cta_clicked", { event_slug: eventSlug })}
        className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        Make your Top 10
      </Link>

      {hasResult ? originalPredictionShare : null}
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\PublicPredictionView.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\PublicPredictionView.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\PublicPredictionView.tsx"
}

try {
    $path = "src\components\scoring\FouchScore.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { getEntryNoun } from "@/lib/events";
import { resolveParticipantsByIds } from "@/lib/participants";
import { getPredictionScore } from "@/lib/scoring-service";
import { getOfficialResult } from "@/lib/results-db";
import { MIN_PERCENTILE_SAMPLE } from "@/lib/scoring";
import { siteUrl } from "@/lib/site";
import { CountryFlag } from "@/components/CountryFlag";
import type { PredictionRecord } from "@/lib/predictions-db";
import type { FouchEvent } from "@/types/event";
import type { ScoreBand } from "@/types/scoring";
import { FouchScoreTracker } from "./FouchScoreTracker";
import { ShareActions } from "@/components/prediction/ShareActions";
import { TrackedLink } from "@/components/TrackedLink";

const BAND_LABEL: Record<ScoreBand, string> = {
  MISSED_IT: "Missed it",
  FAIR: "Fair call",
  GOOD: "Good call",
  EXCELLENT: "Excellent call",
  ELITE: "Elite call",
};

/** "8.333..." -> "8.3", "25.0" -> "25" â€” one decimal, no trailing ".0". */
function formatPoints(value: number): string {
  const rounded = Math.round(value * 10) / 10;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}

/**
 * Renders nothing (returns null) when there's no official result yet â€”
 * the pre-result experience is unchanged, never a fabricated score.
 * Server Component: fetches + scores server-side, only the final
 * numbers reach the client (via the tracker's props, not raw data).
 *
 * Sprint 4.1: UI clarity only. Every number below comes straight from
 * the existing score engine's ScoreBreakdown â€” nothing here
 * recalculates or duplicates scoring logic.
 */
export async function FouchScore({
  prediction,
  event,
  publicId,
}: {
  prediction: PredictionRecord;
  event: FouchEvent;
  publicId: string;
}) {
  const result = await getPredictionScore(
    prediction.id,
    prediction.rankedParticipantIds,
    event.slug,
    prediction.dataStatus,
  );
  if (!result) return null;

  // Re-reads the same official-result row already used inside
  // getPredictionScore, purely to display who the actual winner was â€”
  // no scoring logic is duplicated, only a read.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);

  // FOUCH 0.3B: resolves regardless of current participant status â€”
  // both the user's own historical winner pick and the official
  // result's winner id must still render even if that country's
  // delegate has since become WITHDRAWN/REPLACED.
  const idsToResolve = new Set<string>();
  if (prediction.rankedParticipantIds[0]) idsToResolve.add(prediction.rankedParticipantIds[0]);
  if (official) idsToResolve.add(official.winner);

  const participantsById = await resolveParticipantsByIds(event.slug, Array.from(idsToResolve));
  const userWinnerPick = prediction.rankedParticipantIds[0]
    ? participantsById.get(prediction.rankedParticipantIds[0])
    : undefined;
  const actualWinner = official ? participantsById.get(official.winner) : undefined;
  const pluralNoun = getEntryNoun(event, true);
  const { breakdown, percentile } = result;
  const { winner, podium, top5, top10, ranking } = breakdown.components;

  return (
    <section className="mt-12 border-t border-border pt-10">
      <FouchScoreTracker
        eventSlug={event.slug}
        scoreBand={breakdown.band}
        percentileAvailable={percentile.percentile !== null}
        dataStatus={prediction.dataStatus}
      />

      <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">Fouch score</p>

      {prediction.dataStatus === "demo" ? (
        <p className="mt-2 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo result — not an official outcome
        </p>
      ) : null}

      <p className="mt-3 font-display text-7xl text-accent-strong">{breakdown.displayScore}</p>
      <p className="mt-1 font-display text-2xl uppercase tracking-tight text-text-primary">
        {BAND_LABEL[breakdown.band]}
      </p>

      {percentile.percentile !== null ? (
        <p className="mt-2 text-sm text-text-secondary">
          You beat {Math.round(percentile.percentile)}% of {pluralNoun === "picks" ? "predictions" : pluralNoun} for
          this event, based on {percentile.population} other predictions.
        </p>
      ) : (
        <p className="mt-2 text-xs text-text-muted">
          World ranking unlocks at {MIN_PERCENTILE_SAMPLE} predictions.
        </p>
      )}

      <dl className="mt-6 space-y-3 text-sm">
        <div className="border-b border-border pb-3">
          <dt className="flex items-center justify-between">
            <span className="text-text-secondary">Winner</span>
            <span className="text-text-muted">{formatPoints(winner.earned)} / {winner.max}</span>
          </dt>
          <dd className="mt-2">
            {winner.hit ? (
              <span className="inline-flex items-center gap-1.5 text-accent-strong">
                ✓
                {userWinnerPick ? (
                  <>
                    <CountryFlag countryCode={userWinnerPick.countryCode} />
                    {userWinnerPick.displayName}
                    <span className="text-text-muted">· {userWinnerPick.countryName}</span>
                  </>
                ) : (
                  "Correct"
                )}
              </span>
            ) : (
              <div className="space-y-1 text-text-primary">
                <p className="flex items-center gap-1.5">
                  <span className="text-text-muted">✗ Missed — your pick:</span>
                  {userWinnerPick ? (
                    <>
                      <CountryFlag countryCode={userWinnerPick.countryCode} />
                      {userWinnerPick.displayName}
                      <span className="text-text-muted">· {userWinnerPick.countryName}</span>
                    </>
                  ) : (
                    "—"
                  )}
                </p>
                {actualWinner ? (
                  <p className="flex items-center gap-1.5 text-text-secondary">
                    <span className="text-text-muted">Actual:</span>
                    <CountryFlag countryCode={actualWinner.countryCode} />
                    {actualWinner.displayName}
                    <span className="text-text-muted">· {actualWinner.countryName}</span>
                  </p>
                ) : null}
              </div>
            )}
          </dd>
        </div>

        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Podium</dt>
          <dd className="text-text-primary">
            {podium.hits} of {podium.total} · {formatPoints(podium.earned)} / {podium.max}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Top 5</dt>
          <dd className="text-text-primary">
            {top5.hits} of {top5.total} · {formatPoints(top5.earned)} / {top5.max}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Top 10</dt>
          <dd className="text-text-primary">
            {top10.hits} of {top10.total} · {formatPoints(top10.earned)} / {top10.max}
          </dd>
        </div>
        <div>
          <div className="flex items-center justify-between">
            <dt className="text-text-secondary">Ranking</dt>
            <dd className="text-text-primary">
              {formatPoints(ranking.earned)} / {ranking.max}
            </dd>
          </div>
          <p className="mt-1 text-xs text-text-muted">How close your picks were to the official finish.</p>
        </div>
      </dl>

      <div className="mt-8">
        <TrackedLink
          href={`/events/${event.slug}/leaderboard?from=${publicId}`}
          event="leaderboard_from_score_clicked"
          eventProperties={{ event_slug: event.slug }}
          className="inline-flex items-center justify-center rounded border border-border-strong px-6 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          See where you finished
        </TrackedLink>
      </div>

      <div className="mt-8">
        <p className="font-display text-lg text-text-primary">Share your result</p>
        <div className="mt-3">
          <ShareActions
            variant="result"
            eventSlug={event.slug}
            publicId={publicId}
            publicUrl={`${siteUrl}/p/${publicId}`}
            storyCardUrl={`/p/${publicId}/result-card/story`}
            postCardUrl={`/p/${publicId}/result-card/post`}
          />
        </div>
      </div>
    </section>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\FouchScore.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\FouchScore.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\FouchScore.tsx"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 6 files written successfully." -ForegroundColor Green
}
