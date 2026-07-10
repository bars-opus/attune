// aura-in-web/app/not-found.tsx
//
// Global 404. Replaces the Next.js default for slug misses and any other
// notFound() calls in the app.

import Link from "next/link";

export default function NotFound() {
  return (
    <main className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
      <div className="text-center max-w-sm">
        <h1 className="text-2xl font-semibold text-slate-900 mb-2">
          Link not found
        </h1>
        <p className="text-sm text-slate-500 mb-6">
          This booking link doesn&apos;t exist or has expired. Ask the shop
          owner for a fresh link.
        </p>
        <Link
          href="/"
          className="text-emerald-600 text-sm font-medium underline"
        >
          Go to Aura-In home
        </Link>
      </div>
    </main>
  );
}
