// aura-in-web/app/book/[slug]/components/WorkerPicker.tsx
//
// Step 2 of the booking flow. Horizontally scrolling chip row of workers.
// Hidden entirely on freelancer pages (BookingFlow gates the render on
// targetType === "shop"). "Any available" maps to workerId = null and lets
// generate_available_slots pick from all slot-assigned workers.
"use client";

import type { Worker } from "@/lib/types";

export function WorkerPicker({
  workers,
  selectedId,
  onSelect,
}: {
  workers: Worker[];
  selectedId: string | null;
  onSelect: (id: string | null) => void;
}) {
  if (workers.length === 0) return null;

  return (
    <section className="px-4 pt-3">
      <h2 className="text-xs uppercase tracking-wide text-slate-500 mb-2 font-medium">
        2. Worker{" "}
        <span className="lowercase text-slate-400">(optional)</span>
      </h2>
      <div className="flex gap-2 overflow-x-auto -mx-4 px-4 pb-1">
        <button
          type="button"
          onClick={() => onSelect(null)}
          className={`flex-shrink-0 px-3 py-2 rounded-lg border bg-white ${
            selectedId === null
              ? "border-emerald-500 ring-1 ring-emerald-500 text-slate-900 font-medium"
              : "border-slate-200 text-slate-600"
          }`}
        >
          Any available
        </button>
        {workers.map((w) => (
          <button
            key={w.id}
            type="button"
            onClick={() => onSelect(w.id)}
            className={`flex-shrink-0 px-3 py-2 rounded-lg border bg-white ${
              selectedId === w.id
                ? "border-emerald-500 ring-1 ring-emerald-500 text-slate-900 font-medium"
                : "border-slate-200 text-slate-600"
            }`}
          >
            {w.name}
          </button>
        ))}
      </div>
    </section>
  );
}
