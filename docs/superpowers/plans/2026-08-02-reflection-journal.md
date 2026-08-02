# Reflection Journal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the standalone Reflection Journal — a private, always-available, per-user journal with Gemini-based NVC-informed AI analysis and cross-entry pattern detection — and fix `_ReflectionEntryCard` to route to it instead of the conditional Healing journey.

**Architecture:** Two new `user_id`-scoped Postgres tables (`reflection_journal_entries`, `reflection_journal_analysis`) with `SECURITY DEFINER` RPC functions for all writes (mirroring `healing_journeys`' pattern — client never inserts/updates these tables directly). One new edge function (`analyse-journal-entry`) calls a new `_shared/gemini_json.ts` helper, idempotent via a `sha256(content)` input hash, with a `get-journal-patterns` action in the same function for cross-entry summaries. Flutter side follows the `HealingRepository` → Riverpod `FutureProvider` → screen pattern exactly: a `ReflectionJournalRepository`, providers in `reflection_journal_providers.dart`, and a new `ReflectionJournalScreen` with a plain `DefaultTabController` (Entries / Patterns).

**Tech Stack:** Flutter/Riverpod/Supabase (existing), Deno edge functions (existing), Gemini `generateContent` REST API (new provider for this feature only), `go_router` (existing).

## Global Constraints

- No streaks, badges, or leaderboards — ever, for any reason. (Spec §3)
- No missed-day / re-engagement notifications in this build. (Spec §3, §8)
- AI never diagnoses, never tells the user what to decide. Banned words: toxic, narcissist, codependent, disorder, broken. (Spec §3)
- Every AI claim must be sourced to the user's own words. (Spec §3)
- NVC-derived observations are capped at MEDIUM confidence, always hedged, never stated as flat fact. (Spec §3)
- Never use the word "violation" in AI output. (Spec §3)
- NVC's "Request" component is self-facing only — never partner-directed. A runtime-prohibited pattern `/you should (tell|confront|ask|leave)/i` must reject any drift toward this. (Spec §3, §6)
- Entries are never shared with a partner, never combined into any couple-level view. (Spec §3)
- Entries are fully editable and permanently deletable at any time; delete requires a confirmation dialog before it fires, no undo after confirming. (Spec §3, §9)
- Voice is "a wise, attentive friend," never clinical, never therapy-coded. (Spec §3)
- No paywall on the core journaling or analysis experience in this build. (Spec §3)
- Both new tables are `user_id`-scoped only — no `relationship_id` column, no couple-level joins anywhere. (Spec §5)
- `reflection_journal_entries.tone` is constrained to exactly: `'reflective', 'charged', 'settled', 'searching', 'hopeful', 'heavy'`. (Spec §5, as fixed in self-review)
- Patterns view requires 3-5 completed analyses minimum before showing a summary; below that, an honest "not enough entries yet" state. (Spec §6, §9)
- RLS on both new tables: readable/writable only by `auth.uid() = user_id`. (Spec §5)

---

## File Structure

**New files:**
- `supabase/migrations/20260813120000_reflection_journal.sql` — both tables, RLS, RPC functions (mirrors `20260703193000_healing_mode_v1_1.sql`'s structure exactly).
- `supabase/functions/_shared/gemini_json.ts` — Gemini equivalent of `_shared/claude_json.ts`.
- `supabase/functions/_shared/gemini_json.test.ts` — unit tests for the prohibited-pattern/parsing logic (the pure, non-network parts).
- `supabase/functions/analyse-journal-entry/index.ts` — the edge function: entry analysis + patterns endpoint (two actions dispatched by request body, mirroring how `process-chat-notification-outbox`-style functions branch on a body field — see Task 4 for exact routing).
- `lib/features/reflection_journal/data/models/journal_entry.dart`
- `lib/features/reflection_journal/data/models/journal_analysis.dart`
- `lib/features/reflection_journal/data/repositories/reflection_journal_repository.dart`
- `lib/features/reflection_journal/presentation/providers/reflection_journal_providers.dart`
- `lib/features/reflection_journal/presentation/screens/reflection_journal_screen.dart` — top-level, two tabs (Entries/Patterns).
- `lib/features/reflection_journal/presentation/screens/journal_entry_compose_screen.dart` — write/edit screen.
- `lib/features/reflection_journal/presentation/screens/journal_entry_detail_screen.dart` — view/edit/delete a single entry.
- `lib/features/reflection_journal/presentation/widgets/journal_entry_card.dart` — list row.
- `lib/features/reflection_journal/data/journal_prompts.dart` — curated prompt bank (const list of strings).
- `test/features/reflection_journal/journal_entry_model_test.dart`
- `test/features/reflection_journal/reflection_journal_screen_test.dart`

**Modified files:**
- `lib/app/routing/app_router.dart` — add `reflectionJournal`, `journalEntryCompose`, `journalEntryDetail` routes + imports.
- `lib/features/chat/presentation/screens/chat_couples_locked_screen.dart:170-181,357-362` — remove the `isHealingEligible` gate around `_ReflectionEntryCard`, point `onTap` at the new screen.

---

### Task 1: Database migration — tables, RLS, RPC functions

**Files:**
- Create: `supabase/migrations/20260813120000_reflection_journal.sql`

**Interfaces:**
- Produces: table `public.reflection_journal_entries` (columns: `id, user_id, content, prompt_used, tone, created_at, updated_at, deleted_at`), table `public.reflection_journal_analysis` (columns: `id, entry_id, user_id, status, tone, observation, confidence, input_hash, prompt_version, model_provider, model_name, created_at, updated_at`), RPC functions `create_journal_entry(p_content text, p_prompt_used text)` returns uuid, `update_journal_entry(p_entry_id uuid, p_content text)` returns void, `delete_journal_entry(p_entry_id uuid)` returns void, `upsert_journal_analysis(...)` returns uuid (service-role only, called from the edge function with the service key — not exposed to `authenticated`).

- [ ] **Step 1: Write the migration file**

```sql
-- Reflection Journal v1
-- Private, always-available, user-owned journal with AI-assisted (Gemini)
-- NVC-informed analysis. No relationship_id anywhere — this is explicitly
-- user-scoped only, unlike timeline_events/pulse_scores.

CREATE TABLE IF NOT EXISTS public.reflection_journal_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content text NOT NULL CHECK (char_length(content) > 0),
  prompt_used text,
  tone text CHECK (tone IN ('reflective', 'charged', 'settled', 'searching', 'hopeful', 'heavy')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS reflection_journal_entries_user_created_idx
  ON public.reflection_journal_entries(user_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.reflection_journal_analysis (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id uuid NOT NULL REFERENCES public.reflection_journal_entries(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'completed', 'insufficient_evidence', 'failed')),
  tone text CHECK (tone IN ('reflective', 'charged', 'settled', 'searching', 'hopeful', 'heavy')),
  observation text,
  confidence text CHECK (confidence IN ('high', 'medium', 'low', 'none')),
  input_hash text NOT NULL,
  prompt_version text NOT NULL,
  model_provider text NOT NULL,
  model_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (entry_id, input_hash)
);

CREATE INDEX IF NOT EXISTS reflection_journal_analysis_user_status_idx
  ON public.reflection_journal_analysis(user_id, status, created_at DESC);

DROP TRIGGER IF EXISTS set_reflection_journal_entries_updated_at ON public.reflection_journal_entries;
CREATE TRIGGER set_reflection_journal_entries_updated_at
BEFORE UPDATE ON public.reflection_journal_entries
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_reflection_journal_analysis_updated_at ON public.reflection_journal_analysis;
CREATE TRIGGER set_reflection_journal_analysis_updated_at
BEFORE UPDATE ON public.reflection_journal_analysis
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.reflection_journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reflection_journal_analysis ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.reflection_journal_entries FROM anon;
REVOKE ALL ON public.reflection_journal_analysis FROM anon, authenticated;

GRANT SELECT ON public.reflection_journal_entries TO authenticated;
GRANT SELECT ON public.reflection_journal_analysis TO authenticated;

DROP POLICY IF EXISTS "journal entries owner read" ON public.reflection_journal_entries;
CREATE POLICY "journal entries owner read"
ON public.reflection_journal_entries FOR SELECT
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "journal analysis owner read" ON public.reflection_journal_analysis;
CREATE POLICY "journal analysis owner read"
ON public.reflection_journal_analysis FOR SELECT
USING (user_id = auth.uid());

-- Writes go through SECURITY DEFINER RPCs only (mirrors healing_journeys),
-- so the client never inserts/updates these tables directly.

CREATE OR REPLACE FUNCTION public.create_journal_entry(
  p_content text,
  p_prompt_used text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_entry_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) = 0 THEN
    RAISE EXCEPTION 'content_required' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.reflection_journal_entries (user_id, content, prompt_used)
  VALUES (v_user_id, p_content, p_prompt_used)
  RETURNING id INTO v_entry_id;

  RETURN v_entry_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_journal_entry(
  p_entry_id uuid,
  p_content text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) = 0 THEN
    RAISE EXCEPTION 'content_required' USING ERRCODE = '22023';
  END IF;

  UPDATE public.reflection_journal_entries
  SET content = p_content,
      tone = NULL
  WHERE id = p_entry_id
    AND user_id = v_user_id
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'entry_not_found' USING ERRCODE = '22023';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_journal_entry(
  p_entry_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;

  UPDATE public.reflection_journal_entries
  SET deleted_at = now()
  WHERE id = p_entry_id
    AND user_id = v_user_id
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'entry_not_found' USING ERRCODE = '22023';
  END IF;
END;
$$;

-- Service-role only: called from the analyse-journal-entry edge function
-- with the service key, never from the Flutter client.
CREATE OR REPLACE FUNCTION public.upsert_journal_analysis(
  p_entry_id uuid,
  p_user_id uuid,
  p_status text,
  p_tone text,
  p_observation text,
  p_confidence text,
  p_input_hash text,
  p_prompt_version text,
  p_model_provider text,
  p_model_name text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_status NOT IN ('pending', 'completed', 'insufficient_evidence', 'failed') THEN
    RAISE EXCEPTION 'invalid_status' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.reflection_journal_analysis (
    entry_id, user_id, status, tone, observation, confidence,
    input_hash, prompt_version, model_provider, model_name
  ) VALUES (
    p_entry_id, p_user_id, p_status, p_tone, p_observation, p_confidence,
    p_input_hash, p_prompt_version, p_model_provider, p_model_name
  )
  ON CONFLICT (entry_id, input_hash) DO UPDATE
  SET status = EXCLUDED.status,
      tone = EXCLUDED.tone,
      observation = EXCLUDED.observation,
      confidence = EXCLUDED.confidence
  RETURNING id INTO v_id;

  UPDATE public.reflection_journal_entries
  SET tone = COALESCE(p_tone, tone)
  WHERE id = p_entry_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_journal_entry(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_journal_entry(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_journal_entry(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_journal_analysis(uuid, uuid, text, text, text, text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_journal_entry(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_journal_entry(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_journal_entry(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_journal_analysis(uuid, uuid, text, text, text, text, text, text, text, text) TO service_role;
```

- [ ] **Step 2: Deploy the migration**

Run: `cd /Users/user/attune && supabase db push`
Expected: migration `20260813120000_reflection_journal.sql` applied with no errors.

- [ ] **Step 3: Manually verify RLS via SQL editor or psql**

Run (as two different authenticated test users, or via the Supabase SQL editor using `set local role authenticated; set local "request.jwt.claims" = '{"sub":"<user-a-uuid>"}';`):
```sql
select public.create_journal_entry('test entry', null);
-- as user A, this should return the new row:
select * from public.reflection_journal_entries where user_id = '<user-a-uuid>';
-- as user B, this should return zero rows:
select * from public.reflection_journal_entries where user_id = '<user-a-uuid>';
```
Expected: user B's `SELECT` (going through RLS as `authenticated`, not `service_role`) returns 0 rows for user A's entry.

- [ ] **Step 4: Manually verify edit invalidates analysis (spec §10 requirement)**

This proves the `input_hash` mechanism: editing an entry's content must not return the old entry's analysis for the new content. Run as the service role (SQL editor with service key, or via `psql` connected with the service role):

```sql
-- Create an entry and simulate a completed analysis for its original content:
select public.create_journal_entry('This is my original entry content for testing the hash flow.', null) as entry_id \gset
select public.upsert_journal_analysis(
  :'entry_id'::uuid, '<the-user-id>'::uuid, 'completed', 'reflective',
  'This is the original observation.', 'medium',
  encode(digest('This is my original entry content for testing the hash flow.', 'sha256'), 'hex'),
  '1.0.0', 'google', 'gemini-1.5-flash'
);

-- Edit the entry's content (new input_hash):
select public.update_journal_entry(:'entry_id'::uuid, 'This is completely different edited content now.');

-- Confirm the OLD analysis row still exists (history preserved) but is no
-- longer the one a fresh input_hash lookup for the NEW content would match:
select input_hash, observation from public.reflection_journal_analysis where entry_id = :'entry_id'::uuid;
-- Expected: exactly one row, from the original content's hash — the new
-- content's hash has no matching row yet (analysis is regenerated only when
-- analyse-journal-entry is called again, per Task 4's flow).
select tone from public.reflection_journal_entries where id = :'entry_id'::uuid;
-- Expected: NULL — update_journal_entry clears tone on every content edit.
```
Expected: the analysis lookup for the new content's hash finds nothing (proving the old analysis is never served for edited content), and the entry's own `tone` column was cleared by the edit.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260813120000_reflection_journal.sql
git commit -m "feat(reflection-journal): add DB schema, RLS, and RPC functions"
```

---

### Task 2: `_shared/gemini_json.ts` helper

**Files:**
- Create: `supabase/functions/_shared/gemini_json.ts`
- Create: `supabase/functions/_shared/gemini_json.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `callGeminiJson(params: { promptId: string; systemPrompt: string; userPrompt: string; maxOutputTokens: number; runtimeProhibitedPatterns?: RegExp[] }): Promise<Record<string, unknown> | null>` — same signature shape as `callClaudeJson` in `_shared/claude_json.ts` (system+user prompt in, parsed-and-validated JSON object or `null` out). Also exports `STATIC_PROHIBITED_PATTERNS: RegExp[]` (re-exported, same list as `claude_json.ts`) for reuse by the edge function's own extra patterns, and `escapeRegex` is NOT re-exported (internal only, unused outside this file for this feature).

- [ ] **Step 1: Write the failing test for prohibited-pattern detection and malformed JSON**

```typescript
// supabase/functions/_shared/gemini_json.test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { STATIC_PROHIBITED_PATTERNS } from "./gemini_json.ts";

Deno.test("STATIC_PROHIBITED_PATTERNS: flags banned diagnostic words", () => {
  const text = '{"observation":"this pattern seems toxic"}';
  const hit = STATIC_PROHIBITED_PATTERNS.some((p) => p.test(text));
  assertEquals(hit, true);
});

Deno.test("STATIC_PROHIBITED_PATTERNS: flags partner-directed always/never framing", () => {
  const text = '{"observation":"your partner always dismisses you"}';
  const hit = STATIC_PROHIBITED_PATTERNS.some((p) => p.test(text));
  assertEquals(hit, true);
});

Deno.test("STATIC_PROHIBITED_PATTERNS: allows neutral, sourced language", () => {
  const text = '{"observation":"you described this using always/never terms"}';
  const hit = STATIC_PROHIBITED_PATTERNS.some((p) => p.test(text));
  assertEquals(hit, false);
});

Deno.test("callGeminiJson: returns null when GEMINI_API_KEY is missing", async () => {
  const original = Deno.env.get("GEMINI_API_KEY");
  Deno.env.delete("GEMINI_API_KEY");
  try {
    const { callGeminiJson } = await import("./gemini_json.ts?no-key-test");
    const result = await callGeminiJson({
      promptId: "test",
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 100,
    });
    assertEquals(result, null);
  } finally {
    if (original) Deno.env.set("GEMINI_API_KEY", original);
  }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/user/attune/supabase/functions/_shared && deno test gemini_json.test.ts`
Expected: FAIL — `gemini_json.ts` does not exist yet (module not found).

- [ ] **Step 3: Write the implementation**

```typescript
// supabase/functions/_shared/gemini_json.ts
const DEFAULT_MODEL = "gemini-1.5-flash";
const GEMINI_URL_BASE =
  "https://generativelanguage.googleapis.com/v1beta/models";

export const STATIC_PROHIBITED_PATTERNS = [
  /your partner (always|never|tends to|keeps)/i,
  /\b(toxic|narcissist|codependent|disorder|broken)\b/i,
  /you should (leave|stay|break up|end|tell|confront|ask)/i,
  /this relationship is/i,
  /\bviolation\b/i,
];

export async function callGeminiJson(params: {
  promptId: string;
  systemPrompt: string;
  userPrompt: string;
  maxOutputTokens: number;
  runtimeProhibitedPatterns?: RegExp[];
}): Promise<Record<string, unknown> | null> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    console.error("gemini_missing_api_key", { prompt_id: params.promptId });
    return null;
  }

  const model = Deno.env.get("GEMINI_MODEL") ?? DEFAULT_MODEL;
  const url = `${GEMINI_URL_BASE}/${model}:generateContent?key=${apiKey}`;

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          { role: "user", parts: [{ text: params.userPrompt }] },
        ],
        systemInstruction: {
          parts: [{ text: params.systemPrompt }],
        },
        generationConfig: {
          maxOutputTokens: params.maxOutputTokens,
          responseMimeType: "application/json",
        },
      }),
      signal: AbortSignal.timeout(10000),
    });

    if (!response.ok) {
      console.error("gemini_http_error", {
        prompt_id: params.promptId,
        status: response.status,
      });
      return null;
    }

    const payload = await response.json();
    const text = payload?.candidates?.[0]?.content?.parts
      ?.map((part: { text?: string }) =>
        typeof part?.text === "string" ? part.text : ""
      )
      .join("") ?? "";

    const parsed = JSON.parse(text.replace(/```json|```/g, "").trim());
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      console.error("gemini_shape_invalid", { prompt_id: params.promptId });
      return null;
    }

    const outputText = JSON.stringify(parsed);
    for (const pattern of [
      ...STATIC_PROHIBITED_PATTERNS,
      ...(params.runtimeProhibitedPatterns ?? []),
    ]) {
      if (pattern.test(outputText)) {
        console.error("prohibited_pattern_detected", {
          prompt_id: params.promptId,
          pattern: pattern.source,
        });
        return null;
      }
    }

    return parsed as Record<string, unknown>;
  } catch {
    console.error("gemini_parse_failed", { prompt_id: params.promptId });
    return null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/user/attune/supabase/functions/_shared && deno test gemini_json.test.ts`
Expected: PASS, 4/4 tests.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/gemini_json.ts supabase/functions/_shared/gemini_json.test.ts
git commit -m "feat(reflection-journal): add Gemini JSON helper with safety patterns"
```

---

### Task 3: Curated prompt bank

**Files:**
- Create: `lib/features/reflection_journal/data/journal_prompts.dart`
- Test: `test/features/reflection_journal/journal_prompts_test.dart`

**Interfaces:**
- Produces: `const List<String> journalPrompts` (top-level const, ≥30 entries), `String randomJournalPrompt({int? seed})` — returns one prompt, `seed` param exists purely to make the function deterministic in tests (uses `Random(seed)` when provided, `Random()` otherwise).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/reflection_journal/journal_prompts_test.dart
import 'package:attune/features/reflection_journal/data/journal_prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('journalPrompts has at least 30 entries, all non-empty and unique', () {
    expect(journalPrompts.length, greaterThanOrEqualTo(30));
    expect(journalPrompts.toSet().length, journalPrompts.length);
    for (final prompt in journalPrompts) {
      expect(prompt.trim(), isNotEmpty);
    }
  });

  test('no prompt is a yes/no question', () {
    for (final prompt in journalPrompts) {
      final lower = prompt.toLowerCase();
      final startsYesNo = lower.startsWith('did ') ||
          lower.startsWith('do you ') ||
          lower.startsWith('are you ') ||
          lower.startsWith('is ') ||
          lower.startsWith('was ');
      expect(startsYesNo, isFalse, reason: 'yes/no-shaped: $prompt');
    }
  });

  test('randomJournalPrompt with a fixed seed is deterministic', () {
    final a = randomJournalPrompt(seed: 42);
    final b = randomJournalPrompt(seed: 42);
    expect(a, b);
    expect(journalPrompts, contains(a));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/reflection_journal/journal_prompts_test.dart`
Expected: FAIL — `journal_prompts.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/reflection_journal/data/journal_prompts.dart
import 'dart:math';

/// Curated, hand-written prompt bank for the Reflection Journal's optional
/// daily inspiration banner. Rules (per design spec §4): concrete and
/// moment-anchored, never abstract; open-ended, never yes/no; never
/// therapy-coded.
const List<String> journalPrompts = [
  "What's one thing that surprised you today?",
  "What moment today do you want to remember?",
  "What's taking up the most space in your mind right now?",
  "What did you notice about how you reacted to something today?",
  "What's something you didn't say out loud today, but wish you had?",
  "What made today feel different from yesterday?",
  "What's a conversation that's still sitting with you?",
  "What's something small that went well today?",
  "What are you carrying into tomorrow?",
  "What did you learn about yourself this week?",
  "What's something you noticed but didn't act on?",
  "What's a feeling you had today that you haven't named yet?",
  "What's something you're avoiding thinking about?",
  "What's one thing you'd tell yourself from this morning?",
  "What's changed in how you see things lately?",
  "What's something you did today that felt like you?",
  "What's a moment today when you felt most like yourself?",
  "What's something you're still figuring out?",
  "What's a pattern you've noticed in yourself this month?",
  "What's something you wish someone had asked you today?",
  "What's a decision you made today, and how did it feel?",
  "What's something you're proud of that no one else noticed?",
  "What's weighing on you that you haven't written down yet?",
  "What's a memory that came up unexpectedly today?",
  "What's something you needed today that you didn't get?",
  "What's a boundary you held, or wish you had?",
  "What's something you're curious about in yourself right now?",
  "What's a moment today you'd like to understand better?",
  "What's something that felt harder than it should have today?",
  "What's a small thing that brought you comfort today?",
  "What's something you're ready to let go of?",
  "What's a question you keep circling back to?",
];

/// [seed] makes the pick deterministic for tests; omit it in production
/// callers to get a real random pick each time.
String randomJournalPrompt({int? seed}) {
  final random = seed == null ? Random() : Random(seed);
  return journalPrompts[random.nextInt(journalPrompts.length)];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/reflection_journal/journal_prompts_test.dart`
Expected: PASS, 3/3 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/reflection_journal/data/journal_prompts.dart test/features/reflection_journal/journal_prompts_test.dart
git commit -m "feat(reflection-journal): add curated daily prompt bank"
```

---

### Task 4: `analyse-journal-entry` edge function

**Files:**
- Create: `supabase/functions/analyse-journal-entry/index.ts`

**Interfaces:**
- Consumes: `callGeminiJson` and `STATIC_PROHIBITED_PATTERNS` from `_shared/gemini_json.ts` (Task 2); RPC `upsert_journal_analysis` from Task 1's migration.
- Produces: an HTTP endpoint accepting `POST { action: "analyse_entry", entry_id: string }` → `{ status: "pending" | "completed" | "insufficient_evidence" | "failed", tone: string | null, observation: string | null, confidence: string | null }`, and `POST { action: "get_patterns" }` → `{ status: "completed" | "insufficient_evidence", summary: string | null, entry_count: number }`.

- [ ] **Step 1: Write the implementation**

```typescript
// supabase/functions/analyse-journal-entry/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callGeminiJson, STATIC_PROHIBITED_PATTERNS } from "../_shared/gemini_json.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MODEL_PROVIDER = "google";
const MODEL_NAME = Deno.env.get("GEMINI_MODEL") ?? "gemini-1.5-flash";
const PROMPT_VERSION = "1.0.0";
const MIN_WORDS_FOR_ANALYSIS = 15;
const MIN_ENTRIES_FOR_PATTERNS = 3;
const MAX_ENTRIES_FOR_PATTERNS = 20;

const RUNTIME_PATTERNS = [
  /you should (tell|confront|ask|leave)/i,
];

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "missing_authorization" }, 401);
    }

    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      return json({ error: "authentication_required" }, 401);
    }

    const body = await req.json();
    if (body.action === "get_patterns") {
      return await handleGetPatterns(adminClient, user.id);
    }
    if (body.action === "analyse_entry") {
      return await handleAnalyseEntry(userClient, adminClient, user.id, body.entry_id);
    }
    return json({ error: "unknown_action" }, 400);
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

async function handleAnalyseEntry(
  userClient: any,
  adminClient: any,
  userId: string,
  entryId: string,
) {
  if (!entryId) {
    return json({ error: "entry_id_required" }, 400);
  }

  const entryRes = await userClient
    .from("reflection_journal_entries")
    .select("id, content")
    .eq("id", entryId)
    .is("deleted_at", null)
    .single();
  if (entryRes.error || !entryRes.data) {
    return json({ error: "entry_not_found" }, 404);
  }

  const content: string = entryRes.data.content;
  const inputHash = await sha256(content);

  const existing = await adminClient
    .from("reflection_journal_analysis")
    .select("status, tone, observation, confidence")
    .eq("entry_id", entryId)
    .eq("input_hash", inputHash)
    .eq("status", "completed")
    .maybeSingle();
  if (existing.data) {
    return json({ status: "completed", ...existing.data });
  }

  const wordCount = content.trim().split(/\s+/).filter(Boolean).length;
  if (wordCount < MIN_WORDS_FOR_ANALYSIS) {
    await adminClient.rpc("upsert_journal_analysis", {
      p_entry_id: entryId,
      p_user_id: userId,
      p_status: "insufficient_evidence",
      p_tone: null,
      p_observation: null,
      p_confidence: "none",
      p_input_hash: inputHash,
      p_prompt_version: PROMPT_VERSION,
      p_model_provider: MODEL_PROVIDER,
      p_model_name: MODEL_NAME,
    });
    return json({
      status: "insufficient_evidence",
      tone: null,
      observation: null,
      confidence: "none",
    });
  }

  let output = await maybeGenerate(content);
  if (!output) {
    output = buildFallback();
  }

  validateOutput(output);
  await adminClient.rpc("upsert_journal_analysis", {
    p_entry_id: entryId,
    p_user_id: userId,
    p_status: "completed",
    p_tone: output.tone,
    p_observation: output.observation,
    p_confidence: output.confidence,
    p_input_hash: inputHash,
    p_prompt_version: PROMPT_VERSION,
    p_model_provider: MODEL_PROVIDER,
    p_model_name: MODEL_NAME,
  });

  return json({ status: "completed", ...output });
}

async function handleGetPatterns(adminClient: any, userId: string) {
  const rows = await adminClient
    .from("reflection_journal_analysis")
    .select("observation, tone, created_at")
    .eq("user_id", userId)
    .eq("status", "completed")
    .order("created_at", { ascending: false })
    .limit(MAX_ENTRIES_FOR_PATTERNS);

  const analyses = rows.data ?? [];
  if (analyses.length < MIN_ENTRIES_FOR_PATTERNS) {
    return json({
      status: "insufficient_evidence",
      summary: null,
      entry_count: analyses.length,
    });
  }

  const prompt = buildPatternsPrompt(analyses);
  const result = await callGeminiJson({
    promptId: "journal_patterns",
    systemPrompt: patternsSystemPrompt(),
    userPrompt: prompt,
    maxOutputTokens: 220,
    runtimeProhibitedPatterns: RUNTIME_PATTERNS,
  });

  const summary = typeof result?.summary === "string"
    ? result.summary
    : `Across ${analyses.length} entries, a few recurring tones and themes have shown up in what you've written.`;

  return json({
    status: "completed",
    summary,
    entry_count: analyses.length,
  });
}

function globalConstraintHeader() {
  return [
    "Return ONLY valid JSON, no markdown fences, no commentary.",
    "Never use the words: toxic, narcissist, codependent, disorder, broken.",
    "Never use the word 'violation'.",
    "Never tell the user what to decide about their relationship or their life.",
    "Never attribute always/never behavior to a partner.",
    "Never suggest what the user should say, ask, tell, or confront someone with — this is a private diary with no addressee.",
    "Every claim must be sourced to the user's own words — never invent detail.",
  ].join(" ");
}

function analysisSystemPrompt() {
  return [
    globalConstraintHeader(),
    "You are a wise, attentive friend reading a private journal entry — never clinical, never therapy-coded.",
    "Analyse using only Observation, Feeling, and Need (NVC). Do not include a Request component directed at anyone else.",
    "If you offer a closing thought, it must be inward-facing (what might help the writer, not what they should say to someone).",
    "Confidence must never be 'high' for anything NVC-derived — cap at 'medium'.",
    'Schema: {"tone": one of "reflective"|"charged"|"settled"|"searching"|"hopeful"|"heavy", "observation": string, "confidence": "medium"|"low"}',
  ].join(" ");
}

function patternsSystemPrompt() {
  return [
    globalConstraintHeader(),
    "You are summarizing recurring themes across several private journal entries for the person who wrote them, in a warm, sourced, dated way.",
    'Schema: {"summary": string}',
  ].join(" ");
}

function buildAnalysisPrompt(content: string) {
  return `ENTRY:\n${content}`;
}

function buildPatternsPrompt(analyses: Array<{ observation: string; tone: string | null; created_at: string }>) {
  return `PAST ANALYSES (most recent first):\n${JSON.stringify(analyses)}`;
}

async function maybeGenerate(content: string) {
  const result = await callGeminiJson({
    promptId: "journal_entry_analysis",
    systemPrompt: analysisSystemPrompt(),
    userPrompt: buildAnalysisPrompt(content),
    maxOutputTokens: 220,
    runtimeProhibitedPatterns: RUNTIME_PATTERNS,
  });
  if (!result) return null;

  const validTones = ["reflective", "charged", "settled", "searching", "hopeful", "heavy"];
  const tone = typeof result.tone === "string" && validTones.includes(result.tone)
    ? result.tone
    : "reflective";
  const confidence = result.confidence === "low" ? "low" : "medium";
  const observation = typeof result.observation === "string" ? result.observation : null;
  if (!observation) return null;

  return { tone, observation, confidence };
}

function buildFallback() {
  return {
    tone: "reflective" as const,
    observation:
      "Thank you for writing this down. Sometimes just putting words to something is the reflection itself.",
    confidence: "low" as const,
  };
}

function validateOutput(output: { tone: string; observation: string; confidence: string }) {
  if (!output || typeof output !== "object") {
    throw new Error("invalid_output");
  }
  const outputText = JSON.stringify(output);
  for (const pattern of [...STATIC_PROHIBITED_PATTERNS, ...RUNTIME_PATTERNS]) {
    if (pattern.test(outputText)) {
      throw new Error("prohibited_pattern_in_output");
    }
  }
}

async function sha256(input: string) {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
```

- [ ] **Step 2: Type-check with Deno**

Run: `cd /Users/user/attune/supabase/functions/analyse-journal-entry && deno check index.ts`
Expected: no type errors.

- [ ] **Step 3: Deploy the function**

Run: `cd /Users/user/attune && supabase functions deploy analyse-journal-entry`
Expected: deploy succeeds.

- [ ] **Step 4: Provision the GEMINI_API_KEY secret if not already set**

Run: `supabase secrets list | grep GEMINI_API_KEY`
Expected: if missing, this is a deployment prerequisite — stop and get a Gemini API key from the user before continuing, then run `supabase secrets set GEMINI_API_KEY=<key>`. The function's own `callGeminiJson` already fails soft (returns `null` → fallback path) if this is absent, so a missing key degrades to fallback observations rather than breaking the feature, but real analysis requires the key.

- [ ] **Step 5: Manual smoke test**

Run (replace `<user-jwt>` and `<entry-id>` from a real signed-in session and an entry created via Task 1's `create_journal_entry` RPC):
```bash
curl -s -X POST "https://<project-ref>.supabase.co/functions/v1/analyse-journal-entry" \
  -H "Authorization: Bearer <user-jwt>" \
  -H "Content-Type: application/json" \
  -d '{"action":"analyse_entry","entry_id":"<entry-id>"}'
```
Expected: JSON response with `status: "completed"` (or `insufficient_evidence` for a short entry) and no raw error leaking to the client.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/analyse-journal-entry/index.ts
git commit -m "feat(reflection-journal): add analyse-journal-entry edge function"
```

---

### Task 5: Flutter data layer — models and repository

**Files:**
- Create: `lib/features/reflection_journal/data/models/journal_entry.dart`
- Create: `lib/features/reflection_journal/data/models/journal_analysis.dart`
- Create: `lib/features/reflection_journal/data/repositories/reflection_journal_repository.dart`
- Test: `test/features/reflection_journal/journal_entry_model_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks directly (talks to Supabase tables/RPCs/edge function created in Tasks 1 and 4 at runtime, not compile time).
- Produces: `JournalEntry` (fields: `id, userId, content, promptUsed, tone, createdAt, updatedAt`, factory `fromJson`), `JournalAnalysis` (fields: `status, tone, observation, confidence`, factory `fromJson`), `ReflectionJournalRepository` with methods: `Future<List<JournalEntry>> getEntries()`, `Future<JournalEntry> getEntry(String entryId)`, `Future<String> createEntry({required String content, String? promptUsed})` returns new entry id, `Future<void> updateEntry({required String entryId, required String content})`, `Future<void> deleteEntry(String entryId)`, `Future<JournalAnalysis> analyseEntry(String entryId)`, `Future<({String status, String? summary, int entryCount})> getPatterns()`.

- [ ] **Step 1: Write the failing test for the models**

```dart
// test/features/reflection_journal/journal_entry_model_test.dart
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JournalEntry.fromJson parses all fields', () {
    final entry = JournalEntry.fromJson({
      'id': 'entry-1',
      'user_id': 'user-1',
      'content': 'Today was hard.',
      'prompt_used': "What's one thing that surprised you today?",
      'tone': 'heavy',
      'created_at': '2026-08-01T10:00:00Z',
      'updated_at': '2026-08-01T10:00:00Z',
    });

    expect(entry.id, 'entry-1');
    expect(entry.userId, 'user-1');
    expect(entry.content, 'Today was hard.');
    expect(entry.promptUsed, "What's one thing that surprised you today?");
    expect(entry.tone, 'heavy');
    expect(entry.createdAt, DateTime.parse('2026-08-01T10:00:00Z'));
  });

  test('JournalEntry.fromJson handles null prompt_used and tone', () {
    final entry = JournalEntry.fromJson({
      'id': 'entry-2',
      'user_id': 'user-1',
      'content': 'Quick note.',
      'prompt_used': null,
      'tone': null,
      'created_at': '2026-08-01T10:00:00Z',
      'updated_at': '2026-08-01T10:00:00Z',
    });

    expect(entry.promptUsed, isNull);
    expect(entry.tone, isNull);
  });

  test('JournalAnalysis.fromJson parses a completed analysis', () {
    final analysis = JournalAnalysis.fromJson({
      'status': 'completed',
      'tone': 'reflective',
      'observation': 'You described feeling unheard in this entry.',
      'confidence': 'medium',
    });

    expect(analysis.status, 'completed');
    expect(analysis.tone, 'reflective');
    expect(analysis.observation, 'You described feeling unheard in this entry.');
    expect(analysis.confidence, 'medium');
    expect(analysis.isComplete, isTrue);
  });

  test('JournalAnalysis.fromJson handles insufficient_evidence with nulls', () {
    final analysis = JournalAnalysis.fromJson({
      'status': 'insufficient_evidence',
      'tone': null,
      'observation': null,
      'confidence': 'none',
    });

    expect(analysis.isComplete, isFalse);
    expect(analysis.observation, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/reflection_journal/journal_entry_model_test.dart`
Expected: FAIL — model files do not exist.

- [ ] **Step 3: Write the model implementations**

```dart
// lib/features/reflection_journal/data/models/journal_entry.dart
import 'package:equatable/equatable.dart';

class JournalEntry extends Equatable {
  final String id;
  final String userId;
  final String content;
  final String? promptUsed;
  final String? tone;
  final DateTime createdAt;
  final DateTime updatedAt;

  const JournalEntry({
    required this.id,
    required this.userId,
    required this.content,
    this.promptUsed,
    this.tone,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    return JournalEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String,
      promptUsed: json['prompt_used'] as String?,
      tone: json['tone'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, userId, content, tone, createdAt, updatedAt];
}
```

```dart
// lib/features/reflection_journal/data/models/journal_analysis.dart
import 'package:equatable/equatable.dart';

class JournalAnalysis extends Equatable {
  final String status; // 'pending' | 'completed' | 'insufficient_evidence' | 'failed'
  final String? tone;
  final String? observation;
  final String? confidence; // 'high' | 'medium' | 'low' | 'none'

  const JournalAnalysis({
    required this.status,
    this.tone,
    this.observation,
    this.confidence,
  });

  factory JournalAnalysis.fromJson(Map<String, dynamic> json) {
    return JournalAnalysis(
      status: json['status'] as String,
      tone: json['tone'] as String?,
      observation: json['observation'] as String?,
      confidence: json['confidence'] as String?,
    );
  }

  bool get isComplete => status == 'completed';
  bool get isPending => status == 'pending';
  bool get isInsufficientEvidence => status == 'insufficient_evidence';

  @override
  List<Object?> get props => [status, tone, observation, confidence];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/reflection_journal/journal_entry_model_test.dart`
Expected: PASS, 4/4 tests.

- [ ] **Step 5: Write the repository (no separate test — thin Supabase-call wrapper, exercised via Task 7's screen test using a fake)**

```dart
// lib/features/reflection_journal/data/repositories/reflection_journal_repository.dart
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReflectionJournalRepository {
  ReflectionJournalRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<List<JournalEntry>> getEntries() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _supabase
        .from('reflection_journal_entries')
        .select('*')
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => JournalEntry.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<JournalEntry> getEntry(String entryId) async {
    final response = await _supabase
        .from('reflection_journal_entries')
        .select('*')
        .eq('id', entryId)
        .single();

    return JournalEntry.fromJson(response);
  }

  Future<String> createEntry({
    required String content,
    String? promptUsed,
  }) async {
    final entryId = await _supabase.rpc(
      'create_journal_entry',
      params: {'p_content': content, 'p_prompt_used': promptUsed},
    );
    return entryId as String;
  }

  Future<void> updateEntry({
    required String entryId,
    required String content,
  }) async {
    await _supabase.rpc(
      'update_journal_entry',
      params: {'p_entry_id': entryId, 'p_content': content},
    );
  }

  Future<void> deleteEntry(String entryId) async {
    await _supabase.rpc(
      'delete_journal_entry',
      params: {'p_entry_id': entryId},
    );
  }

  Future<JournalAnalysis> analyseEntry(String entryId) async {
    final response = await _supabase.functions.invoke(
      'analyse-journal-entry',
      body: {'action': 'analyse_entry', 'entry_id': entryId},
    );
    return JournalAnalysis.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<({String status, String? summary, int entryCount})>
  getPatterns() async {
    final response = await _supabase.functions.invoke(
      'analyse-journal-entry',
      body: {'action': 'get_patterns'},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return (
      status: data['status'] as String,
      summary: data['summary'] as String?,
      entryCount: data['entry_count'] as int? ?? 0,
    );
  }
}
```

- [ ] **Step 6: Run `flutter analyze` on the new files**

Run: `cd /Users/user/attune && flutter analyze lib/features/reflection_journal`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/features/reflection_journal/data
git add test/features/reflection_journal/journal_entry_model_test.dart
git commit -m "feat(reflection-journal): add Flutter data models and repository"
```

---

### Task 6: Riverpod providers

**Files:**
- Create: `lib/features/reflection_journal/presentation/providers/reflection_journal_providers.dart`

**Interfaces:**
- Consumes: `ReflectionJournalRepository`, `JournalEntry`, `JournalAnalysis` from Task 5; `supabaseClientProvider` from `lib/features/healing/presentation/providers/healing_providers.dart` (already defined there — reuse it, do not redefine).
- Produces: `reflectionJournalRepositoryProvider` (`Provider<ReflectionJournalRepository>`), `journalEntriesProvider` (`FutureProvider<List<JournalEntry>>`), `journalEntryProvider` (`FutureProvider.family<JournalEntry, String>` keyed by entry id), `journalPatternsProvider` (`FutureProvider<({String status, String? summary, int entryCount})>`), `createJournalEntryProvider` (`FutureProvider.family<String, ({String content, String? promptUsed})>`), `updateJournalEntryProvider` (`FutureProvider.family<void, ({String entryId, String content})>`), `deleteJournalEntryProvider` (`FutureProvider.family<void, String>`), `analyseJournalEntryProvider` (`FutureProvider.family<JournalAnalysis, String>` keyed by entry id).

- [ ] **Step 1: Write the implementation**

```dart
// lib/features/reflection_journal/presentation/providers/reflection_journal_providers.dart
import 'package:attune/features/healing/presentation/providers/healing_providers.dart'
    show supabaseClientProvider;
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/data/repositories/reflection_journal_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reflectionJournalRepositoryProvider =
    Provider<ReflectionJournalRepository>((ref) {
      return ReflectionJournalRepository(ref.read(supabaseClientProvider));
    });

final journalEntriesProvider = FutureProvider<List<JournalEntry>>((
  ref,
) async {
  return ref.read(reflectionJournalRepositoryProvider).getEntries();
});

final journalEntryProvider = FutureProvider.family<JournalEntry, String>((
  ref,
  entryId,
) async {
  return ref.read(reflectionJournalRepositoryProvider).getEntry(entryId);
});

final journalPatternsProvider =
    FutureProvider<({String status, String? summary, int entryCount})>((
      ref,
    ) async {
      return ref.read(reflectionJournalRepositoryProvider).getPatterns();
    });

final createJournalEntryProvider = FutureProvider.family<
  String,
  ({String content, String? promptUsed})
>((ref, params) async {
  final entryId = await ref
      .read(reflectionJournalRepositoryProvider)
      .createEntry(content: params.content, promptUsed: params.promptUsed);
  ref.invalidate(journalEntriesProvider);
  return entryId;
});

final updateJournalEntryProvider =
    FutureProvider.family<void, ({String entryId, String content})>((
      ref,
      params,
    ) async {
      await ref
          .read(reflectionJournalRepositoryProvider)
          .updateEntry(entryId: params.entryId, content: params.content);
      ref.invalidate(journalEntriesProvider);
      ref.invalidate(journalEntryProvider(params.entryId));
    });

final deleteJournalEntryProvider = FutureProvider.family<void, String>((
  ref,
  entryId,
) async {
  await ref.read(reflectionJournalRepositoryProvider).deleteEntry(entryId);
  ref.invalidate(journalEntriesProvider);
});

final analyseJournalEntryProvider =
    FutureProvider.family<JournalAnalysis, String>((ref, entryId) async {
      final analysis = await ref
          .read(reflectionJournalRepositoryProvider)
          .analyseEntry(entryId);
      ref.invalidate(journalEntryProvider(entryId));
      return analysis;
    });
```

- [ ] **Step 2: Run `flutter analyze`**

Run: `cd /Users/user/attune && flutter analyze lib/features/reflection_journal`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/reflection_journal/presentation/providers
git commit -m "feat(reflection-journal): add Riverpod providers"
```

---

### Task 7: Screens — journal list/patterns, compose, detail

**Files:**
- Create: `lib/features/reflection_journal/presentation/widgets/journal_entry_card.dart`
- Create: `lib/features/reflection_journal/presentation/screens/reflection_journal_screen.dart`
- Create: `lib/features/reflection_journal/presentation/screens/journal_entry_compose_screen.dart`
- Create: `lib/features/reflection_journal/presentation/screens/journal_entry_detail_screen.dart`
- Test: `test/features/reflection_journal/reflection_journal_screen_test.dart`

**Interfaces:**
- Consumes: `journalEntriesProvider`, `journalPatternsProvider`, `createJournalEntryProvider`, `updateJournalEntryProvider`, `deleteJournalEntryProvider`, `analyseJournalEntryProvider`, `journalEntryProvider` (Task 6); `JournalEntry`, `JournalAnalysis` (Task 5); `randomJournalPrompt`, `journalPrompts` (Task 3); app-wide `AppButton` (`lib/core/widgets/buttons/app_button.dart`, params: `label`, `onPressed`, `variant`, `size`, `width`, `prefixIcon`), `EmptyStateWidget` (`lib/core/widgets/feedback/empty_state.dart`, params: `icon`, `title`, `subtitle`, `actionLabel`, `onAction`), `CardInkWell`/`InfoRowWidget` (`lib/core/widgets/card_inkwell.dart`, `lib/core/widgets/info_row_widget.dart`).
- Produces: `ReflectionJournalScreen` (`ConsumerStatefulWidget`, no constructor args), `JournalEntryComposeScreen` (`ConsumerStatefulWidget`, optional `entryId` param for edit mode — `const JournalEntryComposeScreen({super.key, this.entryId})`), `JournalEntryDetailScreen` (`ConsumerWidget`, `required String entryId`), `JournalEntryCard` (`StatelessWidget`, `required JournalEntry entry, required VoidCallback onTap`).

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/reflection_journal/reflection_journal_screen_test.dart
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reflection_journal/presentation/screens/reflection_journal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(List<Override> overrides) {
    return ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: ReflectionJournalScreen()),
    );
  }

  testWidgets('shows empty state when there are no entries', (tester) async {
    await tester.pumpWidget(
      wrap([
        journalEntriesProvider.overrideWith((ref) async => []),
        journalPatternsProvider.overrideWith(
          (ref) async => (status: 'insufficient_evidence', summary: null, entryCount: 0),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Write'), findsWidgets);
  });

  testWidgets('shows entry cards when entries are present', (tester) async {
    final entry = JournalEntryFixture.one();
    await tester.pumpWidget(
      wrap([
        journalEntriesProvider.overrideWith((ref) async => [entry]),
        journalPatternsProvider.overrideWith(
          (ref) async => (status: 'insufficient_evidence', summary: null, entryCount: 1),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text(entry.content), findsOneWidget);
  });

  testWidgets('patterns tab shows not-enough-entries state below threshold', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap([
        journalEntriesProvider.overrideWith((ref) async => []),
        journalPatternsProvider.overrideWith(
          (ref) async => (status: 'insufficient_evidence', summary: null, entryCount: 1),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Patterns'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not enough entries'), findsOneWidget);
  });
}

class JournalEntryFixture {
  static one() {
    return _fixtureEntry;
  }
}

final _fixtureEntry = _buildEntry();

_buildEntry() {
  return (
    id: 'entry-1',
    content: 'Today I noticed I felt calmer than usual.',
  );
}
```

Note for the implementer: the fixture above is intentionally minimal scaffolding — replace `_buildEntry()`'s return with an actual `JournalEntry(...)` construction once you're writing this step (import `JournalEntry` from `lib/features/reflection_journal/data/models/journal_entry.dart` and fill in all required fields with fixed test values, e.g. `id: 'entry-1', userId: 'user-1', content: 'Today I noticed I felt calmer than usual.', promptUsed: null, tone: null, createdAt: DateTime(2026, 8, 1), updatedAt: DateTime(2026, 8, 1)`). Update `JournalEntryFixture.one()`'s return type to `JournalEntry` accordingly.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/reflection_journal/reflection_journal_screen_test.dart`
Expected: FAIL — `reflection_journal_screen.dart` does not exist.

- [ ] **Step 3: Write `JournalEntryCard`**

```dart
// lib/features/reflection_journal/presentation/widgets/journal_entry_card.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:intl/intl.dart';

class JournalEntryCard extends StatelessWidget {
  const JournalEntryCard({super.key, required this.entry, required this.onTap});

  final JournalEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final preview = entry.content.length > 120
        ? '${entry.content.substring(0, 120)}…'
        : entry.content;

    return CardInkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                DateFormat.yMMMd().format(entry.createdAt),
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              if (entry.tone != null) ...[
                Gap(Spacing.sm.w),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: Spacing.sm.w,
                    vertical: 2.h,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.sm.r,
                    ),
                  ),
                  child: Text(
                    entry.tone!,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Gap(Spacing.sm.h),
          Text(
            preview,
            style: textTheme.bodyMedium,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write `ReflectionJournalScreen`**

```dart
// lib/features/reflection_journal/presentation/screens/reflection_journal_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_compose_screen.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_detail_screen.dart';
import 'package:attune/features/reflection_journal/presentation/widgets/journal_entry_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReflectionJournalScreen extends ConsumerStatefulWidget {
  const ReflectionJournalScreen({super.key});

  @override
  ConsumerState<ReflectionJournalScreen> createState() =>
      _ReflectionJournalScreenState();
}

class _ReflectionJournalScreenState
    extends ConsumerState<ReflectionJournalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Reflection journal',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Entries'), Tab(text: 'Patterns')],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.pushNamed('journalEntryCompose');
        },
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Write'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_EntriesTab(), _PatternsTab()],
      ),
    );
  }
}

class _EntriesTab extends ConsumerWidget {
  const _EntriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(journalEntriesProvider);

    return entriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Center(child: ErrorStateWidget(subtitle: 'Error: $error', title: '')),
      data: (entries) {
        if (entries.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.book_outlined,
            title: 'Your journal is empty',
            subtitle:
                'Write your first entry whenever you\'re ready. Nothing here is ever shared with anyone.',
            actionLabel: 'Write an entry',
            onAction: () => context.pushNamed('journalEntryCompose'),
          );
        }

        return ListView.separated(
          padding: EdgeInsets.all(Spacing.md.w),
          itemCount: entries.length,
          separatorBuilder: (_, __) => Gap(Spacing.smMd.h),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return JournalEntryCard(
              entry: entry,
              onTap: () => context.pushNamed(
                'journalEntryDetail',
                extra: entry.id,
              ),
            );
          },
        );
      },
    );
  }
}

class _PatternsTab extends ConsumerWidget {
  const _PatternsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patternsAsync = ref.watch(journalPatternsProvider);
    final textTheme = Theme.of(context).textTheme;

    return patternsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Center(child: ErrorStateWidget(subtitle: 'Error: $error', title: '')),
      data: (patterns) {
        if (patterns.status == 'insufficient_evidence') {
          return EmptyStateWidget(
            icon: Icons.insights_outlined,
            title: 'Not enough entries yet',
            subtitle:
                'Once you\'ve written a few entries, patterns across them will show up here.',
          );
        }

        return Padding(
          padding: EdgeInsets.all(Spacing.md.w),
          child: Text(patterns.summary ?? '', style: textTheme.bodyMedium),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Write `JournalEntryComposeScreen`**

```dart
// lib/features/reflection_journal/presentation/screens/journal_entry_compose_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reflection_journal/data/journal_prompts.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JournalEntryComposeScreen extends ConsumerStatefulWidget {
  const JournalEntryComposeScreen({super.key, this.entryId});

  final String? entryId;

  @override
  ConsumerState<JournalEntryComposeScreen> createState() =>
      _JournalEntryComposeScreenState();
}

class _JournalEntryComposeScreenState
    extends ConsumerState<JournalEntryComposeScreen> {
  final _controller = TextEditingController();
  bool _promptDismissed = false;
  bool _isSaving = false;
  String? _promptUsed;
  bool _loadedExisting = false;

  @override
  void initState() {
    super.initState();
    _promptUsed = randomJournalPrompt();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      if (widget.entryId != null) {
        await ref.read(
          updateJournalEntryProvider((
            entryId: widget.entryId!,
            content: content,
          )).future,
        );
        unawaited(
          ref.read(analyseJournalEntryProvider(widget.entryId!).future),
        );
      } else {
        final newId = await ref.read(
          createJournalEntryProvider((
            content: content,
            promptUsed: _promptDismissed ? null : _promptUsed,
          )).future,
        );
        unawaited(ref.read(analyseJournalEntryProvider(newId).future));
      }
      if (mounted) {
        context.showSuccessSnackbar('Saved. Sit with that for a bit.');
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (widget.entryId != null && !_loadedExisting) {
      final entryAsync = ref.watch(journalEntryProvider(widget.entryId!));
      entryAsync.whenData((entry) {
        if (!_loadedExisting) {
          _controller.text = entry.content;
          _loadedExisting = true;
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          widget.entryId != null ? 'Edit entry' : 'New entry',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.entryId == null &&
                !_promptDismissed &&
                _promptUsed != null)
              Container(
                padding: EdgeInsets.all(Spacing.smMd.w),
                margin: EdgeInsets.only(bottom: Spacing.md.h),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(
                    BorderRadiusTokens.md.r,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_promptUsed!, style: textTheme.bodyMedium),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _promptDismissed = true),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Write freely. This stays private.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Write `JournalEntryDetailScreen`**

```dart
// lib/features/reflection_journal/presentation/screens/journal_entry_detail_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_compose_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JournalEntryDetailScreen extends ConsumerWidget {
  const JournalEntryDetailScreen({super.key, required this.entryId});

  final String entryId;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'This can\'t be undone. The entry and its reflection will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(deleteJournalEntryProvider(entryId).future);
      if (context.mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final entryAsync = ref.watch(journalEntryProvider(entryId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.pushNamed(
              'journalEntryCompose',
              extra: entryId,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: entryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: ErrorStateWidget(subtitle: 'Error: $error', title: '')),
        data: (entry) {
          final analysisAsync = ref.watch(analyseJournalEntryProvider(entryId));

          return SingleChildScrollView(
            padding: EdgeInsets.all(Spacing.md.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.content, style: textTheme.bodyLarge),
                Gap(Spacing.lg.h),
                analysisAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (analysis) {
                    if (!analysis.isComplete || analysis.observation == null) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      padding: EdgeInsets.all(Spacing.md.w),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.md.r,
                        ),
                      ),
                      child: Text(
                        analysis.observation!,
                        style: textTheme.bodyMedium,
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 7: Fill in the test fixture and run the test**

Edit `test/features/reflection_journal/reflection_journal_screen_test.dart` per the note in Step 1: import `JournalEntry`, replace `_buildEntry()` to construct a real `JournalEntry`.

Run: `cd /Users/user/attune && flutter test test/features/reflection_journal/reflection_journal_screen_test.dart`
Expected: PASS, 3/3 tests.

- [ ] **Step 8: Run `flutter analyze`**

Run: `cd /Users/user/attune && flutter analyze lib/features/reflection_journal`
Expected: no errors. Fix any `unawaited` import issues (`import 'dart:async';` needed in `journal_entry_compose_screen.dart` for `unawaited`).

- [ ] **Step 9: Commit**

```bash
git add lib/features/reflection_journal/presentation/screens lib/features/reflection_journal/presentation/widgets
git add test/features/reflection_journal/reflection_journal_screen_test.dart
git commit -m "feat(reflection-journal): add journal screens (list, compose, detail)"
```

---

### Task 8: Navigation wiring — routes + fix `_ReflectionEntryCard`

**Files:**
- Modify: `lib/app/routing/app_router.dart` (add imports near line 30, add `RouteNames` constants near line 188/209/247, add `GoRoute`s near line 423-427)
- Modify: `lib/features/chat/presentation/screens/chat_couples_locked_screen.dart:170-181,357-362`

**Interfaces:**
- Consumes: `ReflectionJournalScreen`, `JournalEntryComposeScreen`, `JournalEntryDetailScreen` from Task 7.
- Produces: three new named routes usable via `context.pushNamed('reflectionJournal' | 'journalEntryCompose' | 'journalEntryDetail')`.

- [ ] **Step 1: Add imports to `app_router.dart`**

Add near the existing healing import at line 30:
```dart
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_compose_screen.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_detail_screen.dart';
import 'package:attune/features/reflection_journal/presentation/screens/reflection_journal_screen.dart';
```

- [ ] **Step 2: Add route name constants**

In the `RouteNames` class (starting line 101), add near the `healingJourney`/`healingStage` constants (lines 188, 209):
```dart
  static const String reflectionJournal = '/reflectionJournal';
  static const String journalEntryCompose = '/journalEntryCompose';
  static const String journalEntryDetail = '/journalEntryDetail';
```

- [ ] **Step 3: Add the `GoRoute`s**

Immediately after the existing `healingJourney` `GoRoute` (app_router.dart:423-427), add:
```dart
      GoRoute(
        path: RouteNames.reflectionJournal,
        name: 'reflectionJournal',
        builder: (context, state) => const ReflectionJournalScreen(),
      ),
      GoRoute(
        path: RouteNames.journalEntryCompose,
        name: 'journalEntryCompose',
        builder: (context, state) {
          final entryId = state.extra as String?;
          return JournalEntryComposeScreen(entryId: entryId);
        },
      ),
      GoRoute(
        path: RouteNames.journalEntryDetail,
        name: 'journalEntryDetail',
        builder: (context, state) {
          final entryId = state.extra as String;
          return JournalEntryDetailScreen(entryId: entryId);
        },
      ),
```

- [ ] **Step 4: Fix `chat_couples_locked_screen.dart` — remove the eligibility gate**

Replace the block at lines 170-181 (the `hasHealingJourney`/`hasStartableRelationship`/`isHealingEligible` computation and its explanatory comment) — delete it entirely, since the Reflection Journal this card now points to has no eligibility requirement:

Old (lines 170-181):
```dart
    // ATTUNE_MASTER_SPEC.md §8.9: the Healing journey is "if applicable" —
    // eligible only for a user who already has a journey (in progress or
    // done) or has an actual ended relationship to start one from. A
    // couplesPending/brand-new-personal user has neither: they've never had
    // an Attune relationship yet, just a pending invite. Showing the card
    // to them routed straight into HealingJourneyScreen's empty state, a
    // dead end for a button that should not have been reachable.
    final hasHealingJourney =
        ref.watch(healingJourneyProvider).valueOrNull != null;
    final hasStartableRelationship =
        ref.watch(healingStartContextProvider).valueOrNull != null;
    final isHealingEligible = hasHealingJourney || hasStartableRelationship;
```

New: delete these 12 lines entirely.

- [ ] **Step 5: Point the card at the new screen, remove the conditional wrapper**

Replace lines 357-362:
```dart
            if (isHealingEligible) ...[
              // Gap(Spacing.m.h),
              _ReflectionEntryCard(
                onTap: () => context.pushNamed('healingJourney'),
              ),
            ],
```

With:
```dart
            _ReflectionEntryCard(
              onTap: () => context.pushNamed('reflectionJournal'),
            ),
```

- [ ] **Step 6: Remove now-unused imports if `flutter analyze` flags them**

Run: `cd /Users/user/attune && flutter analyze lib/features/chat/presentation/screens/chat_couples_locked_screen.dart`
Expected: if `healingJourneyProvider`/`healingStartContextProvider` imports are now unused in this file, remove them. Check first with `grep -n "healingJourneyProvider\|healingStartContextProvider" lib/features/chat/presentation/screens/chat_couples_locked_screen.dart` — if no other reference remains in the file, delete the corresponding `import 'package:attune/features/healing/presentation/providers/healing_providers.dart';` line only if nothing else in the file needs it (check for other symbols from that import first, e.g. `supabaseClientProvider`).

- [ ] **Step 7: Run full analyze and existing chat tests**

Run: `cd /Users/user/attune && flutter analyze lib/app/routing/app_router.dart lib/features/chat/presentation/screens/chat_couples_locked_screen.dart lib/features/reflection_journal`
Expected: no errors.

Run: `cd /Users/user/attune && flutter test test/features/reflection_journal`
Expected: all tests still pass (nothing in this task should have changed their behavior).

- [ ] **Step 8: Commit**

```bash
git add lib/app/routing/app_router.dart lib/features/chat/presentation/screens/chat_couples_locked_screen.dart
git commit -m "feat(reflection-journal): wire navigation, fix reflection card routing"
```

---

## Post-implementation manual verification (not a task — a checklist for the final reviewer)

- [ ] Run the app, sign in as a brand-new `personal`-mode user with no relationship history, tap the reflection card on the Chat tab's locked-couples surface — it must open the new journal, not an empty Healing state.
- [ ] Repeat as a `couplesPending` user (sent an invite, not yet accepted) — same expectation.
- [ ] Write an entry under 15 words — confirm it saves and shows no forced analysis (patterns/detail view should show nothing pushy).
- [ ] Write an entry over 15 words — confirm an observation eventually appears in the detail view (may require a manual refresh/re-navigation since there's no polling).
- [ ] Edit an entry — confirm the old analysis disappears and a new one is generated for the new content.
- [ ] Delete an entry — confirm the confirmation dialog appears, and after confirming, the entry is gone from the list.
- [ ] Write 3+ entries with real content, then check the Patterns tab shows a real summary instead of "not enough entries yet."
- [ ] Confirm Healing's own entry points (`conversations_screen.dart`) are untouched and still correctly gated.
