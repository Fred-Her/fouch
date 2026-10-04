"use client";

import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { track } from "@/lib/analytics";
import { useI18n } from "@/components/I18nProvider";

export function ShareYourCallCta({ standsOut = false }: { standsOut?: boolean }) {
  const { dict } = useI18n();
  return (
    <div className="mt-2">
      <p className="font-display text-lg text-text-primary">
        {standsOut ? dict.community.shareStandsOut : dict.community.shareWrong}
      </p>
      <Link
        href="#share"
        onClick={() => track("community_share_clicked")}
        className="group mt-3 inline-flex items-center gap-2 rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        {dict.community.shareCta}
        <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
      </Link>
    </div>
  );
}