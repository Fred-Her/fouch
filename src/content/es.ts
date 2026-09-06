import type { Dictionary } from "./types";

// Prepared for future localization. Not yet wired into routing in Sprint 0 —
// English is the only live locale. Kept in sync with en.ts's shape so a
// future locale switch is a routing change, not a content rewrite.
export const es: Dictionary = {
  meta: {
    title: "Fouch — Haz tu predicción",
    description:
      "Predice los momentos más comentados del entretenimiento y compara tus picks con el mundo.",
  },
  nav: {
    wordmark: "Fouch",
  },
  hero: {
    headline: "Haz tu predicción.",
    subhead: "Predice los momentos de los que todos hablarán.",
    cta: "Arma tu Top 10",
  },
  featuredEvent: {
    eyebrowUpcoming: "Próximamente",
    prompt: "¿Quién entra en tu Top 10?",
    cta: "Arma tu Top 10",
  },
  howItWorks: {
    title: "Cómo funciona",
    steps: [
      { title: "Predice", body: "Arma tu ranking." },
      { title: "Compite", body: "Compara tus picks con los demás." },
      { title: "Compruébalo", body: "Recibe tu puntaje cuando salgan los resultados." },
    ],
  },
  eventPage: {
    back: "Volver a Fouch",
    comingSoon: "El constructor de predicciones de este evento abre pronto.",
  },
  footer: {
    tagline: "Predicciones de entretenimiento.",
  },
};
