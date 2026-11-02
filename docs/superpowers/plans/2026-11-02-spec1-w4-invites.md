# Spec 1 W4 (Invites: W4a, W4b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an invite a single, safe server decision and a couples flow that survives real life: migration 9 (`accept_relationship_invite_v2`, `preview_relationship_invite`, `relationship_invite_eligibility`, the preview attempts table and its retention cron), both invite edge functions on the W4a server rules (the W2 interim guard replaced, the inviter's age check, the accept as one SQL call), and, behind `flow_couples_v2`, R1 with the registers and the code in every message, R2, RI-2/RI-3/RI-4 (`/join-invite`, the only place a stored invite is accepted, D9), R4 "You're both here" with the message-notification ask, R3's day-7 "Send a new invite" and day-30 line, the partner name on this phone only, the Install Referrer, Ask 2 saving as it goes, and an accessible shared `InviteCard`. With `flow_couples_v2` off, today's invite copy, "Invite someone else" and the flag-off accept behave exactly as now, and tests prove it.

**Architecture:** Two sub-waves. **W4a** (Tasks 1–3) is server first: migration 9 and its grants twin, proven on `attune_spec3a` by `invite_v2_contracts.sql` (each refusal code, the acceptor's own invites gone in the same transaction, a forced failure rolling everything back, the users-before-relationships lock order, the preview's limits, retention) with six mutants; then `accept-invite` becomes a thin wrapper over `accept.ts` (one `rpc('accept_relationship_invite_v2')`, today's statuses and messages, plus a `code`), and both functions ask `relationship_invite_eligibility` first (flag off: today's `ensureUserRow`; on: never a users row without a date of birth, D8); then the app reads the W4a answers (`InviteRefusalKind`, `previewInvite`, `inviteErrorCopy`). **W4b** (Tasks 4–8) is the phone: the registers and the device stores; R1 (`InvitePartnerStep`, chosen by `InvitePartnerScreen` under `flow_couples_v2`) and the `InviteCard` accessibility fix; `JoinInviteScreen` (RI-2/RI-3/RI-4 and the acceptor's R4) with every accept site (the v2 gate, HomeScreen) routed to it; R3 v2 and the inviter's R4 (`LinkedMomentGate` inside Tab 2); Ask 2 save-as-you-go and the Install Referrer. Every Dart, Deno and SQL block below was run while writing this plan: the Dart and Deno in a scratch copy of the tree (each new test red before its code, green after; the whole suite at the end), the SQL on a scratch Postgres 17 restored from `attune_spec3a`'s dump (read-only on `attune_spec3a`): the migration applied twice, the contract red before it and green after, and each mutant red with the message quoted.

**Tech Stack:** Flutter 3.29.1 (Dart 3.7), Riverpod 2.6, GoRouter, Supabase Postgres 17 (pg_cron, `extensions.digest`), Deno 2 edge functions, `share_plus`, `url_launcher`, `qr_flutter` (existing), `play_install_referrer` 0.5.0 (new, the spec's package), psql.

**Spec:** `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md` — §1.3–1.5, §2 (copy, motion, §2.3 accessibility, §2.4 permissions, §2.5 flags), §3.8 R1–R5 and RI-1–RI-4, §3.14–3.15, §4 rows tagged W4a/W4b (§4.2 `private.invite_preview_attempts`, §4.3 W4a, §4.5 `create-relationship-invite` and `accept-invite`, §4.6 `invite-preview-retention`, §4.7 #9 `accept_invite_v2`, §4.8), §5.1–5.8 rows tagged W4b (§5.8 `spec1.partner_first_name`, `spec1.ask2_progress`), §7 (`invite_v2_contracts.sql`, `accept-invite` Deno tests, the invitee flow tests, the mutants "Remove the withdrawal statement in `accept_relationship_invite_v2`" and "Accept before RI-3 in `OnboardingGate`"), §8 W4a, W4b and the W4 group gate, §9, §11. Format reference: `docs/superpowers/plans/2026-10-26-spec1-w3-home.md`.

## Global Constraints

- Work in the main working tree on `main` (`/Users/user/attune`). W1 (360db8d1), W2 (8b3477ad) and W3 (c211b262) are committed; the owner may have uncommitted edits: never revert, stash, stage, checkout or reformat them. Every edit below is an exact-string replacement; if the text to replace has moved because a later fix changed it, apply the same change to the current text and say so in the task report.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm`. Tasks end with "Run tests", not "Commit".
- Never `dart format` a pre-existing file (the repo predates the 3.7 formatter). Format only the files this plan creates, by path (Task 8, Step 9 lists them).
- **SQL:** contracts run only on the local scratch database `attune_spec3a`, only as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`, inside the file's own `BEGIN … ROLLBACK`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`; Task 1 **edits** `scripts/local_pg_grants.sql` and never runs it.
- **Migrations** (W4a only): `20261102100000_accept_invite_v2.sql` + `20261102100010_accept_invite_v2_grants.sql`, later than every migration in the tree (the newest is W3's `20261026100010_journal_reminders_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261102100000` when Task 1 starts, shift both to the next free hour, keeping the order, and change the twin's header, the `\i` line and every command below to match. Each file is one `BEGIN; … COMMIT;`, idempotent (applied twice, `exit=0` both times), `SET LOCAL lock_timeout = '5s'`, every `SECURITY DEFINER` function has `SET search_path = ''` and schema-qualifies every name, server-only objects are revoked inside the migration itself and again in the twin, grants are explicit, nothing reaches `anon`; `authenticated` gets EXECUTE on `preview_relationship_invite` only; `service_role` gets EXECUTE on `accept_relationship_invite_v2` and `relationship_invite_eligibility`. The one new table is `private.invite_preview_attempts` (no client or service-role DML: only the definer functions and the cron touch it). No `CREATE INDEX CONCURRENTLY`.
- **Flags:** W4 adds no flag. `flow_couples_v2` (inserted false by W1c; it needs `flow_paths_v2`, which needs `flow_signin_v2`, §2.5) gates every W4b screen change; `supabase/sql/dev_enable_spec1_flags.sql` already turns it on in development, so it doesn't change. The W4a server changes are unflagged security hardening (§2.5: "the atomic accept" is never behind a flag); the age checks inside them follow `flow_signin_v2` (§4.3). Unflagged W4b changes, each tested: the `InviteCard` accessibility fix (P-8), Ask 2 saving as it goes (P-18), the Install Referrer read (P-17).
- **Never touch:** `lib/features/games/**`, `ChatScreen`'s Games entry points, `UniversalBubble` / `ChatTextField` parameters, `lib/features/auth/utility/auth_exports.dart`, every Games route in `app_router.dart` (W3's `test/architecture/games_untouched_test.dart` pins them; Task 6 edits the router and must leave it green), `lib/features/opinions/**` (Opinions stays exactly as is), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, every applied migration, every existing SQL contract, `supabase/sql/dev_enable_spec1_flags.sql`, the legacy `OnboardingGate` (`onboarding_gate.dart`, P-10). HomeScreen's latch block (from `if (isAuthenticated && !_gateData.isComplete) {` to `_redirectingToOnboarding = false;`) stays byte-identical (Task 1 saves it, every gate diffs it).
- **Dates and times** shown to people use `MyDateFormat` only, a date and its detail joined with `MyDateFormat.join` (`' - '`). W4 shows no date (the invite's expiry is never displayed; RI-4 says "expired").
- **Names:** before linking the partner is named by R1's first name (this phone only, `attune.flow.<uid>.partner_first_name`) or the preview's `inviter_first_name`, else "your partner"; never "he", "she", "they" or "both of you". W4 copy names only the partner, never the couple as a unit, so `coupleNameProvider` (placeholder `'Couples'`) has no caller here (D16).
- **Shared phones (D8, W2 rule):** no one's name or date of birth reaches another account. The partner name and the day-30 mark are per account and wiped at sign-out; the inviter's first name is read only by the account that holds the code, after sign-in (§3.8 RI-1); a stored code that RI-3 doesn't join is dropped (P-10).
- **Copy:** every new string is an English `flow_*` key appended to `lib/i10n/app_en.arb` by W3's `.superpowers/sdd/2026-10-26-spec1-w3/arb_append.py` (refuses a key the file already has) and generated with `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package`; the other locales fall back to English. Every fragment is ASCII only: the one non-ASCII character in the copy, "→" in the invite message, is the JSON escape `→`, written by the fragment file and checked with `grep -cP '[^\x00-\x7F]'` (prints `0`) and `grep -c 'u2192'` (prints `1`). Dart string literals use `→` too; non-ASCII appears only in comments, as elsewhere in the repo. "WhatsApp" appears in copy because the spec's own words name it (R1 "Send on WhatsApp", RI-4 "Ask {name} on WhatsApp").
- **UI:** Material 3 from the app theme and W2's flow widgets (`FlowFrame`, `FlowPrimaryButton`, `FlowSecondaryButton`, `FlowTextLink`, `FlowTextField`, `FlowErrorLine`); every new screen inside `FlowFrame` (which wraps `AllowLargeText`), every control labelled, targets ≥ 48 dp, text contrast ≥ 4.5:1, errors announced and shown with an icon, goldens at 1.0, 1.3, 2.0 and right to left (W2's `expectFlowGoldens`), `androidTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline` on every new screen (`expectFlowGuidelines`). R4 is the one calm Relationship celebration (§2.2: `SettleIn`, ≤ 600 ms, one light haptic, static under reduce motion); RI-4 and every refusal state are never animated.
- **Permanent constraints:** no couple report combining both people's insights (W4 reads and writes no insight); asymmetric behaviour data stays self-facing (the Ask 2 progress is the answerer's own, on their phone); safety notifications go to the at-risk person only (W4 sends one push, `invite_accepted`, to the inviter, unchanged); quick exit works everywhere (the Ask 2 wipe is one bounded registry entry, Task 8; no protective setting is touched).
- **No deploys.** `supabase db push`, `supabase functions deploy`, dashboard and store work are the owner's ("Owner deploy checklist"). Don't read `.env*`, credentials or the keychain. One new package (`play_install_referrer: 0.5.0`, the spec's §5.2 choice); `flutter pub get` is run once in Task 8.
- **Regression gate at the end of each sub-wave** (Tasks 3 and 8): the full `flutter test` passes; `flutter analyze --no-pub lib test` shows no `error` line that the Task 1 baseline didn't; the Games test passes; no Opinions, Games or `auth_exports.dart` change; the latch is unchanged; every SQL contract on `attune_spec3a` shows no new FAIL against the Task 1 baseline and `invite_v2_contracts.sql` is PASS; `deno test --allow-read accept-invite/` passes.

## Review Focus

1. **Two people accept the same code at the same moment, or the inviter switches path while their partner accepts.** Expect one link and a clear refusal for the other ("Invite has already been accepted"), no deadlock between an accept and a cancel or a path switch (two people accepting each other's invites at the same instant can abort one transaction; nothing is corrupted) or two active rows: the accept locks the acceptor's users row, then the invite, the order `set_my_path` uses. Tests: Task 1 contract section A (`the accept does not lock the users row before relationships`, mutant `lock`), section C (`someone else reused an accepted code`); the re-check after waiting is in the function body (`Someone accepted it while this call waited`).
2. **A shared phone: Ama opens Yaw's link while signed out, then Kofi signs in on the same phone within a day.** Kofi must never be linked to Yaw without a tap: under `flow_couples_v2` neither the gate nor HomeScreen accepts; RI-3 shows "Join Yaw?", and "Not now" drops the code so it can't wait for the next account (D9). Tests: Task 6 `join_routing_test.dart` (`gate, couples v2, A6 owed: RI-3, nothing accepted`, `HomeScreen, couples v2: opens RI-3, never accepts`), `join_invite_screen_test.dart` (`"Not now" drops the code`).
3. **An under-18 inviter or acceptor, or a legacy account without a date of birth.** The inviter can't make an invite (428 / 403); the acceptor sees only the neutral "We couldn't link these accounts…"; a missing date of birth goes to A2 with the code kept; nothing ever says "18". Tests: Task 1 section B (`a 17-year-old inviter`, `an inviter without a DOB`, mutant `inviter_age`), Task 2 (`the inviter's age rule`), Task 6 (`an age refusal is neutral; no date of birth goes to A2, code kept`).
4. **A server refusal whose English the app used to show** (the cap, "Invite code is invalid", `signup:incomplete`). Expect the app's own words everywhere in R1, R3 and RI-3. Tests: Task 3 `invite_refusal_test.dart` (`every failure has the app's words`), Task 5 (`a refusal is the app's words, never the server's`), Task 7 (`a refusal is the app's words`).
5. **An accept that fails half-way (a trigger error after the update).** Expect nothing left behind: the invite still pending, the acceptor's own invite still there, the path unchanged. Tests: Task 1 section D (`a failed accept left part of its work behind`), mutant `withdraw` (§7.4).

## Decisions found while verifying the code (read before Task 1)

Each is a verified fact about today's code (W1 360db8d1, W2 8b3477ad, W3 c211b262) or the database, with the smallest change that keeps the spec's intent. *Changes spec intent* marks the ones the owner should see.

- **P-1 (migration names).** Migration 9 is `20261102100000_accept_invite_v2.sql` and its twin `…100010_accept_invite_v2_grants.sql` (§4.7 #9, timestamps at build time).
- **P-2 (the interim guard, replaced).** W2's `_shared/sign_up_guard.ts` read `feature_flags` itself and answered 409 `signup:incomplete` / 503 `flags:unavailable`. W4a keeps the file and its exported names but asks the database once: `public.relationship_invite_eligibility(p_user) → text` (service role, in migration 9) returns `legacy` (`flow_signin_v2` effectively off: today's `ensureUserRow`), `signup_incomplete` (no users row: 409, nothing written, D8), `age_required`, `not_possible` or `ok`. An unreadable or unknown answer still fails closed (503 `flags:unavailable`), never `legacy`. `create-relationship-invite` then applies the inviter rule (428 `invite:age_required`, 403 `invite:not_possible`, §4.5); `accept-invite` leaves the ages to the SQL function. The function is not in §4.3's table; it is the smallest seam that keeps the flag read, the account and the date of birth one answer.
- **P-3 (lock order, W1 carry).** `accept_relationship_invite_v2` locks the acceptor's `users` row `FOR UPDATE` first, then the pending `relationships` row `FOR UPDATE`, as `set_my_path` does (users, then the withdraw's relationships delete). It never locks the inviter's users row, so an inviter's concurrent `set_my_path` (users lock, then a delete that waits on the invite) can't form a cycle with it. After waiting for the invite, a call re-reads the acceptances (READ COMMITTED) and answers `invite:already_accepted`. The contract pins the order in the function's source (mutant `lock`).
- **P-4 (the preview).** `preview_relationship_invite` needs a verified phone (`invite:phone_required`), counts every try, invalid codes included (no enumeration, §6.4), refuses past 10 an hour or 30 a day with `invite:try_later` and records nothing then; `linked` means "you already accepted this code". The inviter's first name uses `get_my_home_state`'s rule (first word, never a phone number), now in `private.invite_first_name`.
- **P-5 (accept metrics).** `invite_accepted` on every accept; `invite_accepted_24h` and `invite_accepted_7d` when the invite was made within a day / a week (cumulative: a two-hour accept counts in both). A replay counts nothing. All three keys are under W1b's `invite_accepted` server prefix.
- **P-6 (accept-invite's shape).** The work moves to `accept-invite/accept.ts` (exported, so Deno tests drive it with a fake client); `index.ts` keeps `Deno.serve`, `ensureUserRow` and `handleError`. Statuses and messages stay today's (404 invalid, 409 own / already accepted / already in a relationship with the pinned "You're already in a relationship" prefix, 410 expired); the new refusals are 403 `invite:phone_required`, 428 `invite:age_required`, 403 `invite:not_possible`. Every refusal body also carries `code`. The push goes to the inviter once (never on a replay) and a failed push never fails the accept.
- **P-7 (the app's words for invite errors; carried item 3).** `RelationshipInviteException` gains `kind` (`InviteRefusalKind`), read from the W4a `code` (accept), the inviter's 428/403 (create) and the preview's `invite:try_later`; `inviteErrorCopy(loc, error)` maps every kind to `flow_*` copy. R1 (both the interim `InvitePartnerScreen` and the new step), R3 and RI-3 show only that copy. Flag-off screens that predate Spec 1 (the Chat locked screen, the legacy gate's notice) keep today's text.
- **P-8 (InviteCard, carried item 2).** The shared card failed the guidelines (W3 P-30, batch-3 report: 41.6 dp buttons, 32/42 dp selectable code and link, 3.31:1 and 3.04:1 text). Fixed, unflagged, words unchanged: buttons 48 dp with `onSurface` labels, the code and link plain text in `onSurface` (the code read out as one item, "Invite code K 7 P 2 Q M"), the QR excluded from semantics. It changes how the card looks on R1, R3, the couples waiting step and the Chat locked screen (taller buttons, darker labels); R3's pending goldens are regenerated. *Owner decision 4.*
- **P-9 (R1).** Under `flow_couples_v2` `InvitePartnerScreen` returns `InvitePartnerStep` with the same arguments, so every caller (the gate, `/invite-partner`, R3) gets R1. The invite is made on opening, or, from another path (`switch=1`), on the first send, which is also the switch (§3.12); the preview shows "(your code)" until then. WhatsApp is offered only when `whatsapp://send` can open (iOS `LSApplicationQueriesSchemes`, Android `<queries>`), and falls back to the share sheet if it doesn't open. Pidgin is behind `kPidginRegisterReviewed = false` (W4 group gate). With no name, Simple reads "Hi, I'd like…" (the comma kept, so it reads correctly), Casual "Hey! I found…", Pidgin "Make we try…". *Changes spec intent* (Simple's blank-name comma).
- **P-10 (D9: one accept site, carried item 4).** Under `flow_couples_v2` a stored code is accepted only by `JoinInviteScreen` (`/join-invite`), after "Join {name}": the v2 gate goes there instead of `_acceptStoredInvite` (A6 owed, nothing owed, or a typed code), and HomeScreen's v2 reconcile pushes it once per visit while home is on top. With the flag off, today's accept stays (§2.5 "Off means … silent accept"); the legacy `OnboardingGate` is untouched, because it is only shown with `flow_paths_v2` off, which makes `flow_couples_v2` effectively off. Every way out of RI-3 except a retryable failure ("Not now", "Choose another way", an expired, invalid or own code, a refusal) drops the stored code, so it can't wait for the next account on the phone. *Owner decisions 2 and 5.*
- **P-11 ("Choose another way").** RI-3's link goes to A6 when no path is chosen yet; with a path already chosen it opens Settings → How you use Attune (A6 would be skipped by the gate). *Changes spec intent* (§3.8 says "→ A6").
- **P-12 (RI copy and keys).** W2 already owns `flow_joinTitle` / `flow_joinBody` (Welcome's "Join Attune"), so RI-3's keys are `flow_ri3Title`, `flow_ri3Body`, `flow_ri3Button` (+ `Unnamed`). With no name from the server: "Join your partner?", "Join". RI-4's one sentence is split into a title "This invite has expired." and the line "Ask {name} to send a new one." "Too many tries" (no spec copy): "You've checked a lot of codes. Try again in a little while."
- **P-13 (R4 on both phones).** The acceptor sees R4 as `JoinInviteScreen`'s last step and its moment is recorded at once. The inviter sees it through `LinkedMomentGate` in Tab 2 the first time this phone sees the relationship linked. `HomeTabTwo` stays a `StatelessWidget` (W3's `relationship_space_more_test.dart` calls its `build`) and takes `couplesV2` from the Tab 2 seam (`homeTabTwoBuilderProvider` reads `flowCouplesV2Provider` when it builds). Closing R4 deletes R1's partner name (§4.8: kept until linking).
- **P-14 (couples linked before the flag).** "Shown once on each phone" (§3.8 R4) means every couple already linked when `flow_couples_v2` turns on sees "You're both here" once. It is also their only notification ask: W3's `automaticPushAskAllowed` stops the automatic ask under `flow_couples_v2` (W3 P-24). *Owner decision 1.*
- **P-15 (the linked moment's key).** The spec's `attune.flow.<uid>.linked_moment.<relationshipId>` would be removed by `PreferencesService.clearUserData()` at every sign-out, so R4 would come back after each sign-in. The key is `attune.linked_moment:<uid>:<relationshipId>` and its prefix joins `PreferencesService.keptPrefixes` (it holds no name). *Changes spec intent* (key name).
- **P-16 (days 7 and 30).** Day 7's "Send a new invite" withdraws the open invites with today's zero-argument RPC (the path stays Relationship, Q7), makes a new one and opens R1's share step; it counts `invite_new_day7`. Day 30 (from `get_my_invite_age`) shows once per phone, marked when it is shown (`attune.flow.<uid>.invite_day30`, wiped at sign-out with the partner name) and counts `invite_day30_shown`; its "Send a new invite" is the same action. R3's "Invite your partner" and "Send again" open R1's share step (`/invite-partner`).
- **P-17 (Install Referrer).** `play_install_referrer` 0.5.0 (0.6.0 needs Dart 3.12; this repo is on Dart 3.7). Read once per install on Android (`attune.install_referrer.read`, kept across sign-out in `PreferencesService.keptKeys`), its `invite_code` stored like a link opened while signed out (the anonymous slot, 24-hour claim), never over a code already waiting, never navigated to, never throws. Unflagged: it only stores a code; joining is still RI-3 (or today's flag-off accept).
- **P-18 (Ask 2, R5).** Unflagged: answers and anchors are saved on every change to `attune.ask2.<uid>.<relationshipId>`; reopening skips the intro and resumes at the first unanswered question (or the anchors); a successful submit clears it; a failed submit keeps it (the old TODO "answers are genuinely lost" no longer holds). With no account or no SharedPreferences (a bare test host) nothing is saved, so W3's `ask2_flow_test.dart` is unchanged.
- **P-19 (R2).** R1 shows the heads-up after the first send; R3's heads-up names the partner from R1's name until the server has one.
- **P-20 (fixtures).** The contract uses ids `4e4a0000-0000-0000-0000-0000000000NN` (relationships `…0001NN`) and phones `+15558200NN` (§7.1's `82xx` range), on `auth.users` and `public.users`.

## Owner questions (open; the plan builds the recommendation)

1. **R4 for couples already linked when `flow_couples_v2` turns on (P-14).** *Recommendation:* accept; it is also the only notification ask they get under the flag.
2. **RI-3 "Not now" drops the stored code (P-10).** *Recommendation:* accept; a kept code is exactly what the next person on a shared phone inherits, and "My partner already invited me" takes it again in one step.
3. **"Choose another way" with a path already chosen opens Settings → How you use Attune (P-11).** *Recommendation:* accept; A6 would be skipped.
4. **The InviteCard fix changes the card's look on flag-off screens (P-8).** *Recommendation:* accept; it is an accessibility fix, and the words are unchanged.
5. **With `flow_couples_v2` off, today's silent accept stays on the legacy path (P-10, §2.5).** *Recommendation:* keep the spec; W1c's scoped 24-hour claim bounds it, and production turns `flow_couples_v2` on with W4. *Final review #1 (closes F-10):* the Install Referrer's code is never a source for this: it is kept only to fill RI-1's code field (`attune.install_referrer.code`), never the claimable invite slot, so it is joined only after the person's own Continue (and "Join" under the flag).

## W1/W2/W3 interfaces this plan consumes (adjust here if a later fix renames one)

- SQL (W1b, W1c, W3): `public.users` (`path`, `path_previous`, `display_name`), `public.account_birthdates`, `public.account_age(uuid) → int` (definer callers only), `public.verified_phone(uuid) → text`, `private.spec1_flag_on(text) → boolean` (effective flags), `public.set_user_path_internal(uuid, text)` (locks users `FOR UPDATE`), `public.set_my_path(text, boolean)`, `public.withdraw_my_pending_invites()` and `(boolean)`, `public.get_my_invite_age() → int`, `public.get_my_home_state()`, `private.bump_metric_internal(text)` (prefix `invite_accepted`), `private.normalize_display_name(text)`, `public.relationships`, `public.relationship_invite_acceptances` (`invite_code_hash` PK = SHA-256 hex of the code), the `relationship_one_open_chapter_guard` trigger (`relationship:already_open`), `metric_client_keys` rows `invite_shared:{whatsapp|share|qr|copy}`, `invite_new_day7`, `invite_day30_shown`, `push_ask_{shown|granted}:r4`.
- Edge (W1a, W2): `_shared/attune_auth.ts` (`HttpError`, `jsonResponse`, `requireUser`, `serviceRoleClient`), `_shared/push_queue.ts` (`enqueuePush`), `_shared/sign_up_guard.ts` (`ensureInviteAccount`, `SIGNUP_INCOMPLETE`, `FLAGS_UNAVAILABLE`; rewritten in Task 2), both functions' `ensureUserRow`.
- Dart (W1): `HomeState`, `HomeLink` (`relationshipId`, `partnerFirstName`), `AppPath`, `AppTab`, `LinkState` (`lib/features/onboarding/domain/home_state.dart`); `OnboardingStore` (`userScopePrefix`, `anonymousScope`, `pendingInviteCode`, `storePendingInviteCode`, `clearPendingInviteCode`, `pendingSignUp`, static `storeInviteFromLink(prefs, code, {userId})`); `metricCounterProvider`, `ClientMetricKey.inviteShared{Whatsapp|Share|Qr|Copy}`, `.inviteNewDay7`, `.inviteDay30Shown`.
- Dart (W2): `FlowFrame`, `FlowPrimaryButton`, `FlowSecondaryButton`, `FlowTextLink`, `FlowTextField`, `FlowErrorLine`; `normalizeInviteCode(String) → String?` (`lib/features/auth/sign_up/domain/invite_code.dart`); `InviteLandingScreen` (RI-1/RI-2 signed out, unchanged); `sign_in_redirect.dart` (`inviteLinkLocation`: signed-in links go to `/onboarding`, unchanged); `test/helpers/flow_harness.dart` (`pumpFlowScreen`, `expectFlowGoldens`, `expectFlowGuidelines`, `FakePublicConfigGateway`).
- Dart (W3): `flowCouplesV2Provider` (`lib/features/onboarding/presentation/providers/flow_flags.dart`); `homeStateProvider(uid)` (`HomeSnapshot.path`, `.isComplete`, `.linkDetail`, notifier `refresh()`), `homeStateServiceProvider`, `HomeStateService.withdrawPendingInvites`; `homeAuthProvider`, `homeTabTwoBuilderProvider` (`lib/home/home_seams.dart`); `HomeTabTwo`; `homeLocation(tab:)`; `invitePartnerServiceProvider` and `InvitePartnerScreen` (`onDone`, `switchPath`, `pauseConfirmed`); `OnboardingGateV2` (`_acceptStoredInvite`, `_go`, `InviteCodeStep`); `choosePath`, `PathChoiceOutcome`, `showFlowConfirm`; `RelationshipSpaceScreen`, `PendingInviteGuide`; `PushAskRow`, `PushAskContext.r2|r4`, `pushAskerProvider`; `DeviceWipeRegistry`, `DeviceWipeEntry`, `WipeMoment`, `registerDeviceWipes`, `removePrefsKeys`; `PreferencesService.keptKeys|keptPrefixes`; `RouteNames.invitePartner|howYouUseAttune|onboarding|home`; test helpers `FakeHomeStateGateway`, `homeJson`, `FakeFlowFlagsGateway`, `FakeInvites`, `FakeHomeAuth`, `testUser`, `pumpHome`, `snapshotOf`, `FakePushAsker`.

## File map

**W4a (Tasks 1–3): the server, the edge functions, the app's reading of them**
- Create `supabase/migrations/20261102100000_accept_invite_v2.sql`, `…100010_accept_invite_v2_grants.sql`, `supabase/tests/invite_v2_contracts.sql`; modify `scripts/local_pg_grants.sql` (Task 1).
- Create `supabase/functions/accept-invite/accept.ts`, `accept-invite/accept.test.ts`; replace `supabase/functions/_shared/sign_up_guard.ts`, `accept-invite/index.ts`, `accept-invite/index.test.ts`, `accept-invite/signup_incomplete_guard.test.ts`; modify `supabase/functions/create-relationship-invite/index.ts` (Task 2).
- Replace `lib/features/relationships/data/relationship_invite_service.dart`; create `lib/features/relationships/presentation/invite_error_copy.dart`; modify `lib/features/onboarding/presentation/screens/invite_partner_screen.dart` (the interim screen's error), `test/helpers/fake_invites.dart`, `lib/i10n/app_en.arb` (Task 3).

**W4b (Tasks 4–8): the phone, behind `flow_couples_v2`**
- Create `lib/features/relationships/data/{invite_messages,invite_device_store}.dart`; modify `lib/app/device_wipes.dart`, `lib/core/services/shared_preferences_service.dart` (Task 4).
- Replace `lib/features/onboarding/presentation/widgets/invite_card.dart`; create `lib/features/relationships/presentation/invite_share_actions.dart`, `lib/features/onboarding/presentation/widgets/invite_partner_step.dart`, `test/helpers/fake_share_actions.dart`; modify `invite_partner_screen.dart`, `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml` (Task 5).
- Create `lib/features/relationships/presentation/screens/join_invite_screen.dart`, `lib/features/relationships/presentation/widgets/linked_moment.dart`; modify `lib/app/routing/app_router.dart`, `lib/features/onboarding/presentation/screens/onboarding_gate_v2.dart`, `lib/home/home_screen.dart` (outside the latch), `test/helpers/home_harness.dart` (Task 6).
- Create `lib/features/relationships/presentation/widgets/linked_moment_gate.dart`; replace `lib/home/widgets/home_tab_two.dart`; modify `lib/home/home_seams.dart`, `lib/features/onboarding/presentation/widgets/pending_invite_guide.dart`, `lib/features/relationships/presentation/screens/relationship_space_screen.dart` (Task 7).
- Create `lib/features/onboarding/data/ask2_progress_store.dart`, `lib/core/platform/install_referrer.dart`; modify `lib/features/onboarding/presentation/screens/ask2_flow.dart`, `lib/app/device_wipes.dart`, `lib/core/services/shared_preferences_service.dart`, `lib/main.dart`, `pubspec.yaml` (+ `pubspec.lock` by `flutter pub get`) (Task 8).

Tests live under `supabase/tests/`, `supabase/functions/accept-invite/`, `test/features/relationships/` (`w4/`), `test/features/onboarding/w4/`, `test/core/platform/` and `test/helpers/`.

**Not edited:** HomeScreen's latch block, `lib/features/onboarding/presentation/screens/onboarding_gate.dart`, `lib/features/auth/sign_up/presentation/screens/invite_landing_screen.dart`, `lib/app/routing/sign_in_redirect.dart`, `lib/features/chat/**` (the Chat locked screen gets the card fix through `InviteCard` only), `lib/features/opinions/**`, `lib/features/games/**`, `auth_exports.dart`, `supabase/sql/dev_enable_spec1_flags.sql`, every applied migration and existing contract, every existing test except the three W2 invite-guard Deno files Task 2 replaces and the two helpers Tasks 3 and 6 extend.

---

### Task 1: Baselines and migration 9: the accept, the eligibility, the preview, the attempts' retention (W4a; §4.2, §4.3 W4a, §4.6, §4.7 #9, §7.1, §7.4, D7, D8, P-1–P-5, P-20)

**Files:**
- Create: `supabase/migrations/20261102100000_accept_invite_v2.sql`
- Create: `supabase/migrations/20261102100010_accept_invite_v2_grants.sql`
- Create: `supabase/tests/invite_v2_contracts.sql`
- Modify: `scripts/local_pg_grants.sql` (one `\i` line after W3c's; never run)

**Interfaces:**
- Consumes: the W1/W3 SQL listed above.
- Produces: table `private.invite_preview_attempts (user_id uuid → auth.users ON DELETE CASCADE, attempted_at timestamptz)`; `private.invite_first_name(uuid) → text`; `public.relationship_invite_eligibility(p_user uuid) → text` (`legacy` | `signup_incomplete` | `age_required` | `not_possible` | `ok`; service role); `public.accept_relationship_invite_v2(p_acceptor uuid, p_invite_code text) → jsonb` (`{relationship_id, status, idempotent, inviter_id}`; raises `invite:invalid`, `invite:own`, `invite:expired`, `invite:already_accepted`, `invite:already_in_relationship`, `invite:phone_required`, `invite:age_required`, `invite:not_possible`; service role); `public.preview_relationship_invite(p_code text) → jsonb` (`{state: ok|expired|invalid|own|linked, inviter_first_name}`; raises `invite:not_signed_in`, `invite:phone_required`, `invite:try_later`; authenticated); `private.purge_invite_preview_attempts() → int`; cron `invite-preview-retention` at `39 * * * *`.

- [ ] **Step 1: Confirm the target, W3 green, and record the baselines**

```bash
cd /Users/user/attune
psql -X -d attune_spec3a -Atc 'select current_database()'
ls supabase/migrations | sort | tail -1
mkdir -p .superpowers/sdd/2026-11-02-spec1-w4
git status --short > .superpowers/sdd/2026-11-02-spec1-w4/git-status-before.txt
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-11-02-spec1-w4/sql-baseline.txt
grep '^FAIL' .superpowers/sdd/2026-11-02-spec1-w4/sql-baseline.txt
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test > .superpowers/sdd/2026-11-02-spec1-w4/analyze-baseline.txt 2>&1
grep -E '^\s*error ' .superpowers/sdd/2026-11-02-spec1-w4/analyze-baseline.txt | sed -E 's/:[0-9]+:[0-9]+//' | sort -u > .superpowers/sdd/2026-11-02-spec1-w4/analyze-errors-baseline.txt
wc -l < .superpowers/sdd/2026-11-02-spec1-w4/analyze-errors-baseline.txt
awk '/if \(isAuthenticated && !_gateData.isComplete\) \{/,/_redirectingToOnboarding = false;/' lib/home/home_screen.dart > .superpowers/sdd/2026-11-02-spec1-w4/latch-before.txt
wc -l < .superpowers/sdd/2026-11-02-spec1-w4/latch-before.txt
(cd supabase/functions && deno test --allow-read accept-invite/ 2>&1 | grep -E 'passed|failed' | tail -1)
git diff --stat -- lib/features/opinions lib/features/games lib/features/auth/utility/auth_exports.dart | tail -1
```

Expected: `attune_spec3a`; `20261026100010_journal_reminders_grants.sql` (or a later fix-up below `20261102100000`); the pre-existing FAILs (when this plan was written: the `ai_*` contracts, `couple_map_presence`, `reminder_delivery`, `together_events`, and the time-dependent `ai_session_end_share_contracts.sql`; keep whatever you get, every gate compares with it); `All tests passed!`; `0`; a non-zero line count for the latch; `ok | 9 passed | 0 failed`; no Opinions or Games diff. If the Flutter suite isn't green, stop and report.

- [ ] **Step 2: Write the failing contract**

Create `supabase/tests/invite_v2_contracts.sql` with exactly:

```sql
-- supabase/tests/invite_v2_contracts.sql
-- Spec 1 W4a (§4.3 W4a, §4.6, §7.1, D7, D8): the one-transaction accept,
-- the inviter and acceptor age checks, the preview and its rate limit, the
-- attempts' retention. One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/invite_v2_contracts.sql
-- Fixture ids 4e4a0000-0000-0000-0000-0000000000NN (relationships
-- 4e4a0000-0000-0000-0000-0000000001NN); phones +15558200NN, set on
-- auth.users and public.users. Every refusal is checked by its message.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('4e4a0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.rel(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('4e4a0000-0000-0000-0000-0000000001' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', coalesce(p::text, ''), true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.error_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN raise_exception OR insufficient_privilege THEN
  RETURN SQLERRM;
END $$;

-- An account: a verified Auth phone, a users row named [p_name] (NULL: no
-- users row) and, when [p_age] is set, a date of birth that many years ago.
CREATE FUNCTION pg_temp.person(p_n text, p_name text, p_age int) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at)
  VALUES (pg_temp.id(p_n), '+155582000' || p_n, now());
  IF p_name IS NOT NULL THEN
    INSERT INTO public.users (id, phone, display_name)
    VALUES (pg_temp.id(p_n), '+155582000' || p_n, p_name);
  END IF;
  IF p_age IS NOT NULL THEN
    INSERT INTO public.account_birthdates (user_id, birth_date)
    VALUES (pg_temp.id(p_n), ((now() AT TIME ZONE 'utc')::date - make_interval(years => p_age))::date - 1);
  END IF;
END $$;

-- A pending invite from [p_inviter] with [p_code], made [p_ago] ago.
CREATE FUNCTION pg_temp.invite(p_rel text, p_inviter text, p_code text, p_ago interval) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at, created_at)
  VALUES (pg_temp.rel(p_rel), pg_temp.id(p_inviter), 'pending', p_code,
          now() - p_ago + interval '7 days', now() - p_ago);
END $$;

CREATE FUNCTION pg_temp.accept_error(p_n text, p_code text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  RETURN pg_temp.error_of(format(
    'SELECT public.accept_relationship_invite_v2(%L, %L)', pg_temp.id(p_n), p_code));
END $$;

CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT c.count FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0);
$$;

CREATE FUNCTION pg_temp.flag(p_key text, p_on boolean) RETURNS void LANGUAGE sql AS $$
  UPDATE public.feature_flags SET enabled = p_on WHERE key = p_key;
$$;

-- =====================================================================
-- A. Objects, grants, the cron, the lock order.
-- =====================================================================
DO $$
DECLARE
  v_src text;
BEGIN
  IF to_regprocedure('public.accept_relationship_invite_v2(uuid,text)') IS NULL
     OR to_regprocedure('public.preview_relationship_invite(text)') IS NULL
     OR to_regprocedure('public.relationship_invite_eligibility(uuid)') IS NULL
     OR to_regprocedure('private.purge_invite_preview_attempts()') IS NULL
     OR to_regclass('private.invite_preview_attempts') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W4a objects are missing (accept_relationship_invite_v2, preview_relationship_invite, relationship_invite_eligibility, invite_preview_attempts)';
  END IF;
  IF has_function_privilege('authenticated', 'public.accept_relationship_invite_v2(uuid,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.accept_relationship_invite_v2(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.accept_relationship_invite_v2(uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.relationship_invite_eligibility(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.relationship_invite_eligibility(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.relationship_invite_eligibility(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.preview_relationship_invite(text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.preview_relationship_invite(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.purge_invite_preview_attempts()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.invite_first_name(uuid)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'private.invite_preview_attempts', 'SELECT')
     OR has_table_privilege('authenticated', 'private.invite_preview_attempts', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W4a grants are wrong';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job
                  WHERE jobname = 'invite-preview-retention' AND schedule = '39 * * * *') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: invite-preview-retention is not scheduled at 39 * * * *';
  END IF;
  -- W1 carry: the users row is locked before any relationships row, the
  -- order set_my_path uses.
  v_src := (SELECT p.prosrc FROM pg_proc AS p
             WHERE p.oid = 'public.accept_relationship_invite_v2(uuid,text)'::regprocedure);
  IF position('WHERE u.id = p_acceptor FOR UPDATE' IN v_src) = 0
     OR position('WHERE u.id = p_acceptor FOR UPDATE' IN v_src)
        > position('WHERE r.invite_code = v_code AND r.status = ''pending''' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accept does not lock the users row before relationships';
  END IF;
END $$;

-- =====================================================================
-- B. Refusals, flow_signin_v2 off and on. Fixtures 01-19.
-- =====================================================================
DO $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.flag('flow_signin_v2', false);
  PERFORM pg_temp.person('01', 'Yaw Mensah', 30);     -- inviter
  PERFORM pg_temp.person('02', 'Ama Owusu', 29);      -- acceptor
  PERFORM pg_temp.person('03', NULL, NULL);           -- no users row
  PERFORM pg_temp.person('04', 'Kofi Boateng', 31);   -- in an active relationship
  PERFORM pg_temp.person('05', 'Esi Ofori', 28);      -- Kofi's partner
  PERFORM pg_temp.person('06', 'Abena Paused', 27);   -- in a paused relationship
  PERFORM pg_temp.person('07', 'Kwame Paused', 27);
  PERFORM pg_temp.person('08', 'Adjoa NoPhone', 25);  -- phone not verified
  UPDATE auth.users SET phone_confirmed_at = NULL WHERE id = pg_temp.id('08');
  PERFORM pg_temp.invite('01', '01', 'K7P2QM', interval '1 hour');
  PERFORM pg_temp.invite('02', '01', 'OLD7XY', interval '8 days');
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at)
  VALUES (pg_temp.rel('03'), pg_temp.id('04'), pg_temp.id('05'), 'active', current_date, now()),
         (pg_temp.rel('04'), pg_temp.id('06'), pg_temp.id('07'), 'paused', current_date, now());

  v_msg := pg_temp.accept_error('02', 'NOSUCH');
  IF v_msg IS DISTINCT FROM 'invite:invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown code (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('02', 'K7');
  IF v_msg IS DISTINCT FROM 'invite:invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed code (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('01', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:own' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: own invite (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('02', 'OLD7XY');
  IF v_msg IS DISTINCT FROM 'invite:expired' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an expired invite (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('04', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:already_in_relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an active member accepted (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('06', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:already_in_relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused member accepted (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('08', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:phone_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unverified phone accepted (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- D8: no users row is never a new users row.
  v_msg := pg_temp.accept_error('03', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:phone_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account with no users row (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF EXISTS (SELECT 1 FROM public.users WHERE id = pg_temp.id('03')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accept created a users row (D8)';
  END IF;
  IF (SELECT status FROM public.relationships WHERE id = pg_temp.rel('01')) <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused accept changed the invite';
  END IF;
END $$;

-- Ages, with flow_signin_v2 on (fixtures 11-16).
DO $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.flag('flow_signin_v2', true);
  PERFORM pg_temp.person('11', 'Akua NoDob', NULL);    -- acceptor, no DOB
  PERFORM pg_temp.person('12', 'Yaa Minor', 17);       -- acceptor, 17
  PERFORM pg_temp.person('13', 'Kojo NoDob', NULL);    -- inviter, no DOB
  PERFORM pg_temp.person('14', 'Efua Minor', 17);      -- inviter, 17
  PERFORM pg_temp.person('15', 'Nana Adult', 40);      -- acceptor, adult
  PERFORM pg_temp.invite('13', '13', 'NODOB2', interval '1 hour');
  PERFORM pg_temp.invite('14', '14', 'MINOR2', interval '1 hour');

  v_msg := pg_temp.accept_error('11', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:age_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an acceptor without a DOB (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('12', 'K7P2QM');
  IF v_msg IS DISTINCT FROM 'invite:not_possible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 17-year-old acceptor (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('15', 'NODOB2');
  IF v_msg IS DISTINCT FROM 'invite:not_possible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inviter without a DOB (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.accept_error('15', 'MINOR2');
  IF v_msg IS DISTINCT FROM 'invite:not_possible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 17-year-old inviter (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- The eligibility both edge functions check first.
  IF public.relationship_invite_eligibility(pg_temp.id('15')) <> 'ok'
     OR public.relationship_invite_eligibility(pg_temp.id('13')) <> 'age_required'
     OR public.relationship_invite_eligibility(pg_temp.id('14')) <> 'not_possible'
     OR public.relationship_invite_eligibility(pg_temp.id('03')) <> 'signup_incomplete' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: relationship_invite_eligibility with the flag on';
  END IF;
  PERFORM pg_temp.flag('flow_signin_v2', false);
  IF public.relationship_invite_eligibility(pg_temp.id('03')) <> 'legacy'
     OR public.relationship_invite_eligibility(pg_temp.id('14')) <> 'legacy' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: relationship_invite_eligibility with the flag off is not legacy';
  END IF;
  -- With the flag off, no age check: a person without a DOB still links.
  v_msg := pg_temp.accept_error('11', 'NODOB2');
  IF v_msg IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the flag-off accept checked ages (%)', v_msg;
  END IF;
END $$;

-- =====================================================================
-- C. The accept: the acceptor's own invites go in the same transaction,
--    the path is set, the acceptance is kept, a replay is idempotent,
--    someone else's replay is refused, the code is case- and
--    space-insensitive, metrics move. Fixtures 21-23.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_again jsonb;
  v_msg text;
  v_before bigint := pg_temp.metric('invite_accepted');
  v_before_24h bigint := pg_temp.metric('invite_accepted_24h');
  v_before_7d bigint := pg_temp.metric('invite_accepted_7d');
BEGIN
  PERFORM pg_temp.flag('flow_signin_v2', true);
  PERFORM pg_temp.person('21', 'Yaw Inviter', 33);
  PERFORM pg_temp.person('22', 'Ama Acceptor', 32);
  PERFORM pg_temp.person('23', 'Kofi Late', 35);
  UPDATE public.users SET path = 'just_me' WHERE id = pg_temp.id('22');
  PERFORM pg_temp.invite('21', '21', 'HAPPY2', interval '2 hours');
  -- The acceptor's own invites, live and expired: both must go.
  PERFORM pg_temp.invite('22', '22', 'MINE22', interval '1 hour');
  PERFORM pg_temp.invite('23', '22', 'MINE33', interval '9 days');

  v := public.accept_relationship_invite_v2(pg_temp.id('22'), ' happy2 ');
  IF v->>'relationship_id' <> pg_temp.rel('21')::text OR v->>'status' <> 'active'
     OR (v->>'idempotent')::boolean OR v->>'inviter_id' <> pg_temp.id('21')::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accept answered %', v;
  END IF;
  IF EXISTS (SELECT 1 FROM public.relationships
              WHERE user_a = pg_temp.id('22') AND status = 'pending') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the acceptor''s own pending invites survived the accept';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.relationships
                  WHERE id = pg_temp.rel('21') AND status = 'active' AND user_b = pg_temp.id('22')
                    AND invite_code IS NULL AND invite_accepted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the relationship is not active with the acceptor';
  END IF;
  IF (SELECT path FROM public.users WHERE id = pg_temp.id('22')) IS DISTINCT FROM 'relationship'
     OR (SELECT path_previous FROM public.users WHERE id = pg_temp.id('22')) IS DISTINCT FROM 'just_me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the acceptor''s path is not Relationship (previous just_me)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.relationship_invite_acceptances
                  WHERE relationship_id = pg_temp.rel('21') AND accepted_by = pg_temp.id('22')
                    AND invite_code_hash = encode(extensions.digest('HAPPY2', 'sha256'), 'hex')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no acceptance row with the code''s SHA-256';
  END IF;
  IF pg_temp.metric('invite_accepted') <> v_before + 1
     OR pg_temp.metric('invite_accepted_24h') <> v_before_24h + 1
     OR pg_temp.metric('invite_accepted_7d') <> v_before_7d + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the accept metrics did not move once each';
  END IF;

  v_again := public.accept_relationship_invite_v2(pg_temp.id('22'), 'HAPPY2');
  IF NOT (v_again->>'idempotent')::boolean OR v_again->>'relationship_id' <> pg_temp.rel('21')::text
     OR v_again->>'status' <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay was not idempotent: %', v_again;
  END IF;
  IF pg_temp.metric('invite_accepted') <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay counted a second accept';
  END IF;
  v_msg := pg_temp.accept_error('23', 'HAPPY2');
  IF v_msg IS DISTINCT FROM 'invite:already_accepted' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone else reused an accepted code (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;

-- =====================================================================
-- D. A failure after the update rolls everything back. Fixtures 31-32.
-- =====================================================================
CREATE FUNCTION pg_temp.fail_acceptance() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'forced failure';
END $$;

DO $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.person('31', 'Yaw Rollback', 30);
  PERFORM pg_temp.person('32', 'Ama Rollback', 30);
  UPDATE public.users SET path = 'just_me' WHERE id = pg_temp.id('32');
  PERFORM pg_temp.invite('31', '31', 'ROLL22', interval '1 hour');
  PERFORM pg_temp.invite('32', '32', 'KEEP22', interval '1 hour');
  CREATE TRIGGER w4_fail_acceptance BEFORE INSERT ON public.relationship_invite_acceptances
    FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_acceptance();
  BEGIN
    PERFORM public.accept_relationship_invite_v2(pg_temp.id('32'), 'ROLL22');
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  DROP TRIGGER w4_fail_acceptance ON public.relationship_invite_acceptances;
  IF v_msg IS DISTINCT FROM 'forced failure' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the forced failure did not surface (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF (SELECT status FROM public.relationships WHERE id = pg_temp.rel('31')) <> 'pending'
     OR (SELECT user_b FROM public.relationships WHERE id = pg_temp.rel('31')) IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM public.relationships WHERE id = pg_temp.rel('32') AND status = 'pending')
     OR (SELECT path FROM public.users WHERE id = pg_temp.id('32')) IS DISTINCT FROM 'just_me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed accept left part of its work behind';
  END IF;
END $$;

-- =====================================================================
-- E. The database guard's refusal is the acceptor's message. Fixtures
--    41-43: an inviter already linked to someone else (a legacy state).
-- =====================================================================
DO $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.person('41', 'Yaw Linked', 30);
  PERFORM pg_temp.person('42', 'Esi Partner', 30);
  PERFORM pg_temp.person('43', 'Ama Late', 30);
  PERFORM pg_temp.invite('41', '41', 'STALE2', interval '1 hour');
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at)
  VALUES (pg_temp.rel('42'), pg_temp.id('41'), pg_temp.id('42'), 'active', current_date, now());
  v_msg := pg_temp.accept_error('43', 'STALE2');
  IF v_msg IS DISTINCT FROM 'invite:already_in_relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: relationship:already_open is not mapped (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;

-- =====================================================================
-- F. The preview (RI-3): states, the name only for ok and expired, never
--    a phone as a name, the rate limit. Fixtures 51-56.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_msg text;
BEGIN
  PERFORM pg_temp.person('51', 'Yaw Preview', 30);
  PERFORM pg_temp.person('52', 'Ama Viewer', 30);
  PERFORM pg_temp.person('53', '+233 24 000 0000', 30);
  PERFORM pg_temp.person('54', 'Kofi Limited', 30);
  PERFORM pg_temp.person('55', 'Esi Daily', 30);
  PERFORM pg_temp.invite('51', '51', 'PEEK22', interval '1 hour');
  PERFORM pg_temp.invite('52', '51', 'PEEK33', interval '8 days');
  PERFORM pg_temp.invite('53', '53', 'PHONE2', interval '1 hour');

  PERFORM pg_temp.as_user(pg_temp.id('52'));
  v := public.preview_relationship_invite('peek22');
  IF v <> '{"state": "ok", "inviter_first_name": "Yaw"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: preview ok read %', v;
  END IF;
  v := public.preview_relationship_invite('PEEK33');
  IF v <> '{"state": "expired", "inviter_first_name": "Yaw"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: preview expired read %', v;
  END IF;
  v := public.preview_relationship_invite('NOSUCH');
  IF v <> '{"state": "invalid", "inviter_first_name": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: preview invalid read %', v;
  END IF;
  v := public.preview_relationship_invite('PHONE2');
  IF v <> '{"state": "ok", "inviter_first_name": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone number was given as a name: %', v;
  END IF;
  v := public.preview_relationship_invite('HAPPY2');
  IF v <> '{"state": "invalid", "inviter_first_name": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone else''s accepted code read %', v;
  END IF;
  RESET ROLE;

  PERFORM pg_temp.as_user(pg_temp.id('51'));
  v := public.preview_relationship_invite('PEEK22');
  RESET ROLE;
  IF v <> '{"state": "own", "inviter_first_name": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: preview own read %', v;
  END IF;

  PERFORM pg_temp.as_user(pg_temp.id('22'));
  v := public.preview_relationship_invite('HAPPY2');
  RESET ROLE;
  IF v <> '{"state": "linked", "inviter_first_name": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: preview of my accepted code read %', v;
  END IF;

  -- 10 per hour: the 11th is refused and records nothing.
  PERFORM pg_temp.as_user(pg_temp.id('54'));
  FOR i IN 1..10 LOOP
    PERFORM public.preview_relationship_invite('NOSUCH');
  END LOOP;
  v_msg := pg_temp.error_of('SELECT public.preview_relationship_invite(''PEEK22'')');
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'invite:try_later' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 11th preview in an hour (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF (SELECT count(*) FROM private.invite_preview_attempts WHERE user_id = pg_temp.id('54')) <> 10 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused preview was recorded';
  END IF;

  -- 30 per day: 29 earlier today, then one more, then refused.
  INSERT INTO private.invite_preview_attempts (user_id, attempted_at)
  SELECT pg_temp.id('55'), now() - interval '3 hours' FROM generate_series(1, 29);
  PERFORM pg_temp.as_user(pg_temp.id('55'));
  PERFORM public.preview_relationship_invite('NOSUCH');
  v_msg := pg_temp.error_of('SELECT public.preview_relationship_invite(''NOSUCH'')');
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'invite:try_later' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 31st preview in a day (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- Signed out: nothing.
  PERFORM pg_temp.as_user(NULL);
  v_msg := pg_temp.error_of('SELECT public.preview_relationship_invite(''PEEK22'')');
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'invite:not_signed_in' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a preview without a session (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;

-- =====================================================================
-- G. Retention: only attempts older than a day go.
-- =====================================================================
DO $$
BEGIN
  PERFORM pg_temp.person('56', 'Kojo Old', 30);
  INSERT INTO private.invite_preview_attempts (user_id, attempted_at)
  VALUES (pg_temp.id('56'), now() - interval '25 hours'),
         (pg_temp.id('56'), now() - interval '23 hours');
END $$;
DO $$
DECLARE
  v_young bigint;
BEGIN
  SELECT count(*) INTO v_young FROM private.invite_preview_attempts
   WHERE attempted_at >= now() - interval '1 day';
  PERFORM private.purge_invite_preview_attempts();
  IF EXISTS (SELECT 1 FROM private.invite_preview_attempts WHERE attempted_at < now() - interval '1 day') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an attempt older than a day survived the purge';
  END IF;
  IF (SELECT count(*) FROM private.invite_preview_attempts) <> v_young THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge deleted attempts younger than a day';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'invite_v2_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 3: Run it to verify it fails**

```bash
psql -X -d attune_spec3a -Atc 'select current_database()'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/invite_v2_contracts.sql; echo "exit=$?"
```

Expected: `attune_spec3a`; `ERROR:  CONTRACT VIOLATED: W4a objects are missing (accept_relationship_invite_v2, preview_relationship_invite, relationship_invite_eligibility, invite_preview_attempts)`, `exit=3`.

- [ ] **Step 4: Write the migration**

Create `supabase/migrations/20261102100000_accept_invite_v2.sql` with exactly:

```sql
-- Spec 1 W4a, migration 9 (spec §4.7 #9): accept_invite_v2.
--   * accept_relationship_invite_v2 (service role, D7): the whole accept in
--     one transaction. The acceptor's users row is locked first, then the
--     pending relationship, the order set_my_path uses (users, then
--     relationships), so an accept and a path switch on either side never
--     deadlock. The acceptor's own pending invites go in the same
--     transaction; the acceptor's path becomes Relationship. It never
--     creates a users row (D8): no row is invite:phone_required.
--   * relationship_invite_eligibility (service role): what
--     create-relationship-invite and accept-invite do before anything else
--     (legacy row creation with flow_signin_v2 off; otherwise an account,
--     a date of birth, 18 or over). Replaces the W2 interim guard's flag
--     read (W4 plan P-2).
--   * preview_relationship_invite (authenticated, RI-3): the inviter's first
--     name for a code the caller holds, 10 per hour and 30 per day.
--   * private.invite_preview_attempts and its own retention cron
--     invite-preview-retention (spec §4.6), deleting attempts older than a
--     day.
-- Grants in 20261102100010_accept_invite_v2_grants.sql; every server-only
-- object is revoked here as well.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS private.invite_preview_attempts (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  attempted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS invite_preview_attempts_user_at_idx
  ON private.invite_preview_attempts (user_id, attempted_at);
REVOKE ALL ON private.invite_preview_attempts FROM PUBLIC, anon, authenticated;

-- A display name's first word, never a phone number (the rule
-- get_my_home_state uses for partner_first_name).
CREATE OR REPLACE FUNCTION private.invite_first_name(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
           WHEN split_part(private.normalize_display_name(u.display_name), ' ', 1) ~ '^\+?[0-9 ()-]*$' THEN NULL
           ELSE split_part(private.normalize_display_name(u.display_name), ' ', 1)
         END
    FROM public.users AS u
   WHERE u.id = p_user;
$$;
REVOKE ALL ON FUNCTION private.invite_first_name(uuid) FROM PUBLIC, anon, authenticated;

-- What both invite functions check first (spec §4.5 W4a). 'legacy': with
-- flow_signin_v2 effectively off, today's missing-row insert runs.
-- Otherwise no row is ever created here (D8): 'signup_incomplete' with no
-- users row, 'age_required' with no date of birth, 'not_possible' under
-- 18, else 'ok'.
CREATE OR REPLACE FUNCTION public.relationship_invite_eligibility(p_user uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_age integer;
BEGIN
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF NOT private.spec1_flag_on('flow_signin_v2') THEN
    RETURN 'legacy';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user) THEN
    RETURN 'signup_incomplete';
  END IF;
  v_age := public.account_age(p_user);
  IF v_age IS NULL THEN
    RETURN 'age_required';
  END IF;
  IF v_age < 18 THEN
    RETURN 'not_possible';
  END IF;
  RETURN 'ok';
END;
$$;

-- The accept (spec §4.3 W4a, D7). Codes are case-insensitive, spaces
-- ignored. Refusals: invite:invalid, invite:own, invite:expired,
-- invite:already_accepted, invite:already_in_relationship,
-- invite:phone_required, and with flow_signin_v2 effectively on
-- invite:age_required (acceptor without a date of birth) and
-- invite:not_possible (either side under 18, or an inviter without one;
-- neutral, never says which). A replay by the same acceptor answers
-- idempotent.
CREATE OR REPLACE FUNCTION public.accept_relationship_invite_v2(p_acceptor uuid, p_invite_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_code constant text := upper(regexp_replace(coalesce(p_invite_code, ''), '\s', '', 'g'));
  v_hash text;
  v_done public.relationship_invite_acceptances%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_age integer;
  v_waited interval;
BEGIN
  IF p_acceptor IS NULL OR v_code !~ '^[A-Z0-9]{6,12}$' THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  v_hash := encode(extensions.digest(v_code, 'sha256'), 'hex');

  -- Lock order (W1 carry): the acceptor's users row before any
  -- relationships row, as set_my_path does. No row: nothing is created.
  PERFORM 1 FROM public.users AS u WHERE u.id = p_acceptor FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invite:phone_required';
  END IF;

  SELECT * INTO v_done FROM public.relationship_invite_acceptances AS a
   WHERE a.invite_code_hash = v_hash;
  IF FOUND THEN
    IF v_done.accepted_by IS DISTINCT FROM p_acceptor THEN
      RAISE EXCEPTION 'invite:already_accepted';
    END IF;
    RETURN jsonb_build_object(
      'relationship_id', v_done.relationship_id,
      'status', (SELECT r.status FROM public.relationships AS r WHERE r.id = v_done.relationship_id),
      'idempotent', true,
      'inviter_id', (SELECT r.user_a FROM public.relationships AS r WHERE r.id = v_done.relationship_id));
  END IF;

  SELECT * INTO v_rel FROM public.relationships AS r
   WHERE r.invite_code = v_code AND r.status = 'pending'
   FOR UPDATE;
  IF NOT FOUND THEN
    -- Someone accepted it while this call waited for the row: their
    -- acceptance is committed now.
    SELECT * INTO v_done FROM public.relationship_invite_acceptances AS a
     WHERE a.invite_code_hash = v_hash;
    IF FOUND AND v_done.accepted_by IS DISTINCT FROM p_acceptor THEN
      RAISE EXCEPTION 'invite:already_accepted';
    END IF;
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF v_rel.user_a = p_acceptor THEN
    RAISE EXCEPTION 'invite:own';
  END IF;
  IF v_rel.user_b IS NOT NULL THEN
    RAISE EXCEPTION 'invite:invalid';
  END IF;
  IF v_rel.invite_expires_at < now() THEN
    RAISE EXCEPTION 'invite:expired';
  END IF;
  IF EXISTS (SELECT 1 FROM public.relationships AS r
              WHERE p_acceptor IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')) THEN
    RAISE EXCEPTION 'invite:already_in_relationship';
  END IF;
  IF public.verified_phone(p_acceptor) IS NULL THEN
    RAISE EXCEPTION 'invite:phone_required';
  END IF;
  IF private.spec1_flag_on('flow_signin_v2') THEN
    v_age := public.account_age(p_acceptor);
    IF v_age IS NULL THEN
      RAISE EXCEPTION 'invite:age_required';
    END IF;
    IF v_age < 18 THEN
      RAISE EXCEPTION 'invite:not_possible';
    END IF;
    v_age := public.account_age(v_rel.user_a);
    IF v_age IS NULL OR v_age < 18 THEN
      RAISE EXCEPTION 'invite:not_possible';
    END IF;
  END IF;

  -- The acceptor's own invites go first, in this transaction (spec §7.1).
  DELETE FROM public.relationships AS r
   WHERE r.user_a = p_acceptor AND r.status = 'pending' AND r.user_b IS NULL;

  BEGIN
    UPDATE public.relationships
       SET user_b = p_acceptor,
           status = 'active',
           invite_code = NULL,
           invite_accepted_at = now()
     WHERE id = v_rel.id;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'relationship:already_open' THEN
      RAISE EXCEPTION 'invite:already_in_relationship';
    END IF;
    RAISE;
  END;

  INSERT INTO public.relationship_invite_acceptances
    (invite_code_hash, relationship_id, accepted_by, accepted_at)
  VALUES (v_hash, v_rel.id, p_acceptor, now());

  PERFORM public.set_user_path_internal(p_acceptor, 'relationship');

  -- Server events (internal; spec §4.3 W1b seeds): every accept, and those
  -- within a day and within a week of the invite.
  v_waited := now() - v_rel.created_at;
  PERFORM private.bump_metric_internal('invite_accepted');
  IF v_waited <= interval '24 hours' THEN
    PERFORM private.bump_metric_internal('invite_accepted_24h');
  END IF;
  IF v_waited <= interval '7 days' THEN
    PERFORM private.bump_metric_internal('invite_accepted_7d');
  END IF;

  RETURN jsonb_build_object(
    'relationship_id', v_rel.id,
    'status', 'active',
    'idempotent', false,
    'inviter_id', v_rel.user_a);
END;
$$;

-- RI-3 (spec §3.8, §4.3 W4a): who sent the code the caller holds. A name
-- only for ok and expired; 10 tries per hour and 30 per day, invalid codes
-- included (no enumeration, §6.4).
CREATE OR REPLACE FUNCTION public.preview_relationship_invite(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_code constant text := upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
  v_done public.relationship_invite_acceptances%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'invite:not_signed_in';
  END IF;
  IF public.verified_phone(v_uid) IS NULL THEN
    RAISE EXCEPTION 'invite:phone_required';
  END IF;
  IF (SELECT count(*) FROM private.invite_preview_attempts AS a
       WHERE a.user_id = v_uid AND a.attempted_at > now() - interval '1 hour') >= 10
     OR (SELECT count(*) FROM private.invite_preview_attempts AS a
          WHERE a.user_id = v_uid AND a.attempted_at > now() - interval '1 day') >= 30 THEN
    RAISE EXCEPTION 'invite:try_later';
  END IF;
  INSERT INTO private.invite_preview_attempts (user_id) VALUES (v_uid);

  IF v_code !~ '^[A-Z0-9]{6,12}$' THEN
    RETURN jsonb_build_object('state', 'invalid', 'inviter_first_name', NULL);
  END IF;

  SELECT * INTO v_done FROM public.relationship_invite_acceptances AS a
   WHERE a.invite_code_hash = encode(extensions.digest(v_code, 'sha256'), 'hex');
  IF FOUND THEN
    RETURN jsonb_build_object(
      'state', CASE WHEN v_done.accepted_by = v_uid THEN 'linked' ELSE 'invalid' END,
      'inviter_first_name', NULL);
  END IF;

  SELECT * INTO v_rel FROM public.relationships AS r
   WHERE r.invite_code = v_code AND r.status = 'pending' AND r.user_b IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('state', 'invalid', 'inviter_first_name', NULL);
  END IF;
  IF v_rel.user_a = v_uid THEN
    RETURN jsonb_build_object('state', 'own', 'inviter_first_name', NULL);
  END IF;
  RETURN jsonb_build_object(
    'state', CASE WHEN v_rel.invite_expires_at < now() THEN 'expired' ELSE 'ok' END,
    'inviter_first_name', private.invite_first_name(v_rel.user_a));
END;
$$;

-- Retention (spec §4.6, §4.8): attempts are kept one day.
CREATE OR REPLACE FUNCTION private.purge_invite_preview_attempts()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_n integer;
BEGIN
  DELETE FROM private.invite_preview_attempts AS a
   WHERE a.attempted_at < now() - interval '1 day';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION private.purge_invite_preview_attempts() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.accept_relationship_invite_v2(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_invite_eligibility(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.preview_relationship_invite(text) FROM PUBLIC, anon;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'invite-preview-retention';
END;
$$;
SELECT cron.schedule(
  'invite-preview-retention',
  '39 * * * *',
  $$ SELECT private.purge_invite_preview_attempts(); $$
);

COMMIT;
```

- [ ] **Step 5: Write the grants twin**

Create `supabase/migrations/20261102100010_accept_invite_v2_grants.sql` with exactly:

```sql
-- Spec 1 W4a: grants for 20261102100000_accept_invite_v2.sql. The accept
-- and the eligibility check are the invite edge functions' (service role);
-- the preview is the app's; the attempts table, the name helper and the
-- purge are server-only.
BEGIN;
REVOKE ALL ON private.invite_preview_attempts FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.invite_first_name(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.purge_invite_preview_attempts() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.accept_relationship_invite_v2(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_invite_eligibility(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.preview_relationship_invite(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_relationship_invite_v2(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.relationship_invite_eligibility(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.preview_relationship_invite(text) TO authenticated;
COMMIT;
```

- [ ] **Step 6: Apply both twice, then run the contract**

```bash
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261102100000_accept_invite_v2.sql > /dev/null; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261102100010_accept_invite_v2_grants.sql; echo "grants exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/invite_v2_contracts.sql; echo "exit=$?"
psql -X -d attune_spec3a -Atc "select jobname, schedule, command from cron.job where jobname = 'invite-preview-retention'"
```

Expected: four `… exit=0` (the second pass prints `NOTICE: relation "invite_preview_attempts" already exists, skipping` and the index's); `NOTICE:  invite_v2_contracts: all held`, `exit=0`; `invite-preview-retention|39 * * * *| SELECT private.purge_invite_preview_attempts(); `.

- [ ] **Step 7: Mutation checks (each must turn the contract red with the message quoted)**

```bash
M=supabase/migrations/20261102100000_accept_invite_v2.sql
C=supabase/tests/invite_v2_contracts.sql
D=.superpowers/sdd/2026-11-02-spec1-w4
python3 -I - "$M" "$D" <<'EOF'
import pathlib, sys
m = pathlib.Path(sys.argv[1]).read_text()
d = pathlib.Path(sys.argv[2])
muts = {
  'withdraw': ("  DELETE FROM public.relationships AS r\n   WHERE r.user_a = p_acceptor AND r.status = 'pending' AND r.user_b IS NULL;\n", ""),
  'lock': ("  PERFORM 1 FROM public.users AS u WHERE u.id = p_acceptor FOR UPDATE;\n", "  PERFORM 1 FROM public.users AS u WHERE u.id = p_acceptor;\n"),
  'inviter_age': ("    v_age := public.account_age(v_rel.user_a);\n    IF v_age IS NULL OR v_age < 18 THEN\n      RAISE EXCEPTION 'invite:not_possible';\n    END IF;\n", ""),
  'rate': ("interval '1 hour') >= 10", "interval '1 hour') >= 100"),
  'purge': ("  DELETE FROM private.invite_preview_attempts AS a\n   WHERE a.attempted_at < now() - interval '1 day';\n", "  DELETE FROM private.invite_preview_attempts AS a;\n"),
  'guard': ("    IF SQLERRM = 'relationship:already_open' THEN\n      RAISE EXCEPTION 'invite:already_in_relationship';\n    END IF;\n", ""),
}
for name, (a, b) in muts.items():
    assert m.count(a) == 1, name
    (d / f"mut_{name}.sql").write_text(m.replace(a, b))
print('mutants written')
EOF
for m in withdraw lock inviter_age rate purge guard; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $D/mut_$m.sql > /dev/null 2>&1
  echo "$m: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | grep ERROR | cut -c1-150)"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $M > /dev/null; echo "restored exit=$?"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | tail -1
rm $D/mut_withdraw.sql $D/mut_lock.sql $D/mut_inviter_age.sql $D/mut_rate.sql $D/mut_purge.sql $D/mut_guard.sql
```

Expected: `mutants written`, then:
- `withdraw` (§7.4 "Remove the withdrawal statement"): `ERROR:  CONTRACT VIOLATED: the acceptor's own pending invites survived the accept`
- `lock` (W1 carry): `ERROR:  CONTRACT VIOLATED: the accept does not lock the users row before relationships`
- `inviter_age`: `ERROR:  CONTRACT VIOLATED: an inviter without a DOB (got no error)`
- `rate`: `ERROR:  CONTRACT VIOLATED: the 11th preview in an hour (got no error)`
- `purge`: `ERROR:  CONTRACT VIOLATED: the purge deleted attempts younger than a day`
- `guard`: `ERROR:  CONTRACT VIOLATED: relationship:already_open is not mapped (got relationship:already_open)`

then `restored exit=0` and `NOTICE:  invite_v2_contracts: all held`.

- [ ] **Step 8: Add the twin to the local harness (edit only, never run)**

In `scripts/local_pg_grants.sql`:

Edit 1 of 1. Replace exactly:

```sql
-- Spec 1 W3c: the journal reminder: own row read, RPC writes, the enqueue is
-- the cron's.
\i supabase/migrations/20261026100010_journal_reminders_grants.sql
```

with:

```sql
-- Spec 1 W3c: the journal reminder: own row read, RPC writes, the enqueue is
-- the cron's.
\i supabase/migrations/20261026100010_journal_reminders_grants.sql

-- Spec 1 W4a: the accept and the eligibility check are the invite edge
-- functions' (service role); the preview is the app's.
\i supabase/migrations/20261102100010_accept_invite_v2_grants.sql
```

- [ ] **Step 9: Run tests**

```bash
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-11-02-spec1-w4/sql-after-w4a.txt
grep '^FAIL' .superpowers/sdd/2026-11-02-spec1-w4/sql-after-w4a.txt | comm -13 <(grep '^FAIL' .superpowers/sdd/2026-11-02-spec1-w4/sql-baseline.txt) -
grep -E 'invite_v2|invite_age|sync_fixes|identity_foundation' .superpowers/sdd/2026-11-02-spec1-w4/sql-after-w4a.txt
```

Expected: no new FAIL line; `PASS identity_foundation_contracts.sql`, `PASS invite_age_contracts.sql`, `PASS invite_v2_contracts.sql`, `PASS sync_fixes_contracts.sql`.

### Task 2: The invite edge functions on the W4a rules (W4a; §4.5, §5.6 R8, §7.2, D7, D8, P-2, P-6)

**Files:**
- Replace: `supabase/functions/_shared/sign_up_guard.ts`
- Create: `supabase/functions/accept-invite/accept.ts`
- Replace: `supabase/functions/accept-invite/index.ts`
- Modify: `supabase/functions/create-relationship-invite/index.ts` (import; the guard call)
- Replace: `supabase/functions/accept-invite/signup_incomplete_guard.test.ts`, `supabase/functions/accept-invite/index.test.ts`
- Create: `supabase/functions/accept-invite/accept.test.ts`

**Interfaces:**
- Consumes: Task 1's `relationship_invite_eligibility` and `accept_relationship_invite_v2`; `HttpError`, `jsonResponse`, `requireUser`, `serviceRoleClient`, `enqueuePush`.
- Produces: `_shared/sign_up_guard.ts`: `SIGNUP_INCOMPLETE`, `FLAGS_UNAVAILABLE`, `AGE_REQUIRED` (`invite:age_required`), `NOT_POSSIBLE` (`invite:not_possible`), `type InviteEligibility`, `readInviteEligibility(supabase, userId)`, `ensureInviteAccount(supabase, userId, ensureUserRow) → Promise<InviteEligibility>`, `requireInviterAge(eligibility)`; `accept-invite/accept.ts`: `ALREADY_IN_RELATIONSHIP`, `class InviteRefusal extends HttpError { code }`, `ACCEPT_REFUSAL_CODES`, `acceptRefusal(message) → InviteRefusal | null`, `normalizeInviteCode(raw) → string | null`, `acceptInvite(supabase, userId, rawCode, ensureUserRow) → Promise<{relationship_id, status, idempotent}>`. Response bodies: success `{relationship_id, status, idempotent}`; refusal `{error, code}` with today's status; create's 428 / 403 `{error: 'invite:age_required' | 'invite:not_possible'}`.

- [ ] **Step 1: Write the failing tests**

Replace `supabase/functions/accept-invite/signup_incomplete_guard.test.ts` with exactly:

```ts
// Spec 1 W4a (§4.5; replaces the W2 interim guard's tests). Both invite
// functions ask public.relationship_invite_eligibility first: legacy runs
// today's ensureUserRow; with flow_signin_v2 on, no users row is ever made
// (D8): no account is 409 signup:incomplete; the inviter's age rule is 428
// / 403; an unreadable answer is 503 flags:unavailable, never legacy.
import { HttpError } from "../_shared/attune_auth.ts";
import {
  AGE_REQUIRED,
  ensureInviteAccount,
  FLAGS_UNAVAILABLE,
  NOT_POSSIBLE,
  requireInviterAge,
  SIGNUP_INCOMPLETE,
} from "../_shared/sign_up_guard.ts";

type Answer = { data: unknown; error: unknown } | Error;

function fakeClient(answer: Answer) {
  const calls: { fn: string; params: unknown }[] = [];
  const tables: string[] = [];
  const client = {
    rpc(fn: string, params: unknown) {
      calls.push({ fn, params });
      return answer instanceof Error ? Promise.reject(answer) : Promise.resolve(answer);
    },
    from(table: string) {
      tables.push(table);
      throw new Error(`the guard read ${table} itself`);
    },
  };
  return { calls, tables, client };
}

function ensureUserRowSpy() {
  const spy = { calls: 0, run: () => Promise.resolve() };
  spy.run = () => {
    spy.calls++;
    return Promise.resolve();
  };
  return spy;
}

async function refusalOf(run: () => Promise<unknown>): Promise<HttpError> {
  try {
    await run();
  } catch (error) {
    if (error instanceof HttpError) return error;
    throw error;
  }
  throw new Error("expected a refusal, got none");
}

Deno.test("the codes are the app's", () => {
  if (SIGNUP_INCOMPLETE !== "signup:incomplete") throw new Error(SIGNUP_INCOMPLETE);
  if (FLAGS_UNAVAILABLE !== "flags:unavailable") throw new Error(FLAGS_UNAVAILABLE);
  if (AGE_REQUIRED !== "invite:age_required") throw new Error(AGE_REQUIRED);
  if (NOT_POSSIBLE !== "invite:not_possible") throw new Error(NOT_POSSIBLE);
});

Deno.test("legacy (flag off): today's ensureUserRow runs once", async () => {
  const { calls, client } = fakeClient({ data: "legacy", error: null });
  const ensureUserRow = ensureUserRowSpy();
  const answer = await ensureInviteAccount(client, "u1", ensureUserRow.run);
  if (answer !== "legacy") throw new Error(`answered ${answer}`);
  if (ensureUserRow.calls !== 1) throw new Error(`ensureUserRow ran ${ensureUserRow.calls} times`);
  if (calls.length !== 1 || calls[0].fn !== "relationship_invite_eligibility") {
    throw new Error(`asked ${JSON.stringify(calls)}`);
  }
  if (JSON.stringify(calls[0].params) !== JSON.stringify({ p_user: "u1" })) {
    throw new Error(`asked for ${JSON.stringify(calls[0].params)}`);
  }
});

Deno.test("flag on, no account: 409 signup:incomplete and no ensureUserRow (D8)", async () => {
  const { client } = fakeClient({ data: "signup_incomplete", error: null });
  const ensureUserRow = ensureUserRowSpy();
  const refusal = await refusalOf(() => ensureInviteAccount(client, "u1", ensureUserRow.run));
  if (refusal.status !== 409 || refusal.message !== "signup:incomplete") {
    throw new Error(`got ${refusal.status} ${refusal.message}`);
  }
  if (ensureUserRow.calls !== 0) throw new Error("ensureUserRow ran with the flag on");
});

Deno.test("flag on, an account: the answer, and no ensureUserRow", async () => {
  for (const answer of ["ok", "age_required", "not_possible"] as const) {
    const { client } = fakeClient({ data: answer, error: null });
    const ensureUserRow = ensureUserRowSpy();
    const got = await ensureInviteAccount(client, "u1", ensureUserRow.run);
    if (got !== answer) throw new Error(`${answer}: answered ${got}`);
    if (ensureUserRow.calls !== 0) throw new Error(`${answer}: ensureUserRow ran`);
  }
});

Deno.test("an unreadable answer fails closed: 503 flags:unavailable, no ensureUserRow", async () => {
  for (const [label, answer] of [
    ["an error", { data: null, error: { message: "permission denied" } }],
    ["a thrown call", new Error("network")],
    ["an unknown answer", { data: "maybe", error: null }],
    ["no answer", { data: null, error: null }],
  ] as const) {
    const { client } = fakeClient(answer);
    const ensureUserRow = ensureUserRowSpy();
    const refusal = await refusalOf(() => ensureInviteAccount(client, "u1", ensureUserRow.run));
    if (refusal.status !== 503 || refusal.message !== "flags:unavailable") {
      throw new Error(`${label}: got ${refusal.status} ${refusal.message}`);
    }
    if (ensureUserRow.calls !== 0) throw new Error(`${label}: ensureUserRow ran`);
  }
});

Deno.test("the inviter's age rule: 428 without a date of birth, 403 under 18", async () => {
  const missing = await refusalOf(async () => requireInviterAge("age_required"));
  if (missing.status !== 428 || missing.message !== "invite:age_required") {
    throw new Error(`got ${missing.status} ${missing.message}`);
  }
  const minor = await refusalOf(async () => requireInviterAge("not_possible"));
  if (minor.status !== 403 || minor.message !== "invite:not_possible") {
    throw new Error(`got ${minor.status} ${minor.message}`);
  }
  requireInviterAge("ok");
  requireInviterAge("legacy");
});

// The wiring: create-relationship-invite asks first, applies the age rule
// at once, and reads or writes nothing before; accept-invite asks before
// its one SQL call. ensureUserRow is only ever the guard's flag-off path.
Deno.test("both invite functions ask before any relationship read or write", async () => {
  const create = await Deno.readTextFile(new URL("../create-relationship-invite/index.ts", import.meta.url));
  if (!create.includes('import { ensureInviteAccount, requireInviterAge } from "../_shared/sign_up_guard.ts";')) {
    throw new Error("create-relationship-invite: does not import the guard and the age rule");
  }
  const call = "const eligibility = await ensureInviteAccount(supabase, user.id, () => ensureUserRow(supabase, user));\n    requireInviterAge(eligibility);";
  const at = create.indexOf(call);
  if (at < 0) throw new Error("create-relationship-invite: does not ask, then apply the age rule");
  for (const later of ['.from("relationships")', ".insert(", ".update("]) {
    const first = create.indexOf(later);
    if (first >= 0 && first < at) throw new Error(`create-relationship-invite: ${later} comes before the guard`);
  }
  const bare = create.split("\n").filter((line) => /ensureUserRow\(supabase, user\)/.test(line));
  if (bare.length !== 1) throw new Error(`create-relationship-invite: ensureUserRow outside the guard: ${bare.join(" | ")}`);

  const accept = await Deno.readTextFile(new URL("./accept.ts", import.meta.url));
  const guard = accept.indexOf("await ensureInviteAccount(supabase, userId, ensureUserRow);");
  const rpc = accept.indexOf('supabase.rpc("accept_relationship_invite_v2"');
  if (guard < 0 || rpc < 0 || guard > rpc) throw new Error("accept-invite: the guard does not come before the accept");
  if (accept.includes('.from("relationships")') || accept.includes('.from("relationship_invite_acceptances")')) {
    throw new Error("accept-invite still reads or writes relationships itself (D7: the SQL function does)");
  }
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (!index.includes("() => ensureUserRow(supabase, user),")) {
    throw new Error("accept-invite: ensureUserRow is not handed to the guard");
  }
});
```

Create `supabase/functions/accept-invite/accept.test.ts` with exactly:

```ts
// Spec 1 W4a (§4.5, §5.6 R8, §7.2): accept-invite over
// accept_relationship_invite_v2. Every refusal code maps to today's status
// and message (the app parses them; the "You're already in a relationship"
// prefix is pinned), the code travels too, the push is queued once to the
// inviter and never on a replay, and a failed push never fails the accept.
import { HttpError } from "../_shared/attune_auth.ts";
import {
  ACCEPT_REFUSAL_CODES,
  acceptInvite,
  acceptRefusal,
  ALREADY_IN_RELATIONSHIP,
  InviteRefusal,
  normalizeInviteCode,
} from "./accept.ts";

type Answer = { data: unknown; error: unknown };

function fakeClient(accept: Answer, opts: { eligibility?: string; pushFails?: boolean } = {}) {
  const rpcs: { fn: string; params: Record<string, unknown> }[] = [];
  const pushes: Record<string, unknown>[] = [];
  const client = {
    rpc(fn: string, params: Record<string, unknown>) {
      rpcs.push({ fn, params });
      if (fn === "relationship_invite_eligibility") {
        return Promise.resolve({ data: opts.eligibility ?? "ok", error: null });
      }
      return Promise.resolve(accept);
    },
    from(table: string) {
      if (table !== "scheduled_notifications") throw new Error(`read ${table}`);
      return {
        insert(row: Record<string, unknown>) {
          pushes.push(row);
          return {
            select: () =>
              Promise.resolve(
                opts.pushFails
                  ? { data: null, error: { code: "XX000" } }
                  : { data: [{ id: "n1" }], error: null },
              ),
          };
        },
      };
    },
  };
  return { rpcs, pushes, client };
}

const noRow = () => Promise.resolve();

async function refusalOf(run: () => Promise<unknown>): Promise<HttpError> {
  try {
    await run();
  } catch (error) {
    if (error instanceof HttpError) return error;
    throw error;
  }
  throw new Error("expected a refusal, got none");
}

Deno.test("every SQL refusal maps to today's status and message", () => {
  const expected: Record<string, [number, string]> = {
    "invite:invalid": [404, "Invite code is invalid"],
    "invite:own": [409, "You cannot accept your own invite"],
    "invite:expired": [410, "Invite code has expired"],
    "invite:already_accepted": [409, "Invite has already been accepted"],
    "invite:already_in_relationship": [409, ALREADY_IN_RELATIONSHIP],
    "invite:phone_required": [403, "invite:phone_required"],
    "invite:age_required": [428, "invite:age_required"],
    "invite:not_possible": [403, "invite:not_possible"],
  };
  if (JSON.stringify([...ACCEPT_REFUSAL_CODES].sort()) !== JSON.stringify(Object.keys(expected).sort())) {
    throw new Error(`mapped codes ${ACCEPT_REFUSAL_CODES}`);
  }
  for (const [code, [status, message]] of Object.entries(expected)) {
    const refusal = acceptRefusal(code);
    if (!(refusal instanceof InviteRefusal)) throw new Error(`${code} is not mapped`);
    if (refusal.status !== status || refusal.message !== message || refusal.code !== code) {
      throw new Error(`${code}: ${refusal.status} ${refusal.message} ${refusal.code}`);
    }
  }
  if (acceptRefusal("relationship:already_open") !== null) throw new Error("mapped a non-invite error");
  if (!ALREADY_IN_RELATIONSHIP.startsWith("You're already in a relationship")) {
    throw new Error("the prefix the app matches changed");
  }
});

Deno.test("the code: case-insensitive, spaces ignored, else 400", async () => {
  if (normalizeInviteCode(" k7p2 qm ") !== "K7P2QM") throw new Error("not normalised");
  if (normalizeInviteCode("K7") !== null || normalizeInviteCode(7) !== null) throw new Error("accepted a bad code");
  const { rpcs, client } = fakeClient({ data: null, error: null });
  const refusal = await refusalOf(() => acceptInvite(client, "u2", "K7", noRow));
  if (refusal.status !== 400) throw new Error(`got ${refusal.status}`);
  if (rpcs.length) throw new Error("asked the server about a malformed code");
});

Deno.test("an accept: one SQL call, the push to the inviter, today's answer", async () => {
  const { rpcs, pushes, client } = fakeClient({
    data: { relationship_id: "r1", status: "active", idempotent: false, inviter_id: "u1" },
    error: null,
  });
  const result = await acceptInvite(client, "u2", "k7p2qm", noRow);
  if (JSON.stringify(result) !== JSON.stringify({ relationship_id: "r1", status: "active", idempotent: false })) {
    throw new Error(`answered ${JSON.stringify(result)}`);
  }
  const accept = rpcs.find((c) => c.fn === "accept_relationship_invite_v2");
  if (JSON.stringify(accept?.params) !== JSON.stringify({ p_acceptor: "u2", p_invite_code: "K7P2QM" })) {
    throw new Error(`called ${JSON.stringify(accept)}`);
  }
  if (pushes.length !== 1 || pushes[0].user_id !== "u1" || pushes[0].source_key !== "invite_accepted:r1") {
    throw new Error(`pushed ${JSON.stringify(pushes)}`);
  }
  const meta = pushes[0].metadata as Record<string, unknown>;
  if (meta.type !== "invite_accepted" || meta.relationship_id !== "r1") {
    throw new Error(`push metadata ${JSON.stringify(meta)}`);
  }
});

Deno.test("a replay: idempotent, no second push", async () => {
  const { pushes, client } = fakeClient({
    data: { relationship_id: "r1", status: "active", idempotent: true, inviter_id: "u1" },
    error: null,
  });
  const result = await acceptInvite(client, "u2", "K7P2QM", noRow);
  if (!result.idempotent) throw new Error("not idempotent");
  if (pushes.length) throw new Error("pushed on a replay");
});

Deno.test("a failed push never fails the accept", async () => {
  const { client } = fakeClient(
    { data: { relationship_id: "r1", status: "active", idempotent: false, inviter_id: "u1" }, error: null },
    { pushFails: true },
  );
  const result = await acceptInvite(client, "u2", "K7P2QM", noRow);
  if (result.relationship_id !== "r1") throw new Error("the accept failed with the push");
});

Deno.test("a refusal answers its status, message and code, and pushes nothing", async () => {
  const { pushes, client } = fakeClient({ data: null, error: { message: "invite:already_in_relationship" } });
  const refusal = await refusalOf(() => acceptInvite(client, "u2", "K7P2QM", noRow));
  if (!(refusal instanceof InviteRefusal)) throw new Error("not an InviteRefusal");
  if (refusal.status !== 409 || !refusal.message.startsWith("You're already in a relationship")) {
    throw new Error(`got ${refusal.status} ${refusal.message}`);
  }
  if (refusal.code !== "invite:already_in_relationship") throw new Error(`code ${refusal.code}`);
  if (pushes.length) throw new Error("pushed after a refusal");
});

Deno.test("no account with the flag on: 409 signup:incomplete before the accept", async () => {
  const { rpcs, client } = fakeClient({ data: null, error: null }, { eligibility: "signup_incomplete" });
  const refusal = await refusalOf(() => acceptInvite(client, "u2", "K7P2QM", noRow));
  if (refusal.status !== 409 || refusal.message !== "signup:incomplete") {
    throw new Error(`got ${refusal.status} ${refusal.message}`);
  }
  if (rpcs.some((c) => c.fn === "accept_relationship_invite_v2")) throw new Error("accepted without an account");
});

Deno.test("an unexpected database error is not a refusal", async () => {
  const { client } = fakeClient({ data: null, error: { message: "deadlock detected" } });
  let thrown: unknown;
  try {
    await acceptInvite(client, "u2", "K7P2QM", noRow);
  } catch (error) {
    thrown = error;
  }
  if (thrown instanceof HttpError) throw new Error("a database error became a refusal");
  if (!thrown) throw new Error("no error");
});
```

Replace `supabase/functions/accept-invite/index.test.ts` with exactly (the I-8 accept check moved into SQL, Task 1; the create check and the W1a `ensureUserRow` check stay):

```ts
// Sync audit I-8: nobody in an active or paused relationship accepts or
// makes an invite. Since Spec 1 W4a the accept's check is inside
// accept_relationship_invite_v2 (invite_v2_contracts.sql) and its refusal
// keeps today's readable 409 (accept.test.ts); create-relationship-invite
// still checks for itself. The database guard
// (relationship_one_open_chapter_guard, sync_fixes_contracts) stays the
// real boundary.
const accept = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const create = await Deno.readTextFile(new URL("../create-relationship-invite/index.ts", import.meta.url));

Deno.test("create-relationship-invite refuses a paused person too", () => {
  if (!create.includes('.in("status", ["active", "paused"])')) {
    throw new Error("create-relationship-invite still checks active only");
  }
});

// Spec 1 W1a (D3, §4.5): the service-role safety net that creates a missing
// users row never writes the retired users.mode and never uses a phone
// number as a display name.
Deno.test("ensureUserRow writes no users.mode and no phone as a name", () => {
  for (const [name, source] of [["accept-invite", accept], ["create-relationship-invite", create]]) {
    const start = source.indexOf("async function ensureUserRow(");
    if (start < 0) throw new Error(`${name}: ensureUserRow is missing`);
    const body = source.slice(start, source.indexOf("\n}\n", start));
    if (/\bmode\s*:/.test(body)) throw new Error(`${name}: ensureUserRow still writes users.mode`);
    if (!/display_name:\s*""/.test(body)) throw new Error(`${name}: ensureUserRow must write an empty display_name`);
    if (/user\.phone\s*\?\?|displayName/.test(body)) throw new Error(`${name}: ensureUserRow still derives a name from the phone`);
    if (!body.includes("ignoreDuplicates: true")) throw new Error(`${name}: ensureUserRow must only insert a missing row`);
  }
});

Deno.test("both functions answer an HttpError with its own status and message", () => {
  for (const [name, source] of [["accept-invite", accept], ["create-relationship-invite", create]]) {
    if (!source.includes("return jsonResponse({ error: error.message }, error.status);")) {
      throw new Error(`${name}: an HttpError no longer answers with its own status and message`);
    }
  }
  if (!accept.includes("return jsonResponse({ error: error.message, code: error.code }, error.status);")) {
    throw new Error("accept-invite: a refusal no longer carries its code");
  }
});
```

- [ ] **Step 2: Run them to verify they fail**

```bash
cd supabase/functions && deno test --allow-read accept-invite/ 2>&1 | grep -E "Module not found|does not provide|error:|passed|failed" | head -4; cd ../..
```

Expected: a type-check failure naming `./accept.ts` (module not found) and `AGE_REQUIRED` / `requireInviterAge` not exported by `sign_up_guard.ts`.

- [ ] **Step 3: Replace the guard**

Replace `supabase/functions/_shared/sign_up_guard.ts` with exactly:

```ts
// Spec 1 W4a (§4.5): what both invite functions check before anything else,
// replacing the W2 interim guard. The decision is the database's
// (public.relationship_invite_eligibility, service role), so the flag read,
// the account and the date of birth are one answer:
//   legacy             flow_signin_v2 effectively off: today's ensureUserRow
//                      inserts a missing users row, exactly as before.
//   signup_incomplete  no users row: 409 signup:incomplete; nothing is
//                      written (D8: a users row is only ever made by
//                      complete_sign_up, which needs a date of birth).
//   age_required       no date of birth (a legacy account).
//   not_possible       under 18.
//   ok                 an adult account.
// An answer that can't be read fails closed (503 flags:unavailable): it is
// never taken as legacy, which would let ensureUserRow create a row with
// no date of birth.
import { HttpError } from "./attune_auth.ts";

/// The refusal for a signed-in caller with no account yet; the app keeps
/// the invite and finishes sign-up (relationship_invite_service.dart).
export const SIGNUP_INCOMPLETE = "signup:incomplete";

/// The refusal when the answer can't be read; retryable, and the app keeps
/// the invite code.
export const FLAGS_UNAVAILABLE = "flags:unavailable";

/// create-relationship-invite's refusals for an inviter (spec §4.5 W4a).
export const AGE_REQUIRED = "invite:age_required";
export const NOT_POSSIBLE = "invite:not_possible";

export type InviteEligibility =
  | "legacy"
  | "ok"
  | "signup_incomplete"
  | "age_required"
  | "not_possible";

const ANSWERS: readonly string[] = [
  "legacy",
  "ok",
  "signup_incomplete",
  "age_required",
  "not_possible",
];

// deno-lint-ignore no-explicit-any
export async function readInviteEligibility(supabase: any, userId: string): Promise<InviteEligibility> {
  let result;
  try {
    result = await supabase.rpc("relationship_invite_eligibility", { p_user: userId });
  } catch {
    throw new HttpError(FLAGS_UNAVAILABLE, 503);
  }
  if (result?.error || typeof result?.data !== "string" || !ANSWERS.includes(result.data)) {
    throw new HttpError(FLAGS_UNAVAILABLE, 503);
  }
  return result.data as InviteEligibility;
}

/// Legacy: runs [ensureUserRow]. No account: HttpError(409,
/// signup:incomplete), nothing written. Otherwise the answer, for the
/// caller's own age rule.
export async function ensureInviteAccount(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  ensureUserRow: () => Promise<void>,
): Promise<InviteEligibility> {
  const eligibility = await readInviteEligibility(supabase, userId);
  if (eligibility === "legacy") {
    await ensureUserRow();
    return eligibility;
  }
  if (eligibility === "signup_incomplete") throw new HttpError(SIGNUP_INCOMPLETE, 409);
  return eligibility;
}

/// The inviter's rule (create-relationship-invite): 428 without a date of
/// birth (the app asks for it, then retries), 403 under 18 (neutral).
export function requireInviterAge(eligibility: InviteEligibility): void {
  if (eligibility === "age_required") throw new HttpError(AGE_REQUIRED, 428);
  if (eligibility === "not_possible") throw new HttpError(NOT_POSSIBLE, 403);
}
```

- [ ] **Step 4: The accept, apart from `Deno.serve`**

Create `supabase/functions/accept-invite/accept.ts` with exactly:

```ts
// Spec 1 W4a (§4.5, D7): accept-invite's work, apart from Deno.serve so it
// can be tested. The decision is one SQL transaction,
// accept_relationship_invite_v2 (service role): it locks the acceptor's
// users row, then the invite; refuses with an invite:<code>; withdraws the
// acceptor's own pending invites; activates; records the acceptance; sets
// the acceptor's path to Relationship. This file maps its codes to today's
// statuses and messages (the app parses them) and then queues the
// best-effort invite_accepted push.
import { HttpError } from "../_shared/attune_auth.ts";
import { enqueuePush } from "../_shared/push_queue.ts";
import { ensureInviteAccount } from "../_shared/sign_up_guard.ts";

// Sync audit I-8: shown as is wherever the invite was entered by hand; the
// app matches its opening words (kAlreadyInRelationshipPrefix).
export const ALREADY_IN_RELATIONSHIP =
  "You're already in a relationship on Attune. End it first to join a new one.";

/// An accept refusal: today's status and message, plus the server's code,
/// which the W4b app reads first.
export class InviteRefusal extends HttpError {
  constructor(message: string, status: number, readonly code: string) {
    super(message, status);
    this.name = "InviteRefusal";
  }
}

const REFUSALS: Record<string, { status: number; message: string }> = {
  "invite:invalid": { status: 404, message: "Invite code is invalid" },
  "invite:own": { status: 409, message: "You cannot accept your own invite" },
  "invite:expired": { status: 410, message: "Invite code has expired" },
  "invite:already_accepted": { status: 409, message: "Invite has already been accepted" },
  "invite:already_in_relationship": { status: 409, message: ALREADY_IN_RELATIONSHIP },
  "invite:phone_required": { status: 403, message: "invite:phone_required" },
  "invite:age_required": { status: 428, message: "invite:age_required" },
  "invite:not_possible": { status: 403, message: "invite:not_possible" },
};

/// Every code accept_relationship_invite_v2 raises (the Deno test checks
/// each one is mapped).
export const ACCEPT_REFUSAL_CODES = Object.keys(REFUSALS);

/// The refusal for a database error message, or null when it isn't one.
export function acceptRefusal(message: string): InviteRefusal | null {
  const refusal = REFUSALS[message];
  return refusal ? new InviteRefusal(refusal.message, refusal.status, message) : null;
}

export function normalizeInviteCode(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const code = raw.replace(/\s+/g, "").toUpperCase();
  return /^[A-Z0-9]{6,12}$/.test(code) ? code : null;
}

export type AcceptResult = {
  relationship_id: string;
  status: string;
  idempotent: boolean;
};

export async function acceptInvite(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  rawCode: unknown,
  ensureUserRow: () => Promise<void>,
): Promise<AcceptResult> {
  const inviteCode = normalizeInviteCode(rawCode);
  if (!inviteCode) throw new HttpError("Invite code is required", 400);

  // Flag off: today's missing-row insert. Flag on: an account must exist
  // (409 signup:incomplete); the ages are the SQL function's.
  await ensureInviteAccount(supabase, userId, ensureUserRow);

  const { data, error } = await supabase.rpc("accept_relationship_invite_v2", {
    p_acceptor: userId,
    p_invite_code: inviteCode,
  });
  if (error) {
    const refusal = acceptRefusal(String(error.message ?? ""));
    if (refusal) throw refusal;
    throw error;
  }
  if (!data || typeof data.relationship_id !== "string") {
    throw new Error("accept_relationship_invite_v2: unexpected answer");
  }

  // Best-effort: a failed push must never make this endpoint appear to
  // fail to the accepting user: the relationship already committed, and
  // the home state's resync is the correctness guarantee, not this push
  // (docs/superpowers/specs/2026-08-02-relationship-lifecycle-sync-design.md
  // §2). A replay sends nothing again.
  if (data.idempotent !== true && typeof data.inviter_id === "string") {
    try {
      // Spec 1b: queued, so quiet hours apply; the worker sends it.
      await enqueuePush(supabase, {
        userId: data.inviter_id,
        type: "invite_accepted",
        title: "Your partner joined Attune",
        body: "You can start chatting now.",
        data: { relationship_id: data.relationship_id },
        sourceKey: `invite_accepted:${data.relationship_id}`,
      });
    } catch (pushError) {
      console.error(
        "accept-invite: push notification failed (non-fatal):",
        pushError instanceof Error ? pushError.message : "unknown",
      );
    }
  }

  return {
    relationship_id: data.relationship_id,
    status: String(data.status ?? "active"),
    idempotent: data.idempotent === true,
  };
}
```

Replace `supabase/functions/accept-invite/index.ts` with exactly:

```ts
import {
  HttpError,
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { acceptInvite, InviteRefusal } from "./accept.ts";

// Spec 1 W4a (§4.5, D7): the accept is one SQL transaction
// (accept_relationship_invite_v2); accept.ts maps its refusals and queues
// the push.
Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const user = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const supabase = serviceRoleClient();
    const result = await acceptInvite(
      supabase,
      user.id,
      body.invite_code,
      () => ensureUserRow(supabase, user),
    );
    return jsonResponse(result);
  } catch (error) {
    return handleError(error);
  }
});

async function ensureUserRow(
  supabase: ReturnType<typeof serviceRoleClient>,
  user: { id: string; email: string | null; phone: string | null },
) {
  // Spec 1 W1a: users.mode is retired, so it is never written, and the name
  // is left empty for onboarding to fill: a phone number is never a display
  // name. ignoreDuplicates so this only ever INSERTs a missing row. The
  // phone passed is GoTrue getUser's, confirmed or not; the users insert
  // guard (users_phone_from_auth) stores the verified Auth phone or NULL.
  // Runs only with flow_signin_v2 off (sign_up_guard.ts).
  const { error } = await supabase
    .from("users")
    .upsert(
      {
        id: user.id,
        phone: user.phone,
        display_name: "",
      },
      { onConflict: "id", ignoreDuplicates: true },
    );
  if (error) throw error;
}

function handleError(error: unknown): Response {
  if (error instanceof InviteRefusal) {
    return jsonResponse({ error: error.message, code: error.code }, error.status);
  }
  if (error instanceof HttpError) {
    return jsonResponse({ error: error.message }, error.status);
  }
  console.error(
    "accept-invite failed:",
    error instanceof Error ? error.name : typeof error,
  );
  return jsonResponse({ error: "Could not accept invite" }, 500);
}
```

- [ ] **Step 5: The inviter's age rule in `create-relationship-invite`**

In `supabase/functions/create-relationship-invite/index.ts`:

Edit 1 of 2. Replace exactly:

```ts
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { ensureInviteAccount } from "../_shared/sign_up_guard.ts";

const INVITE_TTL_DAYS = 7;
```

with:

```ts
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { ensureInviteAccount, requireInviterAge } from "../_shared/sign_up_guard.ts";

const INVITE_TTL_DAYS = 7;
```

Edit 2 of 2. Replace exactly:

```ts
    const supabase = serviceRoleClient();

    // Spec 1 W2 interim guard (review I-5, until W4a): under flow_signin_v2
    // no users row is created here; a caller without one gets 409
    // signup:incomplete before anything is read or written.
    await ensureInviteAccount(supabase, user.id, () => ensureUserRow(supabase, user));

    // A user already in an active relationship must never be able to mint
```

with:

```ts
    const supabase = serviceRoleClient();

    // Spec 1 W4a (§4.5): with flow_signin_v2 off, today's missing-row
    // insert. On: no users row is ever created here (D8); the inviter needs
    // an account (409 signup:incomplete), a date of birth (428
    // invite:age_required) and to be 18 or over (403 invite:not_possible),
    // before anything is read or written.
    const eligibility = await ensureInviteAccount(supabase, user.id, () => ensureUserRow(supabase, user));
    requireInviterAge(eligibility);

    // A user already in an active relationship must never be able to mint
```

- [ ] **Step 6: Run them to verify they pass, and type-check both functions**

```bash
cd supabase/functions
deno test --allow-read accept-invite/ 2>&1 | grep -E "passed|failed" | tail -1
deno check accept-invite/index.ts create-relationship-invite/index.ts 2>&1 | tail -2
cd ../..
```

Expected: `ok | 18 passed | 0 failed`; `Check accept-invite/index.ts`, `Check create-relationship-invite/index.ts`, no error.

- [ ] **Step 7: Mutation checks (each must turn a test red)**

```bash
cd supabase/functions
export NO_COLOR=1
cp accept-invite/accept.ts ../../.superpowers/sdd/2026-11-02-spec1-w4/accept.ts.orig
perl -0pi -e 's/  if \(data\.idempotent !== true && typeof data\.inviter_id === "string"\) \{/  if (typeof data.inviter_id === "string") {/' accept-invite/accept.ts
deno test --allow-read accept-invite/accept.test.ts 2>&1 | grep -E "^error|pushed on a replay" | head -2
cp ../../.superpowers/sdd/2026-11-02-spec1-w4/accept.ts.orig accept-invite/accept.ts
perl -0pi -e 's/  await ensureInviteAccount\(supabase, userId, ensureUserRow\);\n//' accept-invite/accept.ts
deno test --allow-read accept-invite/ 2>&1 | grep -E "^error" | head -2
cp ../../.superpowers/sdd/2026-11-02-spec1-w4/accept.ts.orig accept-invite/accept.ts
perl -0pi -e 's/  "invite:own": \{ status: 409,/  "invite:own": { status: 404,/' accept-invite/accept.ts
deno test --allow-read accept-invite/accept.test.ts 2>&1 | grep -E "^error" | head -1
cp ../../.superpowers/sdd/2026-11-02-spec1-w4/accept.ts.orig accept-invite/accept.ts
deno test --allow-read accept-invite/ 2>&1 | grep -E "passed|failed" | tail -1
rm ../../.superpowers/sdd/2026-11-02-spec1-w4/accept.ts.orig
cd ../..
```

Expected: the replay mutant → `error: Error: pushed on a replay`; the guard removal → `error: Error: accept_relationship_invite_v2: unexpected answer` (an account the guard would refuse reached the accept) and `error: Error: accept-invite: the guard does not come before the accept`; the status change → `error: Error: invite:own: 404 You cannot accept your own invite invite:own`; then `ok | 18 passed | 0 failed`.

### Task 3: The app reads the W4a answers; the app's own words; W4a gate (W4a; §3.8 RI-3 states, §4.5, P-7)

**Files:**
- Replace: `lib/features/relationships/data/relationship_invite_service.dart`
- Create: `lib/features/relationships/presentation/invite_error_copy.dart`
- Modify: `lib/features/onboarding/presentation/screens/invite_partner_screen.dart` (the interim screen shows the app's words)
- Modify: `test/helpers/fake_invites.dart` (the preview, scripted)
- Modify: `lib/i10n/app_en.arb` (+ regenerate)
- Test: `test/features/relationships/invite_refusal_test.dart`

**Interfaces:**
- Consumes: Task 2's response shapes; `kAlreadyInRelationshipPrefix`, `kSignUpIncompleteError`, `kFlagsUnavailableError` (kept).
- Produces: `enum InvitePreviewState { ok, expired, invalid, own, linked }`; `class InvitePreview {state, inviterFirstName}`; `enum InviteRefusalKind { invalid, own, expired, alreadyAccepted, alreadyInRelationship, phoneRequired, ageRequired, notPossible, cap, signUpIncomplete, tryLater, unavailable }`; `inviteRefusalKindOf(String?) → InviteRefusalKind?`; `RelationshipInviteService.previewInvite(String) → Future<InvitePreview>`; `invitePreviewFrom(Object?) → InvitePreview`; `inviteCreateFailure(Object) → RelationshipInviteException`; `RelationshipInviteException.kind`; `RelationshipInvite.linkFor(String code) → String`; `inviteErrorCopy(AppLocalizations, RelationshipInviteException) → String`; `FakeInvites.preview`, `.previewError`, `.previewed`; ARB keys `flow_joinAlreadyIn`, `flow_joinNotPossible`, `flow_joinOwn`, `flow_joinInvalid`, `flow_joinTryLater`, `flow_inviteErrorSignUp`, `flow_inviteErrorCap`, `flow_inviteErrorAgeRequired`, `flow_inviteErrorTryAgain`.

- [ ] **Step 1: The copy**

Create `.superpowers/sdd/2026-11-02-spec1-w4/arb_task3.txt` with exactly:

```text
  "flow_joinAlreadyIn": "You're already in a relationship on Attune. End it first to join a new one.",
  "flow_joinNotPossible": "We couldn't link these accounts. If you think this is wrong, contact support.",
  "flow_joinOwn": "This is your own invite. Send it to your partner instead.",
  "flow_joinInvalid": "We couldn't find that invite. Check the code with the person who sent it.",
  "flow_joinTryLater": "You've checked a lot of codes. Try again in a little while.",
  "flow_inviteErrorSignUp": "Finish setting up your account first, then try again.",
  "flow_inviteErrorCap": "You already have 3 invites waiting. Cancel one before you send another.",
  "flow_inviteErrorAgeRequired": "Add your date of birth first, then send your invite.",
  "flow_inviteErrorTryAgain": "We couldn't make your invite. Try again."
```

```bash
D=.superpowers/sdd/2026-11-02-spec1-w4
grep -cP '[^\x00-\x7F]' $D/arb_task3.txt
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_task3.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null; echo "gen exit=$?"
```

Expected: `0`; `added 9 keys`; `gen exit=0`.

- [ ] **Step 2: Write the failing test**

Create `test/features/relationships/invite_refusal_test.dart` with exactly:

```dart
// Spec 1 W4a/W4b (§4.5, P-7): the app reads accept-invite's W4a codes, the
// inviter's 428/403, and the preview; every failure has the app's own
// words, never the server's.
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_error_copy.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

FunctionException _refusal(int status, String message, [String? code]) =>
    FunctionException(
      status: status,
      details: {'error': message, if (code != null) 'code': code},
    );

void main() {
  final loc = lookupAppLocalizations(const Locale('en'));

  test('every W4a accept code is read as its kind', () {
    final cases = <String, (int, String, InviteRefusalKind, bool)>{
      'invite:invalid': (
        404,
        'Invite code is invalid',
        InviteRefusalKind.invalid,
        false,
      ),
      'invite:own': (
        409,
        'You cannot accept your own invite',
        InviteRefusalKind.own,
        false,
      ),
      'invite:expired': (
        410,
        'Invite code has expired',
        InviteRefusalKind.expired,
        false,
      ),
      'invite:already_accepted': (
        409,
        'Invite has already been accepted',
        InviteRefusalKind.alreadyAccepted,
        false,
      ),
      'invite:phone_required': (
        403,
        'invite:phone_required',
        InviteRefusalKind.phoneRequired,
        false,
      ),
      'invite:age_required': (
        428,
        'invite:age_required',
        InviteRefusalKind.ageRequired,
        true,
      ),
      'invite:not_possible': (
        403,
        'invite:not_possible',
        InviteRefusalKind.notPossible,
        false,
      ),
    };
    for (final MapEntry(key: code, value: (status, message, kind, retry))
        in cases.entries) {
      final e = inviteAcceptFailure(_refusal(status, message, code));
      expect(e.kind, kind, reason: code);
      expect(e.retryable, retry, reason: code);
      expect(e.alreadyInRelationship, isFalse, reason: code);
    }
    final already = inviteAcceptFailure(
      _refusal(
        409,
        "You're already in a relationship on Attune. End it first to join a new one.",
        'invite:already_in_relationship',
      ),
    );
    expect(already.kind, InviteRefusalKind.alreadyInRelationship);
    expect(already.alreadyInRelationship, isTrue);
  });

  test('a refusal without a code is read as before (no kind for 4xx)', () {
    final selfAccept = inviteAcceptFailure(
      _refusal(409, 'You cannot accept your own invite'),
    );
    expect(selfAccept.kind, isNull);
    expect(selfAccept.retryable, isFalse);
    final down = inviteAcceptFailure(const FunctionException(status: 500));
    expect(down.kind, InviteRefusalKind.unavailable);
    expect(down.retryable, isTrue);
  });

  test("create: the inviter's 428 and 403, the cap, no account", () {
    final noDob = inviteCreateFailure(_refusal(428, 'invite:age_required'));
    expect(noDob.kind, InviteRefusalKind.ageRequired);
    expect(noDob.retryable, isTrue);
    expect(noDob.message, isNot(contains('invite:')));
    final minor = inviteCreateFailure(_refusal(403, 'invite:not_possible'));
    expect(minor.kind, InviteRefusalKind.notPossible);
    expect(minor.retryable, isFalse);
    final cap = inviteCreateFailure(
      _refusal(409, 'You already have the maximum number of pending invites'),
    );
    expect(cap.kind, InviteRefusalKind.cap);
    final active = inviteCreateFailure(
      _refusal(409, 'You already have an active relationship'),
    );
    expect(active.alreadyActiveRelationship, isTrue);
    expect(active.kind, isNull);
    final none = inviteCreateFailure(_refusal(409, 'signup:incomplete'));
    expect(none.signUpIncomplete, isTrue);
    expect(none.kind, InviteRefusalKind.signUpIncomplete);
  });

  test('the preview: a name only for ok and expired', () {
    final ok = invitePreviewFrom({
      'state': 'ok',
      'inviter_first_name': ' Yaw ',
    });
    expect(ok.state, InvitePreviewState.ok);
    expect(ok.inviterFirstName, 'Yaw');
    final expired = invitePreviewFrom({
      'state': 'expired',
      'inviter_first_name': 'Yaw',
    });
    expect(expired.inviterFirstName, 'Yaw');
    final own = invitePreviewFrom({
      'state': 'own',
      'inviter_first_name': 'Yaw',
    });
    expect(own.state, InvitePreviewState.own);
    expect(own.inviterFirstName, isNull);
    expect(
      invitePreviewFrom({'state': 'linked'}).state,
      InvitePreviewState.linked,
    );
    expect(
      invitePreviewFrom({'state': 'odd'}).state,
      InvitePreviewState.invalid,
    );
    expect(invitePreviewFrom(null).state, InvitePreviewState.invalid);
    expect(
      invitePreviewFrom({
        'state': 'ok',
        'inviter_first_name': '  ',
      }).inviterFirstName,
      isNull,
    );
  });

  test('every failure has the app\'s words, never the server\'s', () {
    final failures = [
      inviteAcceptFailure(
        _refusal(404, 'Invite code is invalid', 'invite:invalid'),
      ),
      inviteAcceptFailure(
        _refusal(409, 'You cannot accept your own invite', 'invite:own'),
      ),
      inviteAcceptFailure(
        _refusal(403, 'invite:not_possible', 'invite:not_possible'),
      ),
      inviteAcceptFailure(
        _refusal(428, 'invite:age_required', 'invite:age_required'),
      ),
      inviteCreateFailure(
        _refusal(409, 'You already have the maximum number of pending invites'),
      ),
      inviteCreateFailure(_refusal(503, 'flags:unavailable')),
      inviteCreateFailure(_refusal(409, 'signup:incomplete')),
      const RelationshipInviteException(
        'Could not check invite.',
        retryable: true,
        kind: InviteRefusalKind.tryLater,
      ),
    ];
    final english = {
      'Invite code is invalid',
      'You cannot accept your own invite',
      'You already have the maximum number of pending invites',
      'Could not create invite.',
      'Could not accept invite.',
    };
    for (final failure in failures) {
      final copy = inviteErrorCopy(loc, failure);
      expect(english, isNot(contains(copy)), reason: failure.message);
      expect(copy, isNot(contains('invite:')));
      expect(copy, isNot(contains('signup:')));
      expect(copy, isNot(contains('flags:')));
    }
    expect(
      inviteErrorCopy(loc, failures[2]),
      "We couldn't link these accounts. If you think this is wrong, contact support.",
    );
    expect(
      inviteErrorCopy(loc, failures[4]),
      'You already have 3 invites waiting. Cancel one before you send another.',
    );
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test --no-pub test/features/relationships/invite_refusal_test.dart 2>&1 | grep -E "Error:" | head -3`
Expected: compile errors: `invite_error_copy.dart` not found, `InviteRefusalKind` / `inviteCreateFailure` / `invitePreviewFrom` not defined.

- [ ] **Step 4: The service reads the W4a answers**

Replace `lib/features/relationships/data/relationship_invite_service.dart` with exactly (today's members, comments and behaviour kept; added: `linkFor`, the preview, `kind`, `inviteCreateFailure`):

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RelationshipInvite {
  const RelationshipInvite({
    required this.relationshipId,
    required this.code,
    required this.expiresAt,
  });

  final String relationshipId;
  final String code;
  final DateTime expiresAt;

  /// A real https:// Universal/App Link — required so the QR code and
  /// shared link actually open (the stock iOS Camera app refuses to open
  /// custom schemes like attune://, and most share targets treat bare
  /// custom schemes as plain unclickable text). Opens the app directly via
  /// Associated Domains / App Links when installed; falls back to a web
  /// landing page (App Store / Play Store) otherwise. The association files
  /// this depends on live in the bars-opus/attune-invite-web repo; see
  /// main.dart's _handleDeepLink for the receiving side.
  String get deepLink => linkFor(code);

  /// The invite link for [code] (R1's message before and after the invite
  /// is made).
  static String linkFor(String code) =>
      'https://invite.attune.barsopus.com/i/$code';
}

class InviteAcceptance {
  const InviteAcceptance({
    required this.relationshipId,
    required this.status,
    required this.idempotent,
  });

  final String relationshipId;
  final String status;
  final bool idempotent;
}

/// What preview_relationship_invite says about a code (Spec 1 §4.3 W4a).
enum InvitePreviewState { ok, expired, invalid, own, linked }

/// RI-3's read: the state and, for ok and expired only, the inviter's
/// first name (never a phone number; null when there is none).
class InvitePreview {
  const InvitePreview({required this.state, this.inviterFirstName});

  final InvitePreviewState state;
  final String? inviterFirstName;
}

/// What an invite refusal is (Spec 1 W4a codes). The app's words are chosen
/// from this, never from the server's text (W4 plan P-7).
enum InviteRefusalKind {
  invalid,
  own,
  expired,
  alreadyAccepted,
  alreadyInRelationship,
  phoneRequired,
  ageRequired,
  notPossible,
  cap,
  signUpIncomplete,
  tryLater,
  unavailable,
}

/// The kind for a W4a server code, or null for anything else.
InviteRefusalKind? inviteRefusalKindOf(String? code) => switch (code) {
  'invite:invalid' => InviteRefusalKind.invalid,
  'invite:own' => InviteRefusalKind.own,
  'invite:expired' => InviteRefusalKind.expired,
  'invite:already_accepted' => InviteRefusalKind.alreadyAccepted,
  'invite:already_in_relationship' => InviteRefusalKind.alreadyInRelationship,
  'invite:phone_required' => InviteRefusalKind.phoneRequired,
  'invite:age_required' => InviteRefusalKind.ageRequired,
  'invite:not_possible' => InviteRefusalKind.notPossible,
  'invite:try_later' => InviteRefusalKind.tryLater,
  _ => null,
};

class RelationshipInviteService {
  RelationshipInviteService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  static const timeout = Duration(seconds: 30);

  SupabaseClient? get _safeClient {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get isConfigured => _safeClient != null;

  /// Returns the caller's current live pending invite (creating the first
  /// one if none exists) — safe to call on every load, per
  /// ATTUNE_MASTER_SPEC.md's "Invite codes are reusable until accepted or
  /// expired": it never mints a new code while one is still live.
  ///
  /// Pass [forceNew] only for the Day 7 pivot's "Invite someone else
  /// (doesn't cancel existing invite)" option — this always creates an
  /// additional pending invite instead of returning an existing one, up to
  /// the spec's cap of 3 concurrent pending invites per inviter (the
  /// function rejects a 4th with [RelationshipInviteException]).
  Future<RelationshipInvite> createInvite({bool forceNew = false}) async {
    final client = _safeClient;
    if (client == null) {
      // Never name the backend in a user-facing message (auth engine spec
      // §Failure Modes: no project refs / internal config in UI errors).
      throw const RelationshipInviteException(
        'Invites are unavailable right now. Please try again later.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }

    try {
      final response = await client.functions
          .invoke('create-relationship-invite', body: {'force_new': forceNew})
          .timeout(timeout);
      final data = _readMap(response.data);

      return RelationshipInvite(
        relationshipId: data['relationship_id'] as String,
        code: data['invite_code'] as String,
        expiresAt: DateTime.parse(data['invite_expires_at'] as String),
      );
    } catch (error) {
      debugPrint('[relationship-invite] create failed: ${error.runtimeType}');
      if (error is RelationshipInviteException) rethrow;
      throw inviteCreateFailure(error);
    }
  }

  /// How long the caller has been waiting on a partner: since their oldest
  /// never-accepted invite, expired ones included (Spec 5, plan review C3),
  /// so a fresh code never resets it. Null when there is none or the server
  /// cannot say.
  Future<Duration?> inviteAge() async {
    final client = _safeClient;
    if (client == null) return null;
    try {
      final seconds = await client.rpc('get_my_invite_age').timeout(timeout);
      return seconds is num ? Duration(seconds: seconds.toInt()) : null;
    } catch (error) {
      debugPrint('[relationship-invite] age failed: ${error.runtimeType}');
      return null;
    }
  }

  /// Day 7's "Use Attune on my own for now" (Spec 5, plan review C2):
  /// removes the caller's own never-accepted invites; the mode sync then
  /// resolves to personal mode.
  Future<void> withdrawPendingInvites() async {
    final client = _safeClient;
    if (client == null) {
      throw const RelationshipInviteException(
        'Invites are unavailable right now. Please try again later.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }
    try {
      await client.rpc('withdraw_my_pending_invites').timeout(timeout);
    } catch (error) {
      debugPrint('[relationship-invite] withdraw failed: ${error.runtimeType}');
      throw const RelationshipInviteException(
        'Could not update your invite.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }
  }

  /// RI-3 (Spec 1 W4a): who sent [inviteCode], for a signed-in caller.
  /// Throws a retryable [RelationshipInviteException]: kind tryLater past
  /// the server's limit (10 an hour, 30 a day), unavailable otherwise.
  Future<InvitePreview> previewInvite(String inviteCode) async {
    final client = _safeClient;
    if (client == null) {
      throw const RelationshipInviteException(
        'Could not check invite.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }
    try {
      final data = await client
          .rpc('preview_relationship_invite', params: {'p_code': inviteCode})
          .timeout(timeout);
      return invitePreviewFrom(data);
    } on PostgrestException catch (error) {
      debugPrint('[relationship-invite] preview refused: ${error.code}');
      throw RelationshipInviteException(
        'Could not check invite.',
        retryable: true,
        kind:
            error.message == 'invite:try_later'
                ? InviteRefusalKind.tryLater
                : InviteRefusalKind.unavailable,
      );
    } catch (error) {
      debugPrint('[relationship-invite] preview failed: ${error.runtimeType}');
      throw const RelationshipInviteException(
        'Could not check invite.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }
  }

  Future<InviteAcceptance> acceptInvite(String inviteCode) async {
    final client = _safeClient;
    if (client == null) {
      // Never name the backend in a user-facing message (auth engine spec
      // §Failure Modes: no project refs / internal config in UI errors).
      throw const RelationshipInviteException(
        'Invites are unavailable right now. Please try again later.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }

    try {
      final response = await client.functions
          .invoke('accept-invite', body: {'invite_code': inviteCode})
          .timeout(timeout);
      final data = _readMap(response.data);

      return InviteAcceptance(
        relationshipId: data['relationship_id'] as String,
        status: data['status'] as String,
        idempotent: data['idempotent'] as bool? ?? false,
      );
    } catch (error) {
      debugPrint('[relationship-invite] accept failed: ${error.runtimeType}');
      if (error is RelationshipInviteException) rethrow;
      throw inviteAcceptFailure(error);
    }
  }

  Map<String, dynamic> _readMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const RelationshipInviteException('Unexpected invite response.');
  }
}

/// preview_relationship_invite's answer; an unknown state reads as invalid.
InvitePreview invitePreviewFrom(Object? data) {
  final map = data is Map ? data : const {};
  final state = switch (map['state']) {
    'ok' => InvitePreviewState.ok,
    'expired' => InvitePreviewState.expired,
    'own' => InvitePreviewState.own,
    'linked' => InvitePreviewState.linked,
    _ => InvitePreviewState.invalid,
  };
  final raw = map['inviter_first_name'];
  final name = raw is String ? raw.trim() : '';
  final named =
      state == InvitePreviewState.ok || state == InvitePreviewState.expired;
  return InvitePreview(
    state: state,
    inviterFirstName: named && name.isNotEmpty ? name : null,
  );
}

/// accept-invite's refusal for someone already in an active or paused
/// relationship (sync audit I-8). Matched on its opening words, which the
/// server keeps fixed (supabase/functions/accept-invite/accept.test.ts).
const kAlreadyInRelationshipPrefix = "You're already in a relationship";

/// Both invite functions' 409 for a signed-in caller with no account yet
/// under flow_signin_v2 (supabase/functions/_shared/sign_up_guard.ts).
const kSignUpIncompleteError = 'signup:incomplete';

/// Their 503 when the server can't read flow_signin_v2 (the guard fails
/// closed): retryable, and never shown.
const kFlagsUnavailableError = 'flags:unavailable';

/// What a failed createInvite call means. create-relationship-invite
/// replies {"error": message}: 409 for no account yet
/// (signup:incomplete), the pending-invite cap or an already active
/// relationship; since W4a 428 invite:age_required (no date of birth) and
/// 403 invite:not_possible (under 18); 503 flags:unavailable.
RelationshipInviteException inviteCreateFailure(Object error) {
  if (error is FunctionException) {
    final details = error.details;
    final message = details is Map ? details['error'] as String? : null;
    if (error.status == 409) {
      // Spec 1 W2 interim guard (review I-5): no account yet. The code is
      // never shown; finishing sign-up resolves it.
      if (message == kSignUpIncompleteError) {
        return const RelationshipInviteException(
          'Could not create invite.',
          signUpIncomplete: true,
          kind: InviteRefusalKind.signUpIncomplete,
        );
      }
      // Two distinct 409s share this status: the spec's 3-concurrent-
      // pending-invites cap, and the newer already-active-relationship
      // guard (create-relationship-invite's own comment explains why
      // that check exists — a stale isPendingCouples flag on this
      // screen calling createInvite() right after a partner's
      // acceptance flipped this relationship to active). Callers need
      // to tell them apart: the cap is a real, showable error, but
      // "already active" means local state is stale and the fix is a
      // resync, not a message.
      final alreadyActive =
          message?.toLowerCase().contains('already have an active') ?? false;
      return RelationshipInviteException(
        message ?? 'You already have the maximum number of pending invites.',
        alreadyActiveRelationship: alreadyActive,
        kind: alreadyActive ? null : InviteRefusalKind.cap,
      );
    }
    final kind = inviteRefusalKindOf(message);
    if (kind == InviteRefusalKind.ageRequired ||
        kind == InviteRefusalKind.notPossible) {
      return RelationshipInviteException(
        'Could not create invite.',
        retryable: kind == InviteRefusalKind.ageRequired,
        kind: kind,
      );
    }
    if (message == kFlagsUnavailableError || error.status >= 500) {
      return const RelationshipInviteException(
        'Could not create invite.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }
  }
  return const RelationshipInviteException(
    'Could not create invite.',
    retryable: true,
    kind: InviteRefusalKind.unavailable,
  );
}

/// What a failed acceptInvite call means. accept-invite's handleError
/// always replies with {"error": "<message>"} plus a real status: 400 bad
/// code, 404 invalid, 409 self-accept/already-accepted/already in a
/// relationship, 410 expired; since W4a also 403 and 428, and a "code"
/// (invite:CODE) the app reads first. None of the refusals are worth
/// retrying with the same code except a missing date of birth (added, then
/// joined), so callers can tell them apart from a transient
/// network/timeout failure instead of showing "try again" for both.
RelationshipInviteException inviteAcceptFailure(Object error) {
  if (error is FunctionException) {
    final details = error.details;
    final message = details is Map ? details['error'] as String? : null;
    final code = details is Map ? details['code'] as String? : null;
    // Spec 1 W2 interim guard (review I-5): no account yet. Retryable, so
    // the stored invite is kept and accepted once sign-up is finished (an
    // unfinished account goes on from /home to /onboarding, whose consent
    // step sends it to /signup under flow_signin_v2).
    if (error.status == 409 && message == kSignUpIncompleteError) {
      return const RelationshipInviteException(
        'Could not accept invite.',
        retryable: true,
        signUpIncomplete: true,
        kind: InviteRefusalKind.signUpIncomplete,
      );
    }
    if (message == kFlagsUnavailableError) {
      return const RelationshipInviteException(
        'Could not accept invite.',
        retryable: true,
        kind: InviteRefusalKind.unavailable,
      );
    }
    final kind = inviteRefusalKindOf(code);
    final alreadyIn =
        kind == InviteRefusalKind.alreadyInRelationship ||
        (error.status == 409 &&
            (message ?? '').startsWith(kAlreadyInRelationshipPrefix));
    return RelationshipInviteException(
      message ?? 'Could not accept invite.',
      retryable:
          error.status >= 500 || kind == InviteRefusalKind.ageRequired,
      alreadyInRelationship: alreadyIn,
      kind:
          alreadyIn
              ? InviteRefusalKind.alreadyInRelationship
              : kind ??
                  (error.status >= 500 ? InviteRefusalKind.unavailable : null),
    );
  }
  return const RelationshipInviteException(
    'Could not accept invite.',
    retryable: true,
    kind: InviteRefusalKind.unavailable,
  );
}

class RelationshipInviteException implements Exception {
  const RelationshipInviteException(
    this.message, {
    this.retryable = false,
    this.alreadyActiveRelationship = false,
    this.alreadyInRelationship = false,
    this.signUpIncomplete = false,
    this.kind,
  });

  /// The server's or service's own words, for logs and today's flag-off
  /// screens. W4b screens show [kind]'s copy instead (inviteErrorCopy).
  final String message;

  /// False for the server's deterministic rejections (bad/expired/
  /// already-accepted/self-accept codes) — retrying acceptInvite with the
  /// same code cannot succeed, so callers should move the user forward
  /// instead of prompting them to try again. True for transient failures
  /// (network/timeout/5xx) where a retry might work.
  final bool retryable;

  /// True only for createInvite's "you already have an active
  /// relationship" 409 — see create-relationship-invite's own guard.
  /// Reaching this means the CALLER's local mode/pendingCouples state is
  /// stale (the relationship already went active server-side), not that
  /// the user did anything wrong, so UI callers should trigger a resync
  /// (relationshipModeResyncSignal) rather than show this as an error.
  final bool alreadyActiveRelationship;

  /// True for acceptInvite's 409 when the person is already in an active
  /// or paused relationship: tell them (showOpenRelationshipNotice) rather
  /// than drop the link silently.
  final bool alreadyInRelationship;

  /// True for either invite function's 409 signup:incomplete (Spec 1 W2
  /// interim guard, review I-5): under flow_signin_v2 the caller is signed
  /// in but has no account yet, which only finishing sign-up resolves.
  final bool signUpIncomplete;

  /// Which refusal this is, when known (Spec 1 W4a).
  final InviteRefusalKind? kind;

  @override
  String toString() => message;
}
```

Create `lib/features/relationships/presentation/invite_error_copy.dart` with exactly:

```dart
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/i10n/generated/app_localizations.dart';

/// The words a person sees for an invite that failed (Spec 1 W4b; W4 plan
/// P-7): always the app's own `flow_*` copy, never the server's or the
/// service's English. Used by R1, R3 and RI-3.
String inviteErrorCopy(
  AppLocalizations loc,
  RelationshipInviteException error,
) {
  if (error.alreadyInRelationship) return loc.flow_joinAlreadyIn;
  if (error.signUpIncomplete) return loc.flow_inviteErrorSignUp;
  return switch (error.kind) {
    InviteRefusalKind.cap => loc.flow_inviteErrorCap,
    InviteRefusalKind.ageRequired => loc.flow_inviteErrorAgeRequired,
    InviteRefusalKind.notPossible ||
    InviteRefusalKind.phoneRequired => loc.flow_joinNotPossible,
    InviteRefusalKind.own => loc.flow_joinOwn,
    InviteRefusalKind.invalid ||
    InviteRefusalKind.alreadyAccepted => loc.flow_joinInvalid,
    InviteRefusalKind.expired => loc.flow_inviteCodeRefused,
    InviteRefusalKind.tryLater => loc.flow_joinTryLater,
    InviteRefusalKind.alreadyInRelationship => loc.flow_joinAlreadyIn,
    InviteRefusalKind.signUpIncomplete => loc.flow_inviteErrorSignUp,
    InviteRefusalKind.unavailable || null =>
      error.retryable ? loc.flow_inviteErrorTryAgain : loc.flow_joinInvalid,
  };
}
```

- [ ] **Step 5: The interim R1 shows the app's words; the fake learns the preview**

In `lib/features/onboarding/presentation/screens/invite_partner_screen.dart`:

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/home/home_seams.dart';
```

with:

```dart
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_error_copy.dart';
import 'package:attune/home/home_seams.dart';
```

Edit 2 of 2. Replace exactly:

```dart
      _fail(error.message);
```

with:

```dart
      _fail(inviteErrorCopy(loc, error));
```

In `test/helpers/fake_invites.dart`:

Edit 1 of 2. Replace exactly:

```dart
  RelationshipInviteException? acceptError;
  RelationshipInviteException? createError;
  final accepted = <String>[];
  int creates = 0;
```

with:

```dart
  RelationshipInviteException? acceptError;
  RelationshipInviteException? createError;

  /// Spec 1 W4b: what previewInvite answers (or throws).
  InvitePreview preview = const InvitePreview(
    state: InvitePreviewState.ok,
    inviterFirstName: 'Yaw',
  );
  RelationshipInviteException? previewError;
  final previewed = <String>[];
  final accepted = <String>[];
  int creates = 0;
```

Edit 2 of 2. Replace exactly:

```dart

  @override
  Future<void> withdrawPendingInvites() async => withdrawals++;
}
```

with:

```dart

  @override
  Future<InvitePreview> previewInvite(String inviteCode) async {
    previewed.add(inviteCode);
    if (previewError != null) throw previewError!;
    return preview;
  }

  @override
  Future<void> withdrawPendingInvites() async => withdrawals++;
}
```

- [ ] **Step 6: Run the tests**

```bash
flutter test --no-pub test/features/relationships/invite_refusal_test.dart test/features/relationships/invite_signup_incomplete_test.dart test/features/relationships/open_relationship_notice_test.dart test/features/onboarding/w3/invite_partner_screen_test.dart 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
```

Expected: `All tests passed!` (W2's guard tests and W3's interim R1 tests unchanged).

- [ ] **Step 7: W4a gate**

```bash
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error ' | sed -E 's/:[0-9]+:[0-9]+//' | sort -u | comm -13 .superpowers/sdd/2026-11-02-spec1-w4/analyze-errors-baseline.txt -
git diff --stat -- lib/features/opinions lib/features/games lib/features/auth/utility/auth_exports.dart | tail -1
awk '/if \(isAuthenticated && !_gateData.isComplete\) \{/,/_redirectingToOnboarding = false;/' lib/home/home_screen.dart | diff .superpowers/sdd/2026-11-02-spec1-w4/latch-before.txt - && echo "latch unchanged"
(cd supabase/functions && deno test --allow-read accept-invite/ 2>&1 | grep -E 'passed|failed' | tail -1)
grep -E 'invite_v2' .superpowers/sdd/2026-11-02-spec1-w4/sql-after-w4a.txt
```

Expected: `All tests passed!`; no analyzer output; no diff line; `latch unchanged`; `ok | 18 passed | 0 failed`; `PASS invite_v2_contracts.sql`. Report the W4a state: the server and both functions are on the W4a rules (unflagged); the app reads them; nothing a person sees changes except the interim R1's error words.

### Task 4: The registers, the partner name on this phone, its wipe (W4b; §3.8 R1, §4.8, §5.5, §5.8, D8, D20, P-9, P-15, P-16)

**Files:**
- Create: `lib/features/relationships/data/invite_messages.dart`
- Create: `lib/features/relationships/data/invite_device_store.dart`
- Modify: `lib/app/device_wipes.dart` (the `spec1.partner_first_name` entry)
- Modify: `lib/core/services/shared_preferences_service.dart` (the linked moment's kept prefix)
- Modify: `lib/i10n/app_en.arb` (+ regenerate)
- Test: `test/features/relationships/w4/invite_messages_test.dart`, `test/features/relationships/w4/invite_device_store_test.dart`

**Interfaces:**
- Consumes: Task 3's l10n; W3's `DeviceWipeEntry`, `removePrefsKeys`, `PreferencesService`.
- Produces: `enum InviteRegister { simple, casual, pidgin }`, `const kPidginRegisterReviewed = false`, `offeredInviteRegisters() → List<InviteRegister>`, `inviteMessage(AppLocalizations, {register, link, code, partnerFirstName, foundItMyself}) → String`; `InviteDeviceStore(prefs, {userId})` with `partnerFirstName`, `savePartnerFirstName(String?)`, `clearPartnerFirstName()`, `day30Done`, `markDay30Done()`, `linkedMomentSeen(relationshipId)`, `markLinkedMomentSeen(relationshipId)`, statics `maxNameLength` (40), `partnerNameKey(uid)`, `day30Key(uid)`, `linkedMomentPrefix` (`attune.linked_moment:`), `linkedMomentKey(uid, rid)`, `isWipedOnSignOut(key)`; wipe entry `spec1.partner_first_name` (sign-out); ARB keys `flow_inviteMsg*` (11).

- [ ] **Step 1: The copy (the one non-ASCII character is the escape `→`)**

Create `.superpowers/sdd/2026-11-02-spec1-w4/arb_task4.txt` with exactly:

```text
  "flow_inviteMsgSimpleOpen": "Hi {name}, I'd like us to try Attune together. It's a private space just for the two of us.",
  "@flow_inviteMsgSimpleOpen": {"placeholders": {"name": {"type": "String"}}},
  "flow_inviteMsgSimpleOpenNoName": "Hi, I'd like us to try Attune together. It's a private space just for the two of us.",
  "flow_inviteMsgSimpleGet": "Get the app: {link}",
  "@flow_inviteMsgSimpleGet": {"placeholders": {"link": {"type": "String"}}},
  "flow_inviteMsgCasualOpen": "Hey {name}! I found an app for couples and thought of us. Private, just you and me.",
  "@flow_inviteMsgCasualOpen": {"placeholders": {"name": {"type": "String"}}},
  "flow_inviteMsgCasualOpenNoName": "Hey! I found an app for couples and thought of us. Private, just you and me.",
  "flow_inviteMsgCasualGet": "Get it here: {link}",
  "@flow_inviteMsgCasualGet": {"placeholders": {"link": {"type": "String"}}},
  "flow_inviteMsgPidginOpen": "{name}, make we try Attune. Na private space for only you and me.",
  "@flow_inviteMsgPidginOpen": {"placeholders": {"name": {"type": "String"}}},
  "flow_inviteMsgPidginOpenNoName": "Make we try Attune. Na private space for only you and me.",
  "flow_inviteMsgPidginGet": "Download am: {link}",
  "@flow_inviteMsgPidginGet": {"placeholders": {"link": {"type": "String"}}},
  "flow_inviteMsgOpenCode": "Open Attune \u2192 I have an invite \u2192 {code}",
  "@flow_inviteMsgOpenCode": {"placeholders": {"code": {"type": "String"}}},
  "flow_inviteMsgFoundMyself": "I found this myself. I just thought it'd be nice."
```

```bash
D=.superpowers/sdd/2026-11-02-spec1-w4
grep -cP '[^\x00-\x7F]' $D/arb_task4.txt
grep -c 'u2192' $D/arb_task4.txt
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_task4.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null; echo "gen exit=$?"
grep -c 'u2192' lib/i10n/app_en.arb
```

Expected: `0`; `1`; `added 11 keys`; `gen exit=0`; `1`.

- [ ] **Step 2: Write the failing tests**

Create `test/features/relationships/w4/invite_messages_test.dart` with exactly:

```dart
// Spec 1 W4b (§3.8 R1): the registers. The code is in every message; the
// name goes with its comma when blank; the optional line goes before the
// link; Pidgin waits for the cultural reviewer; no AI vocabulary.
import 'package:attune/features/relationships/data/invite_messages.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _link = 'https://invite.attune.barsopus.com/i/K7P2QM';

void main() {
  final loc = lookupAppLocalizations(const Locale('en'));

  String message(InviteRegister register, {String? name, bool found = false}) =>
      inviteMessage(
        loc,
        register: register,
        link: _link,
        code: 'K7P2QM',
        partnerFirstName: name,
        foundItMyself: found,
      );

  test('Simple, named: the spec text, the code in the last line', () {
    expect(
      message(InviteRegister.simple, name: 'Ama'),
      "Hi Ama, I'd like us to try Attune together. It's a private space just "
      'for the two of us.\n'
      'Get the app: $_link\n'
      'Open Attune \u2192 I have an invite \u2192 K7P2QM',
    );
  });

  test('Casual and Pidgin, named', () {
    expect(
      message(InviteRegister.casual, name: 'Ama'),
      'Hey Ama! I found an app for couples and thought of us. Private, just '
      'you and me.\n'
      'Get it here: $_link\n'
      'Open Attune \u2192 I have an invite \u2192 K7P2QM',
    );
    expect(
      message(InviteRegister.pidgin, name: 'Ama'),
      'Ama, make we try Attune. Na private space for only you and me.\n'
      'Download am: $_link\n'
      'Open Attune \u2192 I have an invite \u2192 K7P2QM',
    );
  });

  test('no name: the name goes, and so does its comma', () {
    expect(
      message(InviteRegister.simple, name: '  ').split('\n').first,
      "Hi, I'd like us to try Attune together. It's a private space just for "
      'the two of us.',
    );
    expect(
      message(InviteRegister.casual).split('\n').first,
      'Hey! I found an app for couples and thought of us. Private, just you '
      'and me.',
    );
    expect(
      message(InviteRegister.pidgin).split('\n').first,
      'Make we try Attune. Na private space for only you and me.',
    );
  });

  test('the optional line goes before the link', () {
    final lines = message(
      InviteRegister.simple,
      name: 'Ama',
      found: true,
    ).split('\n');
    expect(lines, hasLength(4));
    expect(lines[1], "I found this myself. I just thought it'd be nice.");
    expect(lines[2], 'Get the app: $_link');
  });

  test('every register carries the code and no AI vocabulary', () {
    for (final register in InviteRegister.values) {
      for (final name in [null, 'Ama']) {
        final text = message(register, name: name, found: true);
        expect(text, contains('K7P2QM'));
        expect(text, contains(_link));
        expect(
          text.toLowerCase(),
          isNot(
            matches(RegExp(r'\b(ai|analysis|insight|intelligence|patterns)\b')),
          ),
        );
      }
    }
  });

  test('Pidgin is not offered until the cultural review (W4 gate)', () {
    expect(kPidginRegisterReviewed, isFalse);
    expect(offeredInviteRegisters(), [
      InviteRegister.simple,
      InviteRegister.casual,
    ]);
  });
}
```

Create `test/features/relationships/w4/invite_device_store_test.dart` with exactly:

```dart
// Spec 1 W4b (§3.8, §4.8, §5.8): the partner first name stays on this
// phone, per account; it goes on linking and at sign-out; the linked
// moment is once per phone and survives sign-out; nothing names Dating.
import 'package:attune/app/device_wipes.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the name is per account, trimmed, at most 40 characters', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final mine = InviteDeviceStore(prefs, userId: 'u1');
    final theirs = InviteDeviceStore(prefs, userId: 'u2');
    await mine.savePartnerFirstName('  Ama ');
    expect(mine.partnerFirstName, 'Ama');
    expect(theirs.partnerFirstName, isNull);
    expect(prefs.getString('attune.flow.u1.partner_first_name'), 'Ama');
    await mine.savePartnerFirstName('A' * 60);
    expect(mine.partnerFirstName, hasLength(40));
    await mine.savePartnerFirstName('   ');
    expect(mine.partnerFirstName, isNull);
    expect(prefs.containsKey('attune.flow.u1.partner_first_name'), isFalse);
  });

  test('the linked moment: once per relationship, per account', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = InviteDeviceStore(prefs, userId: 'u1');
    expect(store.linkedMomentSeen('r1'), isFalse);
    await store.markLinkedMomentSeen('r1');
    expect(store.linkedMomentSeen('r1'), isTrue);
    expect(store.linkedMomentSeen('r2'), isFalse);
    expect(
      InviteDeviceStore(prefs, userId: 'u2').linkedMomentSeen('r1'),
      isFalse,
    );
    expect(prefs.getBool('attune.linked_moment:u1:r1'), isTrue);
  });

  test('sign-out removes every account\'s name and day-30 mark, keeps the '
      'linked moment', () async {
    SharedPreferences.setMockInitialValues({
      'attune.flow.u1.partner_first_name': 'Ama',
      'attune.flow.u2.partner_first_name': 'Kofi',
      'attune.flow.u1.invite_day30': true,
      'attune.linked_moment:u1:r1': true,
      'attune.flow.u1.other': 'kept',
    });
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    final entry = registry.entries.firstWhere(
      (e) => e.id == 'spec1.partner_first_name',
    );
    expect(entry.moments, {WipeMoment.signOut});
    expect(entry.protective, isFalse);
    await registry.run(WipeMoment.signOut);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('attune.flow.u1.partner_first_name'), isFalse);
    expect(prefs.containsKey('attune.flow.u2.partner_first_name'), isFalse);
    expect(prefs.containsKey('attune.flow.u1.invite_day30'), isFalse);
    expect(prefs.getBool('attune.linked_moment:u1:r1'), isTrue);
    expect(prefs.getString('attune.flow.u1.other'), 'kept');
  });

  test(
    'the full sign-out clear keeps the linked moment (keptPrefixes)',
    () async {
      SharedPreferences.setMockInitialValues({
        'attune.linked_moment:u1:r1': true,
        'attune.flow.u1.partner_first_name': 'Ama',
      });
      final prefs = await SharedPreferences.getInstance();
      await PreferencesService(prefs).clearUserData();
      expect(prefs.getBool('attune.linked_moment:u1:r1'), isTrue);
      expect(prefs.containsKey('attune.flow.u1.partner_first_name'), isFalse);
    },
  );

  test('no W4 key names Dating (D20)', () {
    for (final key in [
      InviteDeviceStore.partnerNameKey('u1'),
      InviteDeviceStore.day30Key('u1'),
      InviteDeviceStore.linkedMomentKey('u1', 'r1'),
    ]) {
      expect(key.toLowerCase(), isNot(contains('dating')));
    }
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test --no-pub test/features/relationships/w4/ 2>&1 | grep -E "Error:" | head -3`
Expected: compile errors: `invite_messages.dart` and `invite_device_store.dart` not found.

- [ ] **Step 4: The registers and the store**

Create `lib/features/relationships/data/invite_messages.dart` with exactly:

```dart
import 'package:attune/i10n/generated/app_localizations.dart';

/// R1's registers (Spec 1 §3.8): how the invite message sounds.
enum InviteRegister { simple, casual, pidgin }

/// Pidgin is offered only after the Ghanaian cultural reviewer confirms
/// its wording (the W4 group gate). Flip to true in the change that records
/// that review; nothing else changes.
const bool kPidginRegisterReviewed = false;

/// The registers R1 offers, in order.
List<InviteRegister> offeredInviteRegisters() => [
  InviteRegister.simple,
  InviteRegister.casual,
  if (kPidginRegisterReviewed) InviteRegister.pidgin,
];

/// The message the invitee receives (§3.8 R1): the opening (with the
/// partner's first name, or without it and its comma), the optional
/// "I found this myself" line, the app link, then the code line, so the
/// code travels in every message. No AI vocabulary.
String inviteMessage(
  AppLocalizations loc, {
  required InviteRegister register,
  required String link,
  required String code,
  String? partnerFirstName,
  bool foundItMyself = false,
}) {
  final name = partnerFirstName?.trim() ?? '';
  final named = name.isNotEmpty;
  final opening = switch (register) {
    InviteRegister.simple =>
      named
          ? loc.flow_inviteMsgSimpleOpen(name)
          : loc.flow_inviteMsgSimpleOpenNoName,
    InviteRegister.casual =>
      named
          ? loc.flow_inviteMsgCasualOpen(name)
          : loc.flow_inviteMsgCasualOpenNoName,
    InviteRegister.pidgin =>
      named
          ? loc.flow_inviteMsgPidginOpen(name)
          : loc.flow_inviteMsgPidginOpenNoName,
  };
  final getLine = switch (register) {
    InviteRegister.simple => loc.flow_inviteMsgSimpleGet(link),
    InviteRegister.casual => loc.flow_inviteMsgCasualGet(link),
    InviteRegister.pidgin => loc.flow_inviteMsgPidginGet(link),
  };
  return [
    opening,
    if (foundItMyself) loc.flow_inviteMsgFoundMyself,
    getLine,
    loc.flow_inviteMsgOpenCode(code),
  ].join('\n');
}
```

Create `lib/features/relationships/data/invite_device_store.dart` with exactly:

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// What the couples flow keeps on this phone for one account (Spec 1 §3.8,
/// §4.8, §5.8), never on the server:
///   * R1's partner first name, `attune.flow.<uid>.partner_first_name`:
///     used in the message and on this phone only; deleted on linking and
///     by the sign-out wipe (`spec1.partner_first_name`).
///   * R3's day-30 line, `attune.flow.<uid>.invite_day30`: shown once.
///   * R4's linked moment, `attune.linked_moment:<uid>:<relationshipId>`:
///     once per phone per relationship, so it survives sign-out (its prefix
///     is in PreferencesService.keptPrefixes; W4 plan P-15). It holds no
///     name.
class InviteDeviceStore {
  const InviteDeviceStore(this._prefs, {required this.userId});

  final SharedPreferences _prefs;
  final String userId;

  /// A first name is at most 40 characters, as display names are.
  static const maxNameLength = 40;

  static String partnerNameKey(String userId) =>
      'attune.flow.$userId.partner_first_name';

  static String day30Key(String userId) => 'attune.flow.$userId.invite_day30';

  static const linkedMomentPrefix = 'attune.linked_moment:';

  static String linkedMomentKey(String userId, String relationshipId) =>
      '$linkedMomentPrefix$userId:$relationshipId';

  /// The keys the sign-out wipe removes, for every account on the phone.
  static bool isWipedOnSignOut(String key) =>
      key.startsWith('attune.flow.') &&
      (key.endsWith('.partner_first_name') || key.endsWith('.invite_day30'));

  String? get partnerFirstName {
    final name = _prefs.getString(partnerNameKey(userId))?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  /// Blank removes it; longer than [maxNameLength] is cut.
  Future<void> savePartnerFirstName(String? name) async {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      await _prefs.remove(partnerNameKey(userId));
      return;
    }
    await _prefs.setString(
      partnerNameKey(userId),
      trimmed.length > maxNameLength
          ? trimmed.substring(0, maxNameLength)
          : trimmed,
    );
  }

  Future<void> clearPartnerFirstName() => _prefs.remove(partnerNameKey(userId));

  bool get day30Done => _prefs.getBool(day30Key(userId)) ?? false;

  Future<void> markDay30Done() => _prefs.setBool(day30Key(userId), true);

  bool linkedMomentSeen(String relationshipId) =>
      _prefs.getBool(linkedMomentKey(userId, relationshipId)) ?? false;

  Future<void> markLinkedMomentSeen(String relationshipId) =>
      _prefs.setBool(linkedMomentKey(userId, relationshipId), true);
}
```

- [ ] **Step 5: The wipe entry and the kept prefix**

In `lib/app/device_wipes.dart`:

Edit 1 of 3. Replace exactly:

```dart
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
```

with:

```dart
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
```

Edit 2 of 3. Replace exactly:

```dart
/// Spec 1's entries (spec §5.8 table). W4b adds the partner name and Ask 2
/// progress.
```

with:

```dart
/// Spec 1's entries (spec §5.8 table).
```

Edit 3 of 3. Replace exactly:

```dart
              (key.endsWith('.country_override') ||
                  key.endsWith('.first_action')),
        ),
  ),
];
```

with:

```dart
              (key.endsWith('.country_override') ||
                  key.endsWith('.first_action')),
        ),
  ),
  // W4b (§3.8 R1, R3): R1's partner first name and R3's day-30 line, at
  // sign-out, for every account on the phone.
  DeviceWipeEntry(
    id: 'spec1.partner_first_name',
    moments: const {WipeMoment.signOut},
    keys: const {
      'attune.flow.<uid>.partner_first_name',
      'attune.flow.<uid>.invite_day30',
    },
    run: () => removePrefsKeys(InviteDeviceStore.isWipedOnSignOut),
  ),
];
```

In `lib/core/services/shared_preferences_service.dart`:

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
```

with:

```dart
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
```

Edit 2 of 2. Replace exactly:

```dart
  static const keptPrefixes = {'account_known_sessions:'};
```

with:

```dart
  static const keptPrefixes = {
    'account_known_sessions:',
    // Spec 1 W4b (§3.8 R4): "You're both here" once per phone per
    // relationship; keyed by account and relationship, no name.
    InviteDeviceStore.linkedMomentPrefix,
  };
```

- [ ] **Step 6: Run the tests**

```bash
flutter test --no-pub test/features/relationships/w4/ test/app/device_wipes_test.dart test/app/device_wipes_keep_set_test.dart test/architecture/core_prefs_layering_test.dart 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
```

Expected: `All tests passed!`.

- [ ] **Step 7: Mutation check**

```bash
perl -pi -e 's/^const bool kPidginRegisterReviewed = false;/const bool kPidginRegisterReviewed = true;/' lib/features/relationships/data/invite_messages.dart
flutter test --no-pub test/features/relationships/w4/invite_messages_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
perl -pi -e 's/^const bool kPidginRegisterReviewed = true;/const bool kPidginRegisterReviewed = false;/' lib/features/relationships/data/invite_messages.dart
grep -c 'kPidginRegisterReviewed = false' lib/features/relationships/data/invite_messages.dart
```

Expected: `Some tests failed.` (`Pidgin is not offered until the cultural review`), then `1`.

### Task 5: R1 with the registers and R2; the accessible InviteCard (W4b; §2.3, §3.8 R1/R2, P-8, P-9, P-19; carried item 2)

**Files:**
- Replace: `lib/features/onboarding/presentation/widgets/invite_card.dart`
- Create: `lib/features/relationships/presentation/invite_share_actions.dart`
- Create: `lib/features/onboarding/presentation/widgets/invite_partner_step.dart`
- Modify: `lib/features/onboarding/presentation/screens/invite_partner_screen.dart` (R1 under `flow_couples_v2`; `onAlreadyInvited`)
- Modify: `lib/app/routing/app_router.dart` (the `RouteNames.joinInvite` constant only)
- Modify: `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml` (the `whatsapp` scheme)
- Modify: `lib/i10n/app_en.arb` (+ regenerate)
- Test: `test/helpers/fake_share_actions.dart`, `test/features/onboarding/w4/invite_partner_step_test.dart` (+ goldens `w4_r1`), `test/features/onboarding/w4/invite_card_a11y_test.dart`; regenerate `test/features/relationships/goldens/r3_pending.*.png`

**Interfaces:**
- Consumes: Tasks 3–4 (`inviteErrorCopy`, `RelationshipInvite.linkFor`, `inviteMessage`, `offeredInviteRegisters`, `InviteDeviceStore`); W3's `choosePath`, `homeStateProvider`, `PushAskRow`, `flowCouplesV2Provider`, `metricCounterProvider`.
- Produces: `InviteCard.minTarget` (48); `InviteShareActions` (`canOpenWhatsApp`, `openWhatsApp(text) → bool`, `share(text)`, `copy(text)`, static `whatsAppUri`), `inviteShareActionsProvider`; `InvitePartnerStep({required invites, required onDone, switchPath, pauseConfirmed, onAlreadyInvited})`; `InvitePartnerScreen({…, VoidCallback? onAlreadyInvited})` (default: push `RouteNames.joinInvite`, whose route Task 6 adds); `RouteNames.joinInvite = '/join-invite'`; `FakeShareActions`; ARB keys `flow_invitePartnerBodyNamed`, `flow_r1*` (19), `flow_inviteCodeSemantics`.

- [ ] **Step 1: The copy**

Create `.superpowers/sdd/2026-11-02-spec1-w4/arb_task5.txt` with exactly:

```text
  "flow_invitePartnerBodyNamed": "Send a link. When {name} joins, your private space opens.",
  "@flow_invitePartnerBodyNamed": {"placeholders": {"name": {"type": "String"}}},
  "flow_r1NameLabel": "Their first name (optional)",
  "flow_r1NameHelper": "Used in your message and on this phone only.",
  "flow_r1ToneTitle": "How should it sound?",
  "flow_r1ToneGroup": "Choose one of the message styles",
  "flow_r1ToneSimple": "Simple",
  "flow_r1ToneCasual": "Casual",
  "flow_r1TonePidgin": "Pidgin",
  "flow_r1FoundMyselfToggle": "Add: 'I found this myself. I just thought it'd be nice.'",
  "flow_r1PreviewTitle": "What your partner will see",
  "flow_r1PreviewTitleNamed": "What {name} will see",
  "@flow_r1PreviewTitleNamed": {"placeholders": {"name": {"type": "String"}}},
  "flow_r1Making": "Making your invite",
  "flow_r1CodePending": "(your code)",
  "flow_r1SendWhatsApp": "Send on WhatsApp",
  "flow_r1ShareOther": "Share another way",
  "flow_r1ShowQr": "Show QR code",
  "flow_r1CopyCode": "Copy code",
  "flow_r1CodeCopied": "Code copied.",
  "flow_r1QrTitle": "Your invite code",
  "flow_r1QrSemantics": "A QR code for your invite link",
  "flow_inviteCodeSemantics": "Invite code {code}",
  "@flow_inviteCodeSemantics": {"placeholders": {"code": {"type": "String"}}}
```

```bash
D=.superpowers/sdd/2026-11-02-spec1-w4
grep -cP '[^\x00-\x7F]' $D/arb_task5.txt
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_task5.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null; echo "gen exit=$?"
```

Expected: `0`; `added 21 keys`; `gen exit=0`.

- [ ] **Step 2: Write the failing tests**

Create `test/helpers/fake_share_actions.dart` with exactly:

```dart
// Spec 1 W4b: how an invite leaves the phone, recorded.
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';

class FakeShareActions extends InviteShareActions {
  FakeShareActions({this.whatsApp = false, this.whatsAppOpens = true});

  bool whatsApp;
  bool whatsAppOpens;
  final whatsAppTexts = <String>[];
  final shared = <String>[];
  final copied = <String>[];

  @override
  Future<bool> canOpenWhatsApp() async => whatsApp;

  @override
  Future<bool> openWhatsApp(String text) async {
    whatsAppTexts.add(text);
    return whatsAppOpens;
  }

  @override
  Future<void> share(String text) async => shared.add(text);

  @override
  Future<void> copy(String text) async => copied.add(text);
}
```

Create `test/features/onboarding/w4/invite_card_a11y_test.dart` with exactly:

```dart
// Spec 1 W4b (§2.3; carried from W3 P-30 and the batch-3 report): the
// shared InviteCard (R1, R3, the couples waiting step, the Chat locked
// screen) meets the tap-target, label and contrast guidelines; its code is
// one labelled item; its words are unchanged.
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

final _invite = RelationshipInvite(
  relationshipId: 'r1',
  code: 'K7P2QM',
  expiresAt: DateTime.utc(2026, 11, 9),
);

Widget _card() => Scaffold(
  body: SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: InviteCard(invite: _invite),
  ),
);

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('meets the guidelines at $scale', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpFlowScreen(
        tester,
        _card,
        textScale: scale,
        size: const Size(390, 1400),
      );
      await expectFlowGuidelines(tester);
      semantics.dispose();
    });
  }

  testWidgets('the code is one labelled item; the words are today\'s', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(tester, _card, size: const Size(390, 1400));
    expect(find.bySemanticsLabel('Invite code K 7 P 2 Q M'), findsOneWidget);
    expect(find.text('Partner invite'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    for (final label in ['Share', 'Copy link']) {
      final size = tester.getSize(
        find
            .ancestor(of: find.text(label), matching: find.byType(SizedBox))
            .first,
      );
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
    }
    semantics.dispose();
  });
}
```

Create `test/features/onboarding/w4/invite_partner_step_test.dart` with exactly:

```dart
// Spec 1 W4b (§3.8 R1, R2; §2.3): under flow_couples_v2, R1 is the
// registers step: the first name stays on this phone and names the
// preview; Simple and Casual only (Pidgin waits for its review); every
// way of sending carries the code and is counted; R2 asks after a send;
// refusals are the app's words; it meets the guidelines at every size.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_partner_step.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/fake_share_actions.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-r1';

Future<
  (FlowHarness, FakeInvites, FakeShareActions, FakePushAsker, List<String>)
>
_pump(
  WidgetTester tester, {
  FakeInvites? invites,
  FakeShareActions? share,
  bool couplesV2 = true,
  Map<String, Object> prefsValues = const {},
  double textScale = 1.0,
  Size size = const Size(390, 2000),
}) async {
  await tester.pumpWidget(const SizedBox());
  final fakeInvites = invites ?? FakeInvites();
  final actions = share ?? FakeShareActions();
  final asker = FakePushAsker();
  final done = <String>[];
  final h = await pumpFlowScreen(
    tester,
    () => InvitePartnerScreen(
      onDone: () => done.add('done'),
      onAlreadyInvited: () => done.add('already'),
    ),
    textScale: textScale,
    size: size,
    prefsValues: prefsValues,
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(
          FakeHomeStateGateway(state: homeJson(path: 'relationship')),
        ),
      ),
      invitePartnerServiceProvider.overrideWithValue(fakeInvites),
      inviteShareActionsProvider.overrideWithValue(actions),
      pushAskerProvider.overrideWithValue(asker),
      flowCouplesV2Provider.overrideWithValue(couplesV2),
    ],
  );
  return (h, fakeInvites, actions, asker, done);
}

void main() {
  testWidgets('flow_couples_v2 off: today\'s R1, no registers', (tester) async {
    await _pump(tester, couplesV2: false);
    expect(find.byType(InvitePartnerStep), findsNothing);
    expect(find.text('Create my invite'), findsOneWidget);
  });

  testWidgets('on: the invite is made on opening; Simple and Casual only', (
    tester,
  ) async {
    final (_, invites, _, _, _) = await _pump(tester);
    expect(find.byType(InvitePartnerStep), findsOneWidget);
    expect(invites.creates, 1);
    expect(find.text('Simple'), findsOneWidget);
    expect(find.text('Casual'), findsOneWidget);
    expect(find.text('Pidgin'), findsNothing);
    expect(find.text('What your partner will see'), findsOneWidget);
    expect(find.textContaining('K7P2QM'), findsOneWidget);
    expect(
      find.text('Used in your message and on this phone only.'),
      findsOneWidget,
    );
  });

  testWidgets('the first name names the preview and stays on this phone', (
    tester,
  ) async {
    final (h, _, _, _, _) = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'Ama');
    await tester.pumpAndSettle();
    expect(find.text('What Ama will see'), findsOneWidget);
    expect(
      find.text('Send a link. When Ama joins, your private space opens.'),
      findsOneWidget,
    );
    expect(find.textContaining("Hi Ama, I'd like us"), findsOneWidget);
    expect(h.prefs.getString('attune.flow.$_uid.partner_first_name'), 'Ama');
  });

  testWidgets('a name saved before is there when R1 opens again', (
    tester,
  ) async {
    await _pump(
      tester,
      prefsValues: {'attune.flow.$_uid.partner_first_name': 'Kofi'},
    );
    expect(find.text('What Kofi will see'), findsOneWidget);
  });

  testWidgets('Casual and the optional line change the message', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Casual'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Hey! I found an app for couples'),
      findsOneWidget,
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        "I found this myself. I just thought it'd be nice.\nGet it here:",
      ),
      findsOneWidget,
    );
  });

  testWidgets('WhatsApp when installed: the message with the code, counted', (
    tester,
  ) async {
    final share = FakeShareActions(whatsApp: true);
    final (h, _, _, _, _) = await _pump(tester, share: share);
    await tester.tap(find.text('Send on WhatsApp'));
    await tester.pumpAndSettle();
    expect(
      share.whatsAppTexts.single,
      contains('Open Attune \u2192 I have an invite \u2192 K7P2QM'),
    );
    expect(h.metrics, contains('invite_shared:whatsapp'));
  });

  testWidgets('WhatsApp that does not open falls back to the share sheet', (
    tester,
  ) async {
    final share = FakeShareActions(whatsApp: true, whatsAppOpens: false);
    await _pump(tester, share: share);
    await tester.tap(find.text('Send on WhatsApp'));
    await tester.pumpAndSettle();
    expect(share.shared.single, contains('K7P2QM'));
  });

  testWidgets('no WhatsApp: share, QR and copy, each counted', (tester) async {
    final share = FakeShareActions();
    final (h, _, _, _, _) = await _pump(tester, share: share);
    expect(find.text('Send on WhatsApp'), findsNothing);
    await tester.tap(find.text('Share another way'));
    await tester.pumpAndSettle();
    expect(share.shared.single, contains('K7P2QM'));
    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(share.copied, ['K7P2QM']);
    expect(find.text('Code copied.'), findsOneWidget);
    await tester.tap(find.text('Show QR code'));
    await tester.pumpAndSettle();
    expect(find.text('Your invite code'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(
      h.metrics,
      containsAll([
        'invite_shared:share',
        'invite_shared:copy',
        'invite_shared:qr',
      ]),
    );
  });

  testWidgets('R2: after a send, the heads-up names the partner', (
    tester,
  ) async {
    final (_, _, _, asker, _) = await _pump(tester);
    expect(find.textContaining('Get a heads-up'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Ama');
    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(find.text('Get a heads-up when Ama joins'), findsOneWidget);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(asker.asked, [PushAskContext.r2]);
  });

  testWidgets('a refusal is the app\'s words, never the server\'s', (
    tester,
  ) async {
    await _pump(
      tester,
      invites: FakeInvites(
        createError: const RelationshipInviteException(
          'You already have the maximum number of pending invites',
          kind: InviteRefusalKind.cap,
        ),
      ),
    );
    expect(
      find.text(
        'You already have 3 invites waiting. Cancel one before you send another.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('maximum number'), findsNothing);
  });

  testWidgets('"Invite later" and "My partner already invited me"', (
    tester,
  ) async {
    final (_, _, _, _, done) = await _pump(tester);
    await tester.tap(find.text('Invite later'));
    await tester.tap(find.text('My partner already invited me'));
    expect(done, ['done', 'already']);
  });

  testWidgets('meets the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('R1 goldens', (tester) async {
    await expectFlowGoldens(
      tester,
      'w4_r1',
      () => InvitePartnerScreen(onDone: () {}, onAlreadyInvited: () {}),
      overrides: [
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
        homeStateServiceProvider.overrideWithValue(
          HomeStateService(
            FakeHomeStateGateway(state: homeJson(path: 'relationship')),
          ),
        ),
        invitePartnerServiceProvider.overrideWithValue(FakeInvites()),
        inviteShareActionsProvider.overrideWithValue(
          FakeShareActions(whatsApp: true),
        ),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
        flowCouplesV2Provider.overrideWithValue(true),
      ],
    );
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test --no-pub test/features/onboarding/w4/ 2>&1 | grep -E "Error:" | head -3`
Expected: compile errors: `invite_share_actions.dart` and `invite_partner_step.dart` not found; `onAlreadyInvited` isn't a parameter of `InvitePartnerScreen`.

- [ ] **Step 4: The card meets the guidelines (words unchanged)**

Replace `lib/features/onboarding/presentation/widgets/invite_card.dart` with exactly:

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_qr_code.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Shows a just-created or still-live partner invite: code, link, and quick
/// actions (share / copy), with a QR code encoding the deep link, so a
/// partner standing right there can scan it instead of typing the code.
///
/// Used by R1 (InvitePartnerScreen), R3 (RelationshipSpaceScreen), the
/// couples waiting step and the Chat tab's locked-couples surface
/// (chat_couples_locked_screen.dart) — any visual/behavior change here
/// applies to all of them.
///
/// Spec 1 W4b (§2.3; W3 batch-3 report): every target is at least 48 dp,
/// every text is at least 4.5:1 on the surface, and the code and link are
/// read out as one labelled item (they were selectable text, 32 and 42 dp
/// tall, at 3.31:1). The words are unchanged.
class InviteCard extends StatelessWidget {
  const InviteCard({super.key, required this.invite});

  final RelationshipInvite invite;

  /// The smallest target (§2.3), in logical pixels, never scaled down.
  static const double minTarget = 48;

  @override
  Widget build(BuildContext context) {
    return _InviteQrSheet(invite: invite);
  }
}

class _InviteQrSheet extends StatelessWidget {
  const _InviteQrSheet({required this.invite});

  final RelationshipInvite invite;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // The card is also on flag-off screens: when the app's words aren't
    // there (a bare host), the label is the English one.
    final spelled = invite.code.split('').join(' ');
    final codeLabel =
        AppLocalizations.of(context)?.flow_inviteCodeSemantics(spelled) ??
        'Invite code $spelled';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Gap(Spacing.md.h),
        ExcludeSemantics(child: InviteQrCode(data: invite.deepLink)),
        Gap(Spacing.xl.h),
        Center(
          child: Semantics(
            header: true,
            child: Text(
              'Partner invite',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
        Gap(Spacing.xs.h),
        Center(
          child: Semantics(
            container: true,
            label: codeLabel,
            child: ExcludeSemantics(
              child: Text(
                invite.code,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: Spacing.xs,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
        Gap(Spacing.xs.h),
        Center(
          child: Text(
            invite.deepLink,
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
            textAlign: TextAlign.center,
          ),
        ),
        Gap(Spacing.md.h),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Share',
                prefixIcon: Icons.ios_share,
                prefixIconColor: colorScheme.primary,
                elevation: 0,
                size: ButtonSize.small,
                variant: ButtonVariant.outline,
                height: InviteCard.minTarget,
                // The outline label in primary is 3.04:1 at 11 sp.
                textColor: colorScheme.onSurface,
                onPressed: () {
                  Share.share(
                    'Join me on Attune: ${invite.deepLink}',
                    subject: 'Attune invite',
                  );
                },
              ),
            ),
            Gap(Spacing.smMd.w),
            Expanded(
              child: AppButton(
                label: 'Copy link',
                prefixIconColor: colorScheme.primary,
                prefixIcon: Icons.copy,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                height: InviteCard.minTarget,
                // The outline label in primary is 3.04:1 at 11 sp.
                textColor: colorScheme.onSurface,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: invite.deepLink));
                  context.showSuccessSnackbar('Invite link copied.');
                },
              ),
            ),
          ],
        ),
        Gap(Spacing.md.h),
        Text(
          'Have your partner scan this, or share the code below. To join together as couples on Attune.',
          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
          textAlign: TextAlign.center,
        ),
        Gap(Spacing.xxl.h),
      ],
    );
  }
}
```

- [ ] **Step 5: The share actions and R1**

Create `lib/features/relationships/presentation/invite_share_actions.dart` with exactly:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// How an invite leaves the phone (Spec 1 §3.8 R1, RI-4): WhatsApp's
/// share with the text and no recipient (when WhatsApp is installed), the
/// system share sheet, the clipboard. Replaceable in tests.
class InviteShareActions {
  const InviteShareActions();

  static Uri whatsAppUri(String text) =>
      Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}');

  /// Needs `whatsapp` in LSApplicationQueriesSchemes (iOS) and a
  /// `<queries>` intent for the scheme (Android 11+).
  Future<bool> canOpenWhatsApp() async {
    try {
      return await canLaunchUrl(Uri.parse('whatsapp://send'));
    } catch (_) {
      return false;
    }
  }

  /// False when WhatsApp didn't open (the caller falls back to [share]).
  Future<bool> openWhatsApp(String text) async {
    try {
      return await launchUrl(
        whatsAppUri(text),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> share(String text) async {
    await Share.share(text);
  }

  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

final inviteShareActionsProvider = Provider<InviteShareActions>(
  (ref) => const InviteShareActions(),
);
```

Create `lib/features/onboarding/presentation/widgets/invite_partner_step.dart` with exactly:

```dart
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/notifications/presentation/widgets/push_ask_row.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_qr_code.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:attune/features/relationships/data/invite_messages.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_error_copy.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// R1 · Invite your partner, and R2 · the heads-up (Spec 1 §3.8, W4b,
/// under flow_couples_v2). The optional first name stays on this phone
/// (InviteDeviceStore); the message carries the code in every register;
/// the invite is made on opening (or, from another path, on the first
/// send, which is also the switch to Relationship, §3.12).
class InvitePartnerStep extends ConsumerStatefulWidget {
  const InvitePartnerStep({
    super.key,
    required this.invites,
    required this.onDone,
    this.switchPath = false,
    this.pauseConfirmed = false,
    this.onAlreadyInvited,
  });

  final RelationshipInviteService invites;
  final VoidCallback onDone;
  final bool switchPath;
  final bool pauseConfirmed;

  /// "My partner already invited me"; hidden when null.
  final VoidCallback? onAlreadyInvited;

  @override
  ConsumerState<InvitePartnerStep> createState() => _InvitePartnerStepState();
}

enum _Channel { whatsApp, share, qr, copy }

class _InvitePartnerStepState extends ConsumerState<InvitePartnerStep> {
  final _name = TextEditingController();
  RelationshipInvite? _invite;
  Future<RelationshipInvite?>? _making;
  InviteRegister _register = InviteRegister.simple;
  bool _foundItMyself = false;
  bool _whatsApp = false;
  bool _sent = false;
  bool _copied = false;
  bool _busy = false;
  String? _error;
  int _errorCount = 0;

  InviteDeviceStore? _store;

  @override
  void initState() {
    super.initState();
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId != null) {
      try {
        _store = InviteDeviceStore(
          ref.read(sharedPreferencesProvider),
          userId: userId,
        );
        _name.text = _store!.partnerFirstName ?? '';
      } catch (_) {
        // No SharedPreferences (a bare host): the name lives in the field.
      }
    }
    unawaited(_checkWhatsApp());
    // Made after the first frame: the step reads its words from context.
    if (!widget.switchPath) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_ensureInvite());
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _checkWhatsApp() async {
    final can = await ref.read(inviteShareActionsProvider).canOpenWhatsApp();
    if (mounted) setState(() => _whatsApp = can);
  }

  String? get _partnerName {
    final name = _name.text.trim();
    return name.isEmpty ? null : name;
  }

  void _fail(String message) {
    setState(() {
      _error = message;
      _errorCount++;
    });
    SemanticsService.announce(message, Directionality.of(context));
  }

  /// The live invite, made once (concurrent taps share one call).
  Future<RelationshipInvite?> _ensureInvite() {
    final invite = _invite;
    if (invite != null) return Future.value(invite);
    return _making ??= _make().whenComplete(() => _making = null);
  }

  Future<RelationshipInvite?> _make() async {
    final loc = AppLocalizations.of(context)!;
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId == null) return null;
    // Read before the first await: ref can't be used once the step is gone.
    final home = ref.read(homeStateProvider(userId).notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.switchPath) {
        final outcome = await choosePath(
          context,
          ref,
          userId: userId,
          path: AppPath.relationship,
          confirmed: widget.pauseConfirmed,
        );
        if (!mounted) return null;
        if (outcome == PathChoiceOutcome.cancelled) return null;
        if (outcome != PathChoiceOutcome.done) {
          _fail(
            outcome == PathChoiceOutcome.offline
                ? loc.flow_switchOffline
                : loc.flow_saveFailed,
          );
          return null;
        }
      }
      final invite = await widget.invites.createInvite();
      if (!mounted) return null;
      setState(() => _invite = invite);
      return invite;
    } on RelationshipInviteException catch (error) {
      if (!mounted) return null;
      if (error.alreadyActiveRelationship) {
        widget.onDone();
        return null;
      }
      _fail(inviteErrorCopy(loc, error));
      return null;
    } catch (_) {
      if (mounted) _fail(loc.flow_inviteErrorTryAgain);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
      // The link state changed (pending): every reader catches up.
      unawaited(home.refresh());
    }
  }

  String _message(AppLocalizations loc, String code) => inviteMessage(
    loc,
    register: _register,
    link: RelationshipInvite.linkFor(code),
    code: code,
    partnerFirstName: _partnerName,
    foundItMyself: _foundItMyself,
  );

  Future<void> _send(_Channel channel) async {
    final loc = AppLocalizations.of(context)!;
    final actions = ref.read(inviteShareActionsProvider);
    final metrics = ref.read(metricCounterProvider);
    final invite = await _ensureInvite();
    if (invite == null || !mounted) return;
    final text = _message(loc, invite.code);
    switch (channel) {
      case _Channel.whatsApp:
        metrics.bump(ClientMetricKey.inviteSharedWhatsapp);
        final opened = await actions.openWhatsApp(text);
        if (!opened) await actions.share(text);
      case _Channel.share:
        metrics.bump(ClientMetricKey.inviteSharedShare);
        await actions.share(text);
      case _Channel.qr:
        metrics.bump(ClientMetricKey.inviteSharedQr);
        await _showQr(invite);
      case _Channel.copy:
        metrics.bump(ClientMetricKey.inviteSharedCopy);
        await actions.copy(invite.code);
        if (!mounted) return;
        setState(() => _copied = true);
        SemanticsService.announce(
          loc.flow_r1CodeCopied,
          Directionality.of(context),
        );
    }
    if (mounted) setState(() => _sent = true);
  }

  Future<void> _showQr(RelationshipInvite invite) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) {
        final loc = AppLocalizations.of(sheet)!;
        final theme = Theme.of(sheet);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              0,
              Spacing.md,
              Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    loc.flow_r1QrTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Semantics(
                  image: true,
                  label: loc.flow_r1QrSemantics,
                  child: ExcludeSemantics(
                    child: InviteQrCode(data: invite.deepLink),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Semantics(
                  container: true,
                  label: loc.flow_inviteCodeSemantics(
                    invite.code.split('').join(' '),
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      invite.code,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        letterSpacing: Spacing.xs,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                FlowSecondaryButton(
                  label: loc.flow_close,
                  onPressed: () => Navigator.of(sheet).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = _partnerName;
    final invite = _invite;
    final error = _error;
    final registers = offeredInviteRegisters();
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    return FlowFrame(
      title: loc.flow_invitePartnerTitle,
      hint:
          name == null
              ? loc.flow_invitePartnerBody
              : loc.flow_invitePartnerBodyNamed(name),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlowTextField(
            controller: _name,
            label: loc.flow_r1NameLabel,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              LengthLimitingTextInputFormatter(InviteDeviceStore.maxNameLength),
            ],
            onChanged: (value) {
              setState(() {});
              unawaited(_store?.savePartnerFirstName(value));
            },
          ),
          const SizedBox(height: Spacing.xs),
          Text(loc.flow_r1NameHelper, style: bodyStyle),
          const SizedBox(height: Spacing.md),
          Semantics(
            header: true,
            child: Text(
              loc.flow_r1ToneTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: loc.flow_r1ToneGroup,
            child: Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                for (final register in registers)
                  Semantics(
                    inMutuallyExclusiveGroup: true,
                    child: ChoiceChip(
                      label: Text(_registerLabel(loc, register)),
                      selected: _register == register,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _register = register);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _foundItMyself,
            title: Text(loc.flow_r1FoundMyselfToggle, style: bodyStyle),
            onChanged: (value) => setState(() => _foundItMyself = value),
          ),
          const SizedBox(height: Spacing.sm),
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(BorderRadiusTokens.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    name == null
                        ? loc.flow_r1PreviewTitle
                        : loc.flow_r1PreviewTitleNamed(name),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                if (invite == null && _busy)
                  Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: loc.flow_r1Making,
                    ),
                  )
                else
                  Text(
                    _message(loc, invite?.code ?? loc.flow_r1CodePending),
                    style: bodyStyle,
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          if (_whatsApp) ...[
            FlowPrimaryButton(
              label: loc.flow_r1SendWhatsApp,
              busy: _busy,
              onPressed: () => _send(_Channel.whatsApp),
            ),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              label: loc.flow_r1ShareOther,
              onPressed: _busy ? null : () => _send(_Channel.share),
            ),
          ] else
            FlowPrimaryButton(
              label: loc.flow_r1ShareOther,
              busy: _busy,
              onPressed: () => _send(_Channel.share),
            ),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            label: loc.flow_r1ShowQr,
            onPressed: _busy ? null : () => _send(_Channel.qr),
          ),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            label: loc.flow_r1CopyCode,
            onPressed: _busy ? null : () => _send(_Channel.copy),
          ),
          if (_copied) ...[
            const SizedBox(height: Spacing.xs),
            Text(loc.flow_r1CodeCopied, style: bodyStyle),
          ],
          if (error != null) ...[
            const SizedBox(height: Spacing.sm),
            FlowErrorLine(
              key: ValueKey(_errorCount),
              text: error,
              style: bodyStyle,
            ),
          ],
          // R2 (§3.8): the heads-up, once something was sent, while
          // notifications are off.
          if (_sent) ...[
            const SizedBox(height: Spacing.md),
            PushAskRow(
              askContext: PushAskContext.r2,
              reason:
                  name == null
                      ? loc.flow_pushAskR2
                      : loc.flow_pushAskR2Named(name),
              action: loc.flow_pushTurnOn,
            ),
          ],
        ],
      ),
      actions: [
        FlowTextLink(
          label: loc.flow_invitePartnerLater,
          onPressed: widget.onDone,
        ),
        if (widget.onAlreadyInvited != null)
          FlowTextLink(
            label: loc.flow_pathAlreadyInvited,
            onPressed: widget.onAlreadyInvited!,
          ),
      ],
    );
  }

  static String _registerLabel(AppLocalizations loc, InviteRegister register) =>
      switch (register) {
        InviteRegister.simple => loc.flow_r1ToneSimple,
        InviteRegister.casual => loc.flow_r1ToneCasual,
        InviteRegister.pidgin => loc.flow_r1TonePidgin,
      };
}
```

In `lib/features/onboarding/presentation/screens/invite_partner_screen.dart` (after Task 3's edits):

Edit 1 of 7. Replace exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
```

with:

```dart
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
```

Edit 2 of 7. Replace exactly:

```dart
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_error_copy.dart';
```

with:

```dart
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_partner_step.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_error_copy.dart';
```

Edit 3 of 7. Replace exactly:

```dart
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The invite service, replaceable in tests.
```

with:

```dart
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The invite service, replaceable in tests.
```

Edit 4 of 7. Replace exactly:

```dart
/// tap is also the switch to Relationship (§3.12: "path set when the
/// invite is sent"); [pauseConfirmed] says the Dating pause was already
/// confirmed. W4b's InvitePartnerStep replaces it under flow_couples_v2.
class InvitePartnerScreen extends ConsumerStatefulWidget {
  const InvitePartnerScreen({
```

with:

```dart
/// tap is also the switch to Relationship (§3.12: "path set when the
/// invite is sent"); [pauseConfirmed] says the Dating pause was already
/// confirmed. Under flow_couples_v2 it is W4b's InvitePartnerStep (the
/// registers, the share actions, R2), with the same arguments.
class InvitePartnerScreen extends ConsumerStatefulWidget {
  const InvitePartnerScreen({
```

Edit 5 of 7. Replace exactly:

```dart
    this.switchPath = false,
    this.pauseConfirmed = false,
  });
```

with:

```dart
    this.switchPath = false,
    this.pauseConfirmed = false,
    this.onAlreadyInvited,
  });
```

Edit 6 of 7. Replace exactly:

```dart
  final bool switchPath;
  final bool pauseConfirmed;

  @override
```

with:

```dart
  final bool switchPath;
  final bool pauseConfirmed;

  /// R1's "My partner already invited me" (flow_couples_v2); by default
  /// RI-2 and RI-3 (`/join-invite`).
  final VoidCallback? onAlreadyInvited;

  @override
```

Edit 7 of 7. Replace exactly:

```dart
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
```

with:

```dart
  @override
  Widget build(BuildContext context) {
    // Spec 1 W4b (§3.8 R1): the registers and the share step.
    if (ref.watch(flowCouplesV2Provider)) {
      return InvitePartnerStep(
        invites: ref.read(invitePartnerServiceProvider),
        onDone: widget.onDone,
        switchPath: widget.switchPath,
        pauseConfirmed: widget.pauseConfirmed,
        onAlreadyInvited:
            widget.onAlreadyInvited ??
            () => GoRouter.of(context).push(RouteNames.joinInvite),
      );
    }
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
```

In `lib/app/routing/app_router.dart` (the route name R1's link opens; Task 6 adds its route):

Edit 1 of 1. Replace exactly:

```dart
  /// Spec 1 W3a: R1 until W4b (InvitePartnerScreen).
  static const String invitePartner = '/invite-partner';
```

with:

```dart
  /// Spec 1 W3a: R1 until W4b (InvitePartnerScreen).
  static const String invitePartner = '/invite-partner';

  /// Spec 1 W4b: RI-2 (signed in), RI-3 and RI-4 (JoinInviteScreen).
  static const String joinInvite = '/join-invite';
```

- [ ] **Step 6: Let the phone ask whether WhatsApp is installed**

In `ios/Runner/Info.plist`:

Edit 1 of 1. Replace exactly:

```xml
		<key>AppGroupId</key>
		<string>group.com.barsopus.attune</string>
	</dict>
</plist>
```

with:

```xml
		<key>AppGroupId</key>
		<string>group.com.barsopus.attune</string>
		<!-- Spec 1 W4b (§3.8 R1): "Send on WhatsApp" shows only when
		     whatsapp:// can open. -->
		<key>LSApplicationQueriesSchemes</key>
		<array>
			<string>whatsapp</string>
		</array>
	</dict>
</plist>
```

In `android/app/src/main/AndroidManifest.xml`:

Edit 1 of 1. Replace exactly:

```xml
        <intent>
            <action android:name="android.intent.action.INSERT" />
            <data android:mimeType="vnd.android.cursor.item/event" />
        </intent>
    </queries>
```

with:

```xml
        <intent>
            <action android:name="android.intent.action.INSERT" />
            <data android:mimeType="vnd.android.cursor.item/event" />
        </intent>
        <!-- Spec 1 W4b (§3.8 R1): "Send on WhatsApp" shows only when
             whatsapp:// can open (Android 11+ package visibility). -->
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="whatsapp" />
        </intent>
    </queries>
```

```bash
plutil -lint ios/Runner/Info.plist
xmllint --noout android/app/src/main/AndroidManifest.xml && echo "manifest ok"
```

Expected: `ios/Runner/Info.plist: OK`; `manifest ok`.

- [ ] **Step 7: Run the tests; make R1's goldens and R3's new pending goldens, and look at them**

```bash
flutter test --no-pub --update-goldens test/features/onboarding/w4/invite_partner_step_test.dart test/features/relationships/relationship_space_screen_test.dart 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
ls test/features/onboarding/w4/goldens/
flutter test --no-pub test/features/onboarding/w4/ test/features/relationships/ test/features/onboarding/ test/features/chat/chat_couples_locked_screen_no_dating_test.dart 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
```

Expected: `All tests passed!`; `w4_r1.rtl.png  w4_r1.scale1.0.png  w4_r1.scale1.3.png  w4_r1.scale2.0.png`; `All tests passed!`. Open `w4_r1.scale1.0.png`, `w4_r1.scale2.0.png` and `test/features/relationships/goldens/r3_pending.scale1.0.png`: the name field, the two register chips, the switch, the preview box with the code and the four send buttons are in order with nothing clipped; the card's two buttons are taller than before. (`r3_pending` changes only because of the card, P-8; say so in the report.)

- [ ] **Step 8: Mutation check (the card's targets)**

```bash
cp lib/features/onboarding/presentation/widgets/invite_card.dart .superpowers/sdd/2026-11-02-spec1-w4/invite_card.orig
perl -pi -e 's/height: InviteCard\.minTarget,/height: 40,/' lib/features/onboarding/presentation/widgets/invite_card.dart
flutter test --no-pub test/features/onboarding/w4/invite_card_a11y_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
cp .superpowers/sdd/2026-11-02-spec1-w4/invite_card.orig lib/features/onboarding/presentation/widgets/invite_card.dart
rm .superpowers/sdd/2026-11-02-spec1-w4/invite_card.orig
flutter test --no-pub test/features/onboarding/w4/invite_card_a11y_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
```

Expected: `Some tests failed.` (the tap-target guideline and the 48 dp check), then `All tests passed!`.

### Task 6: RI-2/RI-3/RI-4 and the acceptor's R4; the only accept site (W4b; §3.8 RI-2–RI-4, R4, D9, §5.5, §7.4, P-10–P-13; carried item 4)

**Files:**
- Create: `lib/features/relationships/presentation/widgets/linked_moment.dart`
- Create: `lib/features/relationships/presentation/screens/join_invite_screen.dart`
- Modify: `lib/app/routing/app_router.dart` (the import; the `/join-invite` route)
- Modify: `lib/features/onboarding/presentation/screens/onboarding_gate_v2.dart` (no accept under `flow_couples_v2`)
- Modify: `lib/home/home_screen.dart` (the v2 reconcile, outside the latch)
- Modify: `test/helpers/home_harness.dart` (`extraRoutes`)
- Modify: `lib/i10n/app_en.arb` (+ regenerate)
- Test: `test/features/relationships/w4/join_invite_screen_test.dart` (+ goldens `w4_ri3`, `w4_ri4`, `w4_r4`), `test/features/onboarding/w4/join_routing_test.dart`

**Interfaces:**
- Consumes: Tasks 3–5 (`previewInvite`, `InvitePreview`, `InviteRefusalKind`, `InviteDeviceStore.markLinkedMomentSeen`, `inviteShareActionsProvider`); W2's `normalizeInviteCode`, `FlowFrame`, `FlowTextField`; W3's `OnboardingStore`, `homeStateProvider`, `PushAskRow`, `homeLocation`, `RouteNames.howYouUseAttune`.
- Produces: the `/join-invite` route (signed-in only; Task 5 named it `RouteNames.joinInvite`); `JoinInviteScreen({required onDone, required onJoined, required void Function(bool firstChoice) onChooseAnotherWay, required onNeedsAccount})`; `LinkedMoment({required onContinue, partnerFirstName, myInitial = ''})`; `pumpHome(…, extraRoutes:)`; ARB keys `flow_ri3*` (6), `flow_join{OtherWay,EnterAgain,ExpiredTitle,Expired,ExpiredUnnamed,AskWhatsApp,AskWhatsAppUnnamed,ExpiredMessage,ExpiredMessageUnnamed,Checking}`, `flow_linked{Title,Body,BodyUnnamed}`, `flow_pushAskR4`, `flow_pushAskR4Unnamed`.

- [ ] **Step 1: The copy**

Create `.superpowers/sdd/2026-11-02-spec1-w4/arb_task6.txt` with exactly:

```text
  "flow_ri3Title": "Join {name}?",
  "@flow_ri3Title": {"placeholders": {"name": {"type": "String"}}},
  "flow_ri3TitleUnnamed": "Join your partner?",
  "flow_ri3Body": "{name} invited you to a private space for the two of you on Attune.",
  "@flow_ri3Body": {"placeholders": {"name": {"type": "String"}}},
  "flow_ri3BodyUnnamed": "Your partner invited you to a private space for the two of you on Attune.",
  "flow_ri3Button": "Join {name}",
  "@flow_ri3Button": {"placeholders": {"name": {"type": "String"}}},
  "flow_ri3ButtonUnnamed": "Join",
  "flow_joinOtherWay": "Not what you expected? Choose another way to use Attune",
  "flow_joinEnterAgain": "Enter the code again",
  "flow_joinExpiredTitle": "This invite has expired.",
  "flow_joinExpired": "Ask {name} to send a new one.",
  "@flow_joinExpired": {"placeholders": {"name": {"type": "String"}}},
  "flow_joinExpiredUnnamed": "Ask the person who sent it to send a new one.",
  "flow_joinAskWhatsApp": "Ask {name} on WhatsApp",
  "@flow_joinAskWhatsApp": {"placeholders": {"name": {"type": "String"}}},
  "flow_joinAskWhatsAppUnnamed": "Ask on WhatsApp",
  "flow_joinExpiredMessage": "Hi {name}, my Attune invite expired. Could you send me a new one?",
  "@flow_joinExpiredMessage": {"placeholders": {"name": {"type": "String"}}},
  "flow_joinExpiredMessageUnnamed": "Hi, my Attune invite expired. Could you send me a new one?",
  "flow_joinChecking": "Checking your invite",
  "flow_linkedTitle": "You're both here",
  "flow_linkedBody": "Your private space with {name} is open.",
  "@flow_linkedBody": {"placeholders": {"name": {"type": "String"}}},
  "flow_linkedBodyUnnamed": "Your private space with your partner is open.",
  "flow_pushAskR4": "Get notified when {name} messages you",
  "@flow_pushAskR4": {"placeholders": {"name": {"type": "String"}}},
  "flow_pushAskR4Unnamed": "Get notified when your partner messages you"
```

```bash
D=.superpowers/sdd/2026-11-02-spec1-w4
grep -cP '[^\x00-\x7F]' $D/arb_task6.txt
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_task6.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null; echo "gen exit=$?"
```

Expected: `0`; `added 21 keys`; `gen exit=0`.

- [ ] **Step 2: Write the failing tests**

In `test/helpers/home_harness.dart`:

Edit 1 of 2. Replace exactly:

```dart
  HomeTabTwoBuilder? tabTwo,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
```

with:

```dart
  HomeTabTwoBuilder? tabTwo,
  List<Override> overrides = const [],
  // Spec 1 W4b: routes the shell may open (e.g. /join-invite).
  List<RouteBase> extraRoutes = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
```

Edit 2 of 2. Replace exactly:

```dart
        },
      ),
    ],
  );
```

with:

```dart
        },
      ),
      ...extraRoutes,
    ],
  );
```

Create `test/features/relationships/w4/join_invite_screen_test.dart` with exactly:

```dart
// Spec 1 W4b (§3.8 RI-2, RI-3, RI-4, R4; D9): a stored code is joined only
// after "Join {name}"; the name comes from the preview; each state has its
// words; every way out but a retryable failure drops the code; the joined
// moment asks for message notifications; it meets the guidelines.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/features/relationships/presentation/screens/join_invite_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/fake_share_actions.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-join';
const _slot = 'attune.onboarding.user.$_uid.pending_invite';

String _stored(String code) =>
    '{"code":"$code","stored_at":"${DateTime.now().toUtc().toIso8601String()}"}';

class _Out {
  final events = <String>[];
}

Future<(FlowHarness, FakeInvites, FakeShareActions, FakePushAsker, _Out)> _pump(
  WidgetTester tester, {
  FakeInvites? invites,
  String? code = 'K7P2QM',
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(const SizedBox());
  final fakeInvites = invites ?? FakeInvites();
  final share = FakeShareActions(whatsApp: true);
  final asker = FakePushAsker();
  final out = _Out();
  final h = await pumpFlowScreen(
    tester,
    () => JoinInviteScreen(
      onDone: () => out.events.add('done'),
      onJoined: () => out.events.add('joined'),
      onChooseAnotherWay: (first) => out.events.add('other:$first'),
      onNeedsAccount: () => out.events.add('needs'),
    ),
    textScale: textScale,
    prefsValues: {if (code != null) _slot: _stored(code)},
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(
          FakeHomeStateGateway(state: homeJson(path: null, needs: ['path'])),
        ),
      ),
      invitePartnerServiceProvider.overrideWithValue(fakeInvites),
      inviteShareActionsProvider.overrideWithValue(share),
      pushAskerProvider.overrideWithValue(asker),
    ],
  );
  return (h, fakeInvites, share, asker, out);
}

String? _code(FlowHarness h) =>
    OnboardingStore(h.prefs, scope: 'user.$_uid').pendingInviteCode;

void main() {
  testWidgets('RI-3: "Join Yaw?", nothing accepted before the tap (D9)', (
    tester,
  ) async {
    final (_, invites, _, _, _) = await _pump(tester);
    expect(invites.previewed, ['K7P2QM']);
    expect(invites.accepted, isEmpty);
    expect(find.text('Join Yaw?'), findsOneWidget);
    expect(
      find.text(
        'Yaw invited you to a private space for the two of you on Attune.',
      ),
      findsOneWidget,
    );
    expect(find.text('Join Yaw'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(
      find.text('Not what you expected? Choose another way to use Attune'),
      findsOneWidget,
    );
  });

  testWidgets('Join: accepted once, then R4 with the R4 ask, then the chat', (
    tester,
  ) async {
    final (h, invites, _, asker, out) = await _pump(tester);
    await tester.tap(find.text('Join Yaw'));
    await tester.pumpAndSettle();
    expect(invites.accepted, ['K7P2QM']);
    expect(_code(h), isNull);
    expect(find.text("You're both here"), findsOneWidget);
    expect(find.text('Your private space with Yaw is open.'), findsOneWidget);
    expect(h.prefs.getBool('attune.linked_moment:$_uid:r-joined'), isTrue);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(asker.asked, [PushAskContext.r4]);
    await tester.tap(find.text('Continue'));
    expect(out.events, ['joined']);
  });

  testWidgets('"Not now" drops the code (no later silent accept)', (
    tester,
  ) async {
    final (h, invites, _, _, out) = await _pump(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(_code(h), isNull);
    expect(invites.accepted, isEmpty);
    expect(out.events, ['done']);
  });

  testWidgets('"Choose another way" drops the code; A6 when no path yet', (
    tester,
  ) async {
    final (h, _, _, _, out) = await _pump(tester);
    await tester.tap(
      find.text('Not what you expected? Choose another way to use Attune'),
    );
    await tester.pumpAndSettle();
    expect(_code(h), isNull);
    expect(out.events, ['other:true']);
  });

  testWidgets('RI-4: expired names the inviter and asks on WhatsApp', (
    tester,
  ) async {
    final invites =
        FakeInvites()
          ..preview = const InvitePreview(
            state: InvitePreviewState.expired,
            inviterFirstName: 'Yaw',
          );
    final (h, _, share, _, _) = await _pump(tester, invites: invites);
    expect(find.text('This invite has expired.'), findsOneWidget);
    expect(find.text('Ask Yaw to send a new one.'), findsOneWidget);
    expect(_code(h), isNull);
    await tester.tap(find.text('Ask Yaw on WhatsApp'));
    await tester.pumpAndSettle();
    expect(
      share.whatsAppTexts.single,
      'Hi Yaw, my Attune invite expired. Could you send me a new one?',
    );
    expect(invites.accepted, isEmpty);
  });

  testWidgets('invalid: the words, then "Enter the code again" (RI-2)', (
    tester,
  ) async {
    final invites =
        FakeInvites()
          ..preview = const InvitePreview(state: InvitePreviewState.invalid);
    await _pump(tester, invites: invites);
    expect(
      find.text(
        "We couldn't find that invite. Check the code with the person who sent it.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Enter the code again'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your invite code'), findsOneWidget);
  });

  testWidgets('own invite: the words, no accept', (tester) async {
    final invites =
        FakeInvites()
          ..preview = const InvitePreview(state: InvitePreviewState.own);
    await _pump(tester, invites: invites);
    expect(
      find.text('This is your own invite. Send it to your partner instead.'),
      findsOneWidget,
    );
    expect(invites.accepted, isEmpty);
  });

  testWidgets('no stored code: RI-2, then the preview of the typed code', (
    tester,
  ) async {
    final (h, invites, _, _, _) = await _pump(tester, code: null);
    expect(find.text('Enter your invite code'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'k7p2 qm');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(invites.previewed, ['K7P2QM']);
    expect(_code(h), 'K7P2QM');
    expect(find.text('Join Yaw?'), findsOneWidget);
  });

  testWidgets('a malformed typed code is refused in words', (tester) async {
    await _pump(tester, code: null);
    await tester.enterText(find.byType(TextField), 'K7');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Codes have 6 letters and numbers. Check it with the person who sent it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('already in a relationship: the spec\'s words; code dropped', (
    tester,
  ) async {
    final invites = FakeInvites(
      acceptError: const RelationshipInviteException(
        "You're already in a relationship on Attune. End it first to join a new one.",
        alreadyInRelationship: true,
        kind: InviteRefusalKind.alreadyInRelationship,
      ),
    );
    final (h, _, _, _, _) = await _pump(tester, invites: invites);
    await tester.tap(find.text('Join Yaw'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "You're already in a relationship on Attune. End it first to join a new one.",
      ),
      findsOneWidget,
    );
    expect(_code(h), isNull);
  });

  testWidgets(
    'an age refusal is neutral; no date of birth goes to A2, code kept',
    (tester) async {
      final minor = FakeInvites(
        acceptError: const RelationshipInviteException(
          'invite:not_possible',
          kind: InviteRefusalKind.notPossible,
        ),
      );
      await _pump(tester, invites: minor);
      await tester.tap(find.text('Join Yaw'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "We couldn't link these accounts. If you think this is wrong, contact support.",
        ),
        findsOneWidget,
      );
      expect(find.textContaining('18'), findsNothing);

      final noDob = FakeInvites(
        acceptError: const RelationshipInviteException(
          'invite:age_required',
          retryable: true,
          kind: InviteRefusalKind.ageRequired,
        ),
      );
      final (h, _, _, _, out) = await _pump(tester, invites: noDob);
      await tester.tap(find.text('Join Yaw'));
      await tester.pumpAndSettle();
      expect(out.events, ['needs']);
      expect(_code(h), 'K7P2QM');
    },
  );

  testWidgets('offline: said in words, the code kept, Try again', (
    tester,
  ) async {
    final invites =
        FakeInvites()
          ..previewError = const RelationshipInviteException(
            'Could not check invite.',
            retryable: true,
            kind: InviteRefusalKind.unavailable,
          );
    final (h, _, _, _, _) = await _pump(tester, invites: invites);
    expect(
      find.text("We couldn't check that code. Try again when you're online."),
      findsOneWidget,
    );
    expect(_code(h), 'K7P2QM');
    invites.previewError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Join Yaw?'), findsOneWidget);
  });

  testWidgets('too many tries: said in words', (tester) async {
    final invites =
        FakeInvites()
          ..previewError = const RelationshipInviteException(
            'Could not check invite.',
            retryable: true,
            kind: InviteRefusalKind.tryLater,
          );
    await _pump(tester, invites: invites);
    expect(
      find.text("You've checked a lot of codes. Try again in a little while."),
      findsOneWidget,
    );
  });

  testWidgets('no name from the server: "your partner", never a placeholder', (
    tester,
  ) async {
    final invites =
        FakeInvites()
          ..preview = const InvitePreview(state: InvitePreviewState.ok);
    await _pump(tester, invites: invites);
    expect(find.text('Join your partner?'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
  });

  testWidgets('RI-3 and R4 meet the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    await expectFlowGuidelines(tester);
    await tester.tap(find.text('Join Yaw'));
    await tester.pumpAndSettle();
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('RI-3, RI-4 and R4 goldens', (tester) async {
    List<Override> overrides(FakeInvites invites) => [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(FakeHomeStateGateway(state: homeJson())),
      ),
      invitePartnerServiceProvider.overrideWithValue(invites),
      inviteShareActionsProvider.overrideWithValue(
        FakeShareActions(whatsApp: true),
      ),
      pushAskerProvider.overrideWithValue(FakePushAsker()),
    ];
    Widget screen() => JoinInviteScreen(
      onDone: () {},
      onJoined: () {},
      onChooseAnotherWay: (_) {},
      onNeedsAccount: () {},
    );
    await expectFlowGoldens(
      tester,
      'w4_ri3',
      screen,
      prefsValues: {_slot: _stored('K7P2QM')},
      overrides: overrides(FakeInvites()),
    );
    await expectFlowGoldens(
      tester,
      'w4_ri4',
      screen,
      prefsValues: {_slot: _stored('K7P2QM')},
      overrides: overrides(
        FakeInvites()
          ..preview = const InvitePreview(
            state: InvitePreviewState.expired,
            inviterFirstName: 'Yaw',
          ),
      ),
    );
    await expectFlowGoldens(
      tester,
      'w4_r4',
      screen,
      prefsValues: {_slot: _stored('K7P2QM')},
      overrides: overrides(FakeInvites()),
      before: (tester) async {
        await tester.tap(find.text('Join Yaw'));
        await tester.pumpAndSettle();
      },
    );
  });
}
```

Create `test/features/onboarding/w4/join_routing_test.dart` with exactly:

```dart
// Spec 1 W4b (D9, §5.5, §7.4 "Accept before RI-3 in OnboardingGate"):
// under flow_couples_v2 no screen accepts a stored invite by itself: the
// v2 gate and HomeScreen both open RI-3 (/join-invite) instead. With the
// flag off, today's accept after the name stays (spec 2.5).
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-route';
const _slot = 'attune.onboarding.user.$_uid.pending_invite';

String _stored() =>
    '{"code":"K7P2QM","stored_at":"${DateTime.now().toUtc().toIso8601String()}"}';

Future<(GoRouter, FakeInvites)> _pumpGate(
  WidgetTester tester, {
  required Map<String, dynamic> server,
  required bool couplesV2,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({_slot: _stored()});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final service = HomeStateService(FakeHomeStateGateway(state: server));
  final invites = FakeInvites();
  final auth = FakeHomeAuth(testUser(_uid));
  addTearDown(auth.changes.close);
  final router = GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingGateV2(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('HOME')),
      ),
      GoRoute(
        path: '/join-invite',
        builder: (_, __) => const Scaffold(body: Text('RI-3')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        homeAuthProvider.overrideWithValue(auth),
        homeStateServiceProvider.overrideWithValue(service),
        onboardingSyncServiceProvider.overrideWithValue(
          OnboardingSyncService(homeStateService: service),
        ),
        invitePartnerServiceProvider.overrideWithValue(invites),
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(openCountries: const ['GB', 'GH']),
        ),
        routingNotifierProvider.overrideWith(
          (ref) => RoutingNotifier(flowV2: true),
        ),
        flowCouplesV2Provider.overrideWithValue(couplesV2),
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp.router(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
      ),
    ),
  );
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  return (router, invites);
}

String _at(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('gate, couples v2, A6 owed: RI-3, nothing accepted (D9)', (
    tester,
  ) async {
    final (router, invites) = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
      couplesV2: true,
    );
    expect(_at(router), '/join-invite');
    expect(invites.accepted, isEmpty);
  });

  testWidgets('gate, couples v2, nothing owed: RI-3, not home', (tester) async {
    final (router, invites) = await _pumpGate(
      tester,
      server: homeJson(path: 'just_me'),
      couplesV2: true,
    );
    expect(_at(router), '/join-invite');
    expect(invites.accepted, isEmpty);
  });

  testWidgets('gate, flag off: today\'s accept after the name (spec 2.5)', (
    tester,
  ) async {
    final (_, invites) = await _pumpGate(
      tester,
      server: homeJson(path: null, needs: ['path']),
      couplesV2: false,
    );
    expect(invites.accepted, ['K7P2QM']);
  });

  testWidgets('HomeScreen, couples v2: opens RI-3, never accepts (D9)', (
    tester,
  ) async {
    final invites = FakeInvites();
    await pumpHome(
      tester,
      userId: _uid,
      prefsValues: {
        _slot: _stored(),
        'attune.onboarding.user.$_uid.completed': true,
      },
      server: homeJson(path: 'just_me'),
      overrides: [
        invitePartnerServiceProvider.overrideWithValue(invites),
        flowCouplesV2Provider.overrideWithValue(true),
      ],
      extraRoutes: [
        GoRoute(
          path: '/join-invite',
          builder: (_, __) => const Scaffold(body: Text('RI-3')),
        ),
      ],
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(invites.accepted, isEmpty);
    expect(find.text('RI-3'), findsOneWidget);
  });

  testWidgets('HomeScreen, flag off: today\'s accept stays', (tester) async {
    final invites = FakeInvites();
    await pumpHome(
      tester,
      userId: _uid,
      prefsValues: {
        _slot: _stored(),
        'attune.onboarding.user.$_uid.completed': true,
      },
      server: homeJson(path: 'just_me'),
      overrides: [
        invitePartnerServiceProvider.overrideWithValue(invites),
        flowCouplesV2Provider.overrideWithValue(false),
      ],
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(invites.accepted, ['K7P2QM']);
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test --no-pub test/features/relationships/w4/join_invite_screen_test.dart test/features/onboarding/w4/join_routing_test.dart 2>&1 | grep -E "Error:" | head -3`
Expected: compile error: `join_invite_screen.dart` not found. (Once it exists, the routing test's two couples cases fail on `'/onboarding'`/`'/home'` and on `accepted: ['K7P2QM']` until Step 5.)

- [ ] **Step 4: R4 and RI-2/RI-3/RI-4**

Create `lib/features/relationships/presentation/widgets/linked_moment.dart` with exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notifications/presentation/widgets/push_ask_row.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart' show kSettleDuration;
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// R4 · Linked (Spec 1 §3.8, W4b): "You're both here", the one calm
/// Relationship celebration (§2.2: two avatars settle with SettleIn, the
/// line fades in, one light haptic, all within kCelebrationMaxDuration;
/// reduce motion: static avatars and text), then the in-context ask for
/// message notifications (R4, §2.4), then Chat. The caller records it as
/// seen for this relationship on this phone (InviteDeviceStore).
class LinkedMoment extends StatefulWidget {
  const LinkedMoment({
    super.key,
    required this.onContinue,
    this.myInitial = '',
    this.partnerFirstName,
  });

  final String myInitial;
  final String? partnerFirstName;
  final VoidCallback onContinue;

  @override
  State<LinkedMoment> createState() => _LinkedMomentState();
}

class _LinkedMomentState extends State<LinkedMoment> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!reduceMotionOf(context)) HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = widget.partnerFirstName?.trim();
    final named = name != null && name.isNotEmpty;
    final partnerInitial = named ? name.characters.first.toUpperCase() : '';
    final still = reduceMotionOf(context);
    Widget avatar(String initial, Offset from) => SettleIn(
      animate: !still,
      beginOffset: from,
      child: CircleAvatar(
        radius: 32,
        backgroundColor: theme.colorScheme.primaryContainer,
        child:
            initial.isEmpty
                ? Icon(
                  Icons.person_outline,
                  color: theme.colorScheme.onPrimaryContainer,
                )
                : Text(
                  initial,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
      ),
    );
    return FlowFrame(
      title: loc.flow_linkedTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                avatar(widget.myInitial, const Offset(-0.3, 0)),
                const SizedBox(width: Spacing.sm),
                avatar(partnerInitial, const Offset(0.3, 0)),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),
          // The line fades in as the avatars settle: 280 ms, inside the
          // 600 ms ceiling (kCelebrationMaxDuration).
          TweenAnimationBuilder<double>(
            tween: Tween(begin: still ? 1 : 0, end: 1),
            duration: still ? Duration.zero : kSettleDuration,
            builder: (_, value, child) => Opacity(opacity: value, child: child),
            child: Text(
              named ? loc.flow_linkedBody(name) : loc.flow_linkedBodyUnnamed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          PushAskRow(
            askContext: PushAskContext.r4,
            reason:
                named ? loc.flow_pushAskR4(name) : loc.flow_pushAskR4Unnamed,
            action: loc.flow_pushTurnOn,
          ),
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_continue,
          onPressed: widget.onContinue,
        ),
      ],
    );
  }
}
```

Create `lib/features/relationships/presentation/screens/join_invite_screen.dart` with exactly:

```dart
import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/domain/invite_code.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/features/relationships/presentation/widgets/linked_moment.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// RI-2 (signed in), RI-3 · Join {name}? and RI-4 · Expired (Spec 1 §3.8,
/// W4b, under flow_couples_v2). The one place an invite is accepted: only
/// after an explicit "Join {name}" tap (D9). The code comes from this
/// account's slot (a link, the Install Referrer, or typed here); the
/// inviter's name only after sign-in, from preview_relationship_invite.
/// Every way out but a retryable failure drops the stored code, so it is
/// never accepted later by whoever is signed in (W4 plan P-10).
class JoinInviteScreen extends ConsumerStatefulWidget {
  const JoinInviteScreen({
    super.key,
    required this.onDone,
    required this.onJoined,
    required this.onChooseAnotherWay,
    required this.onNeedsAccount,
  });

  /// "Not now", or nothing to join.
  final VoidCallback onDone;

  /// Joined, after R4: the chat.
  final VoidCallback onJoined;

  /// "Not what you expected? Choose another way to use Attune": A6 when
  /// no path is chosen yet ([firstChoice]), else Settings → How you use
  /// Attune (W4 plan P-11).
  final void Function(bool firstChoice) onChooseAnotherWay;

  /// The account still lacks something (no date of birth, sign-up not
  /// finished): the code is kept and the gate asks for it (§3.8 RI-3).
  final VoidCallback onNeedsAccount;

  @override
  ConsumerState<JoinInviteScreen> createState() => _JoinInviteScreenState();
}

enum _Join { loading, enterCode, ready, expired, invalid, own, failed, joined }

class _JoinInviteScreenState extends ConsumerState<JoinInviteScreen> {
  final _code = TextEditingController();
  _Join _state = _Join.loading;
  String? _name;
  String? _error;
  int _errorCount = 0;
  bool _busy = false;

  /// The failure can be tried again (offline, too many tries).
  bool _retryable = false;

  String? get _userId => ref.read(homeAuthProvider).currentUser?.id;

  OnboardingStore? _store() {
    final userId = _userId;
    if (userId == null) return null;
    return OnboardingStore(
      ref.read(sharedPreferencesProvider),
      scope: '${OnboardingStore.userScopePrefix}.$userId',
    );
  }

  RelationshipInviteService get _invites =>
      ref.read(invitePartnerServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _show(_Join state, {String? error, bool retryable = false}) {
    if (!mounted) return;
    setState(() {
      _state = state;
      _error = error;
      _retryable = retryable;
      if (error != null) _errorCount++;
    });
    if (error != null && state != _Join.enterCode) {
      SemanticsService.announce(error, Directionality.of(context));
    }
  }

  Future<void> _start() async {
    final code = _store()?.pendingInviteCode;
    if (code == null) return _show(_Join.enterCode);
    await _preview(code);
  }

  Future<void> _drop() async => _store()?.clearPendingInviteCode();

  Future<void> _preview(String code) async {
    final loc = AppLocalizations.of(context)!;
    _show(_Join.loading);
    final InvitePreview preview;
    try {
      preview = await _invites.previewInvite(code);
    } on RelationshipInviteException catch (error) {
      return _show(
        _Join.failed,
        error:
            error.kind == InviteRefusalKind.tryLater
                ? loc.flow_joinTryLater
                : loc.flow_inviteCodeOffline,
        retryable: true,
      );
    }
    if (!mounted) return;
    _name = preview.inviterFirstName;
    switch (preview.state) {
      case InvitePreviewState.ok:
        return _show(_Join.ready);
      case InvitePreviewState.expired:
        await _drop();
        return _show(_Join.expired);
      case InvitePreviewState.invalid:
        await _drop();
        return _show(_Join.invalid);
      case InvitePreviewState.own:
        await _drop();
        return _show(_Join.own);
      case InvitePreviewState.linked:
        await _drop();
        widget.onJoined();
    }
  }

  Future<void> _submitCode() async {
    final loc = AppLocalizations.of(context)!;
    final code = normalizeInviteCode(_code.text);
    if (code == null) {
      return _show(_Join.enterCode, error: loc.flow_inviteCodeError);
    }
    await _store()?.storePendingInviteCode(code);
    if (!mounted) return;
    await _preview(code);
  }

  Future<void> _join() async {
    if (_busy) return;
    final loc = AppLocalizations.of(context)!;
    final store = _store();
    final code = store?.pendingInviteCode;
    final userId = _userId;
    if (store == null || code == null || userId == null) {
      return _show(_Join.enterCode);
    }
    final home = ref.read(homeStateProvider(userId).notifier);
    final prefs = ref.read(sharedPreferencesProvider);
    setState(() => _busy = true);
    try {
      final joined = await _invites.acceptInvite(code);
      await store.clearPendingInviteCode();
      // Seen here: R4 is this screen's last step, so the home's R4 doesn't
      // show it again on this phone.
      await InviteDeviceStore(
        prefs,
        userId: userId,
      ).markLinkedMomentSeen(joined.relationshipId);
      unawaited(home.refresh());
      _show(_Join.joined);
    } on RelationshipInviteException catch (error) {
      if (error.signUpIncomplete ||
          error.kind == InviteRefusalKind.ageRequired) {
        widget.onNeedsAccount();
        return;
      }
      if (!error.retryable) await store.clearPendingInviteCode();
      switch (error.kind) {
        case InviteRefusalKind.expired:
          return _show(_Join.expired);
        case InviteRefusalKind.own:
          return _show(_Join.own);
        case InviteRefusalKind.invalid || InviteRefusalKind.alreadyAccepted:
          return _show(_Join.invalid);
        default:
          return _show(
            _Join.failed,
            error:
                error.alreadyInRelationship
                    ? loc.flow_joinAlreadyIn
                    : error.retryable
                    ? loc.flow_inviteCodeOffline
                    : loc.flow_joinNotPossible,
            retryable: error.retryable,
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave(VoidCallback then) async {
    await _drop();
    then();
  }

  Future<void> _askOnWhatsApp() async {
    final loc = AppLocalizations.of(context)!;
    final name = _name;
    final text =
        name == null
            ? loc.flow_joinExpiredMessageUnnamed
            : loc.flow_joinExpiredMessage(name);
    final actions = ref.read(inviteShareActionsProvider);
    if (!await actions.openWhatsApp(text)) await actions.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = _name;
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    Widget words(String text) => Text(text, style: bodyStyle);
    final otherWay = FlowTextLink(
      label: loc.flow_joinOtherWay,
      onPressed: () {
        final userId = _userId;
        final firstChoice =
            userId == null || ref.read(homeStateProvider(userId)).path == null;
        _leave(() => widget.onChooseAnotherWay(firstChoice));
      },
    );

    switch (_state) {
      case _Join.loading:
        return FlowFrame(
          title: loc.flow_inviteCodeTitle,
          body: Center(
            child: CircularProgressIndicator(
              semanticsLabel: loc.flow_joinChecking,
            ),
          ),
        );
      case _Join.enterCode:
        return FlowFrame(
          title: loc.flow_inviteCodeTitle,
          onBack: () => _leave(widget.onDone),
          body: FlowTextField(
            controller: _code,
            label: loc.flow_inviteCodeLabel,
            errorText: _error,
            errorCount: _errorCount,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            inputFormatters: [LengthLimitingTextInputFormatter(12)],
            autofocus: true,
            onSubmitted: (_) => _submitCode(),
          ),
          actions: [
            FlowPrimaryButton(label: loc.flow_continue, onPressed: _submitCode),
          ],
        );
      case _Join.ready:
        return FlowFrame(
          title:
              name == null ? loc.flow_ri3TitleUnnamed : loc.flow_ri3Title(name),
          body: words(
            name == null ? loc.flow_ri3BodyUnnamed : loc.flow_ri3Body(name),
          ),
          actions: [
            FlowPrimaryButton(
              label:
                  name == null
                      ? loc.flow_ri3ButtonUnnamed
                      : loc.flow_ri3Button(name),
              busy: _busy,
              onPressed: _join,
            ),
            FlowSecondaryButton(
              label: loc.flow_notNow,
              onPressed: _busy ? null : () => _leave(widget.onDone),
            ),
            otherWay,
          ],
        );
      // Never animated (§2.2): the expired and refusal states are plain.
      case _Join.expired:
        return FlowFrame(
          title: loc.flow_joinExpiredTitle,
          body: words(
            name == null
                ? loc.flow_joinExpiredUnnamed
                : loc.flow_joinExpired(name),
          ),
          actions: [
            FlowPrimaryButton(
              label:
                  name == null
                      ? loc.flow_joinAskWhatsAppUnnamed
                      : loc.flow_joinAskWhatsApp(name),
              onPressed: _askOnWhatsApp,
            ),
            FlowSecondaryButton(
              label: loc.flow_notNow,
              onPressed: () => _leave(widget.onDone),
            ),
          ],
        );
      case _Join.invalid:
      case _Join.own:
        return FlowFrame(
          title: loc.flow_inviteCodeTitle,
          body: FlowErrorLine(
            text: _state == _Join.own ? loc.flow_joinOwn : loc.flow_joinInvalid,
            style: bodyStyle,
            liveRegion: true,
          ),
          actions: [
            FlowPrimaryButton(
              label: loc.flow_joinEnterAgain,
              onPressed: () {
                _code.clear();
                _show(_Join.enterCode);
              },
            ),
            FlowSecondaryButton(
              label: loc.flow_notNow,
              onPressed: () => _leave(widget.onDone),
            ),
          ],
        );
      case _Join.failed:
        return FlowFrame(
          title: loc.flow_inviteCodeTitle,
          body: FlowErrorLine(
            key: ValueKey(_errorCount),
            text: _error ?? loc.flow_inviteCodeOffline,
            style: bodyStyle,
            liveRegion: true,
          ),
          actions: [
            if (_retryable)
              FlowPrimaryButton(label: loc.flow_tryAgain, onPressed: _start),
            FlowSecondaryButton(
              label: loc.flow_notNow,
              onPressed: () => _leave(widget.onDone),
            ),
          ],
        );
      case _Join.joined:
        return LinkedMoment(
          partnerFirstName: name,
          onContinue: widget.onJoined,
        );
    }
  }
}
```

In `lib/app/routing/app_router.dart` (after Task 5's constant; only these two places, no Games route moves):

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
```

with:

```dart
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/presentation/screens/join_invite_screen.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
```

Edit 2 of 2. Replace exactly:

```dart
              onDone:
                  () => GoRouter.of(context).go(homeLocation(tab: AppTab.chat)),
            ),
      ),
```

with:

```dart
              onDone:
                  () => GoRouter.of(context).go(homeLocation(tab: AppTab.chat)),
            ),
      ),
      // Spec 1 W4b (§3.8 RI-3, D9): the one place a stored invite is
      // accepted, after an explicit "Join {name}"; signed-in only.
      GoRoute(
        path: RouteNames.joinInvite,
        name: 'joinInvite',
        redirect:
            (context, state) =>
                routingNotifier.isSignedIn ? null : RouteNames.login,
        builder:
            (context, state) => JoinInviteScreen(
              onDone: () => GoRouter.of(context).go(RouteNames.home),
              onJoined:
                  () => GoRouter.of(context).go(homeLocation(tab: AppTab.chat)),
              onChooseAnotherWay:
                  (firstChoice) => GoRouter.of(context).go(
                    firstChoice
                        ? RouteNames.onboarding
                        : RouteNames.howYouUseAttune,
                  ),
              onNeedsAccount:
                  () => GoRouter.of(context).go(RouteNames.onboarding),
            ),
      ),
```

- [ ] **Step 5: No accept anywhere else under `flow_couples_v2` (D9)**

In `lib/features/onboarding/presentation/screens/onboarding_gate_v2.dart`:

Edit 1 of 5. Replace exactly:

```dart
  HomeStateService get _service => ref.read(homeStateServiceProvider);

  @override
  void initState() {
```

with:

```dart
  HomeStateService get _service => ref.read(homeStateServiceProvider);

  /// flow_couples_v2, effective: a stored invite is joined only from RI-3
  /// (`/join-invite`), after an explicit tap (D9, W4b).
  bool get _couplesV2 => ref.read(flowCouplesV2Provider);

  @override
  void initState() {
```

Edit 2 of 5. Replace exactly:

```dart
      if (_relationshipChosen) return _show(_Step.invitePartner);
      if (_joined) return _show(_Step.joined);
      await _go(RouteNames.home);
      return;
```

with:

```dart
      if (_relationshipChosen) return _show(_Step.invitePartner);
      if (_joined) return _show(_Step.joined);
      if (_couplesV2 &&
          store.pendingInviteCode != null &&
          !_accountPending(userId)) {
        await _go(RouteNames.joinInvite);
        return;
      }
      await _go(RouteNames.home);
      return;
```

Edit 3 of 5. Replace exactly:

```dart
            store.pendingInviteCode != null &&
            !_accountPending(userId)) {
          return _acceptStoredInvite(userId);
        }
```

with:

```dart
            store.pendingInviteCode != null &&
            !_accountPending(userId)) {
          if (_couplesV2) {
            await _go(RouteNames.joinInvite);
            return;
          }
          return _acceptStoredInvite(userId);
        }
```

Edit 4 of 5. Replace exactly:

```dart
      return _queueFirstChoice(userId, AppPath.relationship);
    }
    _inviteTried = false;
    await _acceptStoredInvite(userId, typed: true);
```

with:

```dart
      return _queueFirstChoice(userId, AppPath.relationship);
    }
    if (_couplesV2) {
      await _go(RouteNames.joinInvite);
      return;
    }
    _inviteTried = false;
    await _acceptStoredInvite(userId, typed: true);
```

Edit 5 of 5. Replace exactly:

```dart
      _Step.invitePartner => InvitePartnerScreen(
        onDone: () => unawaited(_go(RouteNames.home)),
      ),
      // Today's "You are connected" card, in the deck it was built for.
```

with:

```dart
      _Step.invitePartner => InvitePartnerScreen(
        onDone: () => unawaited(_go(RouteNames.home)),
        onAlreadyInvited: () => unawaited(_go(RouteNames.joinInvite)),
      ),
      // Today's "You are connected" card, in the deck it was built for.
```

In `lib/home/home_screen.dart` (`_reconcileGateData`'s v2 branch and one new method; the latch block is not touched):

Edit 1 of 2. Replace exactly:

```dart
          store.pendingSignUp == null &&
          ref.read(homeStateProvider(userId)).isComplete) {
        await _acceptPendingInvite(store);
        await _refreshHomeState();
```

with:

```dart
          store.pendingSignUp == null &&
          ref.read(homeStateProvider(userId)).isComplete) {
        // Spec 1 W4b (D9): under flow_couples_v2 a stored code is joined
        // only from RI-3, after an explicit tap; never here.
        if (ref.read(flowCouplesV2Provider)) {
          await _openJoinInvite();
          return;
        }
        await _acceptPendingInvite(store);
        await _refreshHomeState();
```

Edit 2 of 2. Replace exactly:

```dart
      });
    }
  }
```

with:

```dart
      });
    }
  }

  /// RI-3 for a stored code, once per HomeScreen (flow_couples_v2), while
  /// home is the screen on top.
  bool _joinOffered = false;

  Future<void> _openJoinInvite() async {
    if (_joinOffered || !mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _joinOffered = true;
    unawaited(GoRouter.of(context).push(RouteNames.joinInvite));
  }
```

- [ ] **Step 6: Run the tests; make the goldens and look at them**

```bash
flutter test --no-pub --update-goldens test/features/relationships/w4/join_invite_screen_test.dart 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter test --no-pub test/features/relationships/w4/ test/features/onboarding/w4/ test/features/onboarding/w3/ test/home/ test/architecture/games_untouched_test.dart test/app/routing/ 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
awk '/if \(isAuthenticated && !_gateData.isComplete\) \{/,/_redirectingToOnboarding = false;/' lib/home/home_screen.dart | diff .superpowers/sdd/2026-11-02-spec1-w4/latch-before.txt - && echo "latch unchanged"
```

Expected: `All tests passed!` twice; `latch unchanged`. Open `w4_ri3.scale1.0.png`, `w4_ri4.scale2.0.png` and `w4_r4.scale1.0.png`: one title, one body line, the actions at the bottom; R4 shows two avatars, the line and "Get notified when Yaw messages you" with "Turn on".

- [ ] **Step 7: Mutation checks (§7.4 "Accept before RI-3 in OnboardingGate"; the HomeScreen accept)**

```bash
D=.superpowers/sdd/2026-11-02-spec1-w4
cp lib/features/onboarding/presentation/screens/onboarding_gate_v2.dart $D/gate.orig
perl -0pi -e 's/          if \(_couplesV2\) \{\n            await _go\(RouteNames\.joinInvite\);\n            return;\n          \}\n          return _acceptStoredInvite\(userId\);/          return _acceptStoredInvite(userId);/' lib/features/onboarding/presentation/screens/onboarding_gate_v2.dart
flutter test --no-pub test/features/onboarding/w4/join_routing_test.dart --plain-name "A6 owed" 2>&1 | tr '\r' '\n' | grep -E 'Expected:|Some tests failed' | head -2
cp $D/gate.orig lib/features/onboarding/presentation/screens/onboarding_gate_v2.dart
cp lib/home/home_screen.dart $D/home.orig
perl -0pi -e 's/        if \(ref\.read\(flowCouplesV2Provider\)\) \{\n          await _openJoinInvite\(\);\n          return;\n        \}\n//' lib/home/home_screen.dart
flutter test --no-pub test/features/onboarding/w4/join_routing_test.dart --plain-name "HomeScreen, couples v2" 2>&1 | tr '\r' '\n' | grep -E 'Expected:|Some tests failed' | head -2
cp $D/home.orig lib/home/home_screen.dart
rm $D/gate.orig $D/home.orig
flutter test --no-pub test/features/onboarding/w4/join_routing_test.dart 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
```

Expected: the gate mutant → `Expected: '/join-invite'` and `Some tests failed.`; the HomeScreen mutant → `Expected: empty` (`invites.accepted` was `['K7P2QM']`) and `Some tests failed.`; then `All tests passed!`.

### Task 7: R3 under `flow_couples_v2` and the inviter's R4 (W4b; §3.8 R2, R3, R4, Q7, P-13, P-14, P-16, P-19; carried items 3 and 5)

**Files:**
- Create: `lib/features/relationships/presentation/widgets/linked_moment_gate.dart`
- Replace: `lib/home/widgets/home_tab_two.dart`
- Modify: `lib/home/home_seams.dart` (the Tab 2 seam passes `couplesV2`)
- Modify: `lib/features/onboarding/presentation/widgets/pending_invite_guide.dart` (`v2`, `partnerName`, `onSendNewInvite`)
- Modify: `lib/features/relationships/presentation/screens/relationship_space_screen.dart`
- Modify: `lib/i10n/app_en.arb` (+ regenerate)
- Test: `test/features/relationships/w4/relationship_space_v2_test.dart`

**Interfaces:**
- Consumes: Tasks 3–6 (`inviteErrorCopy`, `InviteDeviceStore`, `LinkedMoment`, `RouteNames.invitePartner`); W3's `HomeTabTwo` callers (`homeTabTwoBuilderProvider`), `flowCouplesV2Provider`, `metricCounterProvider`.
- Produces: `LinkedMomentGate({required relationshipId, required child, partnerFirstName})`; `HomeTabTwo({…, bool couplesV2 = false})`; `PendingInviteGuide({…, bool v2 = false, String? partnerName, VoidCallback? onSendNewInvite})`; ARB keys `flow_guide*` (11), `flow_day30`, `flow_day30Unnamed`, `flow_day30Dismiss`, `flow_r3SendAgain`.

- [ ] **Step 1: The copy**

Create `.superpowers/sdd/2026-11-02-spec1-w4/arb_task7.txt` with exactly:

```text
  "flow_guideWaitLine": "We'll suggest a private reflection space if this takes a little while.",
  "flow_guideReflectTitle": "A private space while you wait",
  "flow_guideReflectBody": "Your reflections stay private to you.",
  "flow_guideOpenJournal": "Open your journal",
  "flow_guideWeekTitle": "It's been a week",
  "flow_guideWeekBody": "Your invite to {name} has run its week. What would you like to do?",
  "@flow_guideWeekBody": {"placeholders": {"name": {"type": "String"}}},
  "flow_guideWeekBodyUnnamed": "Your invite to your partner has run its week. What would you like to do?",
  "flow_guideKeepWaiting": "Keep waiting",
  "flow_guideSendNew": "Send a new invite",
  "flow_guideSendNewHelper": "Send it to the same number or a different one.",
  "flow_guideOnMyOwn": "Use Attune on my own for now",
  "flow_day30": "Want to send {name} a new invite?",
  "@flow_day30": {"placeholders": {"name": {"type": "String"}}},
  "flow_day30Unnamed": "Want to send your partner a new invite?",
  "flow_day30Dismiss": "Dismiss",
  "flow_r3SendAgain": "Send again"
```

```bash
D=.superpowers/sdd/2026-11-02-spec1-w4
grep -cP '[^\x00-\x7F]' $D/arb_task7.txt
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_task7.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null; echo "gen exit=$?"
```

Expected: `0`; `added 15 keys`; `gen exit=0`.

- [ ] **Step 2: Write the failing test**

Create `test/features/relationships/w4/relationship_space_v2_test.dart` with exactly:

```dart
// Spec 1 W4b (§3.8 R3, R4; Q7): under flow_couples_v2 the space names the
// partner from R1 (this phone only); "Send again" and "Invite your partner"
// open R1's share step; day 7 offers "Send a new invite" (old code gone, a
// new one made, counted); day 30 asks once; refusals are the app's words.
// Tab 2's first linked view on a phone is "You're both here".
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/widgets/pending_invite_guide.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/screens/relationship_space_screen.dart';
import 'package:attune/features/relationships/presentation/widgets/linked_moment_gate.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/home/widgets/home_tab_two.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_invites.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

const _uid = 'u-r3v2';

final _pending = snapshotOf(homeJson(path: 'relationship', link: 'pending'));

Future<(FlowHarness, FakeInvites)> _pump(
  WidgetTester tester, {
  FakeInvites? invites,
  HomeSnapshot? home,
  bool couplesV2 = true,
  Map<String, Object> prefsValues = const {},
}) async {
  await tester.pumpWidget(const SizedBox());
  final fake = invites ?? FakeInvites();
  final h = await pumpFlowScreen(
    tester,
    () => RelationshipSpaceScreen(home: home ?? _pending),
    size: const Size(390, 2600),
    prefsValues: prefsValues,
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(
          FakeHomeStateGateway(state: homeJson(path: 'relationship')),
        ),
      ),
      invitePartnerServiceProvider.overrideWithValue(fake),
      relationshipLifecycleProvider.overrideWith((ref) async => null),
      pushAskerProvider.overrideWithValue(FakePushAsker()),
      flowCouplesV2Provider.overrideWithValue(couplesV2),
    ],
  );
  return (h, fake);
}

void main() {
  testWidgets('the partner named from R1, on this phone only', (tester) async {
    await _pump(
      tester,
      prefsValues: {'attune.flow.$_uid.partner_first_name': 'Ama'},
    );
    expect(find.text('Get a heads-up when Ama joins'), findsOneWidget);
    expect(
      find.text(
        'When your partner joins, read receipts start off. You and Ama can '
        'each turn them on later.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('"Send again" opens R1\'s share step', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Send again'));
    await tester.pumpAndSettle();
    expect(find.text('at /invite-partner'), findsOneWidget);
  });

  testWidgets('day 7: keep waiting, send a new invite, on my own', (
    tester,
  ) async {
    final invites = FakeInvites()..age = const Duration(days: 7, hours: 1);
    final (h, _) = await _pump(
      tester,
      invites: invites,
      prefsValues: {'attune.flow.$_uid.partner_first_name': 'Ama'},
    );
    expect(find.text("It's been a week"), findsOneWidget);
    expect(
      find.text(
        'Your invite to Ama has run its week. What would you like to do?',
      ),
      findsOneWidget,
    );
    expect(find.text('Keep waiting'), findsOneWidget);
    expect(
      find.text('Send it to the same number or a different one.'),
      findsOneWidget,
    );
    expect(find.text('Use Attune on my own for now'), findsOneWidget);
    expect(find.text('Invite someone else'), findsNothing);
    final before = invites.creates;
    await tester.tap(
      find.descendant(
        of: find.byType(PendingInviteGuide),
        matching: find.text('Send a new invite'),
      ),
    );
    await tester.pumpAndSettle();
    expect(invites.withdrawals, 1);
    expect(invites.creates, before + 1);
    expect(h.metrics, contains('invite_new_day7'));
    expect(find.text('at /invite-partner'), findsOneWidget);
  });

  testWidgets('day 30: asked once, counted; never again on this phone', (
    tester,
  ) async {
    final invites = FakeInvites()..age = const Duration(days: 31);
    final (h, _) = await _pump(tester, invites: invites);
    expect(
      find.text('Want to send your partner a new invite?'),
      findsOneWidget,
    );
    expect(h.metrics, contains('invite_day30_shown'));
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Want to send your partner a new invite?'), findsNothing);
    final (_, _) = await _pump(
      tester,
      invites: FakeInvites()..age = const Duration(days: 32),
      prefsValues: {'attune.flow.$_uid.invite_day30': true},
    );
    expect(find.text('Want to send your partner a new invite?'), findsNothing);
  });

  testWidgets('a refusal is the app\'s words', (tester) async {
    await _pump(
      tester,
      invites: FakeInvites(
        createError: const RelationshipInviteException(
          'You already have the maximum number of pending invites',
          kind: InviteRefusalKind.cap,
        ),
      ),
    );
    expect(
      find.text(
        'You already have 3 invites waiting. Cancel one before you send another.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('maximum number'), findsNothing);
  });

  testWidgets('flag off: today\'s guide, no "Send again"', (tester) async {
    await _pump(
      tester,
      couplesV2: false,
      invites: FakeInvites()..age = const Duration(days: 8),
    );
    expect(find.text('Invite someone else'), findsOneWidget);
    expect(find.text('Send again'), findsNothing);
  });

  testWidgets('Tab 2, linked, first time on this phone: R4, then the chat', (
    tester,
  ) async {
    final home = snapshotOf(
      homeJson(
        path: 'relationship',
        link: 'linked',
        relationshipId: 'r1',
        partnerFirstName: 'Ama',
      ),
    );
    final h = await pumpFlowScreen(
      tester,
      () => HomeTabTwo(
        tab: AppTab.chat,
        home: home,
        onInviteSent: () {},
        couplesV2: true,
      ),
      prefsValues: {'attune.flow.$_uid.partner_first_name': 'Ama'},
      overrides: [
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
      ],
    );
    expect(find.byType(LinkedMomentGate), findsOneWidget);
    expect(find.text("You're both here"), findsOneWidget);
    expect(find.text('Get notified when Ama messages you'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(h.prefs.getBool('attune.linked_moment:$_uid:r1'), isTrue);
    expect(
      h.prefs.containsKey('attune.flow.$_uid.partner_first_name'),
      isFalse,
    );
    expect(find.text("You're both here"), findsNothing);
  });

  testWidgets('Tab 2, linked, already seen or flag off: no R4', (tester) async {
    final home = snapshotOf(
      homeJson(path: 'relationship', link: 'linked', relationshipId: 'r1'),
    );
    final seen = HomeTabTwo(
      tab: AppTab.chat,
      home: home,
      onInviteSent: () {},
      couplesV2: false,
    );
    expect(seen.couplesV2, isFalse);
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          expect(seen.build(context), isNot(isA<LinkedMomentGate>()));
          return const SizedBox();
        },
      ),
    );
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test --no-pub test/features/relationships/w4/relationship_space_v2_test.dart 2>&1 | grep -E "Error:" | head -3`
Expected: compile errors: `linked_moment_gate.dart` not found; `couplesV2` isn't a parameter of `HomeTabTwo`.

- [ ] **Step 4: The inviter's R4 in Tab 2**

Create `lib/features/relationships/presentation/widgets/linked_moment_gate.dart` with exactly:

```dart
import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:attune/features/relationships/presentation/widgets/linked_moment.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// R4 on the inviter's phone (Spec 1 §3.8, W4b): the first time this phone
/// sees [relationshipId] linked, "You're both here" comes before [child]
/// (the chat), on the next open if the phone wasn't open at link time.
/// Closing it records it for this relationship on this phone and deletes
/// the partner name R1 kept (§4.8: until linking).
class LinkedMomentGate extends ConsumerStatefulWidget {
  const LinkedMomentGate({
    super.key,
    required this.relationshipId,
    required this.child,
    this.partnerFirstName,
  });

  final String relationshipId;
  final String? partnerFirstName;
  final Widget child;

  @override
  ConsumerState<LinkedMomentGate> createState() => _LinkedMomentGateState();
}

class _LinkedMomentGateState extends ConsumerState<LinkedMomentGate> {
  /// The relationship whose R4 was closed in this visit.
  String? _closed;

  InviteDeviceStore? _device() {
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId == null) return null;
    try {
      return InviteDeviceStore(
        ref.read(sharedPreferencesProvider),
        userId: userId,
      );
    } catch (_) {
      return null;
    }
  }

  void _close() {
    final device = _device();
    if (device != null) {
      unawaited(device.markLinkedMomentSeen(widget.relationshipId));
      unawaited(device.clearPartnerFirstName());
    }
    setState(() => _closed = widget.relationshipId);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.relationshipId;
    if (_closed == id) return widget.child;
    final device = _device();
    if (device == null || device.linkedMomentSeen(id)) return widget.child;
    return LinkedMoment(
      partnerFirstName: widget.partnerFirstName,
      onContinue: _close,
    );
  }
}
```

Replace `lib/home/widgets/home_tab_two.dart` with exactly:

```dart
import 'package:attune/features/chat/presentation/widgets/authenticated_chat_workspace.dart';
import 'package:attune/features/me/presentation/screens/me_home_screen.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/relationships/presentation/screens/relationship_space_screen.dart';
import 'package:attune/features/relationships/presentation/widgets/linked_moment_gate.dart';
import 'package:flutter/widgets.dart';

/// Tab 2 under flow_paths_v2 (Spec 1 §3.11): a linked couple gets the chat
/// (ChatHomeScreen, unchanged); the rest of the Relationship path gets its
/// space (R3, never Dating); Dating and Just for me get Me.
///
/// Spec 1 W4b (§3.8 R4): with [couplesV2], the chat waits behind "You're
/// both here" the first time this phone sees the relationship linked
/// (LinkedMomentGate).
class HomeTabTwo extends StatelessWidget {
  const HomeTabTwo({
    super.key,
    required this.tab,
    required this.home,
    required this.onInviteSent,
    this.couplesV2 = false,
  });

  final AppTab tab;
  final HomeSnapshot home;
  final VoidCallback onInviteSent;

  /// flow_couples_v2, effective (read by the seam when it builds Tab 2).
  final bool couplesV2;

  @override
  Widget build(BuildContext context) {
    if (tab == AppTab.me) return MeHomeScreen(home: home);
    if (home.link == LinkState.linked) {
      final chat = AuthenticatedChatWorkspace(
        isCouples: true,
        isPendingCouples: false,
        onInviteSent: onInviteSent,
      );
      final relationshipId = home.linkDetail.relationshipId;
      if (!couplesV2 || relationshipId == null) return chat;
      return LinkedMomentGate(
        relationshipId: relationshipId,
        partnerFirstName: home.linkDetail.partnerFirstName,
        child: chat,
      );
    }
    return RelationshipSpaceScreen(home: home);
  }
}
```

In `lib/home/home_seams.dart`:

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/opinions/presentation/screen/opinions_tab.dart';
```

with:

```dart
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/opinions/presentation/screen/opinions_tab.dart';
```

Edit 2 of 2. Replace exactly:

```dart
    Widget Function(AppTab tab, HomeSnapshot home, VoidCallback onInviteSent);

/// Tab 2 under flow_paths_v2, replaceable in the shell's tests.
final homeTabTwoBuilderProvider = Provider<HomeTabTwoBuilder>(
  (ref) =>
      (tab, home, onInviteSent) =>
          HomeTabTwo(tab: tab, home: home, onInviteSent: onInviteSent),
);
```

with:

```dart
    Widget Function(AppTab tab, HomeSnapshot home, VoidCallback onInviteSent);

/// Tab 2 under flow_paths_v2, replaceable in the shell's tests. W4b: R4
/// under flow_couples_v2, read when Tab 2 is built.
final homeTabTwoBuilderProvider = Provider<HomeTabTwoBuilder>(
  (ref) =>
      (tab, home, onInviteSent) => HomeTabTwo(
        tab: tab,
        home: home,
        onInviteSent: onInviteSent,
        couplesV2: ref.read(flowCouplesV2Provider),
      ),
);
```

- [ ] **Step 5: The guide's v2 words and day 7**

In `lib/features/onboarding/presentation/widgets/pending_invite_guide.dart`:

Edit 1 of 4. Replace exactly:

```dart
//                (and Continue, where there is a next step)
// Shared by the onboarding waiting step and the locked Chat screen.

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_info_tile.dart';
```

with:

```dart
//                (and Continue, where there is a next step)
// Shared by the onboarding waiting step and the locked Chat screen.
//
// Spec 1 W4b (§3.8 R3, Q7): with [v2] (R3 under flow_couples_v2) the words
// are the spec's, the partner is named, and day 7 offers "Send a new
// invite" (withdraws the old code, mints a new one, opens the share step)
// instead of "Invite someone else". Without it, nothing changes.

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_info_tile.dart';
```

Edit 2 of 4. Replace exactly:

```dart
    this.onContinue,
    this.busy = false,
  });
```

with:

```dart
    this.onContinue,
    this.busy = false,
    this.v2 = false,
    this.partnerName,
    this.onSendNewInvite,
  });
```

Edit 3 of 4. Replace exactly:

```dart
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final waited = age ?? Duration.zero;
```

with:

```dart
  final bool busy;

  /// R3's words and day 7 (Spec 1 W4b).
  final bool v2;

  /// The invited partner's first name (R1's, this phone only), or null.
  final String? partnerName;

  /// Day 7's "Send a new invite" (v2 only).
  final VoidCallback? onSendNewInvite;

  @override
  Widget build(BuildContext context) {
    if (v2) return _buildV2(context);
    final colorScheme = Theme.of(context).colorScheme;
    final waited = age ?? Duration.zero;
```

Edit 4 of 4. Replace exactly:

```dart
    );
  }
}
```

with:

```dart
    );
  }

  Widget _buildV2(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final text = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final title = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final waited = age ?? Duration.zero;
    final name = partnerName?.trim();
    final named = name != null && name.isNotEmpty;

    if (waited >= pivotAfter) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(loc.flow_guideWeekTitle, style: title),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            named
                ? loc.flow_guideWeekBody(name)
                : loc.flow_guideWeekBodyUnnamed,
            style: text,
          ),
          const SizedBox(height: Spacing.smMd),
          FlowSecondaryButton(
            label: loc.flow_guideKeepWaiting,
            onPressed: busy ? null : onKeepWaiting,
          ),
          const SizedBox(height: Spacing.sm),
          FlowPrimaryButton(
            label: loc.flow_guideSendNew,
            busy: busy,
            onPressed: onSendNewInvite ?? onInviteSomeoneElse,
          ),
          const SizedBox(height: Spacing.xs),
          Text(loc.flow_guideSendNewHelper, style: text),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            label: loc.flow_guideOnMyOwn,
            onPressed: busy ? null : onUseAlone,
          ),
        ],
      );
    }

    if (waited >= reflectAfter) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(loc.flow_guideReflectTitle, style: title),
          ),
          const SizedBox(height: Spacing.xs),
          Text(loc.flow_guideReflectBody, style: text),
          const SizedBox(height: Spacing.smMd),
          FlowSecondaryButton(
            label: loc.flow_guideOpenJournal,
            onPressed: onReflect,
          ),
        ],
      );
    }

    return Text(loc.flow_guideWaitLine, style: text);
  }
}
```

- [ ] **Step 6: R3 under `flow_couples_v2`**

In `lib/features/relationships/presentation/screens/relationship_space_screen.dart`:

Edit 1 of 14. Replace exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notifications/presentation/widgets/push_ask_row.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
```

with:

```dart
import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/notifications/presentation/widgets/push_ask_row.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
```

Edit 2 of 14. Replace exactly:

```dart
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/pending_invite_guide.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/widgets/relationship_lifecycle_card.dart';
import 'package:attune/home/home_seams.dart';
```

with:

```dart
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/pending_invite_guide.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_error_copy.dart';
import 'package:attune/features/relationships/presentation/widgets/relationship_lifecycle_card.dart';
import 'package:attune/home/home_seams.dart';
```

Edit 3 of 14. Replace exactly:

```dart
/// After the window: one "More ways" row. Never anything about Dating, in
/// any state (§3.8, review R-5).
class RelationshipSpaceScreen extends ConsumerStatefulWidget {
  const RelationshipSpaceScreen({super.key, required this.home});
```

with:

```dart
/// After the window: one "More ways" row. Never anything about Dating, in
/// any state (§3.8, review R-5).
///
/// Spec 1 W4b, under flow_couples_v2: the partner is named from R1's
/// first name (this phone only); "Invite your partner" and "Send again"
/// open R1's share step; day 7 offers "Send a new invite"; day 30 asks
/// once; every invite error is the app's own words.
class RelationshipSpaceScreen extends ConsumerStatefulWidget {
  const RelationshipSpaceScreen({super.key, required this.home});
```

Edit 4 of 14. Replace exactly:

```dart
  LinkState get _link => widget.home.link;

  /// The invited partner's first name, if the server gave one.
  String? get _partnerName {
    final name = widget.home.linkDetail.partnerFirstName?.trim();
    return name == null || name.isEmpty ? null : name;
  }
```

with:

```dart
  LinkState get _link => widget.home.link;

  /// Day 30's line (§3.8 R3): shown in this visit, once per phone.
  bool _day30 = false;

  bool get _couplesV2 => ref.read(flowCouplesV2Provider);

  InviteDeviceStore? get _device {
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId == null) return null;
    try {
      return InviteDeviceStore(
        ref.read(sharedPreferencesProvider),
        userId: userId,
      );
    } catch (_) {
      return null;
    }
  }

  /// The invited partner's first name: the server's once linked, else
  /// (flow_couples_v2) the one typed at R1 on this phone.
  String? get _partnerName {
    final name = widget.home.linkDetail.partnerFirstName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return _couplesV2 ? _device?.partnerFirstName : null;
  }
```

Edit 5 of 14. Replace exactly:

```dart
    final invites = _invites;
    final refreshHome = _homeRefresher();
    setState(() {
      _busy = true;
```

with:

```dart
    final invites = _invites;
    final refreshHome = _homeRefresher();
    final device = _couplesV2 ? _device : null;
    setState(() {
      _busy = true;
```

Edit 6 of 14. Replace exactly:

```dart
      final age = await invites.inviteAge();
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _age = age;
      });
    } on RelationshipInviteException catch (error) {
```

with:

```dart
      final age = await invites.inviteAge();
      if (!mounted) return;
      final showDay30 =
          device != null &&
          age != null &&
          age >= const Duration(days: 30) &&
          !device.day30Done;
      if (showDay30) {
        ref.read(metricCounterProvider).bump(ClientMetricKey.inviteDay30Shown);
        unawaited(device.markDay30Done());
      }
      setState(() {
        _invite = invite;
        _age = age;
        if (showDay30) _day30 = true;
      });
    } on RelationshipInviteException catch (error) {
```

Edit 7 of 14. Replace exactly:

```dart
        return;
      }
      setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
```

with:

```dart
        return;
      }
      setState(
        () => _error = inviteErrorCopy(AppLocalizations.of(context)!, error),
      );
    } catch (_) {
      if (mounted) {
```

Edit 8 of 14. Replace exactly:

```dart
  Future<void> _inviteNow() async {
    final refreshHome = _homeRefresher();
    await _loadInvite();
    await refreshHome();
  }
```

with:

```dart
  Future<void> _inviteNow() async {
    final refreshHome = _homeRefresher();
    if (_couplesV2) {
      await _openShareStep();
    } else {
      await _loadInvite();
    }
    await refreshHome();
  }

  /// R1's share step (flow_couples_v2): the registers and the code.
  Future<void> _openShareStep() async {
    await context.push(RouteNames.invitePartner);
    if (!mounted) return;
    if (_link == LinkState.pending) await _loadInvite();
  }

  /// Day 7 and day 30's "Send a new invite" (§3.8 R3): the old code stops
  /// working, a new one is made, and the share step opens with it.
  Future<void> _sendNewInvite() async {
    final invites = _invites;
    final refreshHome = _homeRefresher();
    final loc = AppLocalizations.of(context)!;
    final metrics = ref.read(metricCounterProvider);
    setState(() {
      _busy = true;
      _error = null;
      _day30 = false;
    });
    try {
      await invites.withdrawPendingInvites();
      final invite = await invites.createInvite();
      metrics.bump(ClientMetricKey.inviteNewDay7);
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _age = Duration.zero;
      });
    } on RelationshipInviteException catch (error) {
      if (mounted) setState(() => _error = inviteErrorCopy(loc, error));
      return;
    } catch (_) {
      if (mounted) setState(() => _error = loc.flow_inviteErrorTryAgain);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
      await refreshHome();
    }
    if (mounted) await _openShareStep();
  }

  Future<void> _dismissDay30() async {
    setState(() => _day30 = false);
  }
```

Edit 9 of 14. Replace exactly:

```dart
          onRetry: _error == null ? null : () => _loadInvite(),
          onCancel: _cancelInvite,
        ),
        // W3c (§3.8 R2, §2.4): the heads-up ask, while notifications are off.
        PushAskRow(
```

with:

```dart
          onRetry: _error == null ? null : () => _loadInvite(),
          onCancel: _cancelInvite,
          onSendAgain: _couplesV2 ? _openShareStep : null,
        ),
        if (_day30) ...[
          const SizedBox(height: Spacing.md),
          _Day30Card(
            partnerName: _partnerName,
            busy: _busy,
            onSend: _sendNewInvite,
            onDismiss: _dismissDay30,
          ),
        ],
        // W3c (§3.8 R2, §2.4): the heads-up ask, while notifications are off.
        PushAskRow(
```

Edit 10 of 14. Replace exactly:

```dart
          onUseAlone: _onMyOwn,
          onInviteSomeoneElse: () => _loadInvite(forceNew: true),
        ),
        const SizedBox(height: Spacing.md),
```

with:

```dart
          onUseAlone: _onMyOwn,
          onInviteSomeoneElse: () => _loadInvite(forceNew: true),
          v2: _couplesV2,
          partnerName: _partnerName,
          onSendNewInvite: _sendNewInvite,
        ),
        const SizedBox(height: Spacing.md),
```

Edit 11 of 14. Replace exactly:

```dart
    required this.onCancel,
    this.onRetry,
  });
```

with:

```dart
    required this.onCancel,
    this.onRetry,
    this.onSendAgain,
  });
```

Edit 12 of 14. Replace exactly:

```dart
  final bool busy;
  final VoidCallback? onCancel;

  /// Shown when the code couldn't be loaded (review I-1).
```

with:

```dart
  final bool busy;
  final VoidCallback? onCancel;

  /// "Send again" under the card (flow_couples_v2): R1's share step.
  final VoidCallback? onSendAgain;

  /// Shown when the code couldn't be loaded (review I-1).
```

Edit 13 of 14. Replace exactly:

```dart
              ],
            ),
            if (current != null)
              InviteCard(invite: current)
            else if (busy)
              const Padding(
                padding: EdgeInsets.all(Spacing.md),
```

with:

```dart
              ],
            ),
            if (current != null) ...[
              InviteCard(invite: current),
              if (onSendAgain != null)
                FlowPrimaryButton(
                  label: loc.flow_r3SendAgain,
                  onPressed: onSendAgain,
                ),
            ] else if (busy)
              const Padding(
                padding: EdgeInsets.all(Spacing.md),
```

Edit 14 of 14. Replace exactly:

```dart
            ),
          ],
        ),
      ),
    );
  }
}
```

with:

```dart
            ),
          ],
        ),
      ),
    );
  }
}

/// Day 30, once (§3.8 R3): "Want to send {name} a new invite?" with
/// "Send a new invite" and a close button. Codes are never renewed
/// silently.
class _Day30Card extends StatelessWidget {
  const _Day30Card({
    required this.partnerName,
    required this.busy,
    required this.onSend,
    required this.onDismiss,
  });

  final String? partnerName;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = partnerName;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name == null ? loc.flow_day30Unnamed : loc.flow_day30(name),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: loc.flow_day30Dismiss,
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              label: loc.flow_guideSendNew,
              busy: busy,
              onPressed: onSend,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Run the tests**

```bash
flutter test --no-pub test/features/relationships/ test/features/onboarding/couples_waiting_step_test.dart test/home/ 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
```

Expected: `All tests passed!` (W3's R3 tests, `relationship_space_more_test.dart`'s Tab 2 cases and the couples waiting step unchanged).

- [ ] **Step 8: Mutation check (R4 is recorded once)**

```bash
D=.superpowers/sdd/2026-11-02-spec1-w4
cp lib/features/relationships/presentation/widgets/linked_moment_gate.dart $D/gate_r4.orig
perl -0pi -e 's/      unawaited\(device\.markLinkedMomentSeen\(widget\.relationshipId\)\);\n//' lib/features/relationships/presentation/widgets/linked_moment_gate.dart
flutter test --no-pub test/features/relationships/w4/relationship_space_v2_test.dart --plain-name "first time on this phone" 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
cp $D/gate_r4.orig lib/features/relationships/presentation/widgets/linked_moment_gate.dart
rm $D/gate_r4.orig
```

Expected: `Some tests failed.` (`attune.linked_moment:u-r3v2:r1` is not set).

### Task 8: Ask 2 saves as it goes; the Install Referrer; W4b gate and W4 group gate (W4b; §3.8 R5, RI Android, §5.2 `main.dart`/`pubspec.yaml`, §5.8, P-17, P-18)

**Files:**
- Create: `lib/features/onboarding/data/ask2_progress_store.dart`
- Create: `lib/core/platform/install_referrer.dart`
- Modify: `lib/features/onboarding/presentation/screens/ask2_flow.dart`
- Modify: `lib/app/device_wipes.dart` (the `spec1.ask2_progress` entry)
- Modify: `lib/core/services/shared_preferences_service.dart` (the referrer mark is kept)
- Modify: `lib/main.dart` (one read at boot)
- Modify: `pubspec.yaml` (+ `pubspec.lock`)
- Test: `test/features/onboarding/w4/ask2_progress_test.dart`, `test/core/platform/install_referrer_test.dart`

**Interfaces:**
- Consumes: W3's `homeAuthProvider`, `sharedPreferencesProvider`, the registry; W1's `OnboardingStore.storeInviteFromLink`; W2's `normalizeInviteCode`.
- Produces: `Ask2Progress {answers, anchors, isEmpty, firstUnanswered}`; `Ask2ProgressStore(prefs, {userId, relationshipId})` with `read({questionCount, anchorCount})`, `write`, `clear`, statics `prefix`, `keyFor`, `isProgressKey`; wipe entry `spec1.ask2_progress` (sign-out, quick exit); `kInstallReferrerReadKey`, `inviteCodeFromReferrer(String?)`, `readInstallReferrerInvite(prefs, {source, isAndroid}) → Future<String?>`.

- [ ] **Step 1: The package**

In `pubspec.yaml`:

Edit 1 of 1. Replace exactly:

```yaml
  app_links: ^6.0.0
```

with:

```yaml
  app_links: ^6.0.0
  # Spec 1 W4b (§3.8 RI): the Play Install Referrer's invite code. 0.5.0:
  # 0.6.0 needs Dart 3.12.
  play_install_referrer: 0.5.0
```

```bash
flutter pub get 2>&1 | tail -2
grep -n -A6 '^  play_install_referrer:' pubspec.lock | grep -E 'version'
```

Expected: `Changed 1 dependency!` (or `Got dependencies!`); `version: "0.5.0"`.

- [ ] **Step 2: Write the failing tests**

Create `test/features/onboarding/w4/ask2_progress_test.dart` with exactly:

```dart
// Spec 1 W4b (§3.8 R5, §5.8): Ask 2 saves as it goes; reopening resumes at
// the first unanswered item; the progress is wiped at sign-out and on
// quick exit, and never names Dating.
import 'package:attune/app/device_wipes.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/onboarding/data/ask2_progress_store.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/screens/ask2_flow.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/home_harness.dart';

const _uid = 'u-ask2';
const _rel = 'r-ask2';
final _key = Ask2ProgressStore.keyFor(_uid, _rel);

Future<SharedPreferences> _pump(
  WidgetTester tester, [
  Map<String, Object> values = const {},
]) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
      ],
      child: MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => const Ask2Flow(relationshipId: _rel),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  test('the store: shaped to the quiz, empty reads as none', () async {
    SharedPreferences.setMockInitialValues({
      _key: '{"answers":[2,null,"x"],"anchors":["a"]}',
    });
    final prefs = await SharedPreferences.getInstance();
    final store = Ask2ProgressStore(prefs, userId: _uid, relationshipId: _rel);
    final read = store.read(questionCount: 4, anchorCount: 3)!;
    expect(read.answers, [2, null, null, null]);
    expect(read.anchors, ['a', '', '']);
    expect(read.firstUnanswered, 1);
    await store.write(const Ask2Progress(answers: [null], anchors: ['']));
    expect(store.read(questionCount: 1, anchorCount: 1), isNull);
    expect(_key.toLowerCase(), isNot(contains('dating')));
  });

  testWidgets('an answer is saved as it is given', (tester) async {
    final prefs = await _pump(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('3'),
      ),
    );
    await tester.pumpAndSettle();
    final saved = Ask2ProgressStore(
      prefs,
      userId: _uid,
      relationshipId: _rel,
    ).read(questionCount: attachmentQuestions.length, anchorCount: 3);
    expect(saved, isNotNull);
    expect(saved!.answers.first, 3);
  });

  testWidgets('reopening resumes at the first unanswered question', (
    tester,
  ) async {
    final answers = List<int?>.filled(attachmentQuestions.length, null);
    answers[0] = 1;
    answers[1] = 2;
    await _pump(tester, {
      _key:
          '{"answers":${answers.map((a) => a ?? 'null').toList()},"anchors":["","",""]}',
    });
    expect(find.text('A closer look'), findsNothing);
    expect(find.text('Relationship reflection quiz'), findsOneWidget);
    expect(find.textContaining('3 of'), findsWidgets);
  });

  test('wiped at sign-out and on quick exit, for every account', () async {
    SharedPreferences.setMockInitialValues({
      _key: '{}',
      Ask2ProgressStore.keyFor('u2', 'r9'): '{}',
      'attune.flow.$_uid.first_action': 'kept-by-this-entry',
    });
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    final entry = registry.entries.firstWhere(
      (e) => e.id == 'spec1.ask2_progress',
    );
    expect(entry.moments, {WipeMoment.signOut, WipeMoment.quickExit});
    expect(entry.protective, isFalse);
    await entry.run();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where(Ask2ProgressStore.isProgressKey), isEmpty);
    expect(prefs.containsKey('attune.flow.$_uid.first_action'), isTrue);
  });
}
```

Create `test/core/platform/install_referrer_test.dart` with exactly:

```dart
// Spec 1 W4b (§3.8 RI): the Play Install Referrer's invite code is stored
// once per install, like a link opened while signed out; never on iOS;
// never over a code already waiting; never throws.
import 'package:attune/core/platform/install_referrer.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the code in a referrer string', () {
    expect(
      inviteCodeFromReferrer('utm_source=invite&invite_code=k7p2qm'),
      'K7P2QM',
    );
    expect(inviteCodeFromReferrer('invite_code=K7P2QM'), 'K7P2QM');
    expect(
      inviteCodeFromReferrer('utm_source=google-play&utm_medium=organic'),
      isNull,
    );
    expect(inviteCodeFromReferrer('invite_code=NOPE'), isNull);
    expect(inviteCodeFromReferrer(null), isNull);
    expect(inviteCodeFromReferrer('%%%'), isNull);
  });

  test('Android, first launch: stored in the anonymous slot, once', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var reads = 0;
    Future<String?> source() async {
      reads++;
      return 'utm_source=invite&invite_code=K7P2QM';
    }

    expect(
      await readInstallReferrerInvite(prefs, source: source, isAndroid: true),
      'K7P2QM',
    );
    expect(
      OnboardingStore(
        prefs,
        scope: OnboardingStore.anonymousScope,
      ).pendingInviteCode,
      'K7P2QM',
    );
    expect(
      await readInstallReferrerInvite(prefs, source: source, isAndroid: true),
      isNull,
    );
    expect(reads, 1);
    expect(prefs.getBool(kInstallReferrerReadKey), isTrue);
  });

  test('iOS: nothing is read', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var reads = 0;
    expect(
      await readInstallReferrerInvite(
        prefs,
        source: () async {
          reads++;
          return 'invite_code=K7P2QM';
        },
        isAndroid: false,
      ),
      isNull,
    );
    expect(reads, 0);
  });

  test('a link already waiting wins; a failing read never throws', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await OnboardingStore.storeInviteFromLink(prefs, 'LINK22');
    expect(
      await readInstallReferrerInvite(
        prefs,
        source: () async => 'invite_code=K7P2QM',
        isAndroid: true,
      ),
      isNull,
    );
    expect(
      OnboardingStore(
        prefs,
        scope: OnboardingStore.anonymousScope,
      ).pendingInviteCode,
      'LINK22',
    );
    SharedPreferences.setMockInitialValues({});
    final fresh = await SharedPreferences.getInstance();
    expect(
      await readInstallReferrerInvite(
        fresh,
        source: () async => throw StateError('no Play services'),
        isAndroid: true,
      ),
      isNull,
    );
  });

  test(
    'the mark survives the sign-out clear, so the code never comes back',
    () async {
      SharedPreferences.setMockInitialValues({kInstallReferrerReadKey: true});
      final prefs = await SharedPreferences.getInstance();
      await PreferencesService(prefs).clearUserData();
      expect(prefs.getBool(kInstallReferrerReadKey), isTrue);
    },
  );
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test --no-pub test/features/onboarding/w4/ask2_progress_test.dart test/core/platform/install_referrer_test.dart 2>&1 | grep -E "Error:" | head -3`
Expected: compile errors: `ask2_progress_store.dart` and `install_referrer.dart` not found.

- [ ] **Step 4: The store and the referrer**

Create `lib/features/onboarding/data/ask2_progress_store.dart` with exactly:

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Ask 2 so far: one answer per quiz question (null: not yet) and the
/// three anchors as typed.
class Ask2Progress {
  const Ask2Progress({required this.answers, required this.anchors});

  final List<int?> answers;
  final List<String> anchors;

  bool get isEmpty =>
      answers.every((a) => a == null) && anchors.every((a) => a.isEmpty);

  /// The first unanswered question, or null when every one is answered.
  int? get firstUnanswered {
    final index = answers.indexWhere((a) => a == null);
    return index < 0 ? null : index;
  }
}

/// R5 · Ask 2 saves as it goes (Spec 1 §3.8, W4b): each answer and anchor
/// is written to `attune.ask2.<uid>.<relationshipId>` as it is given;
/// cleared on completion, and by the device wipe registry on sign-out and
/// on quick exit (`spec1.ask2_progress`, §5.8). The server write stays at
/// the end (ask2_submission_service.dart).
class Ask2ProgressStore {
  const Ask2ProgressStore(
    this._prefs, {
    required this.userId,
    required this.relationshipId,
  });

  final SharedPreferences _prefs;
  final String userId;
  final String relationshipId;

  static const prefix = 'attune.ask2.';

  static String keyFor(String userId, String relationshipId) =>
      '$prefix$userId.$relationshipId';

  /// Every account's progress on the phone (the wipe's match).
  static bool isProgressKey(String key) => key.startsWith(prefix);

  String get _key => keyFor(userId, relationshipId);

  /// The saved progress, shaped to [questionCount] answers and
  /// [anchorCount] anchors; null when there is none or it can't be read.
  Ask2Progress? read({required int questionCount, required int anchorCount}) {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final answers = json['answers'];
      final anchors = json['anchors'];
      if (answers is! List || anchors is! List) return null;
      final progress = Ask2Progress(
        answers: [
          for (var i = 0; i < questionCount; i++)
            i < answers.length && answers[i] is int ? answers[i] as int : null,
        ],
        anchors: [
          for (var i = 0; i < anchorCount; i++)
            i < anchors.length && anchors[i] is String
                ? anchors[i] as String
                : '',
        ],
      );
      return progress.isEmpty ? null : progress;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Ask2Progress progress) => _prefs.setString(
    _key,
    jsonEncode({'answers': progress.answers, 'anchors': progress.anchors}),
  );

  Future<void> clear() => _prefs.remove(_key);
}
```

Create `lib/core/platform/install_referrer.dart` with exactly:

```dart
import 'dart:io' show Platform;

import 'package:attune/features/auth/sign_up/domain/invite_code.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter/foundation.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Play Install Referrer, once (Spec 1 §3.8 RI, W4b): the invite web
/// page appends `invite_code=K7P2QM` to its Play link, so a person who
/// installs from an invite has the code waiting, as if they had opened the
/// link. Android only; iOS types the code. Read once per install, on any
/// outcome, and never sent anywhere.
typedef InstallReferrerSource = Future<String?> Function();

Future<String?> _playReferrer() async {
  final details = await PlayInstallReferrer.installReferrer;
  return details.installReferrer;
}

/// Set once the referrer has been read on this install (never cleared:
/// sign-out keeps it, as an app setting).
const kInstallReferrerReadKey = 'attune.install_referrer.read';

/// The invite code in a Play referrer string (URL-encoded query, e.g.
/// `utm_source=invite&invite_code=K7P2QM`), or null.
String? inviteCodeFromReferrer(String? referrer) {
  if (referrer == null || referrer.isEmpty) return null;
  try {
    final query = Uri.splitQueryString(referrer);
    final raw = query['invite_code'];
    return raw == null ? null : normalizeInviteCode(raw);
  } catch (_) {
    return null;
  }
}

/// Reads the referrer once and stores its code like a link opened while
/// signed out (the anonymous slot, §5.5), unless a code is already waiting.
/// Never throws; returns the stored code, or null.
Future<String?> readInstallReferrerInvite(
  SharedPreferences prefs, {
  InstallReferrerSource? source,
  bool? isAndroid,
}) async {
  try {
    if (!(isAndroid ?? (!kIsWeb && Platform.isAndroid))) return null;
    if (prefs.getBool(kInstallReferrerReadKey) ?? false) return null;
    await prefs.setBool(kInstallReferrerReadKey, true);
    final code = inviteCodeFromReferrer(await (source ?? _playReferrer)());
    if (code == null) return null;
    final anonymous = OnboardingStore(
      prefs,
      scope: OnboardingStore.anonymousScope,
    );
    if (anonymous.pendingInviteCode != null) return null;
    await OnboardingStore.storeInviteFromLink(prefs, code);
    return code;
  } catch (error) {
    debugPrint('[install-referrer] not read: ${error.runtimeType}');
    return null;
  }
}
```

- [ ] **Step 5: Ask 2 saves as it goes**

In `lib/features/onboarding/presentation/screens/ask2_flow.dart`:

Edit 1 of 7. Replace exactly:

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/safety/self_check/safety_self_check_row.dart';
import 'package:attune/features/onboarding/data/ask2_submission_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
```

with:

```dart
import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/safety/self_check/safety_self_check_row.dart';
import 'package:attune/features/onboarding/data/ask2_progress_store.dart';
import 'package:attune/features/onboarding/data/ask2_submission_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
```

Edit 2 of 7. Replace exactly:

```dart
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
```

with:

```dart
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
```

Edit 3 of 7. Replace exactly:

```dart
/// widgets Ask 1 uses for personal mode, so fixes to those widgets apply
/// to both automatically.
class Ask2Flow extends StatefulWidget {
  const Ask2Flow({super.key, required this.relationshipId});
```

with:

```dart
/// widgets Ask 1 uses for personal mode, so fixes to those widgets apply
/// to both automatically.
///
/// Spec 1 W4b (§3.8 R5): every answer and anchor is saved on this phone as
/// it is given (Ask2ProgressStore); reopening resumes at the first
/// unanswered item; the saved progress goes on completion, and with the
/// sign-out and quick-exit wipes.
class Ask2Flow extends ConsumerStatefulWidget {
  const Ask2Flow({super.key, required this.relationshipId});
```

Edit 4 of 7. Replace exactly:

```dart

  @override
  State<Ask2Flow> createState() => _Ask2FlowState();
}

class _Ask2FlowState extends State<Ask2Flow> {
  static const int _introStep = 0;
  static const int _quizStep = 1;
```

with:

```dart

  @override
  ConsumerState<Ask2Flow> createState() => _Ask2FlowState();
}

class _Ask2FlowState extends ConsumerState<Ask2Flow> {
  static const int _introStep = 0;
  static const int _quizStep = 1;
```

Edit 5 of 7. Replace exactly:

```dart
  int _step = _introStep;
  int _questionIndex = 0;

  @override
```

with:

```dart
  int _step = _introStep;
  int _questionIndex = 0;

  /// Null when there's no account or no SharedPreferences (nothing saved).
  Ask2ProgressStore? _progress;

  @override
  void initState() {
    super.initState();
    _progress = _progressStore();
    final saved = _progress?.read(
      questionCount: attachmentQuestions.length,
      anchorCount: _anchorControllers.length,
    );
    if (saved != null) {
      for (var i = 0; i < saved.answers.length; i++) {
        _quizAnswers[i] = saved.answers[i];
      }
      for (var i = 0; i < saved.anchors.length; i++) {
        _anchorControllers[i].text = saved.anchors[i];
      }
      final next = saved.firstUnanswered;
      _step = next == null ? _anchorsStep : _quizStep;
      _questionIndex = next ?? attachmentQuestions.length - 1;
    }
    for (final controller in _anchorControllers) {
      controller.addListener(_save);
    }
  }

  Ask2ProgressStore? _progressStore() {
    try {
      final userId = ref.read(homeAuthProvider).currentUser?.id;
      if (userId == null || userId.isEmpty) return null;
      return Ask2ProgressStore(
        ref.read(sharedPreferencesProvider),
        userId: userId,
        relationshipId: widget.relationshipId,
      );
    } catch (_) {
      return null;
    }
  }

  void _save() {
    final progress = _progress;
    if (progress == null) return;
    unawaited(
      progress.write(
        Ask2Progress(
          answers: List<int?>.of(_quizAnswers),
          anchors: [for (final c in _anchorControllers) c.text],
        ),
      ),
    );
  }

  @override
```

Edit 6 of 7. Replace exactly:

```dart
      await _submissionService.submit(attachmentAnswers: answers, anchors: anchors);
      await _markAsk2StateCompleted();
    } catch (_) {
      // TODO: Ask 2 has no persistence/retry layer yet (unlike Ask 1's
      // OnboardingFlow with PendingOnboardingSubmission + OnboardingSyncService).
      // If submission fails here, answers are genuinely lost. Future task should
      // implement proper recovery mechanism.
      if (mounted) {
        context.showInfoSnackbar(
```

with:

```dart
      await _submissionService.submit(attachmentAnswers: answers, anchors: anchors);
      await _markAsk2StateCompleted();
      // Done: nothing is owed any more (§3.8 R5). A failure keeps it, so
      // reopening resumes with every answer.
      await _progress?.clear();
    } catch (_) {
      // Spec 1 W4b (§3.8 R5): the answers stay saved on this phone
      // (Ask2ProgressStore), so reopening Ask 2 resumes with every one of
      // them; the server write is retried from there.
      if (mounted) {
        context.showInfoSnackbar(
```

Edit 7 of 7. Replace exactly:

```dart
        onChanged: (value) {
          setState(() => _quizAnswers[_questionIndex] = value);
        },
        onBack:
```

with:

```dart
        onChanged: (value) {
          setState(() => _quizAnswers[_questionIndex] = value);
          _save();
        },
        onBack:
```

- [ ] **Step 6: The wipe entry, the kept mark, the boot read**

In `lib/app/device_wipes.dart` (after Task 4's edits):

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
```

with:

```dart
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/onboarding/data/ask2_progress_store.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
```

Edit 2 of 2. Replace exactly:

```dart
    run: () => removePrefsKeys(InviteDeviceStore.isWipedOnSignOut),
  ),
];
```

with:

```dart
    run: () => removePrefsKeys(InviteDeviceStore.isWipedOnSignOut),
  ),
  // W4b (§3.8 R5): Ask 2's saved answers, at sign-out and on quick exit.
  DeviceWipeEntry(
    id: 'spec1.ask2_progress',
    moments: const {WipeMoment.signOut, WipeMoment.quickExit},
    keys: const {'attune.ask2.<uid>.<relationshipId>'},
    run: () => removePrefsKeys(Ask2ProgressStore.isProgressKey),
  ),
];
```

In `lib/core/services/shared_preferences_service.dart` (after Task 4's edits):

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/core/flags/signed_in_flow_flags.dart';
```

with:

```dart
import 'package:attune/core/flags/signed_in_flow_flags.dart';
import 'package:attune/core/platform/install_referrer.dart';
```

Edit 2 of 2. Replace exactly:

```dart
    FlowFlagsCache.key,
    // Add any other app settings you want to preserve
```

with:

```dart
    FlowFlagsCache.key,
    // Spec 1 W4b: the Install Referrer is read once per install, so a
    // sign-out never stores its invite code again.
    kInstallReferrerReadKey,
    // Add any other app settings you want to preserve
```

In `lib/main.dart`:

Edit 1 of 2. Replace exactly:

```dart
import 'package:attune/core/notifications/config/notification_config.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
```

with:

```dart
import 'package:attune/core/notifications/config/notification_config.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/platform/install_referrer.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
```

Edit 2 of 2. Replace exactly:

```dart
  // Spec 1 §5.8: every feature's sign-out and quick-exit wipes, once.
  registerDeviceWipes();
  final chatCache = ChatCacheService();
  // init() recovers from a corrupt or locked store itself and bounds the
```

with:

```dart
  // Spec 1 §5.8: every feature's sign-out and quick-exit wipes, once.
  registerDeviceWipes();
  // Spec 1 W4b (§3.8 RI): an invite code in the Play Install Referrer, read
  // once per install, waits like a link opened while signed out.
  unawaited(SharedPreferences.getInstance().then(readInstallReferrerInvite));
  final chatCache = ChatCacheService();
  // init() recovers from a corrupt or locked store itself and bounds the
```

- [ ] **Step 7: Run the tests**

```bash
flutter test --no-pub test/features/onboarding/w4/ test/core/platform/install_referrer_test.dart test/features/onboarding/ask2_flow_test.dart test/app/ test/architecture/ 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
```

Expected: `All tests passed!` (W3's `ask2_flow_test.dart`, the keep-set and protective-key tests and the layering test unchanged).

- [ ] **Step 8: Mutation check (quick exit takes Ask 2's answers)**

```bash
D=.superpowers/sdd/2026-11-02-spec1-w4
cp lib/app/device_wipes.dart $D/device_wipes.orig
perl -pi -e 's/moments: const \{WipeMoment\.signOut, WipeMoment\.quickExit\},/moments: const {WipeMoment.signOut},/' lib/app/device_wipes.dart
flutter test --no-pub test/features/onboarding/w4/ask2_progress_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
cp $D/device_wipes.orig lib/app/device_wipes.dart
rm $D/device_wipes.orig
flutter test --no-pub test/features/onboarding/w4/ask2_progress_test.dart 2>&1 | tr '\r' '\n' | grep -E 'Some tests failed|All tests passed' | tail -1
```

Expected: `Some tests failed.` (`wiped at sign-out and on quick exit, for every account`), then `All tests passed!`.

- [ ] **Step 9: Format the new files only, then the W4b gate and the W4 group gate**

```bash
dart format lib/features/relationships/data/invite_messages.dart lib/features/relationships/data/invite_device_store.dart lib/features/relationships/presentation/invite_error_copy.dart lib/features/relationships/presentation/invite_share_actions.dart lib/features/onboarding/presentation/widgets/invite_partner_step.dart lib/features/relationships/presentation/screens/join_invite_screen.dart lib/features/relationships/presentation/widgets/linked_moment.dart lib/features/relationships/presentation/widgets/linked_moment_gate.dart lib/features/onboarding/data/ask2_progress_store.dart lib/core/platform/install_referrer.dart test/helpers/fake_share_actions.dart test/features/relationships/invite_refusal_test.dart test/features/relationships/w4/ test/features/onboarding/w4/ test/core/platform/install_referrer_test.dart
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error ' | sed -E 's/:[0-9]+:[0-9]+//' | sort -u | comm -13 .superpowers/sdd/2026-11-02-spec1-w4/analyze-errors-baseline.txt -
git diff --stat -- lib/features/opinions lib/features/games lib/features/auth/utility/auth_exports.dart ATTUNE_SOUL.md ATTUNE_THESIS.md supabase/sql/dev_enable_spec1_flags.sql lib/features/onboarding/presentation/screens/onboarding_gate.dart | tail -1
awk '/if \(isAuthenticated && !_gateData.isComplete\) \{/,/_redirectingToOnboarding = false;/' lib/home/home_screen.dart | diff .superpowers/sdd/2026-11-02-spec1-w4/latch-before.txt - && echo "latch unchanged"
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done | grep '^FAIL' | comm -13 <(grep '^FAIL' .superpowers/sdd/2026-11-02-spec1-w4/sql-baseline.txt) -
(cd supabase/functions && deno test --allow-read accept-invite/ 2>&1 | grep -E 'passed|failed' | tail -1)
git status --short > .superpowers/sdd/2026-11-02-spec1-w4/git-status-after.txt
diff .superpowers/sdd/2026-11-02-spec1-w4/git-status-before.txt .superpowers/sdd/2026-11-02-spec1-w4/git-status-after.txt | grep '^>' | wc -l
```

Expected: the format line lists only the new files (`Formatted N files (0 changed)` or a few changed; never a pre-existing path); `All tests passed!` (if `test/features/chat/chat_upload_progress_cancel_test.dart` or `chat_w1a_final_fixes_test.dart` fails under the full run, run the file alone: both are timing-sensitive under load and passed alone when this plan was written); no analyzer output; no diff line; `latch unchanged`; no new SQL FAIL; `ok | 18 passed | 0 failed`; the count of paths this plan touched (report the list). The **W4 group gate** itself is not code: **the Ghanaian cultural reviewer confirms the Pidgin register** (until then `kPidginRegisterReviewed` stays `false` and only Simple and Casual are offered), and the regression check of `main.dart`'s invite deep link on a device (checklist 5). Report both as outstanding.

## Owner deploy checklist (the plan never runs any of this)

1. **Order.** W1–W3 are deployed first (their checklists). W4a's migration and functions go before any W4b build reaches a tester: the W4b app reads `code` and calls `preview_relationship_invite`. Deploy the migration before the functions (`accept-invite` calls `accept_relationship_invite_v2`; both call `relationship_invite_eligibility`).
2. **Server (W4a).** `supabase db push` applies `20261102100000_accept_invite_v2.sql` and `20261102100010_accept_invite_v2_grants.sql`. Then `supabase functions deploy accept-invite` and `supabase functions deploy create-relationship-invite`. Afterwards, in the SQL editor: `select jobname, schedule from cron.job where jobname = 'invite-preview-retention';` → `invite-preview-retention | 39 * * * *`; `select has_function_privilege('authenticated', 'public.accept_relationship_invite_v2(uuid,text)', 'EXECUTE'), has_function_privilege('service_role', 'public.accept_relationship_invite_v2(uuid,text)', 'EXECUTE'), has_function_privilege('anon', 'public.preview_relationship_invite(text)', 'EXECUTE');` → `f | t | f`. Then (final review #5): `select has_table_privilege('authenticated', 'public.relationships', 'INSERT');` → `f` (N-1: no client insert, so no live-code oracle); `select has_function_privilege('authenticated', 'public.note_invite_attempt(uuid)', 'EXECUTE'), has_function_privilege('anon', 'public.note_invite_attempt(uuid)', 'EXECUTE'), has_function_privilege('service_role', 'public.note_invite_attempt(uuid)', 'EXECUTE');` → `f | f | t` (the attempt budget is service-role only). Both were checked on the local `attune_spec3a` (f; f, f, t).
3. **Flags.** Nothing to insert: `flow_couples_v2` exists (W1c) and is on in development (W1's dev script, unchanged). On the development project, installing a W4b build switches R1, RI-3, R3 and R4 at once.
4. **The invite web page (`bars-opus/attune-invite-web`, owner).** Its Play Store link appends `&referrer=invite_code%3D{CODE}` (URL-encoded `invite_code=K7P2QM`), so the Install Referrer carries the code (§3.8 RI). **Switch the page's referrer on only after the W4b build is the live Play production version** (batch-6 review I-1): an install made before W4b is live would otherwise carry a code into an update's first launch. (The app also stores nothing when a session exists at that first read.)
5. **Device checks (development project, both platforms):**
   - R1: type a name; Simple and Casual change the preview; "Send on WhatsApp" opens WhatsApp with the text and no recipient (only when it is installed); "Share another way", "Show QR code", "Copy code" each work; the heads-up names the partner after a send.
   - A second phone opens the link while signed out, creates an account (A1–A5): RI-3 "Join {name}?" appears; "Join" → "Welcome, {couple}" (the couple's chat name, else "Welcome, Couples"; preflight F-1) → "Turn on" asks for notifications → Chat. The inviter's phone shows the same R4 on its next open, once.
   - Shared phone: open a link signed out, sign in as a different existing account within 24 hours: RI-3 names the inviter and nothing links until "Join"; "Not now" leaves no code behind (reopen the app: no RI-3).
   - Expired code: RI-4 "This invite has expired." with "Ask {name} on WhatsApp".
   - A legacy account without a date of birth accepting: A2 first, then RI-3 again.
   - R3 at day 7 (age an invite by editing `created_at` on the development project): "Send a new invite" makes a new code and opens the share step; day 30 shows the line once.
   - Ask 2: answer two questions, kill the app, reopen from the notification: it resumes at question 3; quick exit, then reopen: it starts again.
   - Install Referrer: a clean Android install from the invite page (Play internal testing track) → Welcome → "I have an invite" shows RI-1 with the code already there.
   - Regression (W4 group gate): tap an invite link on a cold start, signed in and signed out, on both platforms: signed out → RI-1; signed in → RI-3 (flag on) or today's accept (flag off).
   - TalkBack and VoiceOver through R1, RI-3, RI-4 and R4; 200% system text.
6. **W4 group gate (before `flow_couples_v2` in production):** the Ghanaian cultural reviewer confirms the Pidgin register; then, in the change that records the review, set `kPidginRegisterReviewed = true` (`lib/features/relationships/data/invite_messages.dart`) and run `invite_messages_test.dart` (its Pidgin case then needs `[simple, casual, pidgin]`). `flow_couples_v2` has no production gate row (§2.5); it also needs `flow_paths_v2` on.
7. **Production switch-on, last:** after W3's switch-on (`flow_paths_v2`), `update public.feature_flags set enabled = true where key = 'flow_couples_v2';`. Existing couples see R4 ("Welcome, {couple}") once (owner decision 1); under the flag it is their only notification ask (W3 P-24).
   - Flip day: a phone holding a cached 'off' runs today's silent accept once, for a stored code, before its first flags answer (R-3). Expect it; nothing to do unless a report names it.
8. **Every W4 gate item still open after batch 6 (the code gates passed; see `.superpowers/sdd/2026-11-02-spec1-w4-invites/batch-6-report.md`):**
   - W4 group gate: the Ghanaian cultural reviewer confirms the Pidgin register (item 6). Until then only Simple and Casual are offered.
   - W4 group gate: the `main.dart` invite deep-link regression on a device, both platforms, signed in and signed out (item 5, "Regression").
   - The deploys in items 1–2 (2 migrations, 2 functions) and the post-deploy SQL checks.
   - The invite web page's referrer parameter (item 4), and the clean-install Install Referrer check on the Play internal track (item 5).
   - Every device check in item 5, including TalkBack/VoiceOver and 200% text.
   - Owner notes to confirm: the Simple invite message keeps the sender's own "just for the two of us" (preflight F-2); most couples see "Welcome, Couples" because `chat_name` is usually empty at linking (F-1); owner question 5's Install Referrer line (F-10, closed by final review #1).
   - Flip day (item 7): a phone holding a cached 'off' runs today's silent accept once, for a stored code, before its first flags answer (R-3).
   - The invite page's Play referrer goes on only after W4b is live on Play (item 4, review I-1).
   - Production `FLOW_V2_DEFAULT`/`flow_signin_v2`: with `flow_signin_v2` off (today's production) the signed-in flags count as known at once, so today's legacy gate and accept run unchanged (Task 6 re-review R-1). The fail-closed wait applies only once `flow_signin_v2` is on.

## Spec coverage (self-review)

| Spec item | Where |
|---|---|
| §1.3 Q7 ("Send a new invite" replaces "Invite someone else"; withdraw returns to the previous path) | Task 7 (P-16); W3's R3 cancel unchanged |
| §2.1 copy as `flow_*` keys, ASCII fragments, the partner named | Tasks 3–7 (P-12) |
| §2.2 motion: R4's calm celebration; RI-4 and refusals never animated | Task 6 (`LinkedMoment`, P-13) |
| §2.3 accessibility: goldens 1.0/1.3/2.0/RTL, three guidelines, labels, announced errors | Tasks 5, 6, 7 |
| §2.4 R2 and R4 in-context asks; no automatic ask under `flow_couples_v2` (W3) | Tasks 5, 6, 7 (P-14, P-19) |
| §2.5 `flow_couples_v2` gates W4b; off = today | Tasks 5, 6, 7 flag-off tests (P-10) |
| §3.8 R1 registers, the code in every message, Pidgin held, WhatsApp/share/QR/copy, "Invite later", "My partner already invited me" | Tasks 4, 5 (P-9) |
| §3.8 R2 heads-up | Task 5 (P-19) |
| §3.8 R3 "Send again", day 7, day 30, the receipts line named | Task 7 (P-16) |
| §3.8 R4 once per phone, on the next open | Tasks 6, 7 (P-13, P-15) |
| §3.8 R5 Ask 2 saves as it goes | Task 8 (P-18) |
| §3.8 RI-1/RI-2 signed out (W2), Install Referrer | W2 unchanged; Task 8 (P-17) |
| §3.8 RI-3 states, RI-4 | Task 6 (P-10, P-11, P-12) |
| §3.14 `accept-invite` waits for the DOB on the server | Task 2 (`signup_incomplete`), Task 6 (`onNeedsAccount`) |
| §4.2 `private.invite_preview_attempts`; §4.6 its cron; §4.8 one day | Task 1 |
| §4.3 W4a `accept_relationship_invite_v2`, `preview_relationship_invite` | Task 1 (P-3, P-4, P-5) |
| §4.5 `create-relationship-invite` (428/403), `accept-invite` (one SQL call, mapped, push) | Task 2 (P-2, P-6) |
| §4.7 #9 `accept_invite_v2` | Task 1 (P-1) |
| §5.1 `invite_partner_step.dart`, `join_invite_screen.dart`, `linked_moment.dart`, `invite_messages.dart`, `install_referrer.dart` | Tasks 4–8 (`invite_landing_screen.dart` is W2's, unchanged) |
| §5.2 `main.dart`, `onboarding_gate.dart`/`onboarding_flow.dart` (no acceptance before the name: RI-3), `pending_invite_guide.dart`, `ask2_flow.dart`, `pubspec.yaml` | Tasks 6, 7, 8 (the v2 gate carries it; the legacy gate is flag-off, P-10) |
| §5.5 under `flow_couples_v2` acceptance only from RI-3 | Task 6 (D9) |
| §5.6 R3 (`main.dart` invite link), R8 (`accept-invite` texts) | Task 2; checklist 5 |
| §5.8 `spec1.partner_first_name`, `spec1.ask2_progress` | Tasks 4, 8 |
| §6.1 an age check on both sides of an invite | Tasks 1, 2 |
| §7.1 `invite_v2_contracts.sql` (each code, withdrawal in the same transaction, forced-failure rollback, idempotent re-accept, path set, preview rate limit, inviter age, retention) | Task 1 |
| §7.2 `accept-invite/index.test.ts`: every code mapped, prefix kept | Task 2 (`accept.test.ts`) |
| §7.3 invitee flow RI-1 → RI-3 → R4; scoped invite claim on a shared phone; day-7 "Send a new invite" | Tasks 6, 7 |
| §7.4 mutants: withdrawal removed; accept before RI-3 in the gate | Task 1 Step 7; Task 6 Step 7 |
| §8 W4a, W4b, the W4 group gate (Pidgin; `main.dart` deep link) | Tasks 1–8; checklist 5, 6 |
| §9 a shared phone's next user inherits an invite; invite errors change wording | Task 6 (P-10); Tasks 2, 3 |
| Carried: interim guard replaced, lock order (W1), D8 | Tasks 1, 2 (P-2, P-3) |
| Carried: InviteCard accessibility | Task 5 (P-8) |
| Carried: raw English invite errors in R1/R3 | Tasks 3, 5, 7 (P-7) |
| Carried: RI-3/RI-4, D9, legacy silent accept | Task 6 (P-10) |
| Carried: `flow_couples_v2` gating, R4, couples' push ask timing | Tasks 5–7 (P-13, P-14) |
