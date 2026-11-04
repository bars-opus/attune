// TEST-ONLY (Spec 1 W9e): journeys, reflections and spied dependencies for
// the two Healing handlers' tests.
import type { HealingDeps } from "../healing_ai_gate.ts";
import { fakeClient } from "./fake_supabase.ts";

export const CRISIS = { answer1: "Some nights I want to kill myself", answer2: "", answer3: "" };
export const VICTIM = { answer1: "he hit me last night and I don't know what to do", answer2: "", answer3: "" };
export const ORDINARY = {
  answer1: "I go quiet instead of saying what I actually need.",
  answer2: "I mistook intensity for closeness.",
  answer3: "Speaking up earlier instead of waiting until I am resentful.",
};

export function journey(over: Record<string, unknown> = {}) {
  return {
    id: "j1",
    user_id: "u1",
    relationship_id: null,
    reflection_answers: ORDINARY,
    post_mortem_status: "not_started",
    post_mortem_observation: null,
    post_mortem_confidence: null,
    post_mortem_reflection_prompt: null,
    portrait_status: "not_started",
    portrait_text: null,
    portrait_prompt: null,
    portrait_reflection: null,
    ...over,
  };
}

/// The caller's own client (RLS): it answers the journey, a profile, and
/// nothing else.
export function userWith(row: unknown, error: unknown = null) {
  return fakeClient((call) => {
    if (call.table === "healing_journeys") return { data: error ? null : row, error };
    if (call.table === "psych_profiles") {
      return { data: { attachment_style: { primary: "secure" } }, error: null };
    }
    return { data: [], error: null };
  });
}

export function spyDeps(opts: {
  paused?: boolean;
  pausedThrows?: boolean;
  victimisation?: boolean;
  victimisationThrows?: boolean;
  reply?: Record<string, unknown> | null;
} = {}) {
  const prompts: string[] = [];
  const deps: HealingDeps = {
    model: (params) => {
      prompts.push(params.userPrompt);
      return Promise.resolve(
        opts.reply === undefined
          ? { portrait: "You notice how you show up.", observation: "A pattern may have surfaced.", reflection_prompt: "What feels familiar?" }
          : opts.reply,
      );
    },
    aiPaused: () => opts.pausedThrows ? Promise.reject(new Error("flag read failed")) : Promise.resolve(opts.paused ?? false),
    victimisationOn: () =>
      opts.victimisationThrows ? Promise.reject(new Error("flag read failed")) : Promise.resolve(opts.victimisation ?? false),
  };
  return { deps, prompts };
}

/// A value whose text cannot be read: reading it throws.
export const THROWS = { toString(): string { throw new Error("unreadable"); } } as unknown as string;

/// reflection_answers nested [depth] levels deep, with ordinary words.
export function nested(depth: number): Record<string, unknown> {
  let value: unknown = "ordinary words";
  for (let i = 0; i < depth; i++) value = { inner: value };
  return value as Record<string, unknown>;
}
