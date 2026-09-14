"use client";

import { useState } from "react";

export function EmailStep({
  submitting,
  errorMessage,
  onSendCode,
}: {
  submitting: boolean;
  errorMessage: string | null;
  onSendCode: (email: string) => void;
}) {
  const [email, setEmail] = useState("");

  return (
    <div className="mt-8 border-t border-border pt-6">
      <p className="font-display text-xl text-text-primary">Enter your email to lock your prediction.</p>
      <p className="mt-1 text-sm text-text-secondary">We&apos;ll send you a verification code — no password needed.</p>

      <label className="mt-4 block">
        <span className="text-sm text-text-secondary">Email</span>
        <input
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          placeholder="you@example.com"
          autoComplete="email"
          className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
        />
      </label>

      {errorMessage ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert">
          {errorMessage}
        </p>
      ) : null}

      <button
        type="button"
        disabled={submitting || email.trim().length === 0}
        onClick={() => onSendCode(email)}
        className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
      >
        {submitting ? "Sending…" : "Send code"}
      </button>

      <p className="mt-3 text-xs text-text-muted">
        FOUCH is an independent fan prediction game — your email is only used to verify your call,
        never shown publicly.
      </p>
    </div>
  );
}