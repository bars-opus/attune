// aura-in-web/app/book/[slug]/components/PhoneInput.tsx
//
// Country-prefix phone input. Emits the assembled E.164 value via onChange
// so callers can keep treating phone as a single string. Defaults the
// country to the shop's country when known (most clients book locally),
// but the visitor can override.
//
// Normalization on input: strips spaces/dashes/parens, drops a leading 0
// (common in many local formats — e.g. Ghana 0501234567 → 501234567 once
// the +233 prefix is applied), and limits to 14 digits after the dial code
// so we never exceed E.164's 15-digit total.
"use client";

import { useMemo, useState, useEffect } from "react";

interface Country {
  iso2: string;       // ISO 3166-1 alpha-2
  name: string;
  dialCode: string;   // e.g. "+233"
  flag: string;       // emoji
}

// Common African + global markets. Order matters — most-likely first so the
// dropdown's default scroll position lands somewhere useful. Add more as
// the business expands; the dropdown is searchable by typing in the box.
const COUNTRIES: Country[] = [
  { iso2: "GH", name: "Ghana",          dialCode: "+233", flag: "🇬🇭" },
  { iso2: "NG", name: "Nigeria",        dialCode: "+234", flag: "🇳🇬" },
  { iso2: "KE", name: "Kenya",          dialCode: "+254", flag: "🇰🇪" },
  { iso2: "ZA", name: "South Africa",   dialCode: "+27",  flag: "🇿🇦" },
  { iso2: "UG", name: "Uganda",         dialCode: "+256", flag: "🇺🇬" },
  { iso2: "TZ", name: "Tanzania",       dialCode: "+255", flag: "🇹🇿" },
  { iso2: "RW", name: "Rwanda",         dialCode: "+250", flag: "🇷🇼" },
  { iso2: "CI", name: "Côte d'Ivoire",  dialCode: "+225", flag: "🇨🇮" },
  { iso2: "SN", name: "Senegal",        dialCode: "+221", flag: "🇸🇳" },
  { iso2: "CM", name: "Cameroon",       dialCode: "+237", flag: "🇨🇲" },
  { iso2: "EG", name: "Egypt",          dialCode: "+20",  flag: "🇪🇬" },
  { iso2: "MA", name: "Morocco",        dialCode: "+212", flag: "🇲🇦" },
  { iso2: "GB", name: "United Kingdom", dialCode: "+44",  flag: "🇬🇧" },
  { iso2: "US", name: "United States",  dialCode: "+1",   flag: "🇺🇸" },
  { iso2: "CA", name: "Canada",         dialCode: "+1",   flag: "🇨🇦" },
  { iso2: "FR", name: "France",         dialCode: "+33",  flag: "🇫🇷" },
  { iso2: "DE", name: "Germany",        dialCode: "+49",  flag: "🇩🇪" },
];

const DEFAULT_COUNTRY = COUNTRIES[0]; // Ghana

function findByIso2(iso2: string | null | undefined): Country | undefined {
  if (!iso2) return undefined;
  return COUNTRIES.find((c) => c.iso2.toLowerCase() === iso2.toLowerCase());
}

function findByDialCode(e164: string): Country | undefined {
  // Match longest dial code first (e.g. +1 vs +1809 — though we only have +1).
  return [...COUNTRIES]
    .sort((a, b) => b.dialCode.length - a.dialCode.length)
    .find((c) => e164.startsWith(c.dialCode));
}

export function PhoneInput({
  value,
  defaultCountryIso2,
  onChange,
}: {
  /** Full E.164 value, e.g. "+233501234567". Empty string for blank. */
  value: string;
  /** Shop's ISO-2 country code, used as the initial picker selection. */
  defaultCountryIso2: string | null;
  /** Called with the assembled E.164 string. */
  onChange: (e164: string) => void;
}) {
  const initialCountry =
    (value ? findByDialCode(value) : findByIso2(defaultCountryIso2)) ??
    DEFAULT_COUNTRY;

  const [country, setCountry] = useState<Country>(initialCountry);

  // Local digits state — what the user actually types into the input,
  // never including the dial code.
  const initialLocal = value.startsWith(initialCountry.dialCode)
    ? value.slice(initialCountry.dialCode.length)
    : "";
  const [local, setLocal] = useState(initialLocal);

  // Re-emit assembled E.164 whenever country or local changes. Strip any
  // leading 0 (common local convention) so +233 + 0501... doesn't become
  // +2330501... which Paystack rejects.
  useEffect(() => {
    const cleaned = local.replace(/[^\d]/g, "").replace(/^0+/, "");
    const e164 = cleaned ? `${country.dialCode}${cleaned}` : "";
    if (e164 !== value) onChange(e164);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [country, local]);

  const placeholder = useMemo(() => {
    // Ghana / Nigeria / Kenya all use 9-10 digit subscriber numbers; show
    // a generic hint rather than country-specific samples.
    return "Mobile number";
  }, []);

  return (
    <div className="flex gap-2">
      <select
        value={country.iso2}
        onChange={(e) => {
          const next = COUNTRIES.find((c) => c.iso2 === e.target.value);
          if (next) setCountry(next);
        }}
        className="bg-white border border-slate-200 rounded-lg px-2 py-2.5 text-sm min-w-[110px]"
        aria-label="Country code"
      >
        {COUNTRIES.map((c) => (
          <option key={c.iso2} value={c.iso2}>
            {c.flag} {c.dialCode}
          </option>
        ))}
      </select>
      <input
        type="tel"
        inputMode="tel"
        autoComplete="tel-national"
        placeholder={placeholder}
        value={local}
        onChange={(e) => setLocal(e.target.value)}
        className="flex-1 bg-white border border-slate-200 rounded-lg px-3 py-2.5 text-sm"
      />
    </div>
  );
}
