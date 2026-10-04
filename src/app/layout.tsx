import type { Metadata } from "next";
import { siteUrl } from "@/lib/site";
import { getI18n } from "@/lib/i18n-server";
import { localizePath } from "@/lib/locale";
import { I18nProvider } from "@/components/I18nProvider";
import "./globals.css";

/**
 * i18n v1: metadata is generated per request locale. Canonical strategy
 * is unchanged from before i18n — every page canonicalizes to the
 * site root on https://joinfouch.com (siteUrl) — now one canonical per
 * locale ("/" for English, "/es" for Spanish), with hreflang tying the
 * two together plus x-default (English). The canonical DOMAIN is
 * unchanged and never falls back to the legacy Vercel domain.
 */
export async function generateMetadata(): Promise<Metadata> {
  const { locale, dict } = await getI18n();
  const canonical = localizePath("/", locale);

  return {
    metadataBase: new URL(siteUrl),
    alternates: {
      canonical,
      languages: {
        en: localizePath("/", "en"),
        es: localizePath("/", "es"),
        "x-default": localizePath("/", "en"),
      },
    },
    title: {
      default: dict.meta.title,
      template: "%s · Fouch",
    },
    description: dict.meta.description,
    openGraph: {
      title: dict.meta.title,
      description: dict.meta.description,
      url: `${siteUrl}${canonical === "/" ? "" : canonical}`,
      siteName: "Fouch",
      locale: locale === "es" ? "es_LA" : "en_US",
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      title: dict.meta.title,
      description: dict.meta.description,
    },
  };
}

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const { locale, dict } = await getI18n();

  return (
    <html lang={locale}>
      <body>
        <I18nProvider locale={locale} dict={dict}>
          {children}
        </I18nProvider>
      </body>
    </html>
  );
}
