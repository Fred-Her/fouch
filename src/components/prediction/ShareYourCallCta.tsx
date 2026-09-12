"use client";

import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { track } from "@/lib/analytics";

export function ShareYourCallCta({ standsOut = false }: { standsOut?: boolean }) {
  return (
    <div className="mt-2">
      <p className="font-display text-lg text-text-primary">
        {standsOut ? "Your call stands out." : "Think the world is wrong?"}
      </p>
      <Link
        href="#share"
        onClick={() => track("community_share_clicked")}
        className="group mt-3 inline-flex items-center gap-2 rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        Share your call
        <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
      </Link>
    </div>
  );
}