/**
 * FOUCH Home v1.1 Round 2 — the reusable "dark cinematic" atmosphere
 * for any event section, used whenever an event has no hero_asset
 * (true for every event today). Pure CSS layers — no photography, no
 * contestant/crown imagery, no external assets, no new dependency.
 *
 * `variant` only shifts WHERE the glow sits and its hue balance — it
 * is derived by the caller from something generic (e.g. a section's
 * position, 0 for the featured event, 1 for the next one), never from
 * a specific event's identity. The same two variants work for any
 * future FOUCH event without new code.
 */
export function CinematicBackdrop({ variant = 0 }: { variant?: 0 | 1 }) {
  const isAlt = variant === 1;

  return (
    <div aria-hidden className="pointer-events-none absolute inset-0 overflow-hidden bg-black">
      {/* Warm oxblood glow — the dominant light source, positioned
          opposite for each variant so two adjacent sections don't
          read as identical twins. */}
      <div
        className={
          "absolute h-[34rem] w-[34rem] rounded-full bg-accent/25 blur-[110px] " +
          (isAlt ? "-bottom-48 -left-40" : "-top-40 -right-32")
        }
      />
      {/* Cool secondary glow for depth/contrast against the warm one. */}
      <div
        className={
          "absolute h-[26rem] w-[26rem] rounded-full bg-slate-500/10 blur-[120px] " +
          (isAlt ? "-top-32 right-0" : "bottom-0 left-0")
        }
      />
      {/* Vignette — pulls focus to the center, gives the section edges
          depth instead of a flat black rectangle. */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent_35%,rgba(0,0,0,0.75)_100%)]" />
      {/* Very subtle grain, inline SVG noise — no image request, no
          new dependency. Kept faint (opacity ~4%) so it reads as
          texture, not visible static. */}
      <div
        className="absolute inset-0 opacity-[0.04] mix-blend-overlay"
        style={{
          backgroundImage:
            "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='120'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E\")",
        }}
      />
    </div>
  );
}
