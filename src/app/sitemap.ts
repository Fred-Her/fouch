import type { MetadataRoute } from "next";
import { getFeaturedEvent } from "@/lib/events";
import { siteUrl } from "@/lib/site";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const entries: MetadataRoute.Sitemap = [
    {
      url: siteUrl,
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 1,
      // i18n v1: hreflang for the two locales of the home page. URLs
      // stay on the canonical joinfouch.com origin (siteUrl).
      alternates: { languages: { en: siteUrl, es: `${siteUrl}/es` } },
    },
  ];

  const featuredEvent = await getFeaturedEvent();
  if (featuredEvent) {
    entries.push({
      url: `${siteUrl}/predict/${featuredEvent.slug}`,
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 0.8,
    });
  }

  return entries;
}