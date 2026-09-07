"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { track } from "@/lib/analytics";
import { loadPrediction, savePrediction } from "@/lib/prediction-storage";
import type { Participant } from "@/types/participant";
import { TopTenList } from "./TopTenList";
import { ParticipantBrowser } from "./ParticipantBrowser";

export function PredictionBuilder({
  eventSlug,
  participants,
  requiredCount,
}: {
  eventSlug: string;
  participants: Participant[];
  requiredCount: number;
}) {
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [hydrated, setHydrated] = useState(false);
  const hasFiredCompletion = useRef(false);

  const participantsById = new Map(participants.map((participant) => [participant.id, participant]));

  // Restore any in-progress prediction once, on mount, then mark
  // "hydrated" so we don't overwrite it with an empty save before the
  // restore runs.
  useEffect(() => {
    const validIds = new Set(participants.map((participant) => participant.id));
    const restored = loadPrediction(eventSlug, validIds);
    setSelectedIds(restored.slice(0, requiredCount));
    setHydrated(true);
    track("start_prediction", { event_slug: eventSlug });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    savePrediction(eventSlug, selectedIds);

    if (selectedIds.length >= requiredCount && !hasFiredCompletion.current) {
      hasFiredCompletion.current = true;
      track("prediction_completed", { event_slug: eventSlug, selected_count: selectedIds.length });
    }
    if (selectedIds.length < requiredCount) {
      hasFiredCompletion.current = false;
    }
  }, [selectedIds, eventSlug, requiredCount, hydrated]);

  function handleToggle(id: string) {
    setSelectedIds((current) => {
      if (current.includes(id)) {
        track("participant_removed", { event_slug: eventSlug, selected_count: current.length - 1 });
        return current.filter((selectedId) => selectedId !== id);
      }
      if (current.length >= requiredCount) return current;

      track("participant_selected", { event_slug: eventSlug, position: current.length + 1 });
      return [...current, id];
    });
  }

  function handleRemove(id: string) {
    setSelectedIds((current) => {
      track("participant_removed", { event_slug: eventSlug, selected_count: current.length - 1 });
      return current.filter((selectedId) => selectedId !== id);
    });
  }

  function swap(array: string[], i: number, j: number): string[] {
    const next = [...array];
    const a = next[i];
    const b = next[j];
    if (a === undefined || b === undefined) return array;
    next[i] = b;
    next[j] = a;
    return next;
  }

  function handleMoveUp(index: number) {
    if (index === 0) return;
    setSelectedIds((current) => {
      track("prediction_reordered", { event_slug: eventSlug });
      return swap(current, index - 1, index);
    });
  }

  function handleMoveDown(index: number) {
    setSelectedIds((current) => {
      if (index === current.length - 1) return current;
      track("prediction_reordered", { event_slug: eventSlug });
      return swap(current, index, index + 1);
    });
  }

  const rankedParticipants = selectedIds
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  const isComplete = selectedIds.length >= requiredCount;

  return (
    <div>
      {/* Compact sticky progress — one line, not a large banner. */}
      <div className="sticky top-0 z-10 w-full border-b border-border bg-background/95 backdrop-blur">
        <div className="mx-auto flex max-w-content items-center justify-between px-6 py-3">
          <span className="text-xs font-medium uppercase tracking-[0.15em] text-text-secondary">
            {selectedIds.length} / {requiredCount} selected
          </span>
          <div className="h-1 w-24 overflow-hidden rounded-full bg-surface-raised">
            <div
              className="h-full bg-accent transition-[width]"
              style={{ width: `${(selectedIds.length / requiredCount) * 100}%` }}
            />
          </div>
        </div>
      </div>

      <div className="mx-auto max-w-content px-6 py-8 lg:grid lg:grid-cols-[380px_1fr] lg:gap-10">
        <section aria-label="Your Top 10" className="lg:sticky lg:top-20 lg:self-start">
          <h2 className="font-display text-lg text-text-primary">Your Top {requiredCount}</h2>
          <div className="mt-3">
            <TopTenList
              rankedParticipants={rankedParticipants}
              requiredCount={requiredCount}
              onRemove={handleRemove}
              onMoveUp={handleMoveUp}
              onMoveDown={handleMoveDown}
            />
          </div>

          {isComplete ? (
            <div className="mt-6 rounded border border-accent/40 bg-accent/10 p-4">
              <p className="font-display text-base text-text-primary">Your Top {requiredCount} is ready.</p>
              <Link
                href={`/predict/${eventSlug}/review`}
                className="group mt-3 inline-flex items-center gap-2 rounded bg-accent px-5 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
              >
                Review my prediction
                <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
              </Link>
            </div>
          ) : null}
        </section>

        <section aria-label="All contestants" className="mt-10 lg:mt-0">
          <h2 className="font-display text-lg text-text-primary">All contestants</h2>
          <div className="mt-3">
            <ParticipantBrowser
              participants={participants}
              selectedIds={new Set(selectedIds)}
              atMax={isComplete}
              onToggle={handleToggle}
            />
          </div>
        </section>
      </div>
    </div>
  );
}