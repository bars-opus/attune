// aura-in-web/app/book/[slug]/error.tsx
//
// Per-route error boundary for /book/[slug] and its subroutes.
// Renders when a server component throws (e.g., resolve-link is down,
// the Supabase fetch fails, or any unhandled exception bubbles).

"use client";

import { useEffect } from "react";

export default function ErrorPage({
  error, reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Log the error for ops visibility. Production should ship this to
    // Sentry/equivalent — Vercel logs catch console.error already.
    console.error("/book/[slug] error:", error);
  }, [error]);

  return (
    <main className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-sm border border-slate-200 max-w-md w-full p-6 text-center">
        <div className="w-14 h-14 mx-auto rounded-full bg-red-100 flex items-center justify-center mb-4">
          <span className="text-red-600 text-2xl">!</span>
        </div>
        <h1 className="text-lg font-semibold text-slate-900 mb-2">
          Something went wrong
        </h1>
        <p className="text-sm text-slate-500 mb-4">
          We couldn&apos;t finish setting up your booking. Please try again,
          or ask the shop owner for a fresh link.
        </p>
        <button
          type="button"
          onClick={reset}
          className="bg-emerald-600 text-white font-medium px-4 py-2 rounded-lg"
        >
          Try again
        </button>
        {error.digest && (
          <p className="text-[10px] text-slate-300 mt-4 font-mono">
            ref: {error.digest}
          </p>
        )}
      </div>
    </main>
  );
}
