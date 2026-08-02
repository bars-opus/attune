# Reflection Journal — Design Spec

**Status:** Approved, ready for implementation planning
**Author:** Claude (Sonnet 5), in collaboration with the Attune team
**Date:** 2026-08-02

## 1. Problem statement

`ATTUNE_MASTER_SPEC.md` §8.9 lists two distinct features available to Personal-mode users:

> ✓ Reflection journal with AI analysis (tone, NVC, patterns)
> ✓ Healing mode journey (if applicable)

Only the second (the conditional, 5-stage post-breakup Healing journey) has ever been built. The first — an always-available, standalone reflection journal — does not exist. `ChatCouplesLockedScreen`'s `_ReflectionEntryCard` currently routes to `HealingJourneyScreen` for every non-couples user regardless of eligibility, which means `couplesPending` and brand-new `personal`-mode users (who by definition have no ended relationship) hit a dead-end empty state.

This spec designs and scopes the real, standalone Reflection Journal feature to close that gap — not a patch, a genuine build, to a launch-ready standard.

## 2. What it is

A private, always-available, per-user reflection journal. Available to any signed-in user regardless of relationship history or mode (`personal`, `couplesPending`, or an active `couples` user journaling between conflicts). No eligibility gate — that is precisely what distinguishes it from the conditional Healing journey, which remains untouched by this work.

Competitive research (see §11) found no existing product that does what this feature does: longitudinal NVC-informed analysis of private writing that is never sent to anyone. Every comparable NVC tool on the market rewrites a single outbound message. This is analysis of writing that never leaves the user — a genuinely unoccupied position, consistent with Attune's stated differentiation strategy.

## 3. Governing constraints (non-negotiable)

Pulled directly from `ATTUNE_SOUL.md`, `ATTUNE_CLINICAL.md` §10, and `ATTUNE_PRINCIPLES_CHECKLIST.md` §B/E/G. Every implementation decision must satisfy these:

- **No streaks, badges, or leaderboards.** Ever, for any reason. (Principles §G)
- **No missed-day / re-engagement notifications** of any kind in this build. (See §8 — deferred entirely.)
- **AI never diagnoses, never tells the user what to decide.** Banned words: toxic, narcissist, codependent, disorder, broken. (Soul §8)
- **Every AI claim must be sourced** to the user's own words — "based on what you wrote" never "it seems like." (Principles §B2, §D)
- **NVC-derived observations are capped at MEDIUM confidence**, always hedged ("some patterns suggest..."), never stated as flat fact. (Clinical §10)
- **Never use the word "violation."** NVC patterns are surfaced as neutral, sourced observations about language, never as compliance verdicts on the user's private grief.
- **NVC's "Request" component is reframed self-facing only** — never partner-directed, never phrased as something to say or ask of someone else. A private diary has no addressee; prompting toward an outbound request risks the exact autonomy violation Principle 5 forbids.
- **Entries are never shared with a partner, never combined into any couple-level view, never used as "evidence."** (Soul §8, Privacy)
- **Full user control**: entries are editable and permanently deletable at any time. (Principles §F)
- **Voice is "a wise, attentive friend," never clinical, never therapy-coded.** (Soul §10)
- **No paywall on the core journaling or analysis experience** in this build (monetization is out of scope for this spec).

## 4. Entry format

Freeform by default. The primary action is "Write an entry" — always a blank page. Above the blank page, an optional, dismissible daily prompt is shown as inspiration, pulled from a curated, hand-written, rotating bank (~30-50 prompts for v1). The user can write from it, ignore it, or dismiss it — never required.

Prompt-writing rules (from competitive/expressive-writing research, §11.4):
- Concrete and moment-anchored, never abstract ("What's one thing that surprised you today?" not "What are you grateful for?")
- Open-ended, never yes/no, never presupposing a conclusion about the user's relationship or their partner's behavior
- Never therapy-coded ("Describe your inner child" is explicitly the wrong register)

Each entry stores `prompt_used` (nullable) so we know which prompt, if any, inspired it — useful for later prompt-bank quality review, not user-facing.

## 5. Data model

Two new Postgres tables, both `user_id`-scoped only (no `relationship_id` — this is a deliberate divergence from `timeline_events` and `pulse_scores`, which are both incorrectly-for-this-purpose relationship-scoped; the correct model to mirror is `healing_journeys`, which is already `user_id`-scoped with an optional nullable `relationship_id`).

### `reflection_journal_entries`

```sql
CREATE TABLE public.reflection_journal_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content text NOT NULL,
  prompt_used text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);
```

Soft-deleted (`deleted_at`), matching `timeline_events`' existing pattern in this codebase — the UI treats deletion as permanent (no "restore" affordance), but the row survives at the DB level for the same reasons the rest of the app soft-deletes.

### `reflection_journal_analysis`

```sql
CREATE TABLE public.reflection_journal_analysis (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id uuid NOT NULL REFERENCES public.reflection_journal_entries(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'completed', 'insufficient_evidence', 'failed')),
  tone text CHECK (tone IN ('reflective', 'charged', 'settled', 'searching', 'hopeful', 'heavy')),
  observation text, -- sourced, O/F/N-framed, quotes the user's own words
  confidence text CHECK (confidence IN ('high', 'medium', 'low', 'none')),
  input_hash text NOT NULL,
  prompt_version text NOT NULL,
  model_provider text NOT NULL, -- 'google' for this feature (see §7)
  model_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (entry_id, input_hash)
);
```

Separated from the entry table so re-analysis on edit is a clean upsert keyed by `input_hash` (sha256 of `content`), never a mutation of the user's actual words. Editing an entry invalidates the old analysis (new `input_hash` → new analysis row generated) rather than deleting history.

**Cross-entry patterns are computed on-demand** from the last 5-20 `completed` analysis rows — not a separately cached/stored aggregate table in v1. Simplest correct thing; avoids a second cache-invalidation surface; trivially re-derivable. If read latency ever becomes a real problem, that is a future optimization, not a v1 concern.

RLS: both tables readable/writable only by `auth.uid() = user_id`, matching every other personal-insight table in this codebase (Principles §F: "readable only by the user it describes — never by their partner").

## 6. AI analysis — edge function design

New edge function: `analyse-journal-entry`.

New shared helper: `_shared/gemini_json.ts`, mirroring `_shared/claude_json.ts`'s exact interface and safety guarantees — same `STATIC_PROHIBITED_PATTERNS` regex set, same strict-JSON-parse-with-fallback, same timeout handling — but calling Gemini's `generateContent` REST API instead of Claude's Messages API. See §7 for the model-choice rationale.

**Flow** (modeled on `generate-healing-post-mortem`'s proven shape):

1. Client saves an entry, calls `analyse-journal-entry` with `entry_id`.
2. Function computes `input_hash = sha256(content)`; checks `reflection_journal_analysis` for an existing `completed` row with that hash. If found, returns it immediately (idempotent — never re-charges for identical content).
3. If entry content is under ~15 words (configurable), skip the model call entirely: `status: insufficient_evidence`. No cost, no forced insight on a one-line entry.
4. Otherwise, calls Gemini via the new `callGeminiJson` helper with:
   - Global constraint header (banned words, never attribute negative behavior to a named/implied partner, never tell the user what to decide, return ONLY valid JSON) — identical header used by every other Attune AI prompt, per Principles §E.
   - **NVC scope: Observation, Feeling, Need only.** No "Request" prompted toward the partner. If a self-facing reflective closing is generated, it must be inward ("what might help you, going forward") — never phrased as something to say or ask of someone else. A runtime-prohibited pattern (e.g. `/you should (tell|confront|ask|leave)/i`) is added on top of the shared static list to catch drift.
   - Confidence is capped at `medium` in the schema itself for anything NVC-derived — the prompt must never be permitted to return `high` for an NVC-flavored observation, per Clinical §10.
   - Explicit instruction never to use the word "violation" — frame language patterns neutrally ("you described this in always/never terms" not "this is a blame-language violation").
5. On any failure — timeout, malformed JSON, a prohibited pattern firing, missing API key — fall back to a warm, honest, generic holding entry (`status: completed`, `observation: null` or a soft acknowledgment, never a raw error surfaced to the user), matching `generate-healing-post-mortem`'s `buildFallback` pattern exactly.
6. **Response timing**: the function returns fast with `status: pending` and the client shows a light, static, warm acknowledgment immediately ("Saved. Sit with that for a bit.") — no analysis forced on the user the moment they finish writing. The actual Gemini call and validation happen server-side; the client picks up the completed row the next time it opens that entry or the journal (simple refetch-on-view, no live polling/streaming UI required for v1).

This two-tempo design (light immediate acknowledgment, deferred substantive analysis) is a direct response to competitive research: apps with pure-immediate AI feedback (Rosebud) get reviewed as "formulaic" over time, and research on private/unsent writing finds the therapeutic value is in writing freely, not in getting an instant reaction. Removing the immediate full-analysis reveal also avoids a heavy AI response landing directly on top of a painful entry the moment it's written.

**Patterns endpoint**: `get-journal-patterns` (or an extension of the same function) reads the last 5-20 `completed` analysis rows for the calling user and returns a short, sourced, dated cross-entry summary ("Across 3 entries this month, a theme of feeling unheard came up twice — on the 4th and the 11th"). Same confidence/sourcing/banned-word rules apply. Below 3-5 completed analyses, returns `insufficient_evidence` and the client shows an honest "not enough entries yet" state — mirroring the existing Healing post-mortem UX pattern already in the codebase, not inventing a new empty-state convention.

## 7. Why Gemini, not Claude

Every existing AI-generation function in Attune (`generate-verdict`, `generate-healing-portrait`, `generate-healing-post-mortem`, `analyse-message`, `translate-conflict`) is Claude-only. This is the first feature to use a different provider, driven by cost: Gemini has a genuine (not trial) free tier and remains a frontier-quality model, unlike a fully open-source/self-hosted option which was assessed and rejected as too unreliable for emotionally-sensitive content with strict safety constraints.

The safety architecture (banned-word patterns, confidence hedging, JSON-only structured output, graceful fallback) is entirely provider-agnostic — it lives in shared validation code, not in the model call itself. `model_provider` is already a tracked column on every generation-job table in this codebase precisely for this kind of variation; this feature sets it to `'google'` while every other function keeps `'anthropic'` untouched. Switching this feature to Claude later, if quality issues surface in practice, is a one-line import change, not a rewrite.

## 8. Explicitly deferred (not gaps — deliberate scope decisions)

- **Content-anchored re-engagement nudges** ("You wrote about feeling unheard twice this month"). Competitive research identified this as the one notification pattern that might survive Attune's anti-dark-pattern constraints (content-grounded, not missed-day-shaming), but it still carries real risk of reading as surveillance. Deferred to a future release once real usage patterns exist to design and tune against. The journal is fully functional and complete without it.
- **AI-generated (vs. curated-bank) daily prompts.** Personalized prompts are a plausible future enhancement aligned with the soul doc's "compounding intelligence" principle, but add cost, a second prompt-safety surface to review, and risk (a badly-targeted personalized prompt landing on a sensitive topic reads worse than a generic one). v1 ships with a hand-written, reviewed, rotating bank.
- **Cached/precomputed pattern aggregates.** On-demand computation is correct and sufficient at expected v1 volume.
- **Personal pulse score / pattern-memory integration.** Both are real, separately-scoped subsystems (pattern memory is explicitly chat-session-driven per the master spec) that Personal-mode users, by definition, don't generate through this journal. Out of scope for this spec; not something this feature should reach into.

## 9. Screens & navigation

**`ReflectionJournalScreen`** — new top-level screen. Two tabs, matching the app's existing tab pattern (same shape as the Forums/Opinions split):

- **Entries tab**: reverse-chronological entry list (preview text, date, tone indicator once analyzed) with a prominent "Write" action. Compose view: optional dismissible daily-prompt banner above a blank text field, Save button. Save is optimistic — the entry appears in the list immediately; the tone/observation badge fills in once analysis completes (picked up on next view, no polling UI).
- **Patterns tab**: below the 3-5 entry threshold, an honest "not enough entries yet" empty state. Above it, the sourced, dated cross-entry summary from `get-journal-patterns`.

Tapping an entry opens a detail view: full text (editable — editing invalidates and regenerates that entry's analysis via the `input_hash` mechanism), a delete action, and the entry's individual analysis once ready. Delete requires a confirmation dialog before it fires (soft-deletes, matches Timeline's pattern and confirm-before-destructive-action convention) — no undo affordance after confirming, since the app has no "trash" surface to recover into.

**Navigation fix**: `_ReflectionEntryCard` in `ChatCouplesLockedScreen` (`lib/features/chat/presentation/screens/chat_couples_locked_screen.dart`) is reverted to unconditional visibility — the `isHealingEligible` gate added in the prior turn is removed, since this card now correctly routes to the new, always-available `ReflectionJournalScreen` instead of the conditional `HealingJourneyScreen`. The Healing journey's own two existing entry points (`conversations_screen.dart`'s icon button and `_ReflectionCard`) are untouched — they remain correctly gated by Healing eligibility, which this spec does not change.

## 10. Testing evidence expected at implementation time

- Widget tests for `ReflectionJournalScreen`'s three states (empty entries list, populated list, patterns-view above/below threshold).
- A unit test proving the edit-invalidates-analysis flow: editing an entry's content changes `input_hash`, and the old analysis row is not returned for the new content.
- An edge-function-level test (or documented manual verification) confirming the banned-word/prohibited-pattern validation actually rejects a deliberately bad model response before it reaches the client — mirroring how `generate-healing-post-mortem`'s `validateOutput` is exercised.
- Confirmation that RLS prevents a user from reading another user's `reflection_journal_entries` or `reflection_journal_analysis` rows.

## 11. Competitive research summary

Full research (via a dedicated research pass across Rosebud, Mindsera, Stoic, How We Feel, Daylio, Reflectly, Journey, Wysa, Youper, plus breakup-specific apps and existing NVC tools) is available in the session transcript; key findings folded into this spec:

- **No existing product does longitudinal NVC analysis of private, unsent writing.** Every comparable tool rewrites a single outbound message. This is Attune's genuine white space.
- **Streaks/counters are the dominant mechanic in breakup-recovery apps specifically** (no-contact-day counters) and are exactly the loss-aversion gamification this feature must never use — doubly disqualified as both gamification and an implicit judgment about a life decision.
- **Immediate-only AI feedback becomes detectably "formulaic"** in longitudinal use (Rosebud reviews); informed the two-tempo (light-immediate + deferred-substance) response design in §6.
- **Clinical/detached AI tone is the most-cited failure mode** (Mindsera: "more like a productivity app than an emotional companion") — directly validates the soul doc's "wise, attentive friend" voice requirement as a competitive differentiator, not just an ethical one.
- **Purposeless AI follow-up questions read as extraction, not care** (Wysa's "tell me more" loop) — any follow-up prompt generated by the analysis must have a self-evident reason for existing.
- **On-device/opt-in privacy framing builds trust more than technical claims alone** (How We Feel, Stoic) — since Attune cannot do on-device inference (server-side Gemini call is required), trust must be earned through explicit, user-visible retention/deletion/export commitments, not implied by architecture.
