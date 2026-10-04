"use client";

import { useEffect, useState } from "react";
import { Share2, Download, Link2, Check, Camera } from "lucide-react";
import { track } from "@/lib/analytics";
import type { FouchAnalyticsEvent } from "@/lib/analytics";
import { useI18n } from "@/components/I18nProvider";
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
  const { dict } = useI18n();
  const st = dict.share;

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
      await navigator.share({ title: st.shareTitle, url: publicUrl });
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
        await navigator.share({ files: [file], url: publicUrl, title: st.shareTitle });
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
          {st.story}
        </button>
        <button
          type="button"
          onClick={() => setFormat("post")}
          className={`rounded px-3 py-1.5 transition-colors ${
            format === "post" ? "bg-surface-raised text-text-primary" : "text-text-muted"
          }`}
        >
          {st.post}
        </button>
      </div>

      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={activeCardUrl}
        alt={variant === "result" ? st.resultCardAlt : st.predictionCardAlt}
        className="mt-3 w-full max-w-xs rounded border border-border"
      />

      {instagramState === "ready" ? (
        <div className="mt-4 rounded border border-border-strong p-4">
          <p className="text-sm font-medium uppercase tracking-wide text-text-primary">
            {st.storyReady}
          </p>
          <p className="mt-2 text-sm text-text-secondary">
            {instagramDeviceType === "mobile"
              ? st.storyReadyMobile
              : st.storyReadyDesktop}
          </p>
          <button
            type="button"
            onClick={handleCopyLink}
            className="mt-3 inline-flex items-center gap-2 rounded border border-border-strong px-4 py-2.5 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            {copied ? <Check className="h-4 w-4" aria-hidden /> : <Link2 className="h-4 w-4" aria-hidden />}
            {copied ? st.copied : st.copyPredictionLink}
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
            {instagramState === "generating" ? st.preparing : st.instagramStory}
          </button>

          {canNativeShare ? (
            <button
              type="button"
              onClick={handleShare}
              className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
            >
              <Share2 className="h-4 w-4" aria-hidden />
              {st.share}
            </button>
          ) : null}

          <a
            href={activeCardUrl}
            download={`fouch-${variant}-${format}.png`}
            onClick={handleDownload}
            className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            <Download className="h-4 w-4" aria-hidden />
            {st.saveImage}
          </a>

          <button
            type="button"
            onClick={handleCopyLink}
            className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            {copied ? <Check className="h-4 w-4" aria-hidden /> : <Link2 className="h-4 w-4" aria-hidden />}
            {copied ? st.copied : st.copyLink}
          </button>
        </div>
      )}
    </div>
  );
}
