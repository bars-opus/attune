// aura-in-web/app/book/[slug]/success/page.tsx
//
// After Paystack/Stripe redirects here, polls bookings by
// payment_intent_id every 2s for up to 60s. Renders the success state
// once status='confirmed'. After 60s, renders a graceful fallback
// ("processing — WhatsApp incoming").
//
// Next 16: params and searchParams are Promises — must await.

import { fetchBookingByReference } from "@/lib/api";
import { redirect } from "next/navigation";

interface Props {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ reference?: string }>;
}

const POLL_TIMEOUT_MS = 60_000;
const POLL_INTERVAL_MS = 2_000;

async function pollForBooking(reference: string) {
  const deadline = Date.now() + POLL_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const booking = await fetchBookingByReference(reference);
    if (booking) return booking;
    await new Promise(r => setTimeout(r, POLL_INTERVAL_MS));
  }
  return null;
}

export default async function SuccessPage({ params, searchParams }: Props) {
  const { slug } = await params;
  const { reference } = await searchParams;

  if (!reference) redirect(`/book/${slug}`);

  const booking = await pollForBooking(reference);

  if (booking) {
    return (
      <main className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
        <div className="bg-white rounded-2xl shadow-sm border border-slate-200 max-w-md w-full p-6 text-center">
          <div className="w-14 h-14 mx-auto rounded-full bg-emerald-100 flex items-center justify-center mb-4">
            <span className="text-emerald-600 text-3xl">✓</span>
          </div>
          <h1 className="text-xl font-semibold text-slate-900 mb-2">Booking confirmed</h1>
          <p className="text-sm text-slate-500 mb-6">
            We&apos;ll send you a WhatsApp message with the details shortly.
          </p>
          <p className="text-xs text-slate-400">
            Reference: {booking.id.slice(0, 8)}
          </p>
        </div>
      </main>
    );
  }

  // Webhook didn't fire within 60s — graceful fallback.
  return (
    <main className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-sm border border-slate-200 max-w-md w-full p-6 text-center">
        <div className="w-14 h-14 mx-auto rounded-full bg-amber-100 flex items-center justify-center mb-4">
          <span className="text-amber-600 text-2xl">⏳</span>
        </div>
        <h1 className="text-lg font-semibold text-slate-900 mb-2">
          Payment is processing
        </h1>
        <p className="text-sm text-slate-500">
          Your payment was received but the booking is taking longer than usual
          to confirm. We&apos;ll send a WhatsApp message as soon as it&apos;s
          confirmed — you can safely close this page.
        </p>
      </div>
    </main>
  );
}

// Disable static generation — this page is dynamic per request.
export const dynamic = "force-dynamic";
