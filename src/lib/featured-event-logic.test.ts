import { describe, it, expect } from "vitest";
import { pickFeaturedEventSlug } from "./featured-event-logic";

describe("pickFeaturedEventSlug — FOUCH 0.3B Event Resolution Fix", () => {
  it("returns null when no event is featured", () => {
    expect(
      pickFeaturedEventSlug([
        { slug: "miss-universe-2026", isFeatured: false },
        { slug: "miss-grand-international-2026", isFeatured: false },
      ]),
    ).toBeNull();
  });

  it("returns the one featured event's slug", () => {
    expect(
      pickFeaturedEventSlug([
        { slug: "miss-universe-2026", isFeatured: false },
        { slug: "miss-grand-international-2026", isFeatured: true },
      ]),
    ).toBe("miss-grand-international-2026");
  });

  it("Miss Grand featured, Miss Universe upcoming secondary — the exact target state for this fix", () => {
    const slug = pickFeaturedEventSlug([
      { slug: "miss-grand-international-2026", isFeatured: true },
      { slug: "miss-universe-2026", isFeatured: false },
    ]);
    expect(slug).toBe("miss-grand-international-2026");
  });

  it("CRITICAL: if more than one event is ever marked featured (a data-entry mistake, not a supported state), picks deterministically — the alphabetically first slug — never an arbitrary/unstable choice", () => {
    const first = pickFeaturedEventSlug([
      { slug: "miss-universe-2026", isFeatured: true },
      { slug: "miss-grand-international-2026", isFeatured: true },
    ]);
    const second = pickFeaturedEventSlug([
      { slug: "miss-grand-international-2026", isFeatured: true },
      { slug: "miss-universe-2026", isFeatured: true },
    ]);
    // Same input set, different array order — must resolve to the
    // SAME slug both times (order-independent), and it must be the
    // alphabetically-first one.
    expect(first).toBe("miss-grand-international-2026");
    expect(second).toBe("miss-grand-international-2026");
  });

  it("empty candidate list returns null, never throws", () => {
    expect(() => pickFeaturedEventSlug([])).not.toThrow();
    expect(pickFeaturedEventSlug([])).toBeNull();
  });
});
