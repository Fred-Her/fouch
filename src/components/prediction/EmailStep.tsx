"use client";

import { useState } from "react";
import { getEmailStepHeading, type EmailStepMode } from "@/lib/email-step-copy";
import { useI18n } from "@/components/I18nProvider";
import { translateServerError } from "@/lib/server-error-i18n";

export function EmailStep({
  mode,
  submitting,
  errorMessage,
  onSendCode,
}: {
  /** FOUCH 0.3A.1 — "create" for a first-time submission, "edit" for
   * an existing verified prediction. Drives the heading copy only;
   * OTP behavior is identical either way (brief §8-9). */
  mode: EmailStepMode;
  submitting: boolean;
  errorMessage: string | null;
  onSendCode: (email: string) => void;
}) {
  const [email, setEmail] = useState("");
  const { locale, dict } = useI18n();
  const t = dict.auth;

  return (
    <div className="mt-8 border-t border-border pt-6">
      <p className="font-display text-xl text-text-primary">{getEmailStepHeading(mode, { create: t.headingCreate, edit: t.headingEdit })}</p>
      <p className="mt-1 text-sm text-text-secondary">{t.subheading}</p>

      <label className="mt-4 block">
        <span className="text-sm text-text-secondary">{t.emailLabel}</span>
        <input
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          placeholder={t.emailPlaceholder}
          autoComplete="email"
          className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
        />
      </label>

      {errorMessage ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert">
          {translateServerError(errorMessage, locale)}
        </p>
      ) : null}

      <button
        type="button"
        disabled={submitting || email.trim().length === 0}
        onClick={() => onSendCode(email)}
        className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
      >
        {submitting ? t.sending : t.sendCode}
      </button>

      <p className="mt-3 text-xs text-text-muted">
        {t.privacyNote}
      </p>
    </div>
  );
}