// aura-in-web/app/book/[slug]/components/ServicePicker.tsx
//
// Step 1 of the booking flow. Vertical list of services with price +
// duration. When the visitor is a returning guest (lookup-guest matched
// their phone), the service they last booked gets a "Booked last time"
// pill so they can re-book in one tap.
"use client";

import type { Service } from "@/lib/types";
import { formatDuration, formatMoney } from "@/lib/format";

export function ServicePicker({
  services,
  currency,
  selectedId,
  lastBookedServiceName,
  onSelect,
}: {
  services: Service[];
  currency: string | null;
  selectedId: string | null;
  lastBookedServiceName?: string;
  onSelect: (id: string) => void;
}) {
  return (
    <section className="px-4 pt-4">
      <h2 className="text-xs uppercase tracking-wide text-slate-500 mb-2 font-medium">
        1. Service
      </h2>
      <div className="space-y-2">
        {services.map((svc) => {
          const selected = selectedId === svc.id;
          const isLast =
            lastBookedServiceName && svc.name === lastBookedServiceName;
          return (
            <button
              key={svc.id}
              type="button"
              onClick={() => onSelect(svc.id)}
              className={`w-full text-left bg-white rounded-lg p-3 flex justify-between items-center border ${
                selected
                  ? "border-emerald-500 ring-1 ring-emerald-500"
                  : "border-slate-200"
              }`}
            >
              <div>
                <div className="font-medium text-slate-900 flex items-center gap-2">
                  {svc.name}
                  {isLast && (
                    <span className="text-[10px] uppercase tracking-wide bg-emerald-50 text-emerald-700 px-1.5 py-0.5 rounded">
                      Booked last time
                    </span>
                  )}
                </div>
                <div className="text-xs text-slate-500 mt-0.5">
                  {formatDuration(svc.durationMinutes)}
                </div>
              </div>
              <div
                className={`font-semibold ${
                  selected ? "text-emerald-600" : "text-slate-700"
                }`}
              >
                {formatMoney(svc.price, currency)}
              </div>
            </button>
          );
        })}
      </div>
    </section>
  );
}
