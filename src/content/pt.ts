import type { Dictionary } from "./types";

// Prepared for future localization. Not yet wired into routing in Sprint 0 —
// English is the only live locale.
export const pt: Dictionary = {
  meta: {
    title: "Fouch — Faça sua previsão",
    description:
      "Preveja os maiores momentos do entretenimento e veja como suas escolhas se comparam com o mundo.",
  },
  nav: {
    wordmark: "Fouch",
  },
  hero: {
    headline: "Faça sua previsão.",
    subhead: "Preveja os momentos dos quais todos vão falar.",
    cta: "Monte seu Top 10",
  },
  featuredEvent: {
    eyebrowUpcoming: "Em breve",
    prompt: "Quem entra no seu Top 10?",
    cta: "Monte seu Top 10",
  },
  howItWorks: {
    title: "Como funciona",
    steps: [
      { title: "Preveja", body: "Monte seu ranking." },
      { title: "Compita", body: "Veja como suas escolhas se comparam." },
      { title: "Comprove", body: "Receba sua pontuação quando sair o resultado." },
    ],
  },
  eventPage: {
    back: "Voltar ao Fouch",
    comingSoon: "O criador de previsões deste evento abre em breve.",
  },
  footer: {
    tagline: "Previsões de entretenimento.",
  },
};
