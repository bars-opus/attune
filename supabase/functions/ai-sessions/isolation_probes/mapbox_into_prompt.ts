// NEGATIVE COMPILE PROBE. THIS FILE MUST NOT TYPE-CHECK.
//
// It is the executable form of spec §2's "Mapbox response text never
// re-enters Gemini" and §8.2.5's cross-provider isolation -- the two
// things Plan B's own review flagged as the highest-risk data-flow claim
// in the whole spec. index.test.ts's test
// "THE §2 ISOLATION IS STRUCTURAL" runs `deno check` on this file and
// asserts it FAILS with TS2322 on all three attempts below. If a future
// refactor weakens PromptApprovedText's brand, this file starts
// compiling and that test fails -- which is the alarm.
//
// It lives under isolation_probes/ rather than beside index.ts so that
// `deno check supabase/functions/ai-sessions/index.ts` and the test
// runner do not pick it up as ordinary source.
import {
  buildSessionUserPrompt,
  type SessionPromptInputs,
} from "../index.ts";
import type { PlaceSource } from "../../_shared/mapbox_search.ts";

const place: PlaceSource = {
  provider_id: "x",
  name: "Chez Mapbox",
  formatted_address: "1 Leak Street",
  category: "cafe",
  map_url: null,
};

// ATTEMPT 1 -- a Mapbox place NAME as an approved context snippet.
export const attempt1: SessionPromptInputs = {
  userInstruction: "more ideas like last time",
  history: [],
  contextWindow: [place.name],
};

// ATTEMPT 2 -- a Mapbox ADDRESS smuggled in as a prior Attune turn,
// which is how a "remember what we found" refactor would do it.
export const attempt2: SessionPromptInputs = {
  userInstruction: "more ideas like last time",
  history: [{ role: "attune", content: place.formatted_address ?? "" }],
  contextWindow: [],
};

// ATTEMPT 3 -- the whole Mapbox payload serialized, called directly on
// the prompt builder.
export const attempt3 = buildSessionUserPrompt(
  "{{CONTEXT_WINDOW_JSON}}",
  "ideas",
  {
    userInstruction: "more ideas like last time",
    history: [],
    contextWindow: [JSON.stringify(place)],
  },
);
