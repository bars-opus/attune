// aura-in-web/app/book/[slug]/components/ShopHero.tsx
import type { Shop } from "@/lib/types";

export function ShopHero({ target }: { target: Shop }) {
  return (
    <header className="bg-white border-b border-slate-200 px-4 py-4 flex items-center gap-3">
      {target.logoUrl
        ? <img
            src={target.logoUrl}
            alt=""
            className="w-12 h-12 rounded-lg object-cover bg-slate-200"
          />
        : <div className="w-12 h-12 rounded-lg bg-slate-800 text-white flex items-center justify-center font-semibold">
            {target.name.slice(0, 2).toUpperCase()}
          </div>}
      <div className="flex-1 min-w-0">
        <h1 className="font-semibold text-slate-900 truncate">{target.name}</h1>
        <p className="text-xs text-slate-500 truncate">
          {target.type ?? "Shop"}
          {target.address ? ` · ${target.address}` : ""}
        </p>
      </div>
    </header>
  );
}
