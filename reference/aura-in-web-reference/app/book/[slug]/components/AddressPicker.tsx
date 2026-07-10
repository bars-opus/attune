"use client";

import { useEffect, useRef, useState } from "react";
import type { Shop } from "@/lib/types";

interface PickedAddress {
  text: string;
  lat: number;
  lng: number;
}

export function AddressPicker({
  freelancer,
  travelRadiusKm,
  onChange,
}: {
  freelancer: Shop;
  travelRadiusKm: number | null;
  onChange: (addr: PickedAddress | null, distanceKm: number | null) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let geocoder: any = null;
    let cancelled = false;

    async function init() {
      const token = process.env.NEXT_PUBLIC_MAPBOX_TOKEN;
      if (!token) {
        setError("Address autocomplete unavailable (no Mapbox token)");
        return;
      }
      // Lazy import — only pulled into the bundle on freelancer pages.
      const mod = await import("@mapbox/mapbox-gl-geocoder");
      if (cancelled) return;
      const Geocoder: any = (mod as any).default ?? mod;

      // Mapbox geocoder accepts a 2-letter ISO country code; if shop.country
      // is null or non-ISO, omit countries to geocode globally.
      const cc =
        freelancer.country && freelancer.country.length === 2
          ? freelancer.country.toLowerCase()
          : undefined;

      geocoder = new Geocoder({
        accessToken: token,
        placeholder: "Enter your address",
        countries: cc,
        types: "address,place,locality",
      });

      if (containerRef.current) {
        geocoder.addTo(containerRef.current);
      }

      geocoder.on("result", (e: any) => {
        const lng = e.result.center[0];
        const lat = e.result.center[1];
        if (freelancer.latitude == null || freelancer.longitude == null) {
          // No origin to measure from — accept the address but skip range check.
          setError(null);
          onChange({ text: e.result.place_name, lat, lng }, null);
          return;
        }
        const distance = haversineKm(
          freelancer.latitude,
          freelancer.longitude,
          lat,
          lng,
        );
        if (travelRadiusKm != null && distance > travelRadiusKm) {
          setError(
            `${distance.toFixed(1)}km from ${freelancer.name} (max ${travelRadiusKm}km)`,
          );
          onChange(null, distance);
        } else {
          setError(null);
          onChange({ text: e.result.place_name, lat, lng }, distance);
        }
      });

      geocoder.on("clear", () => {
        setError(null);
        onChange(null, null);
      });
    }
    init();
    return () => {
      cancelled = true;
      if (geocoder && typeof geocoder.onRemove === "function") {
        try {
          geocoder.onRemove();
        } catch {}
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <section className="px-4 pt-3">
      <h2 className="text-xs uppercase tracking-wide text-slate-500 mb-2 font-medium">
        Where should they come?
      </h2>
      <div
        ref={containerRef}
        className="[&_.mapboxgl-ctrl-geocoder]:!w-full [&_.mapboxgl-ctrl-geocoder]:!max-w-none [&_.mapboxgl-ctrl-geocoder]:!shadow-none [&_.mapboxgl-ctrl-geocoder]:!border [&_.mapboxgl-ctrl-geocoder]:!border-slate-200 [&_.mapboxgl-ctrl-geocoder]:!rounded-lg [&_.mapboxgl-ctrl-geocoder_input]:!h-11"
      />
      <link
        rel="stylesheet"
        href="https://api.mapbox.com/mapbox-gl-js/plugins/mapbox-gl-geocoder/v5.0.0/mapbox-gl-geocoder.css"
      />
      {error && <p className="text-xs text-red-600 mt-2">{error}</p>}
    </section>
  );
}

function haversineKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}
