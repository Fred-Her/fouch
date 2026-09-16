﻿"use client";

import { useState } from "react";
import { PREDICTOR_COUNTRIES } from "@/lib/countries";

export function SubmitPanel({
  requiredCount,
  submitting,
  errorMessage,
  onSubmit,
}: {
  requiredCount: number;
  submitting: boolean;
  errorMessage: string | null;
  onSubmit: (nickname: string, countryCode: string) => void;
}) {
  const [nickname, setNickname] = useState("");
  const [countryCode, setCountryCode] = useState("");

  return (
    <div className="mt-8 border-t border-border pt-6">
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="text-sm text-text-secondary">Nickname</span>
          <input
            type="text"
            value={nickname}
            onChange={(event) => setNickname(event.target.value)}
            maxLength={24}
            placeholder="Optional"
            className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
          />
        </label>

        <label className="block">
          <span className="text-sm text-text-secondary">Country</span>
          <select
            value={countryCode}
            onChange={(event) => setCountryCode(event.target.value)}
            className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary focus:border-accent"
          >
            <option value="">Optional</option>
            {PREDICTOR_COUNTRIES.map((country) => (
              <option key={country.code} value={country.code}>
                {country.name}
              </option>
            ))}
          </select>
        </label>
      </div>

      <p className="mt-2 text-xs text-text-muted">
        Optional — shown publicly with your prediction. You can update your picks until predictions
        close.
      </p>

      {errorMessage ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert">
          {errorMessage}
        </p>
      ) : null}

      <button
        type="button"
        disabled={submitting}
        onClick={() => onSubmit(nickname, countryCode)}
        className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
      >
        {submitting ? "Saving…" : `Save my Top ${requiredCount}`}
      </button>
    </div>
  );
}