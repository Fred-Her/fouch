export interface Dictionary {
  meta: {
    title: string;
    description: string;
  };
  nav: {
    wordmark: string;
  };
  hero: {
    headline: string;
    subhead: string;
    cta: string;
  };
  featuredEvent: {
    eyebrowUpcoming: string;
    prompt: string;
    cta: string;
  };
  howItWorks: {
    title: string;
    steps: { title: string; body: string }[];
  };
  eventPage: {
    back: string;
    comingSoon: string;
  };
  footer: {
    tagline: string;
  };
}
