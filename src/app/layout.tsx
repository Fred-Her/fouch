import type { Metadata } from "next";
import { en } from "@/content/en";
import "./globals.css";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://fouch.app";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: en.meta.title,
    template: "%s · Fouch",
  },
  description: en.meta.description,
  openGraph: {
    title: en.meta.title,
    description: en.meta.description,
    url: siteUrl,
    siteName: "Fouch",
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: en.meta.title,
    description: en.meta.description,
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
