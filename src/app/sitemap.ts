import type { MetadataRoute } from "next";
import { getFeaturedEvent } from "@/lib/events";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://fouch.app";

export default function sitemap(): MetadataRoute.Sitemap {
  const entries: MetadataRoute.Sitemap = [
    {
      url: siteUrl,
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 1,
    },
  ];

  const featuredEvent = getFeaturedEvent();
  if (featuredEvent) {
    entries.push({
      url: `${siteUrl}/events/${featuredEvent.slug}`,
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 0.8,
    });
  }

  return entries;
}
