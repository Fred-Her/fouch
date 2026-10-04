// STALE Sprint-0 stub — NOT wired into anything and NOT part of i18n v1
// (English + Spanish only; Portuguese is explicitly out of scope for
// now). Its shape predates the current Dictionary, so it is excluded
// from the typed Dictionary rather than silently "fixed" with unreviewed
// Portuguese copy. Rebuild it against src/content/en.ts when
// Portuguese is actually scoped.

// Prepared for future localization. Not yet wired into routing in Sprint 0 —
// English is the only live locale.
export const pt = {
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