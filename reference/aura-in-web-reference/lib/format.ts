// aura-in-web/lib/format.ts
//
// Display formatters for the booking UI. Kept dependency-free — we use
// Intl APIs everywhere so the bundle doesn't ship a locale library.

/**
 * Format an amount with a currency symbol. resolve-link doesn't return
 * the shop's currency in v1 (Plan A gap), so this accepts `null` and
 * defaults to GHS — that matches the launch market. When Plan A is
 * patched to include currency on Shop, BookingFlow will thread it
 * through and the default branch becomes dead code.
 *
 * We map only the symbols we actually expect; anything else falls
 * through to the raw ISO code so it's still readable.
 */
export function formatMoney(amount: number, currency: string | null): string {
  const c = currency ?? "GHS";
  const symbol =
    c === "GHS" || c === "GHC"
      ? "GH₵" // GHS cedi
      : c === "NGN"
        ? "₦" // naira
        : c === "KES"
          ? "KSh"
          : c === "USD"
            ? "$"
            : c === "EUR"
              ? "€"
              : c === "GBP"
                ? "£"
                : c;
  return `${symbol} ${amount.toFixed(2)}`;
}

/**
 * Human duration: "30 min", "1h", "1h 30min". Avoids "0h 45min" style
 * weirdness for short slots.
 */
export function formatDuration(minutes: number): string {
  if (minutes < 60) return `${minutes} min`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}min`;
}

/**
 * Format a slot's start (or end) time as a localised clock label, e.g.
 * "2:30 pm". en-GB gives 12-hour with am/pm; if we ever localise the
 * page we can plumb the user's locale in here.
 */
export function formatTimeSlot(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleTimeString("en-GB", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });
}

/**
 * Day header for grouping slot rows: "Mon, 26 May".
 */
export function formatDateHeader(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", {
    weekday: "short",
    day: "numeric",
    month: "short",
  });
}
