// aura-in-web/app/book/[slug]/page.tsx
//
// Server component. Resolves the slug, fetches shop/freelancer + services +
// workers + slots from Plan A's resolve-link edge function, renders the page
// server-side for fast first paint. Interactive client components (slot
// picker, form) receive the data as props.
//
// Next 16: params is a Promise — must await it.

import { resolveLink } from "@/lib/api";
import { ShopHero } from "./components/ShopHero";
import { FreelancerHero } from "./components/FreelancerHero";
import { BookingFlow } from "./components/BookingFlow";
import { notFound } from "next/navigation";
import type { Metadata } from "next";

interface Props {
  params: Promise<{ slug: string }>;
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const data = await resolveLink(slug);
  if (!data) {
    return { title: "Booking link not found · Aura-In" };
  }
  return {
    title: `Book at ${data.target.name} · Aura-In`,
    description: `Book your appointment at ${data.target.name}. Pay deposit, get WhatsApp confirmation.`,
  };
}

export default async function BookingPage({ params }: Props) {
  const { slug } = await params;
  const data = await resolveLink(slug);

  if (!data) notFound();

  return (
    <main className="min-h-screen bg-slate-50 pb-32">
      <div className="max-w-md mx-auto">
        {data.targetType === "shop"
          ? <ShopHero target={data.target} />
          : <FreelancerHero target={data.target} />}

        <BookingFlow data={data} slug={slug} />
      </div>
    </main>
  );
}
