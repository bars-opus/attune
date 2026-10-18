# Spec 8: Conflict toolkit v1 and AI gates — Implementation Plan

> **For agentic workers:** native execution on main, no commits; Fable plan review before code; final Fable review and one fix pass.

**Goal:** Give couples pull-only tools for the hard moments (Pause, repair phrases, apology and conversation scaffolds, a plain register), put the safety gates in front of every AI call, and make the paused AI jobs safe to resume. The resume itself is the owner's step.

**Architecture:**
- Fixed-copy tools are built client-side and sent as ordinary messages; only the Pause message and its single reply are server-typed.
- A private safety check (own table, `auth.uid()` only, a service-only predicate) hides the conjoint steps.
- A deterministic pre-check (do-not-interpret family plus the existing immediate-risk families) runs before Understand, Assist and the translator call a provider.
- A service-only suppression predicate keeps Layer 2/4 patterns, Pulse chat dimensions and the Verdict away from relationships with a safety context.

**Tech stack:** Flutter 3.29 / Dart 3.7, Riverpod 2.6; Supabase Postgres 17; Deno edge functions with Gemini (`_shared/gemini_json.ts`).

**Spec:** `docs/superpowers/research/2026-10-16-couples-research/06-synthesis-roadmap.md`:
- F14 (:151), F15 (:152), B3 (:203), B10 (:217), A4/A5/A8 (:185-189), programme row 8 (:657);
- `05-scenarios-strain-risk.md` :145, :565 P0-13, :571-595 Part C (exact repair phrases, apology fields, "never" column);
- `lib/architecture/attune/ATTUNE_RISK_SOLUTIONS.md` :56, :71, :122;
- `ATTUNE_CLINICAL.md` §8.3 :765-772 (the seventh need), §9.3 :893-905 (referral copy);
- MASTER_SPEC permanent constraints 13 and 14 (:2912-2922), :3030 (pull-only).

## Context (code map, 2026-10-18)

- **Composer** (`chat_text_field.dart`):
  - callback-gated affordances (null hides them) and the attach list `_attachActions()`;
  - the send satellite `ComposerSatellite` has no long-press, and with voice on and an empty field the mic replaces it;
  - fixed-draft insertion precedent: `_askForSupport` (`chat_screen.dart`).
- **Server-typed message precedent:** `20261018140200_appreciation.sql` (CHECK extension, guard trigger with a GUC, RPC).
- **Translator** (`translate-conflict/index.ts`):
  - no auth or membership check, and no pre-check;
  - its own pattern list; NVC only.
  - The six-need list is hard-coded in `translate-conflict` :78, `analyse-session` :657/:744, `refresh-love-map` :30-38 and `translator_pattern_service.dart` :59-67.
  - `translator_pattern_service.dart` :72-87 writes a counted insight ("N of your last 6").
- **Understand and Assist:**
  - `ai-understand` pre-check seam after the own-message reject (~:369), before consent and quota;
  - `ai-assist` after the target load (~:381);
  - client result model has only `ok` and `cannot_help`;
  - footer seam `understand_sheet.dart` ~:174.
- **Safety corpus code:** `_shared/chat_safety.ts` (`normalizeForTokenPhrase`, `detectImmediateFamilies`), `_shared/ai_session_safety.ts` (config shape, `classifySessionContent`; ai-sessions pre-dispatch at `ai-sessions/index.ts` ~:2179).
- **Prohibited patterns:**
  - `_shared/gemini_json.ts` `STATIC_PROHIBITED_PATTERNS`;
  - stale duplicate in `_shared/claude_json.ts`;
  - `gemini_json.test.ts` has 4 tests.
- **Paused jobs:**
  - `20260931150000_pause_ai_jobs.sql`;
  - `20260931160000_resume_ai_jobs.sql.disabled` re-schedules the Verdict cron too (must not);
  - Pulse chat dimensions use `stonewall_rate`;
  - there is no cost ledger beyond `ai_assistant_usage`.
- **Safety events:** `safety_events` (relationship_id, tier, family); no suppression flag exists.
- **Verdict:**
  - `generate-verdict` exports nothing testable;
  - its four tests are source greps;
  - `verdict_screen.dart` "Watch areas" ~:168 (screen unrouted).

## Rulings made while planning

- **P1. Dependencies F14 and F11 are built here.** Their clinician-authored content ships as marked placeholders: the 4 safety-check items, the DV lexicon additions, the referral card copy and "When your partner is struggling". Each placeholder string starts with `[DRAFT]`, and a test fails launch readiness while any `[DRAFT]` string is reachable with its flag on. Flags stay off in migrations; the dev snippet turns them on for testing.
- **P2. Pause.** RPC `send_pause(rel, client_id, variant 1-3)` sends one of three fixed texts as `media_type='pause'` with `message_analysis_skipped=true` (no Pulse or AI input). The partner gets one optional fixed reply, `send_pause_reply(pause_message_id)` → `media_type='pause_reply'` "Okay. I'll be here.":
  - at most one per pause;
  - recipient only;
  - refused when the conjoint steps are hidden for that relationship.

  The 20–45 minute timer and the self-soothing card are device-local and visible to the sender only. The partner never sees a timer.
- **P3.** The repair tray (long-press on send, plus a "Repair" chip on an empty composer), the apology scaffold and the start-a-conversation scaffold insert fixed or assembled, editable text into the composer. They never send by themselves, nothing is logged, and there is no counter or record of who used what.
- **P4. Private safety check.** Table `safety_self_checks` (one row per user):
  - 4 items, each yes, no or prefer not to say;
  - `positive` is computed server-side (any yes);
  - `until` = answered + 180 days;
  - `resources_shown` boolean.

  `get_my_safety_check()` returns the caller's own row. `user_safety_flagged(uid)` is service-role only. `relationship_conjoint_hidden(rel)` is callable by members: true when either member's check is positive and unexpired, and it returns only a boolean with no reason. Offered at the end of Ask-2 (skippable), from Pulse every 90 days, and from Safety resources.
- **P5. Toolkit visibility.**
  - Every toolkit affordance is behind `conflict_toolkit` (seeded false).
  - The conjoint step (the partner's Pause reply) is also hidden whenever `relationship_conjoint_hidden`.
  - The caller's own tools are hidden while the caller's own check is positive. Their partner keeps their sender-side tools, so nothing changes visibly for them.
- **P6. The pre-check** (`_shared/do_not_interpret.ts`):
  - normalised phrases ("not tonight", "stop", "I don't want to", "leave me alone", "no means no"…) plus the existing immediate-risk families;
  - runs on the target message (and the Assist instruction) before consent, quota and any provider call;
  - a match returns `status: 'boundary'` with the fixed requester-only card: "A no is complete on its own. It isn't something to decode." plus resources;
  - nothing is stored. The translator runs the same check on its input.
- **P7. Translator.**
  - Fix auth (`requireUser`) and membership in the active relationship.
  - Use the shared prohibited patterns.
  - Add `register: 'nvc' | 'plain'`.
  - Post-check boundary statements: if the input contains a negation or refusal, the rewrite must keep one, otherwise `cannot_help`.
  - Remove the counted "N of your last 6" insight.
- **P8. Seventh need `communal_obligation`** goes into every taxonomy (translator prompt and display, Layer 2 prompt and validator, Love map mapping → `history`).
- **P9. Suppression.** `relationship_ai_suppressed(rel)` is service-role only: true when the relationship has a tier-1/2 `safety_events` row in the last 90 days or either member's safety check is positive and unexpired. While it is true:
  - `analyse-session` writes no Layer 2/4 patterns or insights;
  - `compute-pulse` skips chat dimensions;
  - `generate-verdict` returns ineligible.
  - Stonewalling (`stonewall_rate`) is excluded from Pulse everywhere until clinical sign-off (`stonewall_signal_enabled` flag, false).
- **P10. Co-framing line** (RISK_SOLUTIONS :71, verbatim) on every shared conflict insight surface (Verdict watch areas; pattern cards if any appear).
- **P11. Resume.**
  - `20260931160000_resume_ai_jobs.sql.disabled` is fixed to drop the Verdict cron and kept disabled.
  - The dev snippet `supabase/sql/dev_resume_ai_jobs.sql` re-schedules the three jobs locally.
  - Enabling in production and flipping `ai_together_enabled` are owner steps after the smoke test and suites.
  - A cost view `ai_cost_per_relationship` (service-role) aggregates provider calls per relationship per day.

## Global constraints

- Work on main with no commits; format only new files.
- Don't touch `lib/features/planning/**`, `test/features/planning/**`, SOUL or THESIS.
- Scratch DB `attune_spec3a`.
- Grants go in `…10_grants.sql` files replayed from `scripts/local_pg_grants.sql`.
- Pull-only:
  - nothing appears automatically or is detected from content;
  - no counts, streaks or Pulse inputs;
  - no partner-visible timer or state;
  - no AI-written text sent in anyone's name.
- Flags seeded false: `conflict_toolkit`, `private_safety_check`, `stonewall_signal_enabled`. The dev snippet sets the first two true.

## Review focus

1. No provider call happens for a do-not-interpret or immediate-risk input, in Understand, Assist or the translator; no quota is spent; nothing is stored.
2. Nothing about the safety check reaches the partner beyond the absence of the Pause reply; answers never leave `safety_self_checks`; no analytics.
3. A Pause never feeds Pulse or AI; the reply is single and recipient-only; the timer is sender-only.
4. Suppression truly stops pattern and insight writes, chat-derived Pulse dimensions and the Verdict for a relationship with a safety context.
5. The translator rejects unauthenticated and non-member callers and never drops a "no".

---

### Task 1: Private safety check (F14) and suppression predicates (P4, P9)

**Files:**
- migration `20261018150000_safety_self_check.sql` (+ `150010` grants);
- `lib/features/safety/self_check/` (service, screen with 4 `[DRAFT]` items and "Prefer not to say", resources-once);
- entry points: Ask-2 end card, Pulse row (every 90 days), Safety resources row;
- tests: `safety_self_check_contracts.sql` and widget tests.

**SQL:**
- table and RPCs `submit_my_safety_check(p_answers jsonb)` (validates 4 keys and values), `get_my_safety_check()`, `mark_safety_resources_shown()`;
- `user_safety_flagged(uuid)` (service_role), `relationship_conjoint_hidden(uuid)` (members, boolean), `relationship_ai_suppressed(uuid)` (service_role);
- flag `private_safety_check`.

**Contracts:**
- the partner can read neither the row nor `user_safety_flagged`;
- `conjoint_hidden` is true for both members when either is positive;
- it expires after 180 days;
- prefer-not or all-no is not positive;
- suppression is true after a tier-1 safety event or a positive check.

### Task 2: Pre-check, footer, handoff card, prohibited patterns (F15 (2)–(4), B10)

**Files:**
- `_shared/do_not_interpret.ts` (+ test);
- `ai-understand`, `ai-assist` (pre-check seam; tests with `neverCalledGemini`);
- client `understand_result_model.dart` (`boundary` branch), `understand_sheet.dart` (boundary card, footer, handoff link);
- `lib/features/safety/presentation/outside_perspective_screen.dart` (B10, `[DRAFT]` country lists) and its route;
- `_shared/gemini_json.ts` third-party attribution patterns (+ tests); retire the duplicate in `claude_json.ts` by importing the shared list.

### Task 3: Translator (P7, P8, A8)

**Files:**
- `translate-conflict/index.ts`: auth, membership, pre-check, shared patterns, register, boundary post-check, seventh need. Pure helpers are exported for Deno tests.
- client translator: register toggle, seventh-need copy; remove the counted insight.
- `analyse-session` taxonomy and validator; `refresh-love-map` mapping;
- tests.

### Task 4: Conflict toolkit (B3, P2, P3, P5)

**Files:**
- migration `20261018150100_pause_messages.sql` (+ `150110`): media types `pause`/`pause_reply`, guard trigger, `send_pause`, `send_pause_reply`, flag `conflict_toolkit`;
- client:
  - `lib/features/conflict_toolkit/` (pause sheet with 3 fixed messages; sender-only timer with self-soothing card and return prompt; repair tray with the 6 phrases; apology scaffold with 4 fields; start-a-conversation scaffold with the 7 needs);
  - composer wiring (attach actions "Pause", "Repair", "Help me apologise", "Start a conversation"; long-press on send);
  - bubble rendering for pause/pause_reply with the reply chip (recipient, once, not when hidden);
- gate test: no counts or records.

**Contracts:**
- fixed texts only;
- `analysis_skipped`;
- reply once and recipient only;
- reply refused when hidden;
- active relationship only;
- a client cannot forge either type.

### Task 5: AI gates and the resume path (F15 (1), P9–P11, A4, A5)

- `analyse-session`, `compute-pulse`, `generate-verdict` honour `relationship_ai_suppressed`.
- Stonewalling is excluded from Pulse behind `stonewall_signal_enabled`.
- Co-framing line on the Verdict watch areas.
- Adversarial Verdict suite: export `validateModelOutput`/`buildEvidence`, inject `callGemini`; cases for blame, attribution, verdict language, safety leakage and third-party attribution.
- Fix the `.disabled` resume file (no Verdict cron).
- Dev snippet `supabase/sql/dev_resume_ai_jobs.sql`.
- Cost view `ai_cost_per_relationship`.
- Dev flag snippet `supabase/sql/dev_enable_spec8_flags.sql`.
- `[DRAFT]` launch-readiness test.
- Full runs, final Fable review, one fix pass, memory.

## Plan review amendments (Fable, 2026-10-18): BINDING

Review: `.superpowers/sdd/2026-10-18-spec8-plan-review.md` (3 Critical, 18 Important, 10 Minor; its §2.2 outcome table, §6.3 resume gates and §7 B10 content are part of these amendments). Where an amendment and the task text differ, the amendment wins.


**Critical**

1. **C1.** Remove `relationship_conjoint_hidden(uuid)` from anything `authenticated` can call. No member-callable function or RLS-visible value may depend on the partner's `safety_self_checks` row. Gate each person's participation on their **own** row only.
2. **C2.** Do not hide a positive user's own sender-side tools. Pause, repair tray, apology and start-a-conversation are shown to every member under the feature flags. The only step hidden by a positive check is the reply chip, hidden for the **recipient** whose own check is positive. Record the deviation from F14(3)'s "partner-facing reply" wording with the Scenario 3/4 rationale.
3. **C3.** Replace `status:'boundary'` with the outcome table in §2.2: do-not-interpret on a partner-authored target → the Scenario 12 line "A no is complete on its own. If you want to understand more, ask them when you're both calm."; self-harm on a partner-authored target → the supporter card; victimisation/threat/control on a partner-authored target → `cannot_help: unsafe_to_infer` byte-identical to the model's refusal; self-harm/victimisation in requester-authored text → the writer-facing resources card. Freeze the response keys in a test.

**Important**

4. **I1.** `get_my_safety_check()` returns only `answered_at`, `until`, `resources_shown`. The client never receives answers or `positive`. The screen never re-displays answers; the resources card renders once at submit; the Pulse and Safety rows use identical copy regardless of state.
5. **I2.** Positive is sticky: `submit_my_safety_check` may extend `positive_until` and never shorten it; no per-feature delete.
6. **I3.** Key `safety_self_checks` by `(user_id, relationship_id)` with `ON DELETE CASCADE` to `relationships` and `auth.users`; add it to `account_deletion_contracts.sql`.
7. **I4.** Add `pause_reply_state(pause_message_id) → 'available'|'unavailable'`; the chip is driven only by it. Reply allowed only within 60 minutes of the pause and while the recipient has sent nothing since; one reply per pause enforced by a unique partial index on `reply_to_message_id WHERE media_type='pause_reply'`; `edit_message` refuses `pause` and `pause_reply`.
8. **I5.** Toolkit affordances render only when `conflict_toolkit` **and** `private_safety_check` are both on; the dev snippet sets both.
9. **I6.** Build `_shared/do_not_interpret.ts` as its own versioned corpus with sentence splitting before normalisation, short-sentence-only matching for single tokens, golden negatives, and the pre-normalised-pattern test.
10. **I7.** Add `_shared/self_disclosure.ts` (`self_disclosure-0.1.0-draft`, victimisation + self-harm families, `[DRAFT]`) and run it in Understand, Assist and the translator through one shared `classifyAssistantInput` module.
11. **I8.** Add `media_type IS NULL AND message_analysis_skipped = false` to `loadAiAssistantTarget`, `loadBoundedContext` and `ai_session_context.ts`'s filter, with tests.
12. **I9.** Translator: `requireUser`, user-scoped relationship load (active, not archived), 2,000-char cap, remove the client `context` object (no partner tone summary), per-user limit, `no-store`; deterministic refusal-token post-check returning the generic failure copy; prompt rule for boundaries; golden eval pairs.
13. **I10.** `relationship_ai_suppressed(rel)`: any `trigger_tier`, `anonymised_at IS NULL`, 180-day window, or either member's unexpired positive check; add index `safety_events(relationship_id, created_at DESC) WHERE anonymised_at IS NULL`.
14. **I11.** Gate `analyse-session` at `processRelationship`/`retryExistingSession` entry (before `consumeMessagesIntoSession`), returning `status:'suppressed'`; gate `refresh-love-map` the same way.
15. **I12.** `compute-pulse` under suppression sets `analysedCount=0, sessionCount=0` so `dimension_confidence` equals the no-chat-data case; the backlog metric ignores suppressed relationships.
16. **I13.** Put the Verdict suppression check in `request_verdict_generation`, returning a payload jsonb-equal to `insufficient_evidence`; the edge function also refuses queued jobs for suppressed relationships.
17. **I14.** Gate stonewalling **and** contempt (`severe_rate`) behind one false flag; exclude both from Verdict evidence.
18. **I15.** Add the `ai_provider_calls` ledger written by `callGeminiJson` from `usageMetadata` with an `attribution` argument, service-role only, 90-day purge; the cost view aggregates it; a test asserts every call site passes attribution.
19. **I16.** Resume gate list in the `.disabled` header per §6.3, including "flow-testing `patterns`/`analysis_sessions`/chat-derived `pulse_scores` purged or verified empty".
20. **I17.** Understand footer verbatim per F15(3), rendered unconditionally; B10 card content and entry points (Pulse, Settings, Understand footer, every toolkit overflow) per §7.
21. **I18.** Adversarial Verdict suite adds "fabrication without evidence IDs" and "degrades to not enough data" cases.

**Minor**

22. **M1.** Use HARK's four published items verbatim as the `[DRAFT]` placeholders with "within the last year"; four prefer-not answers show the plain resources link.
23. **M2.** Co-framing line, apology line, and the six repair phrases bound verbatim; repair phrases as l10n keys; assembler never emits "forgive".
24. **M3.** Pause push: ordinary message push only, generic by default; sender timer persisted locally; return prompt generic; the other two pause texts `[DRAFT]` naming a 20–45 minute return; UI copy "Take a pause" to avoid the `paused` relationship state.
25. **M4.** `analyse-message` skips suppressed relationships.
26. **M5.** Plain register as a second versioned prompt file; choice stored locally only.
27. **M6.** Verify the Love map domain key before mapping `communal_obligation`; record the category definition as pending clinician sign-off.
28. **M7.** Consolidate dev schedule snippets (reuse or delete `schedule_analyse_*.sql`, `schedule_generate_verdict.sql`); note `refresh-love-map-weekly` is already scheduled and calls no provider.
29. **M8.** Group the four toolkit actions under one attach entry; long-press send opens the repair tray and appends on a new line like `_askForSupport` (`chat_screen.dart:229-238`), never sends.
30. **M9.** Plan records: gridlock ritual and debrief share follow the own-state rule when built; sender-side writer-facing routing on toolkit fields is F11 work; name the `claimProviderStart` smoke-test script for A5.
31. **M10.** Define the `[DRAFT]` scanner precisely (feature dirs × flags seeded true in migrations) and the no-writes scanner for the toolkit and self-check directories.
