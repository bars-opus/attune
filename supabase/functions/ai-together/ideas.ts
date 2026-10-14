// Together date ideas (plan Phase 7 R5, R6): a free window → three things to do.
import { weekdayOf } from "./capture.ts";

export type DateIdea = { title: string; blurb: string };

const LOCAL_DT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/;
const ms = (s: string) => Date.parse(`${s}:00Z`);

export function validateIdeasRequest(body: Record<string, unknown>):
  { ok: true; startLocal: string; endLocal: string } | { ok: false } {
  const allowed = new Set(["window_start_local", "window_end_local"]);
  if (Object.keys(body).some((k) => !allowed.has(k))) return { ok: false };
  const s = body.window_start_local, e = body.window_end_local;
  if (typeof s !== "string" || typeof e !== "string" || !LOCAL_DT.test(s) || !LOCAL_DT.test(e)) return { ok: false };
  const len = ms(e) - ms(s);
  // Free windows run up to a whole waking day (08:00–22:00), so allow 24 hours.
  if (Number.isNaN(len) || len < 3_600_000 || len > 24 * 3_600_000) return { ok: false };
  return { ok: true, startLocal: s, endLocal: e };
}

export function buildIdeasPrompt(p: { startLocal: string; endLocal: string }) {
  const hours = (ms(p.endLocal) - ms(p.startLocal)) / 3_600_000;
  const length = Number.isInteger(hours) ? `${hours} hours` : `${hours.toFixed(1)} hours`;
  const system = [
    "Suggest exactly three warm, specific things a couple could do together in a free window.",
    "Reply with JSON only: {\"ideas\": [{\"title\": string, \"blurb\": string}, ...]} with exactly three items.",
    "title: at most 50 characters. blurb: one sentence, at most 140 characters.",
    "Fit the time of day and the length. Mix the kinds: something at home, something out, something that costs little.",
    "No named businesses or places. Nothing about the state of the relationship or either person's behaviour; no advice or therapy language.",
  ].join("\n");
  const user = `WINDOW: ${weekdayOf(p.startLocal)} ${p.startLocal.slice(0, 10)}, ${p.startLocal.slice(11)}–${p.endLocal.slice(11)} (${length})`;
  return { system, user };
}

export function parseIdeas(raw: Record<string, unknown>): DateIdea[] | null {
  const list = raw.ideas;
  if (!Array.isArray(list) || list.length !== 3) return null;
  const out: DateIdea[] = [];
  for (const i of list) {
    if (!i || typeof i !== "object") return null;
    const t = typeof (i as DateIdea).title === "string" ? (i as DateIdea).title.trim() : "";
    const b = typeof (i as DateIdea).blurb === "string" ? (i as DateIdea).blurb.trim() : "";
    if (!t || !b || [...t].length > 60 || [...b].length > 160) return null;
    out.push({ title: t, blurb: b });
  }
  return out;
}
