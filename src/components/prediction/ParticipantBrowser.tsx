"use client";

import { useMemo, useState } from "react";
import { Search } from "lucide-react";
import { flagEmoji } from "@/lib/flags";
import type { Participant } from "@/types/participant";

export function ParticipantBrowser({
  participants,
  selectedIds,
  atMax,
  onToggle,
}: {
  participants: Participant[];
  selectedIds: Set<string>;
  atMax: boolean;
  onToggle: (id: string) => void;
}) {
  const [query, setQuery] = useState("");

  const filtered = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    if (!normalized) return participants;

    return participants.filter(
      (participant) =>
        participant.displayName.toLowerCase().includes(normalized) ||
        participant.countryName.toLowerCase().includes(normalized),
    );
  }, [participants, query]);

  return (
    <div>
      <div className="relative">
        <Search
          className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted"
          aria-hidden
        />
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search countries..."
          aria-label="Search countries"
          className="w-full rounded border border-border bg-surface py-2.5 pl-10 pr-3 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
        />
      </div>

      {filtered.length === 0 ? (
        <p className="mt-6 text-sm text-text-muted">No countries match &ldquo;{query}&rdquo;.</p>
      ) : (
        <ul className="mt-4 divide-y divide-border">
          {filtered.map((participant) => {
            const selected = selectedIds.has(participant.id);
            const disabled = atMax && !selected;

            return (
              <li key={participant.id}>
                <button
                  type="button"
                  onClick={() => onToggle(participant.id)}
                  disabled={disabled}
                  aria-pressed={selected}
                  className={`flex w-full items-center gap-3 py-3 text-left transition-colors disabled:cursor-not-allowed disabled:opacity-40 ${
                    selected ? "text-accent-strong" : "text-text-primary hover:text-accent-strong"
                  }`}
                >
                  <span aria-hidden className="text-lg">
                    {flagEmoji(participant.countryCode)}
                  </span>
                  <span className="flex-1 text-sm">{participant.displayName}</span>
                  {selected ? (
                    <span className="text-xs font-medium uppercase tracking-wide">Selected</span>
                  ) : null}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}