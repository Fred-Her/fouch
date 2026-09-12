"use client";

import { useEffect, useState } from "react";
import { Share2, Download, Link2, Check } from "lucide-react";
import { track } from "@/lib/analytics";
import type { FouchAnalyticsEvent } from "@/lib/analytics";

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

export function ShareActions({
  eventSlug,
  publicUrl,
  storyCardUrl,
  postCardUrl,
  variant = "prediction",
}: {
  eventSlug: string;
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

      <div className="mt-4 flex flex-wrap gap-2">
        {canNativeShare ? (
          <button
            type="button"
            onClick={handleShare}
            className="inline-flex items-center gap-2 rounded bg-accent px-5 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
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
    </div>
  );
}