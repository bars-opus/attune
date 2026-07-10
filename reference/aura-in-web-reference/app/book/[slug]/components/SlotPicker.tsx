// aura-in-web/app/book/[slug]/components/SlotPicker.tsx
//
// Step 3 of the booking flow. Renders a horizontal day-strip + a 3-column
// time-slot grid. Slots are pre-filtered by worker selection (get-slots
// emits one entry per worker that can take the slot; if the visitor picks
// a specific worker we narrow to that worker's entries).
"use client";

import { useMemo, useState } from "react";
import type { SlotEntry } from "@/lib/types";
import { formatTimeSlot, formatDateHeader } from "@/lib/format";

export function SlotPicker({
  slots,
  workerId,
  selectedSlot,
  onSelect,
  loading,
}: {
  slots: SlotEntry[];
  workerId: string | null;
  selectedSlot: SlotEntry | null;
  onSelect: (slot: SlotEntry) => void;
  loading: boolean;
}) {
  // When the visitor has selected a specific worker, drop slots assigned
  // to other workers. workerId=null means "any" — keep everything.
  const filtered = useMemo(() => {
    if (!workerId) return slots;
    return slots.filter((s) => s.workerId === workerId || s.workerId === null);
  }, [slots, workerId]);

  // Group by local-date (toDateString gives "Mon May 27 2026" — stable
  // across same-day slots, sortable by inserting in chronological order).
  const byDate = useMemo(() => {
    const groups: Record<string, SlotEntry[]> = {};
    for (const s of filtered) {
      const date = new Date(s.startTime).toDateString();
      (groups[date] ??= []).push(s);
    }
    // Each day's slots are already in RPC order (chronological). Deduplicate
    // identical startTimes (multiple workerIds can produce the same slot;
    // the picker only shows the time, not the worker).
    for (const k of Object.keys(groups)) {
      const seen = new Set<string>();
      groups[k] = groups[k].filter((s) => {
        if (seen.has(s.startTime)) return false;
        seen.add(s.startTime);
        return true;
      });
    }
    return Object.entries(groups);
  }, [filtered]);

  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const effectiveDate = selectedDate ?? byDate[0]?.[0] ?? null;
  const slotsForDate =
    byDate.find(([d]) => d === effectiveDate)?.[1] ?? [];

  if (loading) {
    return (
      <section className="px-4 pt-3">
        <h2 className="text-xs uppercase tracking-wide text-slate-500 mb-2 font-medium">
          3. When
        </h2>
        <div className="text-center text-sm text-slate-400 py-6">
          Loading slots…
        </div>
      </section>
    );
  }

  if (byDate.length === 0) {
    return (
      <section className="px-4 pt-3">
        <h2 className="text-xs uppercase tracking-wide text-slate-500 mb-2 font-medium">
          3. When
        </h2>
        <div className="text-center text-sm text-slate-400 py-6">
          No available slots in the next 7 days.
        </div>
      </section>
    );
  }

  return (
    <section className="px-4 pt-3">
      <h2 className="text-xs uppercase tracking-wide text-slate-500 mb-2 font-medium">
        3. When
      </h2>

      <div className="flex gap-1 overflow-x-auto -mx-4 px-4 pb-2 mb-2">
        {byDate.map(([date]) => {
          const dh = formatDateHeader(date);
          // formatDateHeader returns "Mon, 26 May" — first token is the
          // weekday label we want above the day number.
          const weekday = dh.split(",")[0];
          const day = new Date(date).getDate();
          const selected = effectiveDate === date;
          return (
            <button
              key={date}
              type="button"
              onClick={() => setSelectedDate(date)}
              className={`flex-shrink-0 min-w-[3rem] px-2 py-1.5 rounded text-center border ${
                selected
                  ? "bg-slate-900 text-white border-slate-900"
                  : "bg-white text-slate-700 border-slate-200"
              }`}
            >
              <div className="text-[10px] opacity-70">{weekday}</div>
              <div className="font-semibold text-sm">{day}</div>
            </button>
          );
        })}
      </div>

      <div className="grid grid-cols-3 gap-1">
        {slotsForDate.map((slot) => {
          const selected = selectedSlot?.startTime === slot.startTime;
          return (
            <button
              key={slot.startTime}
              type="button"
              onClick={() => onSelect(slot)}
              className={`py-2 text-center rounded text-sm border ${
                selected
                  ? "bg-emerald-50 border-emerald-500 text-emerald-700 font-semibold"
                  : "bg-white border-slate-200 text-slate-700"
              }`}
            >
              {formatTimeSlot(slot.startTime)}
            </button>
          );
        })}
        {slotsForDate.length === 0 && (
          <div className="col-span-3 text-center text-sm text-slate-400 py-6">
            No slots on this date.
          </div>
        )}
      </div>
    </section>
  );
}
