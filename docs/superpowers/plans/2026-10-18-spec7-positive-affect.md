# Spec 7: Positive-affect pair and quiet states — Implementation Plan

> **For agentic workers:** native execution (executing-plans) on main, no commits; final Fable review + one fix pass.

**Goal:** Give couples the two cheapest, best-evidenced positive surfaces — "I noticed…" appreciation notes and "Share a win" — and make every celebratory surface go quiet for a person who says they are having a hard time.

**Architecture:** Server-authoritative SQL RPCs (SECURITY DEFINER, `search_path=''`, grants files) write every new kind of thing; the client renders and asks. A per-user quiet state (server table, 14-day expiry) is read by the client (shimmer) and by the SQL/edge generators (daily summary, On this day, memory prompts, Love map rounds, Planning celebration notice, AI ideas tone). Three feature flags gate the three surfaces, seeded off, turned on by the dev snippet.

**Tech stack:** Flutter 3.29 / Dart 3.7, Riverpod 2.6, go_router; Supabase Postgres 17 (RLS, pg_cron); Deno edge functions.

**Spec:** `docs/superpowers/research/2026-10-16-couples-research/06-synthesis-roadmap.md` rows B1 (:199), B2 (:201), B9 (:215), A9 (:190), programme row 7 (:656). Soul constraints: `lib/architecture/attune/ATTUNE_SOUL.md` :364-367 (no counts, no "thank your partner N times"), §8 :600-616, :635-638 (special-category prefs incl. faith never inferred, never in an AI prompt), :648-649 (no AI-written affection). Code map: summarised in Context below.

## Context (code map, 2026-10-18)

- Messages: no subtype column; `messages_media_type_check` latest in `20260932180000_game_card_moves_sides.sql` (image, audio, video, streak, game, place, game_trail). Server-insert precedent `post_place_update` (`20260932120000_place_update_messages.sql`). Bubble branches in `message_bubble.dart` `_BubbleBody` (~:1397). Preview `conversation_preview.dart:34`; push preview `process-chat-notification-outbox` `previewBody`; export `export_chat_page`. Composer attach list `chat_text_field.dart` `_attachActions()` (~:879). Message actions `message_actions_sheet.dart` (~:170). Self-only save precedent: `message_stars`.
- Care cards are client-derived (`together_care.dart`); open chat via `_openChatWith(draft)` in `together_screen.dart` (~:414) using the `draft` query parameter (`ChatScreen.initialDraft`).
- Highlights: `timeline_events` (event_type 'highlight'); trigger `notify_partner_moment_logged` (`20261014100100_moment_partner_push.sql`) pushes the partner for every non-conflict moment.
- First-message shimmer: `chat_screen.dart` ~:3610. Planning celebration: SQL `planning_v2_maybe_celebrate` (shared system notice). Daily summary lines: `together_digest_lines` (latest `20261017180000_push_copy.sql`). On this day / memory prompts / moments: `list_together_on_this_day`, `list_together_memory_prompts`, `list_together_moments` (`20261014150000_together_story.sql`). Love map rounds: `supabase/functions/refresh-love-map/index.ts` (domains ~:80, :160). AI ideas: `supabase/functions/ai-together/ideas.ts` `buildIdeasPrompt`. Planning Recent: `list_planning_recent` does not filter archived (`20261015140000_planning_recent.sql`).
- No faith setting exists. `lib/features/planning/**` is off-limits for edits.

## Rulings made while planning

- **P1.** The appreciation note is a new `media_type = 'appreciation'` sent by RPC `send_appreciation`, which builds the fixed text server-side ("I noticed you {text}. Thank you." or "Thankful for you because {text}."). It is an ordinary message in every other way (push, preview, analysis, delete, export) — cost if wrong: a CHECK value.
- **P2.** Faith-on phrasing: no faith setting is inferred. A device-local preference "Offer 'Thankful for you because…'" (Settings → Chat feel, off by default) shows the alternative phrasing in the note sheet. Never sent anywhere but as the chosen message text (SOUL :635).
- **P3.** The jar holds received notes the person saved (`appreciation_jar`, self-only RPCs). No count anywhere, no list of sent notes, no reminder.
- **P4.** A win is a `timeline_events` highlight with `is_win = true`, created by RPC `share_a_win`; the moment-push trigger skips wins (never a push). The partner sees an in-app card for 3 days ("Ask {name} about it — what was the best part?") until they tap or dismiss it; the tap opens Chat with the fixed draft "{title}! What was the best part?" (no AI text).
- **P5.** Quiet state is per user (not per relationship), private, 14 days, kinds `hard_time` / `loss`. Shared surfaces whose content both partners see (the Planning goal-reached notice, the Love map round) are suppressed when **either** member is quiet, so nothing reveals who; personal surfaces (shimmer, own daily summary, own On this day and memory prompts) are suppressed only for the quiet person.
- **P6.** "Put this away gently" ships as RPC `put_planning_entry_away(p_entry_id)` (archives, cancels pending countdown pushes, drops it from Recent and On this day) plus the Recent filter fix; the button inside Planning is on the owner list (folder off-limits).
- **P7.** Support-request chips live in the composer's attach sheet ("Ask for support") and insert a fixed, editable draft; they never send by themselves.

## Global constraints

- Work on main, no commits; never `dart format` pre-existing files (only new ones); don't touch `lib/features/planning/**`, `test/features/planning/**`, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`.
- Scratch DB `attune_spec3a`; grants in separate `…_grants.sql` files replayed from `scripts/local_pg_grants.sql`; every new function `REVOKE ALL … FROM PUBLIC, anon`.
- Writes are active-relationship only (Spec 3a); chat-open gate `relationship_chat_open`.
- No counts, streaks, history of sent notes, reminders to appreciate, Pulse inputs or analytics on any of these. No push for wins. No AI text. Nothing celebratory fires from message content.
- Feature flags (seeded false; dev snippet sets true): `appreciation_notes`, `share_a_win`, `quiet_states`.

## Review focus

1. A quiet state silences every celebratory surface it covers, server and client, and expires on its own after 14 days; ending it early restores everything.
2. Nothing tells the partner that someone is quiet (shared surfaces are suppressed for both, never with a reason).
3. Only the recipient can save a note to their jar; the jar has no count and lists no sent notes; deleting the message removes it from the jar.
4. A win never sends a push (trigger, digest, outbox) and its card disappears after the tap, a dismiss, or 3 days.
5. `send_appreciation` and `share_a_win` reject empty, over-long and non-member input, and paused/ended relationships.

---

### Task 1: Quiet states core (B9a, A9)

**Files:** migration `20261018140000_quiet_states.sql` (+ `140010` grants); `lib/features/quiet/` (data service, providers, settings screen, once-line sheet); route `/settings/quiet`; Settings row; `chat_screen.dart` shimmer hook; tests `supabase/tests/quiet_state_contracts.sql`, `test/features/quiet/quiet_state_test.dart`, extend `test/features/chat/first_of_day_shimmer_test.dart`.

- SQL: table `quiet_states(user_id uuid PK → users ON DELETE CASCADE, kind text CHECK IN ('hard_time','loss'), started_at, until timestamptz, line_offered boolean default false)`, RLS on, no client privileges. Functions: `user_is_quiet(p_user uuid) → boolean` (until > now()), `set_my_quiet_state(p_kind text)` (until = now()+14 days, resets line_offered), `end_my_quiet_state()`, `get_my_quiet_state()` → (kind, until, line_offered), `mark_quiet_line_offered()`. Flag `quiet_states`.
- Client: `QuietStateService` (rpc), `quietStateProvider` (FutureProvider of `QuietState?`, null when off/expired), `isQuietProvider`. Settings → "Quiet for a while" screen: two InfoRowWidget toggles ("Having a hard time", "Going through a loss", mutually exclusive), "Until {date}" line, "End now". On first switch-on, a sheet offers once the fixed line "I'm in a heavy patch. I may be quieter; it isn't about you." with Send (posts it as an ordinary text message to the active relationship) and Not now; then `mark_quiet_line_offered`.
- Shimmer: `chat_screen.dart` first-of-day shimmer requires `!isQuiet`.
- Tests first: contract (expiry, one row per user, kinds, line offered once per activation, only self can read, anon none); widget (toggles, once-line shown once, End now); shimmer off when quiet.

### Task 2: Quiet effects on generators + Hide a period (B9a, B9d, A9)

**Files:** migration `20261018140100_quiet_effects.sql` (+ `140110` grants); `supabase/functions/refresh-love-map/index.ts`, `supabase/functions/ai-together/ideas.ts` + handler; `lib/features/quiet/presentation/hidden_periods_screen.dart`; tests `quiet_effects_contracts.sql`, Deno tests.

- `together_digest_lines`: when the recipient is quiet, only plain lines (no big-day, no suggestion lines).
- `list_together_on_this_day`, `list_together_memory_prompts`: empty for a quiet caller; both exclude events whose date falls in one of the caller's hidden periods; `list_together_moments` excludes hidden periods too.
- `planning_v2_maybe_celebrate`: no goal-reached notice while either member is quiet (P5).
- `refresh-love-map`: excludes the fears and dreams domains while either member is quiet (via a service RPC `relationship_has_quiet_member(rel)`).
- `ai-together` ideas: when the requester is quiet, a fixed system line "Keep ideas gentle, low-effort and unceremonious." (no state named in the prompt).
- Hidden periods: table `hidden_periods(id, user_id, starts_on date, ends_on date, CHECK ends_on >= starts_on, ≤ 50 per user)`, RPCs `add_hidden_period`, `remove_hidden_period`, `list_my_hidden_periods`. Settings → "Hide a period" screen (list + add with a date-range picker + remove).
- Tests first: contracts per surface, including "the partner of a quiet person still gets their own On this day".

### Task 3: "I noticed…" notes and the jar (B1)

**Files:** migration `20261018140200_appreciation.sql` (+ `140210` grants); `message.dart` (`isAppreciation`), `message_bubble.dart` (leaf branch), `conversation_preview.dart`, `chat_text_field.dart` (attach action), `message_actions_sheet.dart` (Save/Remove from my jar), `lib/features/appreciation/` (sheet, service, jar screen, Together card), route `/appreciation-jar`; Settings → Chat feel toggle (P2); push preview + export check; tests.

- SQL: extend `messages_media_type_check` with 'appreciation'. `send_appreciation(p_relationship_id uuid, p_client_message_id uuid, p_text text, p_phrasing text default 'noticed')`: caller member, relationship active and chat open, text trimmed 1–280 chars, phrasing IN ('noticed','thankful'), idempotent on (sender, client_message_id), content built server-side; returns the message id. Table `appreciation_jar(user_id, message_id → messages ON DELETE CASCADE, saved_at, PK(user_id, message_id))`, RLS on, no client privileges; RPCs `save_to_my_jar(p_message_id)` (recipient only: member, sender ≠ me, media_type appreciation, not deleted), `remove_from_my_jar`, `list_my_jar()` → (message_id, content, sent_at) newest first, excluding deleted messages. Flag `appreciation_notes`.
- Client: sheet "I noticed…" with fixed prefix "I noticed you", a field, fixed suffix ". Thank you.", optional "Thankful for you because…" phrasing (P2), empty-state hint "Specific beats sweeping.", Send. Entry points: composer attach sheet ("I noticed…") and a Together hub card ("Notice something"). Bubble: ordinary bubble with a small leaf icon. Actions sheet: "Save to my jar" / "Remove from my jar" on a received note. Jar screen: list of saved notes with date, no count; empty state "Notes you keep will be here."
- Tests first: contract (format, limits, idempotency, active-only, recipient-only jar, cascade on delete, no count column/function), widget (sheet sends fixed format, leaf rendered, actions shown only for received notes), gate test (no "count"/"total"/"streak" in the appreciation feature), preview text.

### Task 4: "Share a win" and support chips (B2, B9b)

**Files:** migration `20261018140300_share_a_win.sql` (+ `140310` grants); `lib/features/wins/` (sheet, service, card provider); `together_screen.dart` (Today: win card row; "Share a win" action), `chat_text_field.dart` attach action, timeline highlight marker; support chips sheet; tests.

- SQL: `timeline_events.is_win boolean NOT NULL DEFAULT false`; `share_a_win(p_relationship_id, p_title, p_note default null)` (member, active, title 1–80, note ≤300, inserts a shared highlight with is_win); `notify_partner_moment_logged` skips is_win; `list_win_cards()` → partner's wins in the last 3 days, not dismissed by me (id, title, created_at); table `win_card_dismissals(user_id, event_id, PK)`; `dismiss_win_card(p_event_id)`. Flag `share_a_win`.
- Client: sheet (title, optional note) from the composer attach sheet and the Together hub; card row in Together "Today": "Ask {name} about it — what was the best part?" → `dismiss_win_card` then `_openChatWith("{title}! What was the best part?")`, plus a dismiss affordance; timeline shows the highlight with a small star.
- Support chips (P7): attach sheet "Ask for support" → three chips ("I need to vent", "Help me decide", "Just sit with me"), each inserting a fixed editable draft ("I need to vent. Can you just listen for a bit?", "Can you help me decide something?", "Can you just sit with me for a bit?").
- Tests first: contract (no push queued for a win, card lifetime, dismiss, partner-only cards, limits, active-only), widget (card copy and draft, attach actions), digest has no win line.

### Task 5: Put away gently, flags, runs, review (B9c)

- `put_planning_entry_away(p_entry_id)` (member, archives, cancels pending `planning_countdown:<entry>:%` notifications, excluded from Recent and On this day); `list_planning_recent` filters archived. Contract.
- Dev snippet adds the three flags. Owner list: Planning "Put this away gently" button and Progress "Reached 🎉" label under quiet state; Baby/Wedding template keying (the entry does not record its template).
- Full `flutter test`, full SQL rebuild suite, Deno tests for touched functions; final Fable review; one fix pass; memory.

## Plan review amendments (Fable, 2026-10-18): BINDING

Review: `.superpowers/sdd/2026-10-18-spec7-plan-review.md` (2 Critical, 8 Important, 15 Minor). Where an amendment and the task text differ, the amendment wins.


**C1.** `user_is_quiet(uuid)`: `REVOKE ALL … FROM PUBLIC, anon, authenticated`, no grant. `relationship_has_quiet_member(uuid)` (if kept; see I3) `GRANT EXECUTE TO service_role` only. `quiet_state_contracts.sql` asserts both are not executable by `anon` or `authenticated`, that `get_my_quiet_state()` returns only the caller's row, and that a quiet person's partner receives identical output from every Spec 7 RPC and shared surface whether or not the partner is quiet.

**C2.** Gate every read of relationship data with Spec 3b: `list_my_jar()` joins `messages` and requires `public.relationship_chat_open_for(m.relationship_id, auth.uid())`, `m.deleted_at IS NULL`, `m.media_type = 'appreciation'`, and returns `relationship_id`; `save_to_my_jar` requires `public.relationship_active_for_me(m.relationship_id)` and sender ≠ caller; `list_win_cards(p_relationship_id)` and `dismiss_win_card(p_event_id)` resolve the actor via `public.together_actor(rel)`; `win_card_dismissals(event_id → timeline_events CASCADE, user_id → auth.users CASCADE, created_at, PK(event_id,user_id))`, RLS on, `REVOKE ALL FROM PUBLIC, anon, authenticated`. Contracts: note absent from the jar when `ended_at` > 30 days old and immediately after `seal_my_side`; win cards `not_found` for paused/ended.

**I1.** In `planning_v2_maybe_celebrate`, after the goal-reached test: if `user_is_quiet(user_a) OR user_is_quiet(user_b)` then `UPDATE planning_entries SET celebrated_at = clock_timestamp()` and `RETURN` without inserting the notice. Contract: no notice while quiet and none after quiet ends.

**I2.** `put_planning_entry_away(p_entry_id)`: `planning_v2_actor`; set `status='archived'` directly (no `planning_v2_touch_entry`, no activity bump); cancel pending pushes with `UPDATE scheduled_notifications SET status='cancelled', source_key=NULL, last_error='put_away', updated_at=now() WHERE status='pending' AND metadata->>'type'='planning_entry' AND metadata->>'entry_id'=p_entry_id::text`; add `AND e.status <> 'archived'` to `list_planning_recent` and to both planning branches of `together_items_for`. Contract covers all four effects and `last_activity_at` unchanged.

**I3.** `refresh-love-map`: while either member has `quiet_states.until > now()` (read directly as service role), exclude `value_domain IN ('fears','dreams','children')` from both `preferred` and `rest`. Drop `relationship_has_quiet_member` unless another caller needs it. Deno test for both states.

**I4.** `CREATE OR REPLACE edit_message` adding `media_type` to the locked SELECT and `OR v_media_type = 'appreciation'` to the `not_editable` predicate; `Message.canEdit` false for `mediaType == 'appreciation'`. Contract: edit refused, delete allowed, jar row disappears after `delete_message`.

**I5.** Apply hidden periods to `list_together_on_this_day` and `list_together_memory_prompts` only; leave `list_together_moments` unchanged. Update plan :63 and the Task 2 contract accordingly.

**I6.** Export: `export_bundle.personal` gains `appreciation_jar` (relationship label, `ref = left(md5(message_id::text),12)`, `saved_at`), `hidden_periods`, `quiet_state`; `export_relationship.moments` gains `win`; `export_chat_page` gains `kind` for appreciation. Extend `data_export_contracts.sql` with one of each and keep the forbidden-key loop green.

**I7.** Remove `p_phrasing`. `send_appreciation(p_relationship_id, p_client_message_id, p_text)` accepts only text matching `^I noticed you .{1,280}\. Thank you\.$` or `^Thankful for you because .{1,280}\.$` (trimmed, single line, `char_length ≤ 320`), else `invalid_input`. Client composes from the two templates; the device-local toggle (P2) only selects the template. Contract: both templates accepted; free text and empty middles rejected.

**I8.** `send_appreciation` and `share_a_win` gate on `public.relationship_active_for_me(p_relationship_id)` (not `post_place_update`'s test); `send_appreciation` inserts `source='native'`, `is_system_notice=false`, `message_analysis_skipped=false`, idempotent via `ON CONFLICT (sender_id, client_message_id) DO NOTHING` + re-select; `share_a_win` inserts `event_type='highlight'`, `visibility='shared'`, `is_win=true`, title ≤ 80, note ≤ 300. Contract: paused → refused; repeat call → same id, one row.

**M1.** Add `CHECK (NOT is_win OR (event_type='highlight' AND visibility='shared'))` and a BEFORE INSERT OR UPDATE trigger forcing `is_win := false` unless `current_setting('attune.share_a_win', true) = 'on'`; `share_a_win` sets that GUC transaction-locally.

**M2.** Shimmer treats an unknown quiet state as quiet (`valueOrNull ?? true`); invalidate `quietStateProvider` after set/end and on app resume; widget test for the loading case.

**M3.** `set_my_quiet_state` resets `line_offered` only when no unexpired row exists.

**M4.** Name the feature `lib/features/quiet_states/`, tests `test/features/quiet_states/`.

**M5.** Change `_openChatWith(String draft, TogetherItem about)` to `TogetherItem? about`; keep the `together_screen.dart` diff minimal.

**M6.** `share_a_win(… , p_occurred_on date DEFAULT NULL)` → local date via `notification_local_zone`, bounded ±1 day; strip trailing `.!?` from the title in the ask-about-it draft.

**M7.** The jar "cascade on delete" contract exercises `delete_message` (soft delete) and, separately, the hard cascade on relationship purge.

**M8.** User FKs reference `auth.users(id) ON DELETE CASCADE`; `account_deletion_contracts.sql` asserts the four new tables are empty for the deleted user and that the partner's jar row for the deleted user's note is gone.

**M9.** Task 5 names the dev snippet verbatim (`psql -d "${ATTUNE_TEST_DB:-attune_test}" -c "update public.feature_flags set enabled = true where key in ('appreciation_notes','share_a_win','quiet_states')"`), seeds with `INSERT … ON CONFLICT (key) DO NOTHING`, and reads flags through `ChatFeatureFlags.isEnabled`.

**M10.** The note sheet closes on RPC success and relies on the realtime stream; no optimistic row.

**M11.** The once-only line sends through `ChatRepository.sendTextMessage`; Send is shown only when an active, chat-open relationship exists.

**M12.** `buildIdeasPrompt({…, quiet})` appends the fixed sentence; the handler reads `quiet_states` as service role; `ideas.test.ts` asserts the sentence and the absence of state words; nothing is logged.

**M13.** `user_is_quiet` is `STABLE`; only the `big` and `sugg` CTEs of `together_digest_lines` gain `AND NOT public.user_is_quiet(p_user)`; `push_copy_contracts.sql` stays green.

**M14.** `TogetherMoment.fromJson` and `TimelineEvent.fromJson` read `is_win` defaulting to false.

**M15.** The no-count gate test greps `lib/features/appreciation/**` and `lib/features/wins/**` for `count`, `total`, `streak` and `.length}` in interpolations; the Together card subtitle and jar app bar carry no number.
