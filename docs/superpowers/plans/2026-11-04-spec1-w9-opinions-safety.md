# Spec 1 W9 (Opinions safety minimum, journal crisis check) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Q10's safety minimum without the deferred Opinions redesign: one shared Unicode normaliser and a deterministic pre-post content filter on the six Opinion writers (W9a, migration 16, behind `opinions_safety_v1`); the "Someone may be at risk" report reason, review queue v0, the restored removal and ban notices with the strike-3 fix, owner-checked removal of your own opinion or comment, and "Need support now?" (W9b, migrations 17-19); and the journal's hard-coded `self_disclosure` check before any provider call, with the writer's support card (W9c).

**Architecture:** Three sub-waves, ten tasks. **W9a (Tasks 1-4).** Task 1 records the baselines and writes the *flag-off goldens from today's code*, before any edit: every later task runs them unchanged, which is the owner's "byte-for-byte unchanged with the flag off" test. Task 2 is the shared normaliser: `_shared/unicode_fold_table.json` (the one fold table), `_shared/unicode_normaliser.ts` (`baseForm`, `matchForm`, `squashedForm`, for Spec 2) and the shared goldens, proven by `unicode_normaliser.test.ts` and five TypeScript mutants. Task 3 is migration 16 (`private.normalize_for_filter`, `private.match_form`, `private.content_filter_terms`, `private.digits_from_words`, `private.has_contact_info`, `private.content_filter_verdict`, `private.assert_opinion_content_ok`, and the six writers re-created from their live bodies with one added line each), the `[DRAFT]` dev loader, and `opinion_filter_contracts.sql` sections A-F with thirty-eight mutants. Task 4 shows a refusal inline under the field (draft kept, announced, counted) in compose, quote, edit, comment and comment edit. **W9b (Tasks 5-8).** Task 5 is migration 17 (the at-risk reason: valid, priority, never counted toward auto-hide; review queue v0) with the contract's section G and ten mutants. Task 6 is migration 18 (`admin_confirm_content_removal` from its live body: `search_path = ''`, OPN-BAN-42702, the two notices) with `opinion_moderation_notice_contracts.sql` and seven mutants. Task 7 is migration 19 (`remove_my_opinion`, `remove_my_comment`, OPN-DELETE-RLS) with `opinion_remove_own_contracts.sql`, seven mutants and the repository change (ungated). Task 8 is the app: "Need support now?" in compose and every post and comment menu, the at-risk reason in both report lists with its thank-you, the manual passage. **W9c (Tasks 9-10).** Task 9 moves `analyse-journal-entry`'s two actions into `journal_handlers.ts` with the provider, the draft-list flag and the count injected, and runs `detectSelfDisclosure` first (eight Deno tests, eight mutants). Task 10 is the writer's card on the list, in the entry and on Patterns, and "Need support now?" in the entry menu. Every SQL, Deno and Dart block below was run while writing this plan: the SQL on a scratch Postgres 17 cluster restored from `attune_spec3a`'s dump (each migration applied twice, `exit=0` both times; each contract red before its migration with the message quoted and green after; every mutant red with the message quoted; the whole contract suite with no new FAIL: 142 PASS + the three new files), the Deno tests and every TypeScript mutant, and the Dart in a scratch copy of the tree (the flag-off goldens written from the untouched code and green against the finished code, every new test red before its code and green after, goldens looked at, the analyzer clean on every touched file, every Dart mutant red, and the full `flutter test` suite green: 6951 passed, today's 6924 and the 27 new).

**Tech Stack:** Flutter 3.29.1 (Dart 3.7), Riverpod 2.6, GoRouter, Supabase Postgres 17 (RLS, `SECURITY DEFINER` with `search_path = ''`, the `pg_c_utf8` collation, pg_cron, Vault through `public.app_setting`), Supabase CLI 2.75, Deno 2 (JSON import attributes), psql, Python 3 (edit, escape and mutation scripts). No new Dart package, no new Deno import beyond `std@0.224.0/assert` already used by `_shared/self_disclosure.test.ts`.

**Spec:** `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md` — §1.3 (Q9 deferred; Q10 the safety minimum), §1.4 (D12, D13, D17), §1.5, §2.1 (copy), §2.2 (support and report sheets never animated), §2.3 (accessibility), §2.5 (`opinions_safety_v1`, `journal_ai_insights` and their gate rows; the Spec 8 `private_safety_check`), §4.2 (`private.content_filter_terms`, `forum_reports` W9b behaviour), §4.3 W9a and W9b, §4.5 `analyse-journal-entry`, §4.7 #16-#19, §4.8 (blocks and journal matches not stored), §5.1/§5.2 rows tagged W9a-c, §5.6 R10, §5.7 (shared with Spec 3), §6.6, §7.1 (`opinion_filter_contracts.sql`, `opinion_moderation_notice_contracts.sql`, `opinion_remove_own_contracts.sql`), §7.2 (`analyse-journal-entry`, `unicode_normaliser.test.ts`), §7.3, §7.4 (the W9 mutants), §8 W9a-c with their gates, §9, §10 (outside parties), §11 (I-17, OPN-BAN-42702, OPN-DELETE-RLS) and the owner approval (O2, O4). Owner rulings: `docs/superpowers/research/2026-10-24-flow-dating-research/11-synthesis-decisions.md` §12 (Q9 deferred; Q10: the filter, "Need support now?", the at-risk reason and the journal check, in S1 W9, without the redesign), §5.2-§5.3; the owner's ruling of 2026-11-04 (build all of W9 as the spec says; the Opinions safety changes stay off behind `opinions_safety_v1` and are byte-for-byte unchanged with it off, with a test; OPN-BAN-42702 and OPN-DELETE-RLS ship ungated; nothing else in Opinions changes). Spec 3: `docs/superpowers/specs/2026-10-24-forum-removal-design.md` (V8, §10 F-1, the keep list, contract E stops at strike 2, W3 later removes the `forum_post` branch from this body). Format reference: `docs/superpowers/plans/2026-11-03-spec1-w7-resources-image-safety.md`.

## Global Constraints

- Work in the main working tree on `main` (`/Users/user/attune`). W1-W7 are committed (HEAD `75e502c5`); the owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql` at the time of writing): never revert, stash, stage, checkout or reformat them. Every edit below is an exact-string replacement made by a script that asserts each anchor occurs once; if an anchor has moved because a later fix changed it, apply the same change to the current text and say so in the task report.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm`. Tasks end with "Run tests", not "Commit".
- Never `dart format` a pre-existing file (the repo predates the 3.7 formatter). The Dart files this plan creates are given already formatted; each task's last step re-runs `dart format` on exactly those paths (it changes nothing).
- **SQL:** contracts run only on the local scratch database `attune_spec3a`, only as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>` **from the repo root** (`opinion_filter_contracts.sql` reads the two JSON files with `\set ... \`cat ...\``), inside the file's own `BEGIN … ROLLBACK`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh`, `scripts/local_pg_grants.sql` or `scripts/local_pg_bootstrap.sql`; Tasks 3, 5, 6 and 7 **edit** `scripts/local_pg_grants.sql`, never running it. The only writes to `attune_spec3a` are applying this plan's migration files and its mutant files (each mutant is undone at once by re-applying the migration); the loader is checked inside a rolled-back transaction.
- **Migrations:** `20261104100000_opinion_content_filter.sql` + `…100010_…_grants.sql` (16, Task 3); `20261104110000_opinion_at_risk_and_review_queue.sql` + `…110010` (17, Task 5); `20261104120000_opinion_moderation_notices.sql` + `…120010` (18, Task 6); `20261104130000_opinion_remove_own.sql` + `…130010` (19, Task 7). They are later than every migration in the tree (the newest is W7's `20261103140110_media_scan_enqueue_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261104100000` when Task 3 starts, shift all eight to the next free hour, keeping their order, and change every header, `\i` line and command below to match. Each file is one `BEGIN; … COMMIT;`, idempotent (applied twice, `exit=0` both times), `SET LOCAL lock_timeout = '5s'` (no step has a lock fallback: a busy table fails the migration loudly, and `db push` is simply re-run), server-only objects are revoked inside the migration itself and again in the twin, grants are explicit, nothing reaches `anon`. No new public table, so no `service_role` table grant is needed; `private.content_filter_terms` has no grant at all. Every re-created function starts from its LIVE latest body (found with `grep -l` and checked identical to `pg_get_functiondef` on `attune_spec3a` while writing this plan) and changes only the lines marked `Spec 1 W9a` / `Spec 1 W9b`; Task 1 saves the "before" bodies and Tasks 3, 5 and 6 diff against them. No `CREATE INDEX CONCURRENTLY`. No new trigger on any table (so no shared-table writer regression beyond the re-created functions, which their own contracts and Spec 3's contract E cover).
- **Postgres 17 is required** (the `pg_c_utf8` collation gives one Unicode lower-case mapping on every database whatever its locale). The development and production projects must report `server_version_num >= 170000` before `db push` (owner checklist 1).
- **Flags:** W9 adds no flag row. `opinions_safety_v1` and `journal_ai_insights` exist from W1c (`20261025100400`), inserted false, with their production gate rows (`'W9a and W9b gates: reviewed slur and explicit lists signed; a named daily reviewer works review queue v0'`; `'W9c gate: the clinician and the suicide-prevention reviewer sign the journal card and the self-harm corpus'`); `supabase/sql/dev_enable_spec1_flags.sql` already turns both on in development and is not edited. `private_safety_check` (Spec 8) is read, never written.
- **Owner ruling 2026-11-04 (Opinions):** with `opinions_safety_v1` off, the Opinions UX and behaviour are byte-for-byte unchanged: no support link, no at-risk reason, no filter, the same snackbars, the same menus and report lists, the same pixels (Task 1's goldens, run unchanged by Tasks 4, 8 and 10). OPN-BAN-42702 (migration 18) and OPN-DELETE-RLS (migration 19 and the repository) ship ungated, and so do the restored notices (spec §8 W9b: they restore live behaviour). Nothing else in Opinions changes: only the files and rows the W9 spec names (plus two new files its table doesn't list, P-10, and test helpers).
- **Never touch:** `lib/features/games/**`, `ChatScreen`'s Games entry points, `UniversalBubble` / `ChatTextField` parameters (the comment field is used as it is), `lib/features/auth/utility/auth_exports.dart`, every Games route in `app_router.dart` (`test/architecture/games_untouched_test.dart` stays green), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, every applied migration, `supabase/sql/dev_enable_spec1_flags.sql`, every existing SQL contract (Spec 3's `forum_retirement_contracts.sql` section E deliberately stops at strike 2 and is not edited), the couples `_shared/chat_safety.ts`, `_shared/self_disclosure.ts` and its corpus, `lib/features/opinions/presentation/widgets/opinion_card.dart`, `opinions_tab.dart`, `create_content_chooser.dart`, `create_content_fab.dart`, `notification_config.dart` (the two notice types already land on home), `process-scheduled-notifications`, `lib/home/home_screen.dart` (its latch block, from `if (isAuthenticated && !_gateData.isComplete) {` to `_redirectingToOnboarding = false;`, stays byte-identical: Task 1 saves its hash, Tasks 4, 8 and 10 compare).
- **Safety system rules:** nothing in W9 depends on an LLM: the filter is SQL, the normaliser a fixed table, the journal check the hard-coded `self_disclosure` corpus, run before the cache and any provider call. Safety notices go to the affected person only: the removal and ban notices to the author; an at-risk report is never shown to the reported person or anyone else (it reaches the review queue only); the journal card only to the writer. Filter term lists are `[DRAFT]` in development (a small English list, `supabase/sql/load_content_filter_terms.sql`, refused outside development), and a draft term never matches outside development whatever is loaded (P-6); production holds only the cultural reviewer's signed lists (owner gate). Never invent terms beyond that minimal list: the contract uses invented placeholder words. Quick exit works everywhere: the app shell's `QuickExitZone` sits above every route and sheet, and nothing here adds a route of its own.
- **Copy:** every new string is an English key appended to `lib/i10n/app_en.arb` (`opinions_*` for Opinions, `support_*` for the shared link, `journal_*` for the journal card) by W3's `.superpowers/sdd/2026-10-26-spec1-w3/arb_append.py`, then generated with `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package` (never W2 P-9's perl fix); other locales fall back to English. Every fragment is pure ASCII (straight apostrophes, no dash or ellipsis), checked with `grep -cP '[^\x00-\x7F]' <fragment>` (prints `0`). Files whose content needs a non-ASCII character as an escape (the two JSON files, the TypeScript port and its test) are normalised by script to `\uXXXX` escapes and checked with `grep -cP '[^\x00-\x7F]'` (prints `0`), never by hand: an editor or tool may turn an escape into the character. W9 copy names no partner (never "they" for the partner, never "both of you") and shows no date (any later one uses `MyDateFormat`).
- **UI:** Material 3 from the app theme; every new widget and sheet is wrapped in `AllowLargeText` (the shell clamps routes, dialogs and sheets to 1.0: W7's lesson I-1); every control labelled, targets at least 48 dp, text contrast at least 4.5:1, goldens at 1.0, 1.3, 2.0 and right to left (`expectFlowGoldens`), `androidTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline` (`expectFlowGuidelines`). Errors are announced (`SemanticsService.announce`) and never shown by colour alone. Nothing on a support, report or journal-card surface animates (`AnimationStyle.noAnimation` for the at-risk sheet; the card and the notice are plain widgets).
- **No deploys.** `supabase db push`, function deploys, loading term lists on a hosted project and every gate are the owner's ("Owner deploy checklist"). Don't read `.env*`, credentials or the keychain. No `flutter pub get` (no package change).
- **Regression gate at the end of each sub-wave (Tasks 4, 8, 10):** every SQL contract on `attune_spec3a` shows no new FAIL against the Task 1 baseline, and the W9 contracts, `identity_foundation_contracts.sql`, `forum_retirement_contracts.sql` and `account_deletion_contracts.sql` are PASS; the Deno tests named in the task pass; the full `flutter test` passes; `flutter analyze --no-pub lib test` shows no `error` line that the Task 1 baseline didn't; the Games test passes; Task 1's flag-off goldens pass unchanged; no Games or `auth_exports.dart` change; the latch is unchanged.

## Review Focus

1. **Ordinary posts that look like contact details: years, amounts, dates and times, scores, a Twi or Pidgin sentence, an `@` used as "at".** Expect them to pass with the filter on; only a real phone number, e-mail, link or handle is held back. Tests: Task 3 contract D (the thirteen negatives, every `ordinary_*` and `twi_*` golden), contract F (an ordinary post goes through with the filter on), mutants `no_year_exemption`, `no_thousands_exemption`.
2. **A filter refusal arriving while the phone thinks the flag is off (a stale or unread flag).** Expect the inline reason, never a raw `PostgrestException` in a snackbar: the server is the authority, and with the server's flag off no refusal can arrive (P-9). Tests: Task 4 (`compose: the reason shows under the field…` and the others run with the client flag off), and `any other failure keeps today's message`.
3. **Draft terms reaching production, or the dev loader run against production.** Expect neither: the loader refuses outside development, and a draft term never matches outside development whatever the table holds. Tests: Task 3 contract E (`a draft term matched outside development`), mutant `draft_in_production`, and the loader's `env:not_development` refusal (Task 3 Step 7).
4. **A crisis entry reaching the model by a side door: a cached reflection, the title only, Patterns, an unreadable journal.** Expect no provider call in any of them, and the old reflection gone. Tests: Task 9 (`a crisis entry never reaches the provider, or the cache…` with the crisis in the title and in the text, both flag states; `get_patterns: the newest entry matches…`; `get_patterns leaves matched entries out…`; `an unreadable journal never reaches the provider`), mutants `check_after_cache`, `patterns_fail_open`, `keeps_stale_reflection`.
5. **The seventh report reason with the flag on: a sheet that overflows a phone, or an at-risk report that silently fails.** Expect the list to scroll (six reasons render exactly as before) and a failed at-risk report to say so. Tests: Task 8 (`a post reported "Someone may be at risk"…`, which fails on an overflow; `an at-risk report that fails says so`), Task 1's `flag_off_report_reasons` golden.

## Decisions found while verifying the code (read before Task 1)

Each is a verified fact about today's code (HEAD `75e502c5`), the database or the runtime, with the smallest change that keeps the spec's intent. *Changes spec intent* marks the ones the owner should see.

**W9a**

- **P-1 (timestamps).** Migrations 16-19 are `20261104100000`, `…110000`, `…120000`, `…130000`, each with its `…10` grants twin.
- **P-2 (flags already exist).** Both W9 flags, their gate rows and the dev-script lines were made by W1c (Global Constraints). `opinions_safety_v1` is not in `get_public_app_config()` (only the four pre-auth flags are), and `feature_flags` is readable signed in only, so a guest reads it as off (owner question 5).
- **P-3 (the two forms, exactly).** Spec §4.3 W9a fixes the order (NFKC, lower, invisible and bidi controls removed, confusables, separators) and what each form keeps; the table fixes the characters:
  - *lower case* uses the `pg_c_utf8` collation (Unicode simple case mapping, the same on every PG17 database whatever its locale); the TypeScript port lowers one code point at a time with U+0130 (`İ`) special-cased, which is exactly the simple mapping (JavaScript's `toLowerCase` is the full mapping, which differs only there and for a final sigma in context). A golden pins each.
  - *removed:* U+00AD, U+200B-U+200F, U+202A-U+202E, U+2060-U+2064, **and U+2066-U+2069** (the bidi isolates are bidi controls too), U+FEFF.
  - *confusables:* 35 Cyrillic and Greek look-alikes and three Latin ones (ı, ɑ, ɡ), lower case (they run after lower case). Arabic-Indic, Extended Arabic-Indic, Devanagari and Bengali digits fold to 0-9 in the base form (a phone number typed in them is still a number; fullwidth and circled digits are NFKC's).
  - *separators:* C0 controls, whitespace (incl. NBSP and the Unicode spaces), ASCII punctuation, and the common Unicode punctuation blocks: 165 characters, each to one space, then runs collapsed.
  - *kept in the base form:* `$ + , . / : @ _`: `$` (spec), and what contact rules need (`+` for +233, `.` `/` `:` for links and e-mails, `@` for handles and e-mails, `_` inside handles). **`,` is kept** so an amount written with thousands commas (`2,500,000,000`) is never read as one long number. In the match form, `@` and `$` fold (leetspeak) and the rest become spaces.
  - *match form:* the West African fold is exactly the spec's eight (`ɛ ɔ ŋ ƒ ʋ ɓ ɗ ƙ`; `ŋ` → `ng`), the leetspeak fold exactly the spec's eight. Any further letter (Ewe ɖ, Yoruba ẹ ọ, Hausa ƴ) is the cultural reviewer's call (W9a gate), added in the table, the migration and the goldens together.
- **P-4 (contact rules, exactly).** On the base form after digit words:
  - a run of 9-15 digits joined by at most single separators (` ` `.` `/`; `-` `(` `)` are already spaces) is contact when it starts with `+`, or with `0` (covers `00`), or has the NANP shape (groups 3-3-4 or 10 digits, area and exchange not starting 0/1; or the same after a `1`), or is 11-15 digits starting with a calling code from a fixed list (233, 234, 44, 27, 254, 255, 256, 225, 237, 221, 229, 228, 226, 231, 232, 220, 353, 49, 33, 31, 91, 971, 966, 86, 1) — **except** when every group is a year 1900-2099 (`1999 2004 2010`), or when it is an amount grouped in thousands (`250 000 000`, first group 1-3 digits not starting 0, every later group 3 digits, at least 3 groups). The calling-code rule needs 11+ digits so a 9-10 digit amount is never caught by it.
  - e-mail addresses; "at … dot …" (with `@`/`at`, `.`/`dot`, spaces optional) for a fixed list of providers; `http(s):/`; `www.`; `wa.me` and `t.me`; twelve short-link hosts; **bare domains only on `com net org info biz io xyz ly gh ng uk`** (TLDs that are English words — `.me`, `.co`, `.to`, `.app`, `.live` — are left out, because "done.me too" and "co.worker" are ordinary typing; `wa.me`/`t.me` and `co.uk`-style links are still caught); `@handles` of 3+ characters; a platform name (Instagram, Insta, IG, Snapchat, Snap, TikTok, Telegram, TG, WhatsApp, Signal, Twitter, Facebook, FB, Threads) then `:` or `@` then a 3+ character handle.
  - digit words: zero-nine; `oh`/`o` only next to a digit word or numeral; adjacent digit words join into one group (`four one five …` is a 10-digit NANP number); reviewed local number words come from the term table (P-5).
- **P-5 (the term table).** §4.2's columns, plus: **family `number_word` and a `digit` column** for the reviewer's local number words ("local number words come from the reviewed list"; §4.2's `CHECK IN ('slur','explicit')` has nowhere to put them). *Changes spec intent* (one extra family value and column; no rows until the reviewer supplies them). Checks: the term is stored in the match form; `squashed` only for terms of 5+ letters and never for number words (§9: only distinctive terms squash); a `reviewed` row names its `review_ref`; unique per family, term and locale. `id` is a bigint identity.
- **P-6 (draft terms are inert outside development).** `content_filter_verdict` and `digits_from_words` use a `draft` row only when `private.attune_environment()` reads `development`. A dev list loaded by mistake into production can never block a post; production blocks only on reviewed rows. (Adds a fail-safe the spec doesn't state.)
- **P-7 (the six writers).** Each is its live body plus one line, placed right after the content check (`invalid_content`) and before anything is read or written (so before `assert_can_post`): `create_opinion`, `edit_opinion`, `edit_opinion_comment` check `p_content`; **`create_opinion_with_poll` checks the content and every option in its one line** (an option is shown to everyone); **`create_opinion_comment` checks `p_content` and `p_quoted_text`** (client-supplied text shown with the reply; otherwise a phone number would bypass the filter through it); **`create_opinion_with_quote` checks right after its `quote_requires_target` check, before the target lookup** (so a refusal is the content's, whatever the target). The poll and quote also reach `create_opinion`, which checks the content again: harmless, and it makes each writer's own line testable (each writer's mutant is caught on its own). Only the lines marked `-- Spec 1 W9a` differ from the live bodies (Task 3 diffs them).
- **P-8 (the refusal).** `RAISE EXCEPTION 'content:<contact_info|slur|explicit>' USING ERRCODE = '22023'` (the writers' own `invalid_content` code; PostgREST answers 400). Nothing about the post is stored; the app counts `opinion_blocked:<reason>` (keys seeded in W1b).
- **P-9 (the app shows any filter refusal inline).** `ContentFilterReason.of(error)` reads exactly `content:<reason>`; when it matches, the screen shows the reason under the field (draft kept, announced, counted) **whatever the client's copy of the flag says**, because only the server refuses and it does so only while the server's flag is on. With the flag off the server never refuses, so the screens behave exactly as before (Task 1's goldens and snackbar test). The notice clears when the person edits the text; under the comment field (whose `ChatTextField` parameters are never touched) it clears at the next successful post or the next refusal.
- **P-10 (new files the spec doesn't list).** `lib/features/opinions/presentation/widgets/content_filter_notice.dart` (the inline notice; the spec's `content_filter_error.dart` is the domain mapping), `lib/features/opinions/presentation/providers/opinions_safety_provider.dart` (§5.3's `opinionsSafetyProvider`), and test helpers.
- **P-11 (the TypeScript port).** `unicode_normaliser.ts` imports the fold table with a JSON import attribute, so the port is the table by construction; the test runs every golden and every table entry, needs `--allow-read`, and the four files are ASCII-only (escapes).
- **P-12 (the at-risk reason on the server).** Accepted by the server whatever the flag says (only the app offers it, and only with the flag on); the spec gives the server no flag here.

**W9b**

- **P-13 (the report RPCs).** Re-created from their live bodies with only `IF p_reason = 'Someone may be at risk' THEN RETURN; END IF;` after the dedup return: the report row is written (priority) and `report_count` never moves, so an at-risk report can never auto-hide (D13). Their `search_path = public, private` and grants stay as live. **Found (not fixed, owner question 2):** the live dedup return never fires: `INSERT … ON CONFLICT DO NOTHING RETURNING true INTO v_inserted` leaves `v_inserted` NULL on a repeat, `IF NOT NULL` is not true, and a repeat report from the same account still increments `report_count` (verified on the scratch copy: two reports from one account → `report_count = 2`), so one account can still auto-hide a post.
- **P-14 (comment reports).** Today the comment report dialog never calls the server for any reason (`// Implement comment report provider`). W9b sends only the at-risk reason (`report_opinion_comment`), which must reach a person; the other six stay as they are (owner ruling). Owner question 4.
- **P-15 (review queue v0).** `admin_list_priority_reports(p_limit int DEFAULT 50) → jsonb`: pending priority reports on an opinion or a comment, oldest first (then id), at most 200: `{report_id, reason, reported_at, content_type, content_id, excerpt (280 characters), content_removed, hidden_pending_review}`. It never names the reporter. Its gate is `admin_confirm_content_removal`'s (`IF auth.role() <> 'service_role'`): a client JWT is refused, the service role and the SQL editor (no JWT) pass; EXECUTE is the service role's only. The reviewer marks a report with `UPDATE public.forum_reports SET status = …, reviewed_at = now()` (runbook, owner checklist 6).
- **P-16 (`admin_confirm_content_removal`).** The live body (`20260802120000`, identical to `pg_get_functiondef` on `attune_spec3a`) with only: `SET search_path = ''` (every name was already qualified), `v_prev_ban`, the removal notice after the strike count, the ban-extension `SELECT` qualified (`public.profiles AS p … p.banned_until`) and also reading the ban as it was, and the ban notice. "New ban" means no future ban before this removal; "extended" means there was one. A `forum_post` removal gets the removal notice with no item id (forum is retired; Spec 3 W3 later removes that branch from this body). The twin grants `EXECUTE` to `service_role` explicitly (hosted projects already have it by default privileges; the local scratch database did not, and the contract checks it). Task 6 diffs the body against Task 1's saved "before".
- **P-17 (`remove_my_opinion` / `remove_my_comment`).** As §4.3 W9b; the repository calls them and nothing else (no pre-select, no `decrement_opinion_comment_count`). Ungated.
- **P-18 (where "Need support now?" and the at-risk reason go).** Compose: under the text field (and under the filter notice), in `OpinionComposeScreen` and `QuoteComposeScreen`. Post menu (`OpinionMoreData`, used by the feed card and the thread's AppBar): the first row; it closes the menu, then opens Support. Comment menu: the last item, on every comment, mine and others'. Report lists: "Someone may be at risk" first, in both. With seven reasons the post report sheet scrolls (`SingleChildScrollView`, only when the seventh reason is there, so six render exactly as before). The thank-you is a sheet that never animates, with the spec's words, "See emergency numbers" (opens Support) and "Close" (copy the spec doesn't give, P-21); a failed at-risk report says "Couldn't send your report. Please try again." (also new copy). Support is W7's screen and route (`RouteNames.safetyResources`): v2 with `support_resources_v2`, today's screen without it.
- **P-19 (reading the flag).** `opinionsSafetyReadProvider` reads `feature_flags` (`ChatFeatureFlags.isEnabled`), off on any doubt; it is in `refreshedFlagProviders` and listened to by `FeatureFlagRefresher` from app start, so the first menu opened (menus read it once, when they open) already knows. Compose watches it.
- **P-20 (the manual).** One gated passage, "Keeping Opinions safe", in `opinions_docs.dart` (`opinionsSafety` → `opinions_safety_v1` in `DocumentationRegistry._passageFlags`); `documentation_registry_flags_test.dart`'s allow-list gains the flag (one line, as W5 and W7 did).
- **P-21 (copy the spec doesn't give).** "Close" on the at-risk thank-you; "Couldn't send your report. Please try again."; the manual passage. The spec's own strings are used word for word: the three filter reasons, "Need support now?", "Someone may be at risk", the at-risk thank-you and "See emergency numbers", the journal card, "See support", "Not now". The cultural reviewer and the clinician read them at the gates.

**W9c**

- **P-22 (the handler split).** `analyse-journal-entry/index.ts` keeps `serve`, the W1c pause check first and the action dispatch (W1c's source-order test, `journal_pause.test.ts`, passes unchanged); the two actions move verbatim into `journal_handlers.ts` with the provider (`callGeminiJson`), the draft-list flag (`featureFlagEnabled(adminClient, DRAFT_SAFETY_CONTENT_FLAG)`, the way `ai-assist` reads `private_safety_check`) and the count (`bump_metric_server`) injected, so the tests spy on them. The entry is now read with its `title` (the check reads title and text).
- **P-23 (a match also removes the entry's earlier reflection).** `get_journal_entry` shows the newest `reflection_journal_analysis` row whatever text it was written for, so a reflection written for an earlier version of the entry would sit beside words that now read as a crisis. A match therefore deletes that entry's analysis rows (service role). Nothing about the match itself is stored. *Changes spec intent* ("persists nothing" now also removes an old AI note).
- **P-24 (get_patterns).** The newest live entry is checked first (a match → `support_offered`, no provider call, one count); then the analyses' entries are read and every matched one is left out of what the provider sees; an unreadable journal answers 503 and never reaches the provider (fail closed).
- **P-25 (the writer's card in the app).** `analyse_entry` runs when the writer leaves the entry (today's behaviour), so the card is held in memory for this run only (`journalSupportOffersProvider`; never on the phone, never sent) and shown at the top of the journal list, in that entry's footer instead of any reflection, and on the Patterns tab when `get_patterns` answers `support_offered`. "See support" opens Support (counted `support_link_opened:journal`); "Not now" puts it away. This edits `reflection_journal_screen.dart`, which §5.2 doesn't list. *Changes spec intent* (one more file; where the card shows).
- **P-26 (the journal's "Need support now?").** In the entry menu, shown with `journal_ai_insights` (W9c's only flag), so production sees all of W9c only after its clinician gate.
- **P-27 (Healing is not in this plan).** The owner approved O2 ("built in S1 W9 behind `healing_ai_insights`"), but no §2.5, §4.5, §4.7 or §8 row was written for it and the brief scopes W9c to the Journal. Owner question 1. **The follow-on wave is named S1 W9e** (W9 final I-3): the spec already reserves S1 W9d for O4's Opinions enforcement records, after S2 W1; W9e runs straight after W9c and does not wait for S2.

**Fixtures.** `opinion_filter_contracts.sql`: ids `5f9a0000-0000-0000-0000-0000000000NN`, phones `+155586000NN`; `opinion_moderation_notice_contracts.sql`: `5f9b…`, `+155586010NN`; `opinion_remove_own_contracts.sql`: `5f9c…`, `+155586020NN` (spec §7.1's 86xx range), on `auth.users` and `public.users`. Filter fixtures are invented placeholder words (`kɔkɔɔ`, `blorpington`, `zzdraftword`, `fixturetwo`), never real terms.

## Owner questions (open; the plan builds the recommendation where it builds anything)

1. **Healing's AI pause (O2, P-27).** *Recommendation:* plan it as its own small wave, **S1 W9e**, right after W9c and not dependent on S2 W1 (W9 final I-3; not "W9d", which the spec gives O4's Opinions enforcement records after S2 W1): a `healing_ai_insights` flag row (false) and gate row, `detectSelfDisclosure` first in `generate-healing-portrait` and `generate-healing-post-mortem` (same pattern as Task 9), and the Healing screens' support card. Not built here.
2. **One account can still auto-hide a post by reporting it ten times (P-13).** *Recommendation:* fix it in migration 17, ungated, as a third pre-existing Opinions bug: `IF NOT coalesce(v_inserted, false) THEN RETURN; END IF;` in both report RPCs, plus one contract line (a repeat report leaves `report_count` unchanged). Not built (the 2026-11-04 ruling froze other Opinions behaviour).
3. **The filter can be bypassed by a modified client.** `authenticated` still has table `INSERT`/`UPDATE` on `opinions` and `opinion_comments` (owner-only RLS policies), so a client can write content directly, past the filter, the ban and the rate limits. *Recommendation:* before `opinions_safety_v1` goes on in production, a follow-up migration revokes client `INSERT` and `UPDATE` on both tables (after Task 7 the app writes neither directly), with a regression check of the app's writers.
4. **Comment reports never reach the server, except "Someone may be at risk" (P-14).** *Recommendation:* send every reason through `report_opinion_comment` behind `opinions_safety_v1`.
5. **Signed-out readers see no "Need support now?" (P-2).** *Recommendation:* accept for launch (guests can't post or report); add the flag to `get_public_app_config()` in W10 if the owner wants guests to have the link.
6. **Owner nods to confirm:** P-5 (`number_word`), P-23 (old reflection removed), P-25 (where the card shows), D17's restored notice wording (the spec's, not 20260727's).

## W1-W7 interfaces this plan consumes (adjust here if a later fix renames one)

- SQL: `private.spec1_flag_on(text) → boolean` (W1b; `opinions_safety_v1` has no dependency), `private.attune_environment() → text` (W1c; `development` only when unset/`development`, else `production`; a transaction can force it with `set_config('app.settings.attune_environment', 'production', true)`), `private.assert_development_project()` (W1c; raises `env:not_development`), `public.feature_flags (key, enabled)`, `private.flag_production_gates`, `public.bump_metric_server(p_key text)` (W1b; service role; `support_card_shown:journal` is a seeded server prefix), `public.metric_client_keys` (W1b; `opinion_blocked:contact_info|slur|explicit`, `support_link_opened:opinions|journal` seeded, not anon), `private.enqueue_forum_notification(p_user_id, p_title, p_body, p_type, p_opinion_id, p_comment_id, p_forum_post_id) → uuid` (inserts a pending `scheduled_notifications` row with `metadata = {title, body, type, opinion_id?, comment_id?}`; the copy and quiet-hours guards leave the two moderation types alone), `private.assert_can_post(uuid, text)` (ban gate, 5 opinions/24 h with a 60 s cooldown counting any opinion row, 20 comments/24 h), `profiles_guard_moderation_columns` (W1a; acts only for `current_user IN ('authenticated','anon')`), the live writer bodies (`create_opinion`, `edit_opinion`, `create_opinion_comment`, `edit_opinion_comment` from `20260807120000`; `create_opinion_with_poll` from `20260726120000`; `create_opinion_with_quote` from `20260729120000`), `report_opinion` / `report_opinion_comment` / `private.assert_valid_report_reason` from `20260802120000`, `private.is_priority_reason` from `20260716140000`, `admin_confirm_content_removal` from `20260802120000` (all checked against `pg_get_functiondef` on `attune_spec3a`), `public.forum_reports (reported_by, opinion_id, comment_id, forum_post_id, topic_id, reason, priority, status IN ('pending','reviewed_removed','reviewed_kept','escalated'), reviewed_at, created_at)`, the reads `get_discover_opinions(int,int,text[])`, `get_opinions_by_tag(text,int,int)`, `get_following_opinions(int,int)`, `follow_opinion_author(text)`, `public.tags (slug)`, `public.opinion_tags`, `public.reflection_journal_entries (id, user_id, title, content, deleted_at, created_at)`, `public.reflection_journal_analysis (entry_id, user_id, status, observation, tone, input_hash, created_at)`, `public.upsert_journal_analysis(...)`, `public.get_journal_entry(uuid)` (returns the newest analysis row of the entry, whatever its hash).
- Edge: `_shared/self_disclosure.ts` (`detectSelfDisclosure(text, {victimisation}) → "self_harm" | "victimisation" | null`; self-harm is the reviewed sessions corpus), `_shared/feature_flag.ts` (`featureFlagEnabled(client, key)`, `DRAFT_SAFETY_CONTENT_FLAG = "private_safety_check"`), `_shared/gemini_json.ts` (`callGeminiJson`, `STATIC_PROHIBITED_PATTERNS`), `analyse-journal-entry/journal_pause.ts` (`journalInsightsPaused`, `PAUSED_BODY`), `journal_pause.test.ts` (reads `index.ts`: the pause line before both dispatch lines, and `return json(PAUSED_BODY);`).
- Dart: `ClientMetricKey` (`opinionBlockedContactInfo`, `opinionBlockedSlur`, `opinionBlockedExplicit`, `supportLinkOpenedOpinions`, `supportLinkOpenedJournal`), `metricCounterProvider` (`MetricCounter.bump`), `ChatFeatureFlags.isEnabled`, `RouteNames.safetyResources` (`/safety-resources`, W7a's screen under `support_resources_v2`, today's without), `AllowLargeText`, `Spacing`, `BorderRadiusTokens`, `refreshedFlagProviders` and `FeatureFlagRefresher`, `DocumentationRegistry._passageFlags` / `passageVisible`, `documentationFlagsOf`, `opinionRepositoryProvider`, `currentUserIdProvider`, `userRelationshipStatusProvider`, `opinionLiveCountsProvider`, `pollProvider` / `PollNotifier` / `PollTarget`, `OpinionMoreData.getSections` / `showReportReasons`, `postOpinionWithPoll`, `postQuoteOpinion`, `editOpinion`, `postComment`, `editComment`, `deleteComment`, `deleteOpinionProvider`, `ReflectionJournalRepository.analyseEntry` / `getPatterns`, `JournalAnalysis`, `journalListProvider`, `journalPatternsProvider`, `journalEntryDetailProvider`; test helpers `pumpFlowScreen`, `expectFlowGoldens`, `expectFlowGuidelines`, `FlowHarness.metrics` (`test/helpers/flow_harness.dart`), `FakeJournalRepository`, `pumpJournal` (`test/features/reflection_journal/support/`).

## File map

**W9a (Tasks 1-4)**
- Create `test/features/opinions/w9/support/fake_opinions.dart`, `test/features/opinions/w9/opinions_flag_off_test.dart` (+ 6 goldens, written from today's code) (Task 1).
- Create `supabase/functions/_shared/unicode_fold_table.json`, `_shared/unicode_normaliser.ts`, `_shared/unicode_normaliser.test.ts`, `supabase/tests/fixtures/unicode_normaliser_goldens.json` (Task 2).
- Create `supabase/migrations/20261104100000_opinion_content_filter.sql`, `…100010_opinion_content_filter_grants.sql`, `supabase/tests/opinion_filter_contracts.sql`, `supabase/sql/load_content_filter_terms.sql`; modify `scripts/local_pg_grants.sql` (Task 3).
- Create `lib/features/opinions/domain/content_filter_error.dart`, `lib/features/opinions/presentation/widgets/content_filter_notice.dart`, `test/features/opinions/w9/opinion_filter_ui_test.dart` (+ 4 goldens); modify `opinion_compose_screen.dart`, `quote_compose_screen.dart`, `edit_opinion_screen.dart`, `comment_thread_screen.dart` (all under `lib/features/opinions/presentation/screen/`), `lib/i10n/app_en.arb` (+ generated) (Task 4).

**W9b (Tasks 5-8)**
- Create `supabase/migrations/20261104110000_opinion_at_risk_and_review_queue.sql`, `…110010_…_grants.sql`; modify `supabase/tests/opinion_filter_contracts.sql` (section G), `scripts/local_pg_grants.sql` (Task 5).
- Create `supabase/migrations/20261104120000_opinion_moderation_notices.sql`, `…120010_…_grants.sql`, `supabase/tests/opinion_moderation_notice_contracts.sql`; modify `scripts/local_pg_grants.sql` (Task 6).
- Create `supabase/migrations/20261104130000_opinion_remove_own.sql`, `…130010_…_grants.sql`, `supabase/tests/opinion_remove_own_contracts.sql`, `test/features/opinions/w9/opinion_remove_own_repository_test.dart`; modify `lib/features/opinions/data/repositories/opinion_repository.dart` (two methods), `scripts/local_pg_grants.sql` (Task 7).
- Create `lib/features/opinions/presentation/providers/opinions_safety_provider.dart`, `lib/features/opinions/presentation/widgets/need_support_link.dart`, `test/features/opinions/w9/opinions_safety_ui_test.dart` (+ 8 goldens); modify `lib/features/opinions/data/opinion_more_data.dart`, `comment_thread_screen.dart`, `opinion_compose_screen.dart`, `quote_compose_screen.dart`, `lib/app/feature_flag_refresher.dart`, `lib/app/documentations/user_manual/data/opinions_docs.dart`, `…/manual_documentation_registry.dart`, `test/app/documentations/documentation_registry_flags_test.dart` (one line), `lib/i10n/app_en.arb` (+ generated) (Task 8).

**W9c (Tasks 9-10)**
- Create `supabase/functions/analyse-journal-entry/journal_handlers.ts`, `journal_handlers.test.ts`; modify `analyse-journal-entry/index.ts` (Task 9).
- Create `lib/features/reflection_journal/presentation/widgets/journal_support_card.dart`, `test/features/reflection_journal/w9/journal_support_test.dart` (+ 4 goldens); modify `lib/features/reflection_journal/data/models/journal_analysis.dart`, `…/presentation/screens/journal_entry_screen.dart`, `…/presentation/screens/reflection_journal_screen.dart`, `lib/app/feature_flag_refresher.dart`, `lib/app/documentations/user_manual/data/reflection_journal_docs.dart`, `…/manual_documentation_registry.dart`, `test/app/documentations/documentation_registry_flags_test.dart` (one line), `test/features/reflection_journal/support/journal_test_app.dart` (localisations, one route, optional overrides), `lib/i10n/app_en.arb` (+ generated) (Task 10).

**Not edited:** `lib/home/home_screen.dart`, `lib/app/app_shell.dart`, `lib/app/routing/app_router.dart`, `lib/core/notifications/**`, `lib/features/opinions/presentation/widgets/opinion_card.dart`, `opinions_tab.dart`, `lib/features/chat/**`, `lib/features/games/**`, `auth_exports.dart`, `lib/core/flags/public_app_config.dart`, `supabase/config.toml`, `scripts/local_pg_bootstrap.sql`, `supabase/sql/dev_enable_spec1_flags.sql`, `_shared/chat_safety.ts`, `_shared/self_disclosure.ts`, `analyse-journal-entry/journal_pause.ts` and its test, every applied migration, every existing SQL contract, every existing test except the two named one-line allow-list edits and the journal test app's additions.

---

# W9a · Shared normaliser and the pre-post filter (Tasks 1-4)

### Task 1: Baselines, the "before" bodies, and the flag-off goldens from today's code (owner ruling 2026-11-04; §5.6 R10)

**Files:**
- Create: `test/features/opinions/w9/support/fake_opinions.dart`
- Create: `test/features/opinions/w9/opinions_flag_off_test.dart` (+ `goldens/flag_off_{compose,edit,quote,thread,post_menu,report_reasons}.png`)

**Interfaces:**
- Consumes: today's `OpinionComposeScreen`, `EditOpinionScreen`, `QuoteComposeScreen`, `CommentThreadScreen`, `OpinionMoreData`, `OpinionRepository` (faked), `pumpFlowScreen`.
- Produces: `FakeOpinionRepository` (`refuseWith`, `writes`, `reports`, `comments`), `w9Opinion({id, mine, content})`, `w9Comment(id, {mine, content})`, `opinionOverrides(repo)`, `pumpOpinionScreen(tester, screen, {repo, overrides, textScale}) → Future<FlowHarness>`; the six flag-off goldens, which Tasks 4, 8 and 10 run unchanged (never `--update-goldens` on this file after this task). The saved "before" bodies in `.superpowers/sdd/2026-11-04-spec1-w9/before/`.

- [ ] **Step 1: Record the baselines and the "before" bodies**

```bash
psql -X -d attune_spec3a -Atc 'select current_database()'
psql -X -d attune_spec3a -Atc "select current_setting('server_version_num')::int >= 170000"
D=.superpowers/sdd/2026-11-04-spec1-w9
mkdir -p $D/before
ls supabase/migrations | sort | tail -1
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-baseline.txt
grep -c PASS $D/sql-baseline.txt
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error ' | sort > $D/analyze-baseline.txt
sed -n '/if (isAuthenticated && !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum > $D/latch.sha
for sig in 'public.create_opinion(text)' 'public.create_opinion_with_poll(text,text[])' \
           'public.create_opinion_with_quote(text,uuid)' 'public.edit_opinion(uuid,text)' \
           'public.create_opinion_comment(uuid,text,uuid,text)' 'public.edit_opinion_comment(uuid,text)' \
           'public.report_opinion(uuid,text)' 'public.report_opinion_comment(uuid,text)' \
           'private.assert_valid_report_reason(text)' 'private.is_priority_reason(text)' \
           'public.admin_confirm_content_removal(text,uuid)'; do
  n=$(echo "$sig" | sed 's/(.*//')
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before/$n.sql"
done
ls $D/before | wc -l
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env analyse-journal-entry/ 2>&1 | grep -E '^(ok|FAILED) \|')
```

Expected: `attune_spec3a`; `t`; `20261103140110_media_scan_enqueue_grants.sql`; `142` (on the scratch copy used for this plan, with 17 pre-existing FAILs: the fourteen `ai_*` files, `couple_map_presence_contracts.sql`, `reminder_delivery_contracts.sql`, `together_events_contracts.sql`); `11`; `ok | 6 passed | 0 failed`.

- [ ] **Step 2: Write the Opinions test helper**

Create `test/features/opinions/w9/support/fake_opinions.dart` with exactly:

```dart
// Spec 1 W9: Opinions screens on fakes, the way the app shows them (the
// flow harness: app theme, the shell's 1.0 clamp, ScreenUtil, real
// localisations, every other route "at <location>"). Signed in as "me".
import 'package:attune/core/polls/data/models/poll_model.dart';
import 'package:attune/core/polls/presentation/providers/poll_providers.dart';
import 'package:attune/features/opinions/data/models/comment_model.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/data/repositories/opinion_repository.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/flow_harness.dart';

OpinionModel w9Opinion({
  String id = 'o1',
  bool mine = false,
  String content = 'Trust is built in small moments.',
}) => OpinionModel(
  id: id,
  authorHandle: 'quiet-otter',
  isMine: mine,
  content: content,
  relationshipStatus: 'single',
  likeCount: 0,
  dislikeCount: 0,
  commentCount: 2,
  createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
);

CommentModel w9Comment(String id, {required bool mine, String? content}) =>
    CommentModel(
      id: id,
      authorHandle: mine ? 'me' : 'other',
      isMine: mine,
      content:
          content ??
          (mine ? 'My own comment here.' : 'Someone else wrote this.'),
      relationshipStatus: 'single',
      likeCount: 0,
      createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

/// Records every write; [refuseWith] makes every write throw it.
class FakeOpinionRepository implements OpinionRepository {
  Object? refuseWith;
  final writes = <String>[];
  final reports = <String>[];
  List<CommentModel> comments = [
    w9Comment('c-other', mine: false),
    w9Comment('c-mine', mine: true),
  ];

  Future<void> _write(String what) async {
    writes.add(what);
    final error = refuseWith;
    if (error != null) throw error;
  }

  @override
  Future<void> createOpinion({
    required String content,
    List<String>? pollOptions,
    List<String>? tagSlugs,
  }) => _write('create:$content');

  @override
  Future<String> createQuoteOpinion({
    required String content,
    required String quotedOpinionId,
    List<String>? tagSlugs,
  }) async {
    await _write('quote:$content');
    return 'q1';
  }

  @override
  Future<void> editOpinion({
    required String opinionId,
    required String content,
  }) => _write('edit:$content');

  @override
  Future<String> createComment({
    required String opinionId,
    required String content,
    String? replyToCommentId,
    String? quotedText,
  }) async {
    await _write('comment:$content');
    return 'c-new';
  }

  @override
  Future<void> editComment({
    required String commentId,
    required String content,
  }) => _write('edit-comment:$content');

  @override
  Future<void> reportOpinion({
    required String opinionId,
    String reason = 'Other',
  }) async {
    reports.add('opinion:$opinionId:$reason');
    final error = refuseWith;
    if (error != null) throw error;
  }

  @override
  Future<void> reportComment({
    required String commentId,
    String reason = 'Other',
  }) async {
    reports.add('comment:$commentId:$reason');
    final error = refuseWith;
    if (error != null) throw error;
  }

  @override
  Future<List<CommentModel>> getComments(String opinionId) async => comments;

  @override
  Future<OpinionModel?> getQuotedOpinion(String opinionId) async =>
      w9Opinion(id: opinionId);

  @override
  Future<bool> isFollowingAuthor(String authorHandle) async => false;

  @override
  Future<List<String>> getAllTags() async => const ['trust'];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _NoPoll extends PollNotifier {
  @override
  Future<PollModel?> build(PollTarget arg) async => null;
}

/// The overrides every Opinions screen here needs.
List<Override> opinionOverrides(FakeOpinionRepository repo) => [
  opinionRepositoryProvider.overrideWithValue(repo),
  currentUserIdProvider.overrideWithValue('me'),
  userRelationshipStatusProvider.overrideWith((ref) async => 'single'),
  opinionLiveCountsProvider.overrideWith((ref, id) => const Stream.empty()),
  pollProvider.overrideWith(_NoPoll.new),
];

Future<FlowHarness> pumpOpinionScreen(
  WidgetTester tester,
  Widget Function() screen, {
  required FakeOpinionRepository repo,
  List<Override> overrides = const [],
  double textScale = 1.0,
}) => pumpFlowScreen(
  tester,
  screen,
  textScale: textScale,
  overrides: [...opinionOverrides(repo), ...overrides],
);
```

- [ ] **Step 3: Write the flag-off test**

Create `test/features/opinions/w9/opinions_flag_off_test.dart` with exactly:

```dart
// Spec 1 W9 (owner ruling 2026-11-04): with opinions_safety_v1 off, the
// Opinions screens W9 edits look and behave exactly as before W9. The
// goldens below were written from the code BEFORE W9a's first edit (plan
// Task 1, Step 4); every later task runs this file unchanged, without
// --update-goldens. The only ungated change, OPN-DELETE-RLS, is in the
// repository, below the screens.
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/screen/edit_opinion_screen.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/features/opinions/presentation/screen/quote_compose_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_opinions.dart';

Future<void> _golden(String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/flag_off_$name.png'),
);

const _sixReasons = [
  'Identifies a real person',
  'Harmful or dangerous content',
  'Explicit sexual content',
  'Hate speech or discrimination',
  'Spam',
  'Other',
];

void main() {
  testWidgets('compose, edit and quote look as before', (tester) async {
    final repo = FakeOpinionRepository();
    await pumpOpinionScreen(
      tester,
      () => const OpinionComposeScreen(),
      repo: repo,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'A draft that is long enough to post.',
    );
    await tester.pumpAndSettle();
    await _golden('compose');

    await pumpOpinionScreen(
      tester,
      () => EditOpinionScreen(opinion: w9Opinion(mine: true)),
      repo: repo,
    );
    await _golden('edit');

    await pumpOpinionScreen(
      tester,
      () => QuoteComposeScreen(quotedOpinion: w9Opinion()),
      repo: repo,
    );
    await _golden('quote');
  });

  testWidgets('a failed post still says so in a snackbar, draft kept', (
    tester,
  ) async {
    final repo = FakeOpinionRepository()..refuseWith = Exception('network');
    await pumpOpinionScreen(
      tester,
      () => const OpinionComposeScreen(),
      repo: repo,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'A draft that is long enough to post.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to post:'), findsOneWidget);
    expect(find.text('A draft that is long enough to post.'), findsOneWidget);
  });

  testWidgets('the thread, its post menu and both report lists are as before', (
    tester,
  ) async {
    final repo = FakeOpinionRepository();
    final opinion = w9Opinion();
    await pumpOpinionScreen(
      tester,
      () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
      repo: repo,
    );
    await _golden('thread');

    // The post menu (OpinionMoreData): no support row.
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await _golden('post_menu');
    expect(find.text('Need support now?'), findsNothing);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await _golden('report_reasons');
    for (final r in _sixReasons) {
      expect(find.text(r), findsOneWidget, reason: r);
    }
    expect(find.text('Someone may be at risk'), findsNothing);
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    expect(repo.reports, ['opinion:o1:Spam']);
    expect(
      find.text('Thank you. We will review this within 24 hours.'),
      findsOneWidget,
    );
  });

  testWidgets('comment menus and the comment report list are as before', (
    tester,
  ) async {
    final repo = FakeOpinionRepository();
    final opinion = w9Opinion();
    await pumpOpinionScreen(
      tester,
      () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
      repo: repo,
    );
    Iterable<String?> items() => find
        .byType(PopupMenuItem<String>)
        .evaluate()
        .map((e) => ((e.widget as PopupMenuItem<String>).child as Text).data);
    // Top-level comments show newest first: mine (index 0), then the other.
    final menus = find.byIcon(Icons.more_horiz);
    expect(menus, findsNWidgets(2));
    await tester.tap(menus.at(0));
    await tester.pumpAndSettle();
    expect(items(), ['Edit', 'Delete']);
    await tester.tapAt(const Offset(5, 5)); // close the menu
    await tester.pumpAndSettle();
    await tester.tap(menus.at(1));
    await tester.pumpAndSettle();
    expect(items(), ['Report']);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(ListTile),
          )
          .evaluate()
          .map((e) => ((e.widget as ListTile).title as Text).data),
      _sixReasons,
    );
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    // Today a comment report never reaches the server (plan P-14).
    expect(repo.reports, isEmpty);
  });
}
```

- [ ] **Step 4: Write its goldens from today's code (before any W9 edit), and look at them**

```bash
git status --short lib/features/opinions lib/app
flutter test --no-pub test/features/opinions/w9/opinions_flag_off_test.dart --update-goldens 2>&1 | tail -1
ls test/features/opinions/w9/goldens
flutter test --no-pub test/features/opinions/w9/opinions_flag_off_test.dart 2>&1 | tail -1
shasum test/features/opinions/w9/goldens/flag_off_* > .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha
```

Expected: no output from `git status` (nothing under `lib/features/opinions` or `lib/app` is edited yet: these goldens must come from today's code); `All tests passed!`; `flag_off_compose.png flag_off_edit.png flag_off_post_menu.png flag_off_quote.png flag_off_thread.png flag_off_report_reasons.png`; `All tests passed!`. Open each PNG and check it shows the screen (the compose field with the draft and Post; the edit screen; the quote screen with its preview; the thread with the post and two comments; the thread's post menu sheet with Report and Copy text; the six reasons). From here on this file is only ever run **without** `--update-goldens`: a changed pixel with the flag off is a regression, and every gate also checks the six files byte for byte against `flag_off.sha`.

- [ ] **Step 5: Format the new files and run tests**

```bash
dart format test/features/opinions/w9/support/fake_opinions.dart test/features/opinions/w9/opinions_flag_off_test.dart
flutter analyze --no-pub test/features/opinions/w9 2>&1 | tail -1
flutter test --no-pub test/features/opinions/ 2>&1 | tail -1
```

Expected: `Formatted 2 files (0 changed)`; `No issues found!`; `All tests passed!`.

### Task 2: The shared normaliser: fold table, TypeScript port, goldens (§4.3 W9a, §7.2; I-17; P-3, P-11)

**Files:**
- Create: `supabase/functions/_shared/unicode_fold_table.json`
- Create: `supabase/functions/_shared/unicode_normaliser.ts`
- Create: `supabase/functions/_shared/unicode_normaliser.test.ts`
- Create: `supabase/tests/fixtures/unicode_normaliser_goldens.json`

**Interfaces:**
- Consumes: nothing.
- Produces: `unicode_fold_table.json` `{version, about, base: {remove, confusables: {from, to}, digits: {from, to}, separators, kept}, match: {west_african: {from, to, multi: {"ŋ": "ng"}}, leet: {from, to}, separators}}` (the one fold table; Task 3's SQL is written from it and its contract checks every entry); `baseForm(text: string): string`, `matchForm(text: string): string`, `squashedForm(text: string): string` (Spec 2's `_shared/dating_chat_safety.ts` imports these); `unicode_normaliser_goldens.json` `{about, cases: [{name, input, base, match}]}` (32 cases; Task 3's contract runs the same file through SQL).

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/_shared/unicode_normaliser.test.ts` with exactly:

```ts
// Spec 1 W9a (spec 7.2, review I-17): the TypeScript port gives exactly the
// SQL functions' base and match forms for every shared golden, and honours
// every entry of the fold table. opinion_filter_contracts.sql runs the same
// goldens through private.normalize_for_filter / private.match_form.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import table from "./unicode_fold_table.json" with { type: "json" };
import goldens from "../../tests/fixtures/unicode_normaliser_goldens.json" with { type: "json" };
import { baseForm, matchForm, squashedForm } from "./unicode_normaliser.ts";

Deno.test("every shared golden gives the SQL base and match forms", () => {
  if (goldens.cases.length < 30) throw new Error("the goldens file lost cases");
  for (const c of goldens.cases) {
    assertEquals(baseForm(c.input), c.base, `${c.name}: base form`);
    assertEquals(matchForm(c.input), c.match, `${c.name}: match form`);
  }
});

Deno.test("each fold table entry does what it says", () => {
  for (const c of table.base.remove) assertEquals(baseForm(`a${c}b`), "ab", `remove U+${c.codePointAt(0)!.toString(16)}`);
  const pairs = (from: string, to: string) => [...from].map((c, i) => [c, [...to][i]] as const);
  for (const [f, t] of pairs(table.base.confusables.from, table.base.confusables.to)) {
    assertEquals(baseForm(`x${f}x`), `x${t}x`, `confusable U+${f.codePointAt(0)!.toString(16)}`);
  }
  for (const [f, t] of pairs(table.base.digits.from, table.base.digits.to)) assertEquals(baseForm(f), t);
  for (const s of table.base.separators) {
    // NFKC turns a few separators into kept dots (U+2024-U+2026) first.
    const nfkc = `a${s}b`.normalize("NFKC");
    if (nfkc !== `a${s}b`) continue;
    assertEquals(baseForm(`a${s}b`), "a b", `separator U+${s.codePointAt(0)!.toString(16)}`);
  }
  for (const k of table.base.kept) assertEquals(baseForm(`a${k}b`), `a${k}b`, `kept ${k}`);
  for (const [f, t] of pairs(table.match.west_african.from, table.match.west_african.to)) {
    assertEquals(matchForm(`x${f}x`), `x${t}x`);
  }
  for (const [f, t] of Object.entries(table.match.west_african.multi)) assertEquals(matchForm(`x${f}x`), `x${t}x`);
  for (const [f, t] of pairs(table.match.leet.from, table.match.leet.to)) assertEquals(matchForm(`x${f}x`), `x${t}x`);
  for (const s of table.match.separators) assertEquals(matchForm(`a${s}b`), "a b", `match separator ${s}`);
});

Deno.test("a Twi word matches typed with or without its letters", () => {
  assertEquals(matchForm("k\u0254k\u0254\u0254"), matchForm("kokoo"));
  assertEquals(matchForm("\u0190NA"), "ena");
});

Deno.test("the base form keeps what contact and money rules need", () => {
  assertEquals(baseForm("I'm 16"), "i m 16");
  assertEquals(baseForm("Send $40 to kofi@gmail.com"), "send $40 to kofi@gmail.com");
  assertEquals(squashedForm("f u c k"), "fuck");
});
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read _shared/unicode_normaliser.test.ts 2>&1 | grep -E 'TS2307|error:')
```

Expected: three `TS2307 [ERROR]: Cannot find module '…'` lines (the fold table, the goldens, `unicode_normaliser.ts`) and `error: Type checking failed.`

- [ ] **Step 3: Write the fold table and the goldens**

Create `supabase/functions/_shared/unicode_fold_table.json` with exactly:

```json
{
  "version": "2026-11-04.1",
  "about": "Spec 1 W9a (I-17): the one fold table. The SQL functions private.normalize_for_filter and private.match_form (migration 16) and supabase/functions/_shared/unicode_normaliser.ts are written from it; opinion_filter_contracts.sql and unicode_normaliser.test.ts check every entry. Change a rule here, in the migration that re-creates the two SQL functions, and in the goldens, together.",
  "base": {
    "remove": "\u00ad\u200b\u200c\u200d\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2060\u2061\u2062\u2063\u2064\u2066\u2067\u2068\u2069\ufeff",
    "confusables": {
      "from": "\u0430\u0432\u0435\u043a\u043c\u043d\u043e\u0440\u0441\u0442\u0443\u0445\u0455\u0456\u0458\u04bb\u04cf\u04af\u0501\u051b\u051d\u03b1\u03b2\u03b3\u03b5\u03b7\u03b9\u03ba\u03bd\u03bf\u03c1\u03c4\u03c5\u03c7\u03c9\u0131\u0251\u0261",
      "to": "abekmhopctyxsijhlydqwabyenikvoptuxwiag"
    },
    "digits": {
      "from": "\u0660\u0661\u0662\u0663\u0664\u0665\u0666\u0667\u0668\u0669\u06f0\u06f1\u06f2\u06f3\u06f4\u06f5\u06f6\u06f7\u06f8\u06f9\u0966\u0967\u0968\u0969\u096a\u096b\u096c\u096d\u096e\u096f\u09e6\u09e7\u09e8\u09e9\u09ea\u09eb\u09ec\u09ed\u09ee\u09ef",
      "to": "0123456789012345678901234567890123456789"
    },
    "separators": "\u0001\u0002\u0003\u0004\u0005\u0006\u0007\b\t\n\u000b\f\r\u000e\u000f\u0010\u0011\u0012\u0013\u0014\u0015\u0016\u0017\u0018\u0019\u001a\u001b\u001c\u001d\u001e\u001f\u007f!\"#%&'()*-;<=>?[\\]^`{|}~\u0085\u00a0\u00a1\u00a7\u00ab\u00b6\u00b7\u00bb\u00bf\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2010\u2011\u2012\u2013\u2014\u2015\u2016\u2017\u2018\u2019\u201a\u201b\u201c\u201d\u201e\u201f\u2020\u2021\u2022\u2023\u2024\u2025\u2026\u2027\u2028\u2029\u202f\u2030\u2031\u2032\u2033\u2034\u2035\u2036\u2037\u2038\u2039\u203a\u203b\u203c\u203d\u203e\u203f\u2040\u2041\u2042\u2043\u2044\u2045\u2046\u2047\u2048\u2049\u204a\u204b\u204c\u204d\u204e\u204f\u2050\u2051\u2052\u2053\u2054\u2055\u2056\u2057\u2058\u2059\u205a\u205b\u205c\u205d\u205e\u205f\u3000\u3001\u3002\u3008\u3009\u300a\u300b\u300c\u300d\u300e\u300f\u3010\u3011",
    "kept": "$+,./:@_"
  },
  "match": {
    "west_african": {
      "from": "\u025b\u0254\u0192\u028b\u0253\u0257\u0199",
      "to": "eofvbdk",
      "multi": {
        "\u014b": "ng"
      }
    },
    "leet": {
      "from": "013457@$",
      "to": "oieastas"
    },
    "separators": "+,./:_"
  }
}
```

Create `supabase/tests/fixtures/unicode_normaliser_goldens.json` with exactly:

```json
{
  "about": "Spec 1 W9a (I-17): shared normaliser goldens. Each line must give the same base and match form from private.normalize_for_filter / private.match_form (opinion_filter_contracts.sql) and from baseForm / matchForm (unicode_normaliser.test.ts). Spec 2 W6 runs the same file.",
  "cases": [
    {
      "name": "ordinary_gh",
      "input": "Me and my husband have been married since 2015. We live in Kumasi near Kejetia and he sells at Makola on Saturdays.",
      "base": "me and my husband have been married since 2015. we live in kumasi near kejetia and he sells at makola on saturdays.",
      "match": "me and my husband have been married since 2ois we live in kumasi near kejetia and he sells at makola on saturdays"
    },
    {
      "name": "ordinary_ng",
      "input": "Abeg, my oga said make I wait till December before we fix the wedding. Na wa o!",
      "base": "abeg, my oga said make i wait till december before we fix the wedding. na wa o",
      "match": "abeg my oga said make i wait till december before we fix the wedding na wa o"
    },
    {
      "name": "ordinary_uk",
      "input": "We've been together 7 years; I'm knackered, but it's lovely - honestly.",
      "base": "we ve been together 7 years i m knackered, but it s lovely honestly.",
      "match": "we ve been together t years i m knackered but it s lovely honestly"
    },
    {
      "name": "ordinary_money",
      "input": "He wants GH\u20b5 2,500 for the rent and \u20a650,000 for school fees, that's $40.",
      "base": "he wants gh\u20b5 2,500 for the rent and \u20a650,000 for school fees, that s $40.",
      "match": "he wants gh\u20b5 2 soo for the rent and \u20a6so ooo for school fees that s sao"
    },
    {
      "name": "ordinary_years",
      "input": "We met in 1999, broke up in 2004 and got back together in 2010.",
      "base": "we met in 1999, broke up in 2004 and got back together in 2010.",
      "match": "we met in i999 broke up in 2ooa and got back together in 2oio"
    },
    {
      "name": "ordinary_time",
      "input": "Meet me at the mall by 7:30pm on 12/05/2024?",
      "base": "meet me at the mall by 7:30pm on 12/05/2024",
      "match": "meet me at the mall by t eopm on i2 os 2o2a"
    },
    {
      "name": "twi_with_letters",
      "input": "Me d\u0254 wo pa ara, \u0190na me ho y\u025b",
      "base": "me d\u0254 wo pa ara, \u025bna me ho y\u025b",
      "match": "me do wo pa ara ena me ho ye"
    },
    {
      "name": "twi_without_letters",
      "input": "Me do wo pa ara, Ena me ho ye",
      "base": "me do wo pa ara, ena me ho ye",
      "match": "me do wo pa ara ena me ho ye"
    },
    {
      "name": "ewe_hausa_letters",
      "input": "\u0192e \u028bu \u0253a \u0257a \u0199a \u014bk\u0254",
      "base": "\u0192e \u028bu \u0253a \u0257a \u0199a \u014bk\u0254",
      "match": "fe vu ba da ka ngko"
    },
    {
      "name": "zero_width_split",
      "input": "f\u200bu\u200cc\u200dk",
      "base": "fuck",
      "match": "fuck"
    },
    {
      "name": "soft_hyphen_and_bidi",
      "input": "pa\u00adss\u202eword\u202c\u2066x\u2069",
      "base": "passwordx",
      "match": "passwordx"
    },
    {
      "name": "cyrillic_lookalikes",
      "input": "\u0410\u0412\u0421 \u0440\u0430\u0443 \u0435\u0445\u0441\u0435\u0440t",
      "base": "abc pay except",
      "match": "abc pay except"
    },
    {
      "name": "greek_lookalikes",
      "input": "\u039a\u039f\u03a5 \u03b1\u03bd\u03c4\u03b9",
      "base": "kou avti",
      "match": "kou avti"
    },
    {
      "name": "final_sigma",
      "input": "\u039f\u0394\u039f\u03a3 \u03a3",
      "base": "o\u03b4o\u03c3 \u03c3",
      "match": "o\u03b4o\u03c3 \u03c3"
    },
    {
      "name": "dotted_capital_i",
      "input": "\u0130stanbul D\u0130YARBAKIR",
      "base": "istanbul diyarbakir",
      "match": "istanbul diyarbakir"
    },
    {
      "name": "sharp_s",
      "input": "STRA\u1e9eE stra\u00dfe",
      "base": "stra\u00dfe stra\u00dfe",
      "match": "stra\u00dfe stra\u00dfe"
    },
    {
      "name": "fullwidth",
      "input": "\uff26\uff55\uff4c\uff4c \uff57\uff49\uff44\uff54\uff48 \uff10\uff12\uff14",
      "base": "full width 024",
      "match": "full width o2a"
    },
    {
      "name": "math_letters",
      "input": "\ud835\udc1b\ud835\udc1a\ud835\udc1d",
      "base": "bad",
      "match": "bad"
    },
    {
      "name": "arabic_digits",
      "input": "\u0660\u0662\u0664\u0664 \u06f1\u06f2\u06f3 \u0967\u0968",
      "base": "0244 123 12",
      "match": "o2aa i2e i2"
    },
    {
      "name": "leet",
      "input": "b@st4rd 5h1t l33t $10",
      "base": "b@st4rd 5h1t l33t $10",
      "match": "bastard shit leet sio"
    },
    {
      "name": "phone_spaced",
      "input": "Call me on 024 412 3456 or +233 (0)24-412-3456",
      "base": "call me on 024 412 3456 or +233 0 24 412 3456",
      "match": "call me on o2a ai2 eas6 or 2ee o 2a ai2 eas6"
    },
    {
      "name": "phone_words",
      "input": "zero two four four one two three four five six",
      "base": "zero two four four one two three four five six",
      "match": "zero two four four one two three four five six"
    },
    {
      "name": "email",
      "input": "Write to Kofi.Mensah+test@Gmail.COM today",
      "base": "write to kofi.mensah+test@gmail.com today",
      "match": "write to kofi mensah testagmail com today"
    },
    {
      "name": "email_words",
      "input": "kofi (at) gmail [dot] com",
      "base": "kofi at gmail dot com",
      "match": "kofi at gmail dot com"
    },
    {
      "name": "url",
      "input": "https://wa.me/233244123456 www.example.org t.me/kofi",
      "base": "https://wa.me/233244123456 www.example.org t.me/kofi",
      "match": "https wa me 2ee2aai2eas6 www example org t me kofi"
    },
    {
      "name": "handle",
      "input": "Follow @kofi_99 on IG: kofi.99",
      "base": "follow @kofi_99 on ig: kofi.99",
      "match": "follow akofi 99 on ig kofi 99"
    },
    {
      "name": "punctuation_unicode",
      "input": "\u201cHello\u201d \u2014 she said\u2026 \u00abyes\u00bb \u00bfok? \u00a1no!",
      "base": "hello she said... yes ok no",
      "match": "hello she said yes ok no"
    },
    {
      "name": "whitespace_mix",
      "input": "a\tb\nc\r\nd\u00a0e\u2003f\u3000g   h",
      "base": "a b c d e f g h",
      "match": "a b c d e f g h"
    },
    {
      "name": "emoji_kept",
      "input": "I love you \u2764\ufe0f\ud83d\ude0d so much",
      "base": "i love you \u2764\ufe0f\ud83d\ude0d so much",
      "match": "i love you \u2764\ufe0f\ud83d\ude0d so much"
    },
    {
      "name": "accents_kept",
      "input": "Caf\u00e9 na\u00efve \u00c0 bient\u00f4t",
      "base": "caf\u00e9 na\u00efve \u00e0 bient\u00f4t",
      "match": "caf\u00e9 na\u00efve \u00e0 bient\u00f4t"
    },
    {
      "name": "apostrophes",
      "input": "don't won\u2019t it's",
      "base": "don t won t it s",
      "match": "don t won t it s"
    },
    {
      "name": "empty_after",
      "input": "\u200b\u200b  \u00ad",
      "base": "",
      "match": ""
    }
  ]
}
```

Both files are ASCII with `\uXXXX` escapes. A tool may have turned an escape into its character while writing them, so re-serialise both by script (the content is unchanged; the escapes come back) and check them by hash:

```bash
python3 -I - supabase/functions/_shared/unicode_fold_table.json supabase/tests/fixtures/unicode_normaliser_goldens.json <<'PY'
import hashlib, json, pathlib, sys
for f in sys.argv[1:]:
    p = pathlib.Path(f)
    data = json.loads(p.read_text(), strict=False)  # tolerates an escape turned into a raw control character
    p.write_text(json.dumps(data, ensure_ascii=True, indent=2) + "\n")
    print(hashlib.sha256(json.dumps(data, ensure_ascii=True, sort_keys=True).encode()).hexdigest())
PY
grep -cP '[^\x00-\x7F]' supabase/functions/_shared/unicode_fold_table.json supabase/tests/fixtures/unicode_normaliser_goldens.json
```

Expected: `fca87e8a7e5fa23220c4fea44b4a2c168555180426e94281456692acbafc802d`, then `2896513b538d83bb6f9658a4e7a5ccd368ffb7e9325531f3debe11206163594e`; then `…unicode_fold_table.json:0` and `…unicode_normaliser_goldens.json:0`. A different hash means a character was changed or lost: write the file again from this step and re-run the script; never edit the JSON by hand.

- [ ] **Step 4: Write the TypeScript port**

Create `supabase/functions/_shared/unicode_normaliser.ts` with exactly:

```ts
// supabase/functions/_shared/unicode_normaliser.ts
//
// Spec 1 W9a (spec 4.3 W9a, review I-17): the TypeScript port of the one
// shared normaliser. The rules live in ./unicode_fold_table.json, which the
// SQL functions private.normalize_for_filter and private.match_form
// (migration 20261104100000) are written from; the shared goldens
// (supabase/tests/fixtures/unicode_normaliser_goldens.json) must give the
// same output here and in SQL. Spec 2's _shared/dating_chat_safety.ts
// imports this module and has no fold table of its own. The couples
// chat_safety.ts is not touched.
import table from "./unicode_fold_table.json" with { type: "json" };

function charMap(from: string, to: string): Map<string, string> {
  const f = [...from];
  const t = [...to];
  if (f.length !== t.length) throw new Error("unicode_fold_table: from and to differ in length");
  return new Map(f.map((c, i) => [c, t[i]]));
}

const REMOVE = new Set([...table.base.remove]);
const CONFUSABLES = charMap(table.base.confusables.from, table.base.confusables.to);
const DIGITS = charMap(table.base.digits.from, table.base.digits.to);
const SEPARATORS = new Set([...table.base.separators]);
const WEST_AFRICAN = charMap(table.match.west_african.from, table.match.west_african.to);
const WEST_AFRICAN_MULTI = new Map(Object.entries(table.match.west_african.multi as Record<string, string>));
const LEET = charMap(table.match.leet.from, table.match.leet.to);
const MATCH_SEPARATORS = new Set([...table.match.separators]);

// Postgres lowers with the pg_c_utf8 collation: Unicode SIMPLE case mapping,
// one code point at a time. String.prototype.toLowerCase is the FULL
// mapping, which differs only for U+0130 (to "i" + U+0307) and, in context,
// for a final sigma; lowering each code point on its own and special-casing
// U+0130 gives the simple mapping.
function simpleLower(text: string): string {
  let out = "";
  for (const c of text) out += c === "\u0130" ? "i" : c.toLowerCase();
  return out;
}

function collapse(text: string): string {
  return text.replace(/ {2,}/g, " ").replace(/^ +| +$/g, "");
}

/// The base form: NFKC, lower case, invisible and bidi controls removed,
/// look-alikes folded to Latin, other-script digits to 0-9, separators to
/// single spaces. Letters stay as typed; $ + , . / : @ _ are kept.
export function baseForm(text: string): string {
  let out = "";
  for (const c of simpleLower(text.normalize("NFKC"))) {
    if (REMOVE.has(c)) continue;
    const folded = CONFUSABLES.get(c) ?? DIGITS.get(c) ?? c;
    out += SEPARATORS.has(folded) ? " " : folded;
  }
  return collapse(out);
}

/// The match form: the base form, the West African letter fold and the
/// leetspeak fold, then the kept punctuation to spaces. Term lists are
/// stored and matched in this form.
export function matchForm(text: string): string {
  let out = "";
  for (const c of baseForm(text)) {
    const letter = WEST_AFRICAN_MULTI.get(c) ?? WEST_AFRICAN.get(c) ?? c;
    const leet = letter.length === 1 ? (LEET.get(letter) ?? letter) : letter;
    out += MATCH_SEPARATORS.has(leet) ? " " : leet;
  }
  return collapse(out);
}

/// The match form without spaces, for distinctive ("squashed") terms.
export function squashedForm(text: string): string {
  return matchForm(text).replaceAll(" ", "");
}
```

Then put back any escape a tool turned into its character, in both TypeScript files, and check:

```bash
python3 -I - supabase/functions/_shared/unicode_normaliser.ts supabase/functions/_shared/unicode_normaliser.test.ts <<'PY'
import pathlib, sys
for f in sys.argv[1:]:
    p = pathlib.Path(f)
    s = p.read_text()
    p.write_text("".join(c if ord(c) < 128 else "\\u%04x" % ord(c) for c in s))
PY
grep -cP '[^\x00-\x7F]' supabase/functions/_shared/unicode_normaliser.ts supabase/functions/_shared/unicode_normaliser.test.ts
grep -c 'c === "\\u0130"' supabase/functions/_shared/unicode_normaliser.ts
```

Expected: `…unicode_normaliser.ts:0`, `…unicode_normaliser.test.ts:0`; `1`.

- [ ] **Step 5: Run the test and type-check**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read _shared/unicode_normaliser.test.ts 2>&1 | grep -E '^(ok|FAILED) \|')
(cd supabase/functions && NO_COLOR=1 deno check _shared/unicode_normaliser.ts 2>&1 | tail -1)
```

Expected: `ok | 4 passed | 0 failed`; `Check _shared/unicode_normaliser.ts`.

- [ ] **Step 6: Mutation checks (each must turn the test red)**

```bash
(cd supabase/functions && python3 -I - <<'PY'
import os, pathlib, subprocess
p = pathlib.Path('_shared/unicode_normaliser.ts')
orig = p.read_text()
muts = {
 'full_lowercase': ('  for (const c of simpleLower(text.normalize("NFKC"))) {', '  for (const c of text.normalize("NFKC").toLowerCase()) {'),
 'no_dotted_i': ('c === "\\u0130" ? "i" : c.toLowerCase()', 'c.toLowerCase()'),
 'no_remove': ('    if (REMOVE.has(c)) continue;\n', ''),
 'no_multi': ('WEST_AFRICAN_MULTI.get(c) ?? WEST_AFRICAN.get(c)', 'WEST_AFRICAN.get(c)'),
 'no_collapse': ('  return text.replace(/ {2,}/g, " ").replace(/^ +| +$/g, "");', '  return text;'),
}
try:
    for name, (a, b) in muts.items():
        assert orig.count(a) == 1, name
        p.write_text(orig.replace(a, b))
        r = subprocess.run(['deno', 'test', '--allow-read', '_shared/unicode_normaliser.test.ts'],
                           capture_output=True, text=True, env={**os.environ, 'NO_COLOR': '1'})
        print(name, [l for l in r.stdout.splitlines() if l.startswith(('ok |', 'FAILED |'))])
finally:
    p.write_text(orig)
PY
)
(cd supabase/functions && NO_COLOR=1 deno test --allow-read _shared/unicode_normaliser.test.ts 2>&1 | grep -E '^(ok|FAILED) \|')
```

Expected: `full_lowercase ['FAILED | 3 passed | 1 failed …']` (the final-sigma and dotted-I goldens), `no_dotted_i ['FAILED | 3 passed | 1 failed …']`, `no_remove ['FAILED | 2 passed | 2 failed …']`, `no_multi ['FAILED | 2 passed | 2 failed …']`, `no_collapse ['FAILED | 3 passed | 1 failed …']`; then `ok | 4 passed | 0 failed`.

- [ ] **Step 7: Run tests**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env _shared/unicode_normaliser.test.ts _shared/self_disclosure.test.ts analyse-journal-entry/ 2>&1 | grep -E '^(ok|FAILED) \|')
```

Expected: `ok | 14 passed | 0 failed` (4 new, 4 self-disclosure, 6 journal).

### Task 3: Migration 16: the filter in SQL and on the six writers; the [DRAFT] loader (§4.2, §4.3 W9a, §4.7 #16, §5.6 R10, §7.1, §7.4; P-3-P-8, P-12)

**Files:**
- Create: `supabase/migrations/20261104100000_opinion_content_filter.sql`
- Create: `supabase/migrations/20261104100010_opinion_content_filter_grants.sql`
- Create: `supabase/tests/opinion_filter_contracts.sql` (sections A-F; Task 5 appends G)
- Create: `supabase/sql/load_content_filter_terms.sql`
- Modify: `scripts/local_pg_grants.sql` (one `\i` block; never run)

**Interfaces:**
- Consumes: Task 2's two JSON files (the contract reads them); `private.spec1_flag_on`, `private.attune_environment`, `private.assert_development_project`; the six writers' live bodies (Task 1's `before/`).
- Produces: `private.normalize_for_filter(text) → text` and `private.match_form(text) → text` (IMMUTABLE; the base and match forms, equal to Task 2's `baseForm` / `matchForm` on every golden); `private.content_filter_terms (id, family IN ('slur','explicit','number_word'), term (match form), match_mode IN ('token','squashed'), digit, locale, source IN ('draft','reviewed'), review_ref, active, created_at)`; `private.digits_from_words(text) → text`; `private.has_contact_info(text) → boolean`; `private.content_filter_verdict(p_text text, p_families text[]) → text` (NULL, `contact_info`, `slur` or `explicit`; NULL families = all three; Spec 2 calls it for prompts); `private.assert_opinion_content_ok(text)` (raises `content:<verdict>`, SQLSTATE 22023, while `opinions_safety_v1` is on); the six writers each refusing with `content:<reason>`.

- [ ] **Step 1: Write the failing contract**

Create `supabase/tests/opinion_filter_contracts.sql` with exactly:

```sql
-- supabase/tests/opinion_filter_contracts.sql
-- Spec 1 W9a (§4.2, §4.3 W9a, §7.1, §7.4): the shared normaliser and the
-- pre-post content filter. The shared goldens and the fold table go
-- through the SQL forms; the verdict blocks contact details and the term
-- lists and lets ordinary posts through; a draft term never matches
-- outside development; each of the six Opinion writers refuses with
-- content:contact_info / content:slur / content:explicit while
-- opinions_safety_v1 is on, and allows everything while it is off.
-- (W9b appends section G: the at-risk reason and review queue v0.)
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a, from the repo root
-- (the two JSON files are read with \set):
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_filter_contracts.sql
-- Fixture ids 5f9a0000-0000-0000-0000-0000000000NN, phones +155586000NN
-- (spec §7.1's W9 range) on auth.users and public.users. Fixture terms are
-- invented placeholders, not real slurs. Every refusal is checked by its
-- message.
\set goldens `cat supabase/tests/fixtures/unicode_normaliser_goldens.json`
\set fold `cat supabase/functions/_shared/unicode_fold_table.json`
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5f9a0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- The message raised by [p_sql] run as [p_user] (NULL when it ran).
CREATE FUNCTION pg_temp.err_as(p_user uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    v := SQLERRM;
  END;
  RESET ROLE;
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.flag(p_on boolean) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.feature_flags (key, enabled) VALUES ('opinions_safety_v1', p_on)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled;
$$;

-- plpgsql, so the file reaches section A before the migration exists.
CREATE FUNCTION pg_temp.verdict(p_text text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  RETURN private.content_filter_verdict(p_text, NULL);
END $$;

-- Fixtures: six people (one for the refusals and edits, one who wrote the
-- post others comment on, four who each post once, because a post starts
-- a 60-second cooldown).
INSERT INTO auth.users (id, phone)
SELECT pg_temp.id(n), '155586000' || n FROM unnest(ARRAY['01', '02', '03', '04', '05', '06']) AS n
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name)
SELECT pg_temp.id(n), '+155586000' || n, 'W9a ' || n FROM unnest(ARRAY['01', '02', '03', '04', '05', '06']) AS n
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id)
SELECT pg_temp.id(n) FROM unnest(ARRAY['01', '02', '03', '04', '05', '06']) AS n
ON CONFLICT (id) DO NOTHING;
-- Only the fixture terms below: whatever the scratch database holds is set
-- aside (rolled back with the rest).
DO $$
BEGIN
  IF to_regclass('private.content_filter_terms') IS NOT NULL THEN
    DELETE FROM private.content_filter_terms;
  END IF;
END $$;

-- =====================================================================
-- A. Objects and grants: the filter is the database's own; the writers
--    keep their grants (signed-in only).
-- =====================================================================
DO $$
DECLARE
  v_sig text;
BEGIN
  IF to_regclass('private.content_filter_terms') IS NULL
     OR to_regprocedure('private.normalize_for_filter(text)') IS NULL
     OR to_regprocedure('private.match_form(text)') IS NULL
     OR to_regprocedure('private.digits_from_words(text)') IS NULL
     OR to_regprocedure('private.has_contact_info(text)') IS NULL
     OR to_regprocedure('private.content_filter_verdict(text,text[])') IS NULL
     OR to_regprocedure('private.assert_opinion_content_ok(text)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W9a objects are missing';
  END IF;
  IF has_table_privilege('authenticated', 'private.content_filter_terms', 'SELECT')
     OR has_table_privilege('service_role', 'private.content_filter_terms', 'SELECT')
     OR has_table_privilege('anon', 'private.content_filter_terms', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the term lists must have no grants';
  END IF;
  FOREACH v_sig IN ARRAY ARRAY['private.normalize_for_filter(text)', 'private.match_form(text)',
    'private.digits_from_words(text)', 'private.has_contact_info(text)',
    'private.content_filter_verdict(text,text[])', 'private.assert_opinion_content_ok(text)'] LOOP
    IF has_function_privilege('authenticated', v_sig, 'EXECUTE')
       OR has_function_privilege('anon', v_sig, 'EXECUTE')
       OR has_function_privilege('service_role', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % must have no grants', v_sig;
    END IF;
  END LOOP;
  FOREACH v_sig IN ARRAY ARRAY['public.create_opinion(text)', 'public.create_opinion_with_poll(text,text[])',
    'public.create_opinion_with_quote(text,uuid)', 'public.edit_opinion(uuid,text)',
    'public.create_opinion_comment(uuid,text,uuid,text)', 'public.edit_opinion_comment(uuid,text)'] LOOP
    IF NOT has_function_privilege('authenticated', v_sig, 'EXECUTE')
       OR has_function_privilege('anon', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % lost its grants (signed-in only)', v_sig;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- B. The shared goldens give the same base and match forms here as in
--    the TypeScript port (spec §7.1, review I-17).
-- =====================================================================
CREATE TEMP TABLE w9a_goldens ON COMMIT DROP AS
SELECT c->>'name' AS name, c->>'input' AS input, c->>'base' AS base, c->>'match' AS match
  FROM jsonb_array_elements((:'goldens'::jsonb)->'cases') AS c;

DO $$
DECLARE
  r record;
BEGIN
  IF (SELECT count(*) FROM w9a_goldens) < 30 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the goldens file lost cases';
  END IF;
  FOR r IN SELECT * FROM w9a_goldens ORDER BY name LOOP
    IF private.normalize_for_filter(r.input) IS DISTINCT FROM r.base THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: golden % base form is "%", expected "%"',
        r.name, private.normalize_for_filter(r.input), r.base;
    END IF;
    IF private.match_form(r.input) IS DISTINCT FROM r.match THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: golden % match form is "%", expected "%"',
        r.name, private.match_form(r.input), r.match;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- C. The migration's translate() strings equal the fold table: every
--    entry does what the table says, and nothing outside the table changes
--    in the swept blocks (Latin-1 to Cyrillic, General Punctuation, CJK
--    punctuation).
-- =====================================================================
CREATE TEMP TABLE w9a_fold ON COMMIT DROP AS SELECT :'fold'::jsonb AS t;

DO $$
DECLARE
  t constant jsonb := (SELECT w9a_fold.t FROM w9a_fold);
  c text;
  i int;
  v_from text;
  v_to text;
  v_listed text;
  v_cp int;
BEGIN
  FOR c IN SELECT regexp_split_to_table(t #>> '{base,remove}', '') LOOP
    IF private.normalize_for_filter('a' || c || 'b') <> 'ab' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table base.remove U+% is not removed', to_hex(ascii(c));
    END IF;
  END LOOP;
  FOREACH v_from IN ARRAY ARRAY['confusables', 'digits'] LOOP
    v_to := t #>> ARRAY['base', v_from, 'to'];
    FOR i IN 1 .. char_length(t #>> ARRAY['base', v_from, 'from']) LOOP
      c := substr(t #>> ARRAY['base', v_from, 'from'], i, 1);
      IF private.normalize_for_filter('x' || c || 'x') <> 'x' || substr(v_to, i, 1) || 'x' THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: fold table base.% U+% is not folded to %', v_from, to_hex(ascii(c)), substr(v_to, i, 1);
      END IF;
    END LOOP;
  END LOOP;
  FOR c IN SELECT regexp_split_to_table(t #>> '{base,separators}', '') LOOP
    CONTINUE WHEN normalize('a' || c || 'b', NFKC) <> 'a' || c || 'b';  -- NFKC turns it into a kept dot first
    IF private.normalize_for_filter('a' || c || 'b') <> 'a b' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table base.separators U+% is not a separator', to_hex(ascii(c));
    END IF;
  END LOOP;
  FOR c IN SELECT regexp_split_to_table(t #>> '{base,kept}', '') LOOP
    IF private.normalize_for_filter('a' || c || 'b') <> 'a' || c || 'b' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table base.kept % is not kept', c;
    END IF;
  END LOOP;
  FOREACH v_from IN ARRAY ARRAY['west_african', 'leet'] LOOP
    v_to := t #>> ARRAY['match', v_from, 'to'];
    FOR i IN 1 .. char_length(t #>> ARRAY['match', v_from, 'from']) LOOP
      c := substr(t #>> ARRAY['match', v_from, 'from'], i, 1);
      IF private.match_form('x' || c || 'x') <> 'x' || substr(v_to, i, 1) || 'x' THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: fold table match.% % is not folded to %', v_from, c, substr(v_to, i, 1);
      END IF;
    END LOOP;
  END LOOP;
  FOR c, v_to IN SELECT key, value FROM jsonb_each_text(t #> '{match,west_african,multi}') LOOP
    IF private.match_form('x' || c || 'x') <> 'x' || v_to || 'x' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table match.west_african.multi % is not folded to %', c, v_to;
    END IF;
  END LOOP;
  FOR c IN SELECT regexp_split_to_table(t #>> '{match,separators}', '') LOOP
    IF private.match_form('a' || c || 'b') <> 'a b' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fold table match.separators % is not a separator', c;
    END IF;
  END LOOP;
  -- Nothing the table doesn't list is changed (beyond NFKC and lower case).
  v_listed := (t #>> '{base,remove}') || (t #>> '{base,confusables,from}') || (t #>> '{base,digits,from}')
              || (t #>> '{base,separators}') || (t #>> '{base,kept}') || ' ';
  FOR v_cp IN SELECT g FROM generate_series(160, 1327) AS g
              UNION ALL SELECT g FROM generate_series(8192, 8303) AS g
              UNION ALL SELECT g FROM generate_series(12288, 12351) AS g LOOP
    c := chr(v_cp);
    CONTINUE WHEN strpos(v_listed, c) > 0;
    -- NFKC or lower case changes it (or composes it with its neighbours).
    CONTINUE WHEN lower(normalize('a' || c || 'b', NFKC) COLLATE "pg_c_utf8") <> 'a' || c || 'b';
    IF private.normalize_for_filter('a' || c || 'b') <> 'a' || c || 'b' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: U+% is changed by the base form but is not in the fold table', to_hex(v_cp);
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- D. Contact details: blocked in every listed shape; ordinary posts,
--    years, amounts and times pass (spec §4.3 W9a, §9).
-- =====================================================================
DO $$
DECLARE
  v text;
  r record;
BEGIN
  FOREACH v IN ARRAY ARRAY[
    'Call me on 024 412 3456',
    'my number is 0244123456',
    '+233 24 412 3456',
    '+44 7911 123456',
    '00233 24 412 3456',
    '233244123456',
    '(415) 555-0132',
    '415.555.0132',
    '4155550132',
    '+1 415 555 0132',
    '+81 3 1234 5678',
    '0803-123-4567',
    'zero two four four one two three four five six',
    'call oh two four four one two three four five six',
    '024 four one two three four five six',
    'four one five five five five zero one three two',
    'kofi.mensah@gmail.com',
    'write to kofi@school.de',
    'kofi at gmail dot com',
    'kofi (at) yahoo (dot) com',
    'kofi @ hotmail . co . uk',
    'http://example.org',
    'see https://kofi.de/home',
    'see www.mysite.net',
    'www.kofi.de',
    'wa.me/233244123456',
    'wa.me/kofi',
    'come to t.me/kofi',
    'bit.ly/abc123',
    'rb.gy/abc',
    'my site is kofi.com',
    'follow @kofi_99',
    'IG: kofi.99',
    'snap @ kofimensah',
    'telegram:kofi',
    U&'\0660\0662\0664\0664\0661\0662\0663\0664\0665\0666'
  ] LOOP
    IF pg_temp.verdict(v) IS DISTINCT FROM 'contact_info' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: contact details were not caught: "%" gave %', v, pg_temp.verdict(v);
    END IF;
  END LOOP;
  FOREACH v IN ARRAY ARRAY[
    '1999 2004 2010',
    'We met in 1999, broke up in 2004 and got back together in 2010.',
    'I paid 250 000 000 naira for the land',
    'A bridge costs 4 400 000 000 000',
    U&'He wants GH\20B5 2,500,000,000 for the house',
    'Es ist 10.000.000 Euro',
    'Meet me at 7:30pm on 12/05/2024',
    '2024/05/12 13:30',
    'Final scores: 2-0 1-1 0-3 2-2 1-0',
    'I was born in 1990. 2001 was hard',
    'one or two times a week, maybe three',
    'Mr.Mensah said hi.Thanks',
    'I am at home, not @ work',
    'Oh no, oh well'
  ] LOOP
    IF pg_temp.verdict(v) IS NOT NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: an ordinary post was blocked: "%" gave %', v, pg_temp.verdict(v);
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM w9a_goldens WHERE name LIKE 'ordinary_%' OR name LIKE 'twi_%' LOOP
    IF pg_temp.verdict(r.input) IS NOT NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: ordinary golden % was blocked (%)', r.name, pg_temp.verdict(r.input);
    END IF;
  END LOOP;
  IF private.content_filter_verdict('call 0244123456', ARRAY['slur', 'explicit']) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a family that was not asked for was checked';
  END IF;
END $$;

-- =====================================================================
-- E. Term lists: token and squashed matching in the match form; a Twi
--    term typed with e-open/o-open or with e/o; local number words; draft
--    terms only in development (plan P-6). Placeholder terms only.
-- =====================================================================
INSERT INTO private.content_filter_terms (family, term, match_mode, locale, source, review_ref) VALUES
  ('slur', private.match_form(U&'k\0254k\0254\0254'), 'token', 'tw', 'reviewed', 'contract fixture'),
  ('explicit', private.match_form('blorpington'), 'squashed', 'en', 'reviewed', 'contract fixture'),
  ('explicit', private.match_form('zzdraftword'), 'token', 'en', 'draft', NULL);
INSERT INTO private.content_filter_terms (family, term, digit, locale, source, review_ref) VALUES
  ('number_word', private.match_form('fixturetwo'), '2', 'tw', 'reviewed', 'contract fixture');

DO $$
DECLARE
  v_msg text;
BEGIN
  IF pg_temp.verdict(U&'He called me k\0254k\0254\0254 again') IS DISTINCT FROM 'slur'
     OR pg_temp.verdict('He called me KOKOO again') IS DISTINCT FROM 'slur'
     OR pg_temp.verdict('He called me k0k00 again') IS DISTINCT FROM 'slur' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Twi term did not match typed with and without its letters';
  END IF;
  IF pg_temp.verdict('kokoos are red') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a token term matched inside another word';
  END IF;
  IF pg_temp.verdict('b l o r p i n g t o n') IS DISTINCT FROM 'explicit'
     OR pg_temp.verdict(U&'blorp\200Bington') IS DISTINCT FROM 'explicit'
     OR pg_temp.verdict('xblorpingtonx') IS DISTINCT FROM 'explicit' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a squashed term was not matched across separators';
  END IF;
  IF pg_temp.verdict('a zzdraftword here') IS DISTINCT FROM 'explicit' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft term did not match in development';
  END IF;
  IF pg_temp.verdict('024 fixturetwo four four one two three four five six') IS DISTINCT FROM 'contact_info'
     OR private.digits_from_words('fixturetwo') <> '2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reviewed local number word was not read as a digit';
  END IF;
  -- Production: draft terms are inert; reviewed terms still match.
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF pg_temp.verdict('a zzdraftword here') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft term matched outside development';
  END IF;
  IF pg_temp.verdict('He called me kokoo again') IS DISTINCT FROM 'slur' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reviewed term stopped matching in production';
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  -- A term must be stored in the match form; a reviewed one names its review.
  BEGIN
    INSERT INTO private.content_filter_terms (family, term, source) VALUES ('slur', U&'K\0254k\0254', 'draft');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a term not in the match form was stored';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg <> 'content_filter_terms_term_check' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong check %', v_msg; END IF;
  END;
  BEGIN
    INSERT INTO private.content_filter_terms (family, term, source) VALUES ('slur', 'unreviewed', 'reviewed');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reviewed term without its review was stored';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg <> 'content_filter_terms_reviewed_check' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong check %', v_msg; END IF;
  END;
  BEGIN
    INSERT INTO private.content_filter_terms (family, term, match_mode, source) VALUES ('slur', 'abc', 'squashed', 'draft');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a short squashed term was stored';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg <> 'content_filter_terms_squashed_check' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong check %', v_msg; END IF;
  END;
END $$;

-- =====================================================================
-- F. The six writers (spec §4.3 W9a, §7.4): flag on, each refuses by
--    reason before anything is written; flag off, each allows the same
--    text.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.id('01');
  v_own_opinion uuid;
  v_own_comment uuid;
  v_target uuid;
  v_before int;
  v_case record;
BEGIN
  INSERT INTO public.opinions (user_id, content) VALUES (pg_temp.id('04'), 'W9a contract: a post to comment on and quote.')
  RETURNING id INTO v_target;
  INSERT INTO public.opinions (user_id, content) VALUES (v_u, 'W9a contract: my own post, to edit.')
  RETURNING id INTO v_own_opinion;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content) VALUES (v_target, v_u, 'W9a contract: my own comment.')
  RETURNING id INTO v_own_comment;
  PERFORM pg_temp.flag(true);
  SELECT count(*) INTO v_before FROM public.opinions;

  FOR v_case IN
    SELECT * FROM (VALUES
      ('contact_info', 'Call me on 0244123456 tonight'),
      ('slur', 'He called me kokoo again'),
      ('explicit', 'She sent b l o r p i n g t o n')
    ) AS x(reason, body)
  LOOP
    IF pg_temp.err_as(v_u, format('SELECT public.create_opinion(%L)', v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', ''No''])', v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', %L])', 'W9a contract: an ordinary question?', v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_quote(%L, %L)', v_case.body, v_target)) IS DISTINCT FROM 'content:' || v_case.reason
       -- before the target is looked up: an unknown target still gets the content reason
       OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_quote(%L, %L)', v_case.body, gen_random_uuid())) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.edit_opinion(%L, %L)', v_own_opinion, v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_comment(%L, %L)', v_target, v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_comment(%L, %L, NULL, %L)', v_target, 'W9a contract: I agree.', v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason
       OR pg_temp.err_as(v_u, format('SELECT public.edit_opinion_comment(%L, %L)', v_own_comment, v_case.body)) IS DISTINCT FROM 'content:' || v_case.reason THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a writer did not refuse % with content:% (create %, poll %, poll option %, quote %, quote unknown %, edit %, comment %, quoted text %, edit comment %)',
        v_case.body, v_case.reason,
        pg_temp.err_as(v_u, format('SELECT public.create_opinion(%L)', v_case.body)),
        pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', ''No''])', v_case.body)),
        pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', %L])', 'W9a contract: an ordinary question?', v_case.body)),
        pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_quote(%L, %L)', v_case.body, v_target)),
        pg_temp.err_as(v_u, format('SELECT public.create_opinion_with_quote(%L, %L)', v_case.body, gen_random_uuid())),
        pg_temp.err_as(v_u, format('SELECT public.edit_opinion(%L, %L)', v_own_opinion, v_case.body)),
        pg_temp.err_as(v_u, format('SELECT public.create_opinion_comment(%L, %L)', v_target, v_case.body)),
        pg_temp.err_as(v_u, format('SELECT public.create_opinion_comment(%L, %L, NULL, %L)', v_target, 'W9a contract: I agree.', v_case.body)),
        pg_temp.err_as(v_u, format('SELECT public.edit_opinion_comment(%L, %L)', v_own_comment, v_case.body));
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.opinions) <> v_before
     OR (SELECT content FROM public.opinions WHERE id = v_own_opinion) <> 'W9a contract: my own post, to edit.'
     OR (SELECT count(*) FROM public.opinion_comments WHERE opinion_id = v_target) <> 1
     OR (SELECT content FROM public.opinion_comments WHERE id = v_own_comment) <> 'W9a contract: my own comment.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused post or edit still wrote something';
  END IF;
  -- An ordinary post still goes through with the filter on.
  IF pg_temp.err_as(pg_temp.id('05'), 'SELECT public.create_opinion(''W9a contract: we met in 1999 and married in 2004.'')') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ordinary post was refused with the filter on';
  END IF;

  -- Flag off: no filter; each writer allows the same text.
  PERFORM pg_temp.flag(false);
  IF pg_temp.err_as(pg_temp.id('02'), 'SELECT public.create_opinion(''Call me on 0244123456 tonight'')') IS NOT NULL
     OR pg_temp.err_as(pg_temp.id('03'), format('SELECT public.create_opinion_with_poll(%L, ARRAY[''Yes'', %L])', 'He called me kokoo again', 'Call 0244123456')) IS NOT NULL
     OR pg_temp.err_as(v_u, format('SELECT public.edit_opinion(%L, %L)', v_own_opinion, 'She sent b l o r p i n g t o n')) IS NOT NULL
     OR pg_temp.err_as(v_u, format('SELECT public.create_opinion_comment(%L, %L, NULL, %L)', v_target, 'Call me on 0244123456', 'kokoo')) IS NOT NULL
     OR pg_temp.err_as(v_u, format('SELECT public.edit_opinion_comment(%L, %L)', v_own_comment, 'He called me kokoo again')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with opinions_safety_v1 off, a writer still filtered';
  END IF;
  IF pg_temp.err_as(pg_temp.id('06'), format('SELECT public.create_opinion_with_quote(%L, %L)', 'wa.me/233244123456', v_target)) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with opinions_safety_v1 off, create_opinion_with_quote still filtered';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'opinion_filter_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_filter_contracts.sql 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  CONTRACT VIOLATED: W9a objects are missing`.

- [ ] **Step 3: Write migration 16 and its twin**

Create `supabase/migrations/20261104100000_opinion_content_filter.sql` with exactly:

```sql
-- Spec 1 W9a, migration 16 (spec §4.7 #16): the shared normaliser and the
-- pre-post content filter for Opinions.
--   * private.normalize_for_filter(text): the BASE form (spec §4.3 W9a,
--     review I-17): NFKC, lower case (Unicode simple case mapping, the
--     pg_c_utf8 collation, so every database folds alike), invisible and
--     bidi controls removed, Cyrillic and Greek look-alikes folded to Latin,
--     Arabic-Indic, Devanagari and Bengali digits to 0-9, separators
--     (whitespace, ASCII and common Unicode punctuation) to single spaces.
--     Letters stay as typed (e-open, o-open and eng stay) and $ + , . / : @ _
--     are kept, so contact details and amounts keep their meaning.
--   * private.match_form(text): the base form plus the West African letter
--     fold and the leetspeak fold, then the kept punctuation to spaces.
--     Filter terms are stored and matched in this form.
--   * Both are written from supabase/functions/_shared/unicode_fold_table.json
--     (the one fold table; the TypeScript port reads the same file);
--     opinion_filter_contracts.sql checks every entry and the shared goldens.
--   * private.content_filter_terms: slur, explicit and local number words
--     (plan P-5). Development holds a small [DRAFT] English list
--     (supabase/sql/load_content_filter_terms.sql); production holds only
--     reviewed lists (the W9a gate). A draft term never matches outside
--     development (plan P-6).
--   * private.digits_from_words, private.has_contact_info,
--     private.content_filter_verdict (Spec 2 calls this for prompts) and
--     private.assert_opinion_content_ok (opinions_safety_v1; off: nothing).
--   * The six Opinion writers, re-created from their live bodies
--     (20260807120000 create_opinion, edit_opinion, create_opinion_comment;
--     20260726120000 create_opinion_with_poll; 20260729120000
--     create_opinion_with_quote; 20260807120000 edit_opinion_comment),
--     checked identical to pg_get_functiondef on attune_spec3a while writing
--     the plan, each with ONE added line: the assert call (spec §5.6 R10).
-- Nothing is stored about a blocked post; the app counts opinion_blocked:*.
-- Grants in 20261104100010_opinion_content_filter_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------------
-- The two forms (from unicode_fold_table.json).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.normalize_for_filter(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $fn$
  SELECT pg_catalog.btrim(pg_catalog.regexp_replace(
    pg_catalog.translate(
      pg_catalog.translate(
        pg_catalog.translate(
          pg_catalog.translate(
            pg_catalog.lower(pg_catalog.normalize(p_text, 'NFKC') COLLATE "pg_c_utf8"),
            -- base.remove
            U&'\00AD\200B\200C\200D\200E\200F\202A\202B\202C\202D\202E\2060\2061\2062\2063\2064\2066\2067\2068\2069\FEFF',
            ''),
          -- base.confusables
          U&'\0430\0432\0435\043A\043C\043D\043E\0440\0441\0442\0443\0445\0455\0456\0458\04BB\04CF\04AF\0501\051B\051D\03B1\03B2\03B3\03B5\03B7\03B9\03BA\03BD\03BF\03C1\03C4\03C5\03C7\03C9\0131\0251\0261',
          'abekmhopctyxsijhlydqwabyenikvoptuxwiag'),
        -- base.digits
        U&'\0660\0661\0662\0663\0664\0665\0666\0667\0668\0669\06F0\06F1\06F2\06F3\06F4\06F5\06F6\06F7\06F8\06F9\0966\0967\0968\0969\096A\096B\096C\096D\096E\096F\09E6\09E7\09E8\09E9\09EA\09EB\09EC\09ED\09EE\09EF',
        '0123456789012345678901234567890123456789'),
      -- base.separators (165 characters, each to a space)
      U&'\0001\0002\0003\0004\0005\0006\0007\0008\0009\000A\000B\000C\000D\000E\000F\0010\0011\0012\0013\0014\0015\0016\0017\0018\0019\001A\001B\001C\001D\001E\001F\007F!"#%&''()*-;<=>?[\005C]^`{|}~\0085\00A0\00A1\00A7\00AB\00B6\00B7\00BB\00BF\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2010\2011\2012\2013\2014\2015\2016\2017\2018\2019\201A\201B\201C\201D\201E\201F\2020\2021\2022\2023\2024\2025\2026\2027\2028\2029\202F\2030\2031\2032\2033\2034\2035\2036\2037\2038\2039\203A\203B\203C\203D\203E\203F\2040\2041\2042\2043\2044\2045\2046\2047\2048\2049\204A\204B\204C\204D\204E\204F\2050\2051\2052\2053\2054\2055\2056\2057\2058\2059\205A\205B\205C\205D\205E\205F\3000\3001\3002\3008\3009\300A\300B\300C\300D\300E\300F\3010\3011',
      pg_catalog.repeat(' ', 165)),
    ' {2,}', ' ', 'g'));
$fn$;

CREATE OR REPLACE FUNCTION private.match_form(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $fn$
  SELECT pg_catalog.btrim(pg_catalog.regexp_replace(
    pg_catalog.translate(
      pg_catalog.translate(
        pg_catalog.replace(
          -- match.west_african (one to one), then its multi entry
          pg_catalog.translate(private.normalize_for_filter(p_text),
            U&'\025B\0254\0192\028B\0253\0257\0199', 'eofvbdk'),
          U&'\014B', 'ng'),
        -- match.leet
        '013457@$', 'oieastas'),
      -- match.separators
      '+,./:_', '      '),
    ' {2,}', ' ', 'g'));
$fn$;

-- ---------------------------------------------------------------------
-- The term lists (spec §4.2; plan P-5, P-6).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS private.content_filter_terms (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  family text NOT NULL
    CONSTRAINT content_filter_terms_family_check CHECK (family IN ('slur', 'explicit', 'number_word')),
  -- Stored in the match form, so one spelling covers a Twi word typed with
  -- or without e-open/o-open, and leetspeak.
  term text NOT NULL
    CONSTRAINT content_filter_terms_term_check
      CHECK (term <> '' AND term = private.match_form(term) AND char_length(term) <= 80),
  match_mode text NOT NULL DEFAULT 'token'
    CONSTRAINT content_filter_terms_mode_check CHECK (match_mode IN ('token', 'squashed')),
  -- number_word only: the digit the word stands for.
  digit text NULL
    CONSTRAINT content_filter_terms_digit_check CHECK (digit IS NULL OR digit ~ '^[0-9]$'),
  locale text NOT NULL DEFAULT 'en'
    CONSTRAINT content_filter_terms_locale_check CHECK (locale ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$'),
  source text NOT NULL
    CONSTRAINT content_filter_terms_source_check CHECK (source IN ('draft', 'reviewed')),
  review_ref text NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT content_filter_terms_digit_family_check CHECK ((family = 'number_word') = (digit IS NOT NULL)),
  -- Squashed (separator-free) matching only for long, distinctive terms,
  -- and never for number words (spec §9: ordinary posts must pass).
  CONSTRAINT content_filter_terms_squashed_check
    CHECK (match_mode = 'token' OR (family <> 'number_word' AND char_length(replace(term, ' ', '')) >= 5)),
  CONSTRAINT content_filter_terms_reviewed_check CHECK (source = 'draft' OR review_ref IS NOT NULL),
  CONSTRAINT content_filter_terms_unique UNIQUE (family, term, locale)
);
REVOKE ALL ON private.content_filter_terms FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- Digit words (spec §4.3 W9a): English zero..nine, "oh" next to a digit,
-- and the reviewed local number words. Digit words next to each other are
-- joined into one group, so "zero two four four ..." reads as 0244...
-- Takes the base form.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.digits_from_words(p_text text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_tokens text[];
  v_digit text[];
  v_out text := '';
  v_prev_word boolean := false;
  v_dev boolean;
  v_local text;
  v_n int;
  i int;
BEGIN
  IF p_text IS NULL OR p_text = '' THEN
    RETURN p_text;
  END IF;
  v_dev := private.attune_environment() = 'development';
  v_tokens := pg_catalog.string_to_array(p_text, ' ');
  v_n := pg_catalog.array_length(v_tokens, 1);
  v_digit := pg_catalog.array_fill(NULL::text, ARRAY[v_n]);
  FOR i IN 1 .. v_n LOOP
    v_digit[i] := CASE v_tokens[i]
                    WHEN 'zero' THEN '0' WHEN 'one' THEN '1' WHEN 'two' THEN '2'
                    WHEN 'three' THEN '3' WHEN 'four' THEN '4' WHEN 'five' THEN '5'
                    WHEN 'six' THEN '6' WHEN 'seven' THEN '7' WHEN 'eight' THEN '8'
                    WHEN 'nine' THEN '9'
                  END;
    IF v_digit[i] IS NULL THEN
      SELECT t.digit INTO v_local
        FROM private.content_filter_terms AS t
       WHERE t.family = 'number_word' AND t.active
         AND (t.source = 'reviewed' OR v_dev)
         AND t.term = private.match_form(v_tokens[i])
       ORDER BY t.id
       LIMIT 1;
      v_digit[i] := v_local;
    END IF;
  END LOOP;
  -- "oh" / "o" only inside a run: next to a digit word or a numeral.
  FOR i IN 1 .. v_n LOOP
    IF v_digit[i] IS NULL AND v_tokens[i] IN ('oh', 'o')
       AND ((i > 1 AND (v_digit[i - 1] IS NOT NULL OR v_tokens[i - 1] ~ '^[0-9]+$'))
         OR (i < v_n AND (v_digit[i + 1] IS NOT NULL OR v_tokens[i + 1] ~ '^[0-9]+$'))) THEN
      v_digit[i] := '0';
    END IF;
  END LOOP;
  FOR i IN 1 .. v_n LOOP
    IF v_digit[i] IS NOT NULL THEN
      v_out := v_out || CASE WHEN v_prev_word THEN '' WHEN i = 1 THEN '' ELSE ' ' END || v_digit[i];
      v_prev_word := true;
    ELSE
      v_out := v_out || CASE WHEN i = 1 THEN '' ELSE ' ' END || v_tokens[i];
      v_prev_word := false;
    END IF;
  END LOOP;
  RETURN v_out;
END;
$fn$;

-- ---------------------------------------------------------------------
-- Contact details (spec §4.3 W9a), on the base form after digit words.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.has_contact_info(p_text text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $fn$
DECLARE
  m text[];
  v_groups text[];
  v_digits text;
  v_lens int[];
  v_n int;
  g text;
  v_years boolean;
  v_thousands boolean;
BEGIN
  IF p_text IS NULL OR p_text = '' THEN
    RETURN false;
  END IF;

  -- Phone numbers: a run of 9-15 digits joined by at most single
  -- separators (the base form has already turned - ( ) into spaces).
  FOR m IN SELECT pg_catalog.regexp_matches(p_text, '(\+ ?)?([0-9]+(?:[ ./][0-9]+)*)', 'g') LOOP
    v_groups := pg_catalog.regexp_split_to_array(m[2], '[ ./]');
    v_digits := pg_catalog.array_to_string(v_groups, '');
    v_n := char_length(v_digits);
    CONTINUE WHEN v_n < 9 OR v_n > 15;
    -- Years: "1999 2004 2010".
    v_years := true;
    FOREACH g IN ARRAY v_groups LOOP
      IF g !~ '^(19|20)[0-9]{2}$' THEN v_years := false; END IF;
    END LOOP;
    CONTINUE WHEN v_years;
    IF m[1] IS NOT NULL THEN
      RETURN true;                                   -- +233 ..., + 44 ...
    END IF;
    -- Amounts grouped in thousands: "250 000 000".
    v_thousands := pg_catalog.array_length(v_groups, 1) >= 3 AND v_groups[1] ~ '^[1-9][0-9]{0,2}$';
    IF v_thousands THEN
      FOR i IN 2 .. pg_catalog.array_length(v_groups, 1) LOOP
        IF v_groups[i] !~ '^[0-9]{3}$' THEN v_thousands := false; END IF;
      END LOOP;
    END IF;
    CONTINUE WHEN v_thousands;
    IF v_digits ~ '^0' THEN
      RETURN true;                                   -- 024..., 00233...
    END IF;
    SELECT pg_catalog.array_agg(char_length(x) ORDER BY o) INTO v_lens
      FROM pg_catalog.unnest(v_groups) WITH ORDINALITY AS u(x, o);
    IF (v_lens = ARRAY[3, 3, 4] OR v_lens = ARRAY[10]) AND v_digits ~ '^[2-9][0-9]{2}[2-9]' THEN
      RETURN true;                                   -- NANP (415) 555-0132
    END IF;
    IF (v_lens = ARRAY[1, 3, 3, 4] OR v_lens = ARRAY[11]) AND v_digits ~ '^1[2-9][0-9]{2}[2-9]' THEN
      RETURN true;                                   -- NANP with its 1
    END IF;
    IF v_n >= 11 AND v_digits ~ '^(233|234|44|27|254|255|256|225|237|221|229|228|226|231|232|220|353|49|33|31|91|971|966|86|1)' THEN
      RETURN true;                                   -- a calling code, no +
    END IF;
  END LOOP;

  RETURN
    -- E-mail addresses, and "at ... dot ..." for common providers.
    p_text ~ '[a-z0-9._+]+@[a-z0-9]+(\.[a-z0-9]+)*\.[a-z]{2,}'
    OR p_text ~ '\m[a-z0-9._]+ ?(@|\mat\M) ?(gmail|googlemail|yahoo|ymail|hotmail|outlook|live|msn|icloud|aol|proton|protonmail|gmx|zoho|yandex) ?(\.|\mdot\M) ?(com|net|org|co|me|ch|uk|de|fr|gh|ng)\M'
    -- Links: schemes, www., WhatsApp and Telegram links, short-link
    -- hosts, bare domains on a fixed list of endings (plan P-7).
    OR p_text ~ '\mhttps?:/'
    OR p_text ~ '\mwww\.[a-z0-9]'
    OR p_text ~ '\m(wa|t)\.me\M'
    OR p_text ~ '\m(bit\.ly|tinyurl\.com|t\.co|goo\.gl|ow\.ly|is\.gd|buff\.ly|cutt\.ly|rb\.gy|shorturl\.at|tiny\.cc|linktr\.ee)\M'
    OR p_text ~ '\m[a-z0-9]+\.(com|net|org|info|biz|io|xyz|ly|gh|ng|uk)\M'
    -- @handles of three or more characters.
    OR p_text ~ '(^|[^a-z0-9._@])@[a-z0-9._]{3,}'
    -- A platform name, then ":" or "@", then a handle.
    OR p_text ~ '\m(instagram|insta|ig|snapchat|snap|tiktok|telegram|tg|whatsapp|signal|twitter|facebook|fb|threads) ?[:@] ?[a-z0-9._]{3,}';
END;
$fn$;

-- ---------------------------------------------------------------------
-- The verdict (spec §4.3 W9a): NULL, or the first hit of contact_info,
-- slur, explicit, among p_families (NULL = all three). Spec 2 calls this
-- for prompts.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.content_filter_verdict(p_text text, p_families text[])
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_families constant text[] := coalesce(p_families, ARRAY['contact_info', 'slur', 'explicit']);
  v_base text;
  v_match text;
  v_squashed text;
  v_dev boolean;
  v_family text;
BEGIN
  IF p_text IS NULL OR btrim(p_text) = '' THEN
    RETURN NULL;
  END IF;
  v_base := private.normalize_for_filter(p_text);
  IF 'contact_info' = ANY (v_families) AND private.has_contact_info(private.digits_from_words(v_base)) THEN
    RETURN 'contact_info';
  END IF;
  v_match := ' ' || private.match_form(p_text) || ' ';
  v_squashed := replace(v_match, ' ', '');
  v_dev := private.attune_environment() = 'development';
  FOREACH v_family IN ARRAY ARRAY['slur', 'explicit'] LOOP
    CONTINUE WHEN NOT (v_family = ANY (v_families));
    IF EXISTS (
      SELECT 1
        FROM private.content_filter_terms AS t
       WHERE t.family = v_family
         AND t.active
         AND (t.source = 'reviewed' OR v_dev)
         AND (strpos(v_match, ' ' || t.term || ' ') > 0
              OR (t.match_mode = 'squashed' AND strpos(v_squashed, replace(t.term, ' ', '')) > 0))
    ) THEN
      RETURN v_family;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$fn$;

-- opinions_safety_v1 on: a verdict refuses the post with content:{verdict}.
-- Off (or unreadable): nothing is checked.
CREATE OR REPLACE FUNCTION private.assert_opinion_content_ok(p_text text)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_verdict text;
BEGIN
  IF p_text IS NULL OR NOT private.spec1_flag_on('opinions_safety_v1') THEN
    RETURN;
  END IF;
  v_verdict := private.content_filter_verdict(p_text, ARRAY['contact_info', 'slur', 'explicit']);
  IF v_verdict IS NOT NULL THEN
    RAISE EXCEPTION 'content:%', v_verdict USING ERRCODE = '22023';
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION private.normalize_for_filter(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.match_form(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.digits_from_words(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.has_contact_info(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.content_filter_verdict(text, text[]) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.assert_opinion_content_ok(text) FROM PUBLIC, anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- The six writers: live bodies, one added line each (marked W9a).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_opinion(p_content text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 5000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;
  PERFORM private.assert_opinion_content_ok(p_content); -- Spec 1 W9a

  PERFORM private.assert_can_post(v_uid, 'opinion');

  SELECT relationship_status INTO v_status FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.opinions (user_id, content, relationship_status_at_post)
  VALUES (v_uid, p_content, v_status)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_opinion_with_poll(p_content text, p_poll_options text[] DEFAULT NULL::text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM private.assert_opinion_content_ok(t) FROM unnest(array_prepend(p_content, coalesce(p_poll_options, '{}'::text[]))) AS t; -- Spec 1 W9a

  v_id := public.create_opinion(p_content);

  IF p_poll_options IS NOT NULL AND array_length(p_poll_options, 1) IS NOT NULL THEN
    PERFORM private.create_poll_for_post(v_uid, v_id, NULL, p_poll_options);
  END IF;

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_opinion_with_quote(p_content text, p_quoted_opinion_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_target_id uuid;
  v_target_author uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_quoted_opinion_id IS NULL THEN
    RAISE EXCEPTION 'quote_requires_target' USING ERRCODE = '22023';
  END IF;
  PERFORM private.assert_opinion_content_ok(p_content); -- Spec 1 W9a

  -- Resolve to the ORIGINAL. If the caller quoted something that is itself a
  -- quote, re-target to what THAT quotes -- quoted_opinion_id is never
  -- non-null on the row this ends up pointing at, so the chain can never
  -- exceed one hop no matter how many times a quote gets quoted.
  SELECT COALESCE(o.quoted_opinion_id, o.id), COALESCE(orig.user_id, o.user_id)
  INTO v_target_id, v_target_author
  FROM public.opinions o
  LEFT JOIN public.opinions orig ON orig.id = o.quoted_opinion_id
  WHERE o.id = p_quoted_opinion_id;

  -- Deliberately NOT gated on removed_at/hidden_pending_review: unlike
  -- repost_opinion (which refuses to reference something invisible in every
  -- feed), a quote's own text stands on its own even if the original it
  -- references is already gone by the time this call runs -- the read path
  -- (get_quoted_opinion) is what handles a vanished original, not creation.
  IF v_target_id IS NULL THEN
    RAISE EXCEPTION 'opinion_not_found' USING ERRCODE = 'P0002';
  END IF;

  v_id := public.create_opinion(p_content);

  UPDATE public.opinions
  SET quoted_opinion_id = v_target_id
  WHERE id = v_id;

  -- "Someone quoted your opinion" (FORUM.md §10 #10), skipped on self-quote --
  -- spec is explicit that a self-quote does not notify. Same
  -- private.enqueue_forum_notification helper as likes/comments/replies/
  -- reposts, which takes no actor-id parameter -- an anonymity leak here is
  -- structurally inexpressible, not merely a convention to remember.
  IF v_target_author IS NOT NULL AND v_target_author <> v_uid THEN
    PERFORM private.enqueue_forum_notification(
      p_user_id    => v_target_author,
      p_title      => 'New quote',
      p_body       => 'Someone quoted your opinion',
      p_type       => 'opinion_quoted',
      p_opinion_id => v_target_id
    );
  END IF;

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.edit_opinion(p_opinion_id uuid, p_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_updated_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 5000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;
  PERFORM private.assert_opinion_content_ok(p_content); -- Spec 1 W9a

  UPDATE public.opinions
  SET content = p_content, edited_at = now()
  WHERE id = p_opinion_id
    AND user_id = v_uid
    AND removed_at IS NULL
    AND created_at > now() - interval '15 minutes'
  RETURNING id INTO v_updated_id;

  -- Covers three distinct cases with one message, deliberately: wrong owner,
  -- already removed, and window expired all mean the same thing to the
  -- caller -- "you cannot edit this right now" -- and none should leak which
  -- specific reason applies (e.g. distinguishing "not yours" from "removed"
  -- would confirm to a non-owner that a specific opinion exists and its
  -- moderation state, which is not this RPC's business to reveal).
  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'not_editable' USING ERRCODE = '42501';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_opinion_comment(p_opinion_id uuid, p_content text, p_reply_to_comment_id uuid DEFAULT NULL::uuid, p_quoted_text text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_id uuid;
  v_opinion_owner uuid;
  v_parent_author uuid;
  v_preview text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 5000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;
  PERFORM private.assert_opinion_content_ok(t) FROM unnest(ARRAY[p_content, p_quoted_text]) AS t; -- Spec 1 W9a

  PERFORM private.assert_can_post(v_uid, 'comment');

  SELECT relationship_status INTO v_status FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.opinion_comments (
    opinion_id, user_id, content, relationship_status_at_post,
    reply_to_comment_id, quoted_text
  )
  VALUES (p_opinion_id, v_uid, p_content, v_status, p_reply_to_comment_id, p_quoted_text)
  RETURNING id INTO v_id;

  UPDATE public.opinions
  SET comment_count = COALESCE(comment_count, 0) + 1
  WHERE id = p_opinion_id
  RETURNING user_id INTO v_opinion_owner;

  -- Shared 60-char preview for both notification bodies (FORUM.md §10).
  v_preview := CASE
    WHEN char_length(p_content) > 60 THEN left(p_content, 60) || '...'
    ELSE p_content
  END;

  IF p_reply_to_comment_id IS NOT NULL THEN
    SELECT user_id INTO v_parent_author
    FROM public.opinion_comments
    WHERE id = p_reply_to_comment_id;
  END IF;

  -- #3: reply to a comment -> notify the parent comment's author.
  IF v_parent_author IS NOT NULL AND v_parent_author <> v_uid THEN
    PERFORM private.enqueue_forum_notification(
      p_user_id    => v_parent_author,
      p_title      => 'New reply',
      p_body       => v_preview,
      p_type       => 'opinion_comment_reply',
      p_opinion_id => p_opinion_id,
      p_comment_id => v_id
    );
  END IF;

  -- #2: new comment -> notify the opinion's author, unless they are the
  -- commenter, or unless they already got the reply notification above.
  IF v_opinion_owner IS NOT NULL
     AND v_opinion_owner <> v_uid
     AND (v_parent_author IS NULL OR v_parent_author <> v_opinion_owner)
  THEN
    PERFORM private.enqueue_forum_notification(
      p_user_id    => v_opinion_owner,
      p_title      => 'New comment',
      p_body       => v_preview,
      p_type       => 'opinion_commented',
      p_opinion_id => p_opinion_id,
      p_comment_id => v_id
    );
  END IF;

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.edit_opinion_comment(p_comment_id uuid, p_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_updated_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 5000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;
  PERFORM private.assert_opinion_content_ok(p_content); -- Spec 1 W9a

  UPDATE public.opinion_comments
  SET content = p_content, edited_at = now()
  WHERE id = p_comment_id
    AND user_id = v_uid
    AND removed_at IS NULL
    AND created_at > now() - interval '15 minutes'
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'not_editable' USING ERRCODE = '42501';
  END IF;
END;
$function$;

COMMIT;
```

Create `supabase/migrations/20261104100010_opinion_content_filter_grants.sql` with exactly:

```sql
-- Spec 1 W9a: grants for 20261104100000_opinion_content_filter.sql. The
-- normaliser, the term lists, the verdict and the assert are the database's
-- own (no role is granted anything; the writers run them as definers). The
-- six writers keep exactly their live grants: signed-in only.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON private.content_filter_terms FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.normalize_for_filter(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.match_form(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.digits_from_words(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.has_contact_info(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.content_filter_verdict(text, text[]) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.assert_opinion_content_ok(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_opinion(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_opinion_with_poll(text, text[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_opinion_with_quote(text, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.edit_opinion(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_opinion_comment(uuid, text, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.edit_opinion_comment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_opinion(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_opinion_with_poll(text, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_opinion_with_quote(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.edit_opinion(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_opinion_comment(uuid, text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.edit_opinion_comment(uuid, text) TO authenticated;
COMMIT;
```

- [ ] **Step 4: Apply each file twice; diff the writers against their live bodies; run the contract**

```bash
for i in 1 2; do
  for f in 20261104100000_opinion_content_filter 20261104100010_opinion_content_filter_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
D=.superpowers/sdd/2026-11-04-spec1-w9
for sig in 'public.create_opinion(text)' 'public.create_opinion_with_poll(text,text[])' \
           'public.create_opinion_with_quote(text,uuid)' 'public.edit_opinion(uuid,text)' \
           'public.create_opinion_comment(uuid,text,uuid,text)' 'public.edit_opinion_comment(uuid,text)'; do
  echo "== $sig"
  n=$(echo "$sig" | sed 's/(.*//')
  diff "$D/before/$n.sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)") | grep '^[<>]'
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_filter_contracts.sql 2>&1 | tail -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0` lines; under each `==` header exactly one line, beginning `>   PERFORM private.assert_opinion_content_ok(` and ending `-- Spec 1 W9a` (and no `<` line: nothing of the live body changed); `NOTICE:  opinion_filter_contracts: all held`.

- [ ] **Step 5: The [DRAFT] loader**

Create `supabase/sql/load_content_filter_terms.sql` with exactly:

```sql
-- DEV / MANUAL TESTING ONLY (spec §4.2, plan P-5). Never a migration.
-- Loads the [DRAFT] English filter terms into private.content_filter_terms
-- on the development project only. The guard and the insert are one
-- statement, so when private.assert_development_project() raises
-- env:not_development nothing is loaded. Safe to re-run. Draft terms never
-- match outside development (private.content_filter_verdict), whatever is
-- loaded.
--
-- [DRAFT] This list is a placeholder for testing, written by the developer,
-- NOT reviewed. Production holds only the cultural reviewer's signed lists
-- (slur and explicit terms in English, Twi, Ga, Ewe, Hausa and Pidgin, and
-- local number words), loaded with source = 'reviewed' and their review
-- reference: the W9a gate (owner deploy checklist). Terms are stored in the
-- match form (private.match_form), so write them as typed.
--
-- Run (SQL editor, or psql against the development project):
--   psql -X -v ON_ERROR_STOP=1 -f supabase/sql/load_content_filter_terms.sql
-- Check locally without keeping anything:
--   psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' \
--     -f supabase/sql/load_content_filter_terms.sql \
--     -c 'SELECT family, count(*) FROM private.content_filter_terms GROUP BY 1 ORDER BY 1' -c 'ROLLBACK'
DO $$
BEGIN
  PERFORM private.assert_development_project();

  INSERT INTO private.content_filter_terms (family, term, match_mode, locale, source)
  SELECT d.family, private.match_form(d.term), d.match_mode, 'en', 'draft'
    FROM (VALUES
      -- [DRAFT] slurs (English): a minimal set to exercise the filter.
      ('slur', 'nigger', 'squashed'),
      ('slur', 'faggot', 'squashed'),
      ('slur', 'retard', 'token'),
      ('slur', 'tranny', 'token'),
      -- [DRAFT] explicit sexual terms (English).
      ('explicit', 'porn', 'token'),
      ('explicit', 'nudes', 'token'),
      ('explicit', 'blowjob', 'squashed'),
      ('explicit', 'handjob', 'squashed'),
      ('explicit', 'cumshot', 'squashed')
    ) AS d(family, term, match_mode)
  ON CONFLICT (family, term, locale) DO UPDATE
    SET match_mode = EXCLUDED.match_mode, active = true;
END $$;
```

Check it on `attune_spec3a` inside a rolled-back transaction (twice: it is re-runnable), then that it refuses outside development:

```bash
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' \
  -f supabase/sql/load_content_filter_terms.sql -f supabase/sql/load_content_filter_terms.sql \
  -c 'SELECT family, count(*) FROM private.content_filter_terms WHERE source = $$draft$$ GROUP BY 1 ORDER BY 1' \
  -c "SELECT private.content_filter_verdict('you are a r3tard', NULL), private.content_filter_verdict('he is a retired teacher', NULL)" \
  -c 'ROLLBACK' 2>&1 | grep -E '^ (explicit|slur) |^ROLLBACK'
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' \
  -c "SELECT set_config('app.settings.attune_environment', 'production', true)" \
  -f supabase/sql/load_content_filter_terms.sql -c 'ROLLBACK' 2>&1 | grep -o 'ERROR:  env:not_development'
psql -X -d attune_spec3a -Atc "select count(*) from private.content_filter_terms"
```

Expected: ` explicit |     5`, ` slur     |     4`, a line ` slur                   | ` (the leetspeak slur is caught; the retired teacher passes), `ROLLBACK`; `ERROR:  env:not_development`; `0` (nothing was kept).

- [ ] **Step 6: Mutation checks (each must turn the contract red with the message quoted)**

Each mutant runs inside one transaction that the contract's own `ROLLBACK` ends (the mutant files drop the migration's `BEGIN`/`COMMIT`), so no mutant is ever left on `attune_spec3a`.

```bash
M=supabase/migrations/20261104100000_opinion_content_filter.sql
C=supabase/tests/opinion_filter_contracts.sql
D=.superpowers/sdd/2026-11-04-spec1-w9
python3 -I - "$M" "$D" <<'PY'
import pathlib, sys
m = pathlib.Path(sys.argv[1]).read_text()
def body(m):
    # One transaction per mutant: the migration's own BEGIN/COMMIT go, so the
    # contract's ROLLBACK undoes the mutant too.
    assert m.count("\nBEGIN;\n") == 1 and m.count("\nCOMMIT;\n") == 1
    return m.replace("\nBEGIN;\n", "\n").replace("\nCOMMIT;\n", "\n")
m = body(m)
d = pathlib.Path(sys.argv[2])
A = "  PERFORM private.assert_opinion_content_ok(p_content); -- Spec 1 W9a\n"
muts = {
  'no_assert_create': (A + "\n  PERFORM private.assert_can_post(v_uid, 'opinion');", "\n  PERFORM private.assert_can_post(v_uid, 'opinion');"),
  'no_assert_poll': ("  PERFORM private.assert_opinion_content_ok(t) FROM unnest(array_prepend(p_content, coalesce(p_poll_options, '{}'::text[]))) AS t; -- Spec 1 W9a\n", ""),
  'no_assert_quote': ("  END IF;\n" + A + "\n  -- Resolve to the ORIGINAL.", "  END IF;\n\n  -- Resolve to the ORIGINAL."),
  'no_assert_edit': (A + "\n  UPDATE public.opinions\n", "\n  UPDATE public.opinions\n"),
  'no_assert_comment': ("  PERFORM private.assert_opinion_content_ok(t) FROM unnest(ARRAY[p_content, p_quoted_text]) AS t; -- Spec 1 W9a\n", ""),
  'no_quoted_text': ("unnest(ARRAY[p_content, p_quoted_text])", "unnest(ARRAY[p_content])"),
  'no_assert_edit_comment': (A + "\n  UPDATE public.opinion_comments\n", "\n  UPDATE public.opinion_comments\n"),
  'flag_ignored': ("  IF p_text IS NULL OR NOT private.spec1_flag_on('opinions_safety_v1') THEN", "  IF p_text IS NULL THEN"),
  'never_raise': ("    RAISE EXCEPTION 'content:%', v_verdict USING ERRCODE = '22023';", "    NULL;"),
  'no_remove': ("U&'\\00AD\\200B\\200C\\200D\\200E\\200F\\202A\\202B\\202C\\202D\\202E\\2060\\2061\\2062\\2063\\2064\\2066\\2067\\2068\\2069\\FEFF',\n            ''),", "'', ''),"),
  'confusable_wrong': ("'abekmhopctyxsijhlydqwabyenikvoptuxwiag'", "'abekmhopctyxsijhlydqwabyenikvoptuxwiaq'"),
  'no_west_african': ("U&'\\025B\\0254\\0192\\028B\\0253\\0257\\0199', 'eofvbdk'", "'', ''"),
  'no_leet': ("'013457@$', 'oieastas'", "'', ''"),
  'no_year_exemption': ("    CONTINUE WHEN v_years;\n", ""),
  'no_thousands_exemption': ("    CONTINUE WHEN v_thousands;\n", ""),
  'no_plus_rule': ("      RETURN true;                                   -- +233 ..., + 44 ...", "      NULL;"),
  'no_zero_rule': ("      RETURN true;                                   -- 024..., 00233...", "      NULL;"),
  'no_nanp': ("      RETURN true;                                   -- NANP (415) 555-0132", "      NULL;"),
  'no_calling_code': ("      RETURN true;                                   -- a calling code, no +", "      NULL;"),
  'no_email': ("    p_text ~ '[a-z0-9._+]+@[a-z0-9]+(\\.[a-z0-9]+)*\\.[a-z]{2,}'", "    false"),
  'no_at_dot': ("    OR p_text ~ '\\m[a-z0-9._]+ ?(@|\\mat\\M)", "    OR false AND p_text ~ '\\m[a-z0-9._]+ ?(@|\\mat\\M)"),
  'no_scheme': ("    OR p_text ~ '\\mhttps?:/'", "    OR false"),
  'no_www': ("    OR p_text ~ '\\mwww\\.[a-z0-9]'", "    OR false"),
  'no_messenger_links': ("    OR p_text ~ '\\m(wa|t)\\.me\\M'", "    OR false"),
  'no_short_links': ("    OR p_text ~ '\\m(bit\\.ly|", "    OR false AND p_text ~ '\\m(bit\\.ly|"),
  'no_bare_domain': ("    OR p_text ~ '\\m[a-z0-9]+\\.(com|net|org|info|biz|io|xyz|ly|gh|ng|uk)\\M'", "    OR false"),
  'no_handle': ("    OR p_text ~ '(^|[^a-z0-9._@])@[a-z0-9._]{3,}'", "    OR false"),
  'no_platform': ("    OR p_text ~ '\\m(instagram|", "    OR false AND p_text ~ '\\m(instagram|"),
  'no_digit_words': ("WHEN 'zero' THEN '0'", "WHEN 'zeroX' THEN '0'"),
  'no_oh': ("v_tokens[i] IN ('oh', 'o')", "v_tokens[i] IN ('ohX')"),
  'no_join': ("CASE WHEN v_prev_word THEN '' WHEN i = 1", "CASE WHEN v_prev_word THEN ' ' WHEN i = 1"),
  'draft_in_production': ("         AND (t.source = 'reviewed' OR v_dev)\n         AND (strpos(", "         AND (strpos("),
  'no_squashed': ("              OR (t.match_mode = 'squashed' AND strpos(v_squashed, replace(t.term, ' ', '')) > 0))", "              OR false)"),
  'no_token': ("(strpos(v_match, ' ' || t.term || ' ') > 0", "(false"),
  'token_inside_word': ("strpos(v_match, ' ' || t.term || ' ') > 0", "strpos(v_match, t.term) > 0"),
}
for name, (a, b) in muts.items():
    assert m.count(a) == 1, (name, m.count(a))
    (d / f"mut_{name}.sql").write_text(m.replace(a, b))
(d / 'mut_grant_verdict.sql').write_text("GRANT EXECUTE ON FUNCTION private.content_filter_verdict(text, text[]) TO authenticated;\n")
(d / 'mut_grant_terms.sql').write_text("GRANT SELECT ON private.content_filter_terms TO service_role;\n")
(d / 'mut_writer_revoked.sql').write_text("REVOKE EXECUTE ON FUNCTION public.create_opinion_comment(uuid, text, uuid, text) FROM authenticated;\n")
print(len(muts) + 3, 'mutants written')
PY
for f in $D/mut_*.sql; do
  m=$(basename $f .sql)
  echo "${m#mut_}: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f $f -f $C 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-150)"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | tail -1 | sed -E 's/^psql:[^ ]* //'
rm $D/mut_*.sql
```

Expected: `38 mutants written`, then (alphabetical):
- `confusable_wrong`: `ERROR:  CONTRACT VIOLATED: fold table base.confusables U+261 is not folded to g`
- `draft_in_production`: `ERROR:  CONTRACT VIOLATED: a draft term matched outside development`
- `flag_ignored`: `ERROR:  CONTRACT VIOLATED: with opinions_safety_v1 off, a writer still filtered`
- `grant_terms`: `ERROR:  CONTRACT VIOLATED: the term lists must have no grants`
- `grant_verdict`: `ERROR:  CONTRACT VIOLATED: private.content_filter_verdict(text,text[]) must have no grants`
- `never_raise`: `ERROR:  CONTRACT VIOLATED: a writer did not refuse Call me on 0244123456 tonight with content:contact_info (create cooldown, poll cooldown, poll optio …`
- `no_assert_comment`: `ERROR:  CONTRACT VIOLATED: a writer did not refuse Call me on 0244123456 tonight with content:contact_info (create content:contact_info, poll content: …`
- `no_assert_create`: `ERROR:  CONTRACT VIOLATED: a writer did not refuse Call me on 0244123456 tonight with content:contact_info (create cooldown, poll content:contact_info …`
- `no_assert_edit`: `ERROR:  CONTRACT VIOLATED: a writer did not refuse Call me on 0244123456 tonight with content:contact_info (create content:contact_info, poll content: …`
- `no_assert_edit_comment`: `ERROR:  CONTRACT VIOLATED: a writer did not refuse Call me on 0244123456 tonight with content:contact_info (create content:contact_info, poll content: …`
- `no_assert_poll`: `ERROR:  CONTRACT VIOLATED: a writer did not refuse Call me on 0244123456 tonight with content:contact_info (create content:contact_info, poll content: …`
- `no_assert_quote`: `ERROR:  CONTRACT VIOLATED: a writer did not refuse Call me on 0244123456 tonight with content:contact_info (create content:contact_info, poll content: …`
- `no_at_dot`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "kofi at gmail dot com" gave <NULL>`
- `no_bare_domain`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "my site is kofi.com" gave <NULL>`
- `no_calling_code`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "233244123456" gave <NULL>`
- `no_digit_words`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "zero two four four one two three four five six" gave <NULL>`
- `no_email`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "write to kofi@school.de" gave <NULL>`
- `no_handle`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "follow @kofi_99" gave <NULL>`
- `no_join`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "four one five five five five zero one three two" gave <NULL>`
- `no_leet`: `ERROR:  CONTRACT VIOLATED: golden arabic_digits match form is "0244 123 12", expected "o2aa i2e i2"`
- `no_messenger_links`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "wa.me/kofi" gave <NULL>`
- `no_nanp`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "(415) 555-0132" gave <NULL>`
- `no_oh`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "call oh two four four one two three four five six" gave <NULL>`
- `no_platform`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "IG: kofi.99" gave <NULL>`
- `no_plus_rule`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "+81 3 1234 5678" gave <NULL>`
- `no_quoted_text`: `ERROR:  CONTRACT VIOLATED: a writer did not refuse Call me on 0244123456 tonight with content:contact_info (create content:contact_info, poll content: …`
- `no_remove`: `ERROR:  CONTRACT VIOLATED: golden empty_after base form is "\u200b\u200b \u00ad", expected ""`
- `no_scheme`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "see https://kofi.de/home" gave <NULL>`
- `no_short_links`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "rb.gy/abc" gave <NULL>`
- `no_squashed`: `ERROR:  CONTRACT VIOLATED: a squashed term was not matched across separators`
- `no_thousands_exemption`: `ERROR:  CONTRACT VIOLATED: an ordinary post was blocked: "A bridge costs 4 400 000 000 000" gave contact_info`
- `no_token`: `ERROR:  CONTRACT VIOLATED: a Twi term did not match typed with and without its letters`
- `no_west_african`: `ERROR:  CONTRACT VIOLATED: golden ewe_hausa_letters match form is "ƒe ʋu ɓa ɗa ƙa ngkɔ", expected "fe vu ba da ka ngko"`
- `no_www`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "www.kofi.de" gave <NULL>`
- `no_year_exemption`: `ERROR:  CONTRACT VIOLATED: an ordinary post was blocked: "1999 2004 2010" gave contact_info`
- `no_zero_rule`: `ERROR:  CONTRACT VIOLATED: contact details were not caught: "Call me on 024 412 3456" gave <NULL>`
- `token_inside_word`: `ERROR:  CONTRACT VIOLATED: a token term matched inside another word`
- `writer_revoked`: `ERROR:  CONTRACT VIOLATED: public.create_opinion_comment(uuid,text,uuid,text) lost its grants (signed-in only)`

then `NOTICE:  opinion_filter_contracts: all held`.

- [ ] **Step 7: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`, edit 1 of 1. Replace exactly:

```sql
\i supabase/migrations/20261103140110_media_scan_enqueue_grants.sql
```

with:

```sql
\i supabase/migrations/20261103140110_media_scan_enqueue_grants.sql

-- Spec 1 W9a: the content filter is the database's own; the six Opinion
-- writers keep their grants (signed-in only).
\i supabase/migrations/20261104100010_opinion_content_filter_grants.sql
```

- [ ] **Step 8: Run tests**

```bash
D=.superpowers/sdd/2026-11-04-spec1-w9
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-after-task3.txt
grep '^FAIL' $D/sql-after-task3.txt | comm -13 <(grep '^FAIL' $D/sql-baseline.txt) -
grep -E 'opinion_filter|forum_retirement|identity_foundation' $D/sql-after-task3.txt
```

Expected: no new FAIL line; `PASS forum_retirement_contracts.sql`, `PASS identity_foundation_contracts.sql`, `PASS opinion_filter_contracts.sql`.

### Task 4: Filter refusals inline, draft kept, and the W9a gate (§2.3, §5.1, §5.2, §8 W9a; P-8-P-10)

**Files:**
- Create: `lib/features/opinions/domain/content_filter_error.dart`
- Create: `lib/features/opinions/presentation/widgets/content_filter_notice.dart`
- Create: `test/features/opinions/w9/opinion_filter_ui_test.dart` (+ 4 goldens)
- Modify: `lib/features/opinions/presentation/screen/opinion_compose_screen.dart`, `quote_compose_screen.dart`, `edit_opinion_screen.dart`, `comment_thread_screen.dart`
- Modify: `lib/i10n/app_en.arb` (+ `lib/i10n/generated/*`)

**Interfaces:**
- Consumes: Task 3's refusals (`PostgrestException(message: 'content:<reason>', code: '22023')`); `ClientMetricKey.opinionBlocked*`, `metricCounterProvider`; Task 1's helper.
- Produces: `enum ContentFilterReason { contactInfo, slur, explicit }` with `wire`, `metric`, `static ContentFilterReason? of(Object error)`, `String message(AppLocalizations)`; `ContentFilterNotice({required ContentFilterReason reason})` (AllowLargeText, live region, announced). Keys `opinions_filterContactInfo`, `opinions_filterSlur`, `opinions_filterExplicit`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/opinions/w9/opinion_filter_ui_test.dart` with exactly:

```dart
// Spec 1 W9a (§8 W9a, §2.3): a post, quote, edit, comment or comment edit
// the content filter refuses shows the reason inline, under the field; the
// draft stays; it is announced and counted (opinion_blocked:<reason>);
// typing again clears it; any other failure keeps today's message.
//   flutter test --update-goldens test/features/opinions/w9/opinion_filter_ui_test.dart
import 'package:attune/features/opinions/domain/content_filter_error.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/screen/edit_opinion_screen.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/features/opinions/presentation/screen/quote_compose_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/content_filter_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/flow_harness.dart';
import 'support/fake_opinions.dart';

PostgrestException _refusal(String wire) =>
    PostgrestException(message: 'content:$wire', code: '22023');

const _contact =
    "Phone numbers, emails, links and usernames can't go in Opinions. They can identify you or someone else. Take it out and post again.";
const _slur =
    'This includes a word that attacks people for who they are. Opinions doesn\'t allow it.';
const _explicit =
    "Opinions doesn't allow sexual content. You can describe what happened without explicit words.";

void main() {
  test('the three refusals, and nothing else, are read as filter errors', () {
    expect(
      ContentFilterReason.of(_refusal('contact_info')),
      ContentFilterReason.contactInfo,
    );
    expect(ContentFilterReason.of(_refusal('slur')), ContentFilterReason.slur);
    expect(
      ContentFilterReason.of(_refusal('explicit')),
      ContentFilterReason.explicit,
    );
    expect(ContentFilterReason.of(_refusal('other')), isNull);
    expect(
      ContentFilterReason.of(const PostgrestException(message: 'cooldown')),
      isNull,
    );
    expect(ContentFilterReason.of(Exception('content:slur')), isNull);
    expect(ContentFilterReason.values.map((r) => r.metric.key), [
      'opinion_blocked:contact_info',
      'opinion_blocked:slur',
      'opinion_blocked:explicit',
    ]);
  });

  testWidgets('compose: the reason shows under the field and the draft stays', (
    tester,
  ) async {
    final repo = FakeOpinionRepository()..refuseWith = _refusal('contact_info');
    final h = await pumpOpinionScreen(
      tester,
      () => const OpinionComposeScreen(),
      repo: repo,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'Call me on 0244123456 tonight please',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.text(_contact), findsOneWidget);
    expect(find.text('Call me on 0244123456 tonight please'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(h.metrics, ['opinion_blocked:contact_info']);
    // Typing again clears it.
    await tester.enterText(
      find.byType(TextFormField),
      'Call me tonight please, I will be up',
    );
    await tester.pumpAndSettle();
    expect(find.text(_contact), findsNothing);
  });

  testWidgets('quote and edit: the same, by reason', (tester) async {
    final repo = FakeOpinionRepository()..refuseWith = _refusal('slur');
    await pumpOpinionScreen(
      tester,
      () => QuoteComposeScreen(quotedOpinion: w9Opinion()),
      repo: repo,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'A take with a word in it here',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.text(_slur), findsOneWidget);
    expect(find.text('A take with a word in it here'), findsOneWidget);

    repo.refuseWith = _refusal('explicit');
    final h = await pumpOpinionScreen(
      tester,
      () => EditOpinionScreen(opinion: w9Opinion(mine: true)),
      repo: repo,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'An edit with explicit words',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text(_explicit), findsOneWidget);
    expect(find.text('An edit with explicit words'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(h.metrics, ['opinion_blocked:explicit']);
  });

  testWidgets(
    'a comment, and a comment edit: the reason shows, the words stay',
    (tester) async {
      final repo = FakeOpinionRepository();
      final opinion = w9Opinion();
      final h = await pumpOpinionScreen(
        tester,
        () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
        repo: repo,
      );
      repo.refuseWith = _refusal('contact_info');
      await tester.enterText(find.byType(TextField).last, 'my ig: kofi.99');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(find.text(_contact), findsOneWidget);
      expect(find.text('my ig: kofi.99'), findsOneWidget);
      expect(h.metrics, ['opinion_blocked:contact_info']);

      // Inline edit of my own comment (the first menu: newest first).
      repo.refuseWith = _refusal('slur');
      await tester.tap(find.byIcon(Icons.more_horiz).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'My own comment here.'),
        'My own comment, changed.',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text(_slur), findsOneWidget);
      expect(find.text('My own comment, changed.'), findsOneWidget);
    },
  );

  testWidgets('any other failure keeps today\'s message', (tester) async {
    final repo =
        FakeOpinionRepository()
          ..refuseWith = const PostgrestException(
            message: 'cooldown',
            code: '53400',
          );
    final h = await pumpOpinionScreen(
      tester,
      () => const OpinionComposeScreen(),
      repo: repo,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'A draft that is long enough to post.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed to post:'), findsOneWidget);
    expect(find.byType(ContentFilterNotice), findsNothing);
    expect(h.metrics, isEmpty);
  });

  testWidgets('the notice: guidelines and goldens', (tester) async {
    Widget notice() => const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(16),
        child: ContentFilterNotice(reason: ContentFilterReason.contactInfo),
      ),
    );
    await pumpFlowScreen(tester, notice);
    await expectFlowGuidelines(tester);
    await expectFlowGoldens(tester, 'content_filter_notice', notice);
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
flutter test --no-pub test/features/opinions/w9/opinion_filter_ui_test.dart 2>&1 | grep -o "Error when reading '[^']*'" | head -1
```

Expected: `Error when reading 'lib/features/opinions/domain/content_filter_error.dart'`.

- [ ] **Step 3: The copy**

Create `.superpowers/sdd/2026-11-04-spec1-w9/arb_w9a.txt` with exactly:

```text
  "opinions_filterContactInfo": "Phone numbers, emails, links and usernames can't go in Opinions. They can identify you or someone else. Take it out and post again.",
  "@opinions_filterContactInfo": {
    "description": "Shown under an Opinions post, comment or edit the content filter refused for contact details (Spec 1 W9a). The draft stays."
  },
  "opinions_filterSlur": "This includes a word that attacks people for who they are. Opinions doesn't allow it.",
  "@opinions_filterSlur": {
    "description": "Shown under an Opinions post, comment or edit the content filter refused for a slur (Spec 1 W9a). The draft stays."
  },
  "opinions_filterExplicit": "Opinions doesn't allow sexual content. You can describe what happened without explicit words.",
  "@opinions_filterExplicit": {
    "description": "Shown under an Opinions post, comment or edit the content filter refused for explicit sexual content (Spec 1 W9a). The draft stays."
  }
```

```bash
grep -cP '[^\x00-\x7F]' .superpowers/sdd/2026-11-04-spec1-w9/arb_w9a.txt
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py .superpowers/sdd/2026-11-04-spec1-w9/arb_w9a.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null
grep -c 'opinions_filter' lib/i10n/generated/app_localizations_en.dart
```

Expected: `0`; `added 3 keys`; `3`.

- [ ] **Step 4: The mapping, the notice, and the four screens**

Create `lib/features/opinions/domain/content_filter_error.dart` with exactly:

```dart
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why the Opinions content filter refused a post, comment or edit
/// (Spec 1 §4.3 W9a): the writer RPCs raise `content:<wire>`.
enum ContentFilterReason {
  contactInfo('contact_info', ClientMetricKey.opinionBlockedContactInfo),
  slur('slur', ClientMetricKey.opinionBlockedSlur),
  explicit('explicit', ClientMetricKey.opinionBlockedExplicit);

  const ContentFilterReason(this.wire, this.metric);

  final String wire;

  /// The count the app keeps (`opinion_blocked:<wire>`); nothing else about
  /// a blocked post is stored anywhere (§4.8).
  final ClientMetricKey metric;

  /// The refusal in [error], or null when [error] is anything else (which
  /// keeps today's handling).
  static ContentFilterReason? of(Object error) {
    if (error is! PostgrestException) return null;
    for (final r in values) {
      if (error.message == 'content:${r.wire}') return r;
    }
    return null;
  }

  /// The inline line shown under the field (§8 W9a); the draft stays.
  String message(AppLocalizations loc) => switch (this) {
    ContentFilterReason.contactInfo => loc.opinions_filterContactInfo,
    ContentFilterReason.slur => loc.opinions_filterSlur,
    ContentFilterReason.explicit => loc.opinions_filterExplicit,
  };
}
```

Create `lib/features/opinions/presentation/widgets/content_filter_notice.dart` with exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/opinions/domain/content_filter_error.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// The content filter's refusal, shown under the field it refused (Spec 1
/// §8 W9a, §2.3): an icon and the words, never colour alone, announced when
/// it appears. The draft stays in the field.
class ContentFilterNotice extends StatefulWidget {
  const ContentFilterNotice({super.key, required this.reason});

  final ContentFilterReason reason;

  @override
  State<ContentFilterNotice> createState() => _ContentFilterNoticeState();
}

class _ContentFilterNoticeState extends State<ContentFilterNotice> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
  }

  @override
  void didUpdateWidget(ContentFilterNotice old) {
    super.didUpdateWidget(old);
    if (old.reason != widget.reason) _announce();
  }

  void _announce() {
    if (!mounted) return;
    SemanticsService.announce(
      widget.reason.message(AppLocalizations.of(context)!),
      Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = widget.reason.message(AppLocalizations.of(context)!);
    return AllowLargeText(
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
          padding: Spacing.allSm,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadiusTokens.mdAll,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Edit the four screens (exact replacements; each anchor must occur once):

```bash
python3 -I - <<'PY'
# W9a client edits, as exact replacements (run from the repo root).
import pathlib
def edit(path, pairs):
    p = pathlib.Path(path); s = p.read_text()
    for a, b in pairs:
        assert s.count(a) == 1, (path, a[:70], s.count(a))
        s = s.replace(a, b)
    p.write_text(s)

IMPORTS = """import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/features/opinions/domain/content_filter_error.dart';
import 'package:attune/features/opinions/presentation/widgets/content_filter_notice.dart';
"""
COMPOSE_CATCH_OLD = """    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to post: $e')));
      }
"""
COMPOSE_CATCH_NEW = """    } catch (e) {
      // Spec 1 W9a: a filter refusal shows under the field; the draft stays.
      final reason = ContentFilterReason.of(e);
      if (reason != null) {
        ref.read(metricCounterProvider).bump(reason.metric);
        if (mounted) setState(() => _filterReason = reason);
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to post: $e')));
      }
"""
FIELD_TAIL = """              onChanged: (_) => setState(() {}),
              enabled: !_isSubmitting,
              label: '',
            ),
"""
edit('lib/features/opinions/presentation/screen/opinion_compose_screen.dart', [
  ("import 'package:attune/core/widgets/bottom_sheet_header.dart';\n",
   "import 'package:attune/core/widgets/bottom_sheet_header.dart';\n" + IMPORTS),
  ("  List<String> _tagSlugs = const [];\n",
   "  List<String> _tagSlugs = const [];\n\n  /// Spec 1 W9a: the content filter's refusal, shown under the field.\n  ContentFilterReason? _filterReason;\n"),
  (COMPOSE_CATCH_OLD, COMPOSE_CATCH_NEW),
  (FIELD_TAIL,
   """              onChanged: (_) => setState(() => _filterReason = null),
              enabled: !_isSubmitting,
              label: '',
            ),
            if (_filterReason != null) ContentFilterNotice(reason: _filterReason!),
"""),
])
QFIELD_OLD = """                onChanged: (_) => setState(() {}),
                enabled: !_isSubmitting,
                label: '',
              ),
"""
QFIELD_NEW = """                onChanged: (_) => setState(() => _filterReason = null),
                enabled: !_isSubmitting,
                label: '',
              ),
              if (_filterReason != null)
                ContentFilterNotice(reason: _filterReason!),
"""
edit('lib/features/opinions/presentation/screen/quote_compose_screen.dart', [
  ("import 'package:attune/features/opinions/presentation/widgets/quoted_opinion_preview.dart';\n",
   "import 'package:attune/features/opinions/presentation/widgets/quoted_opinion_preview.dart';\n" + IMPORTS),
  ("  bool _isSubmitting = false;\n",
   "  bool _isSubmitting = false;\n\n  /// Spec 1 W9a: the content filter's refusal, shown under the field.\n  ContentFilterReason? _filterReason;\n"),
  (COMPOSE_CATCH_OLD, COMPOSE_CATCH_NEW),
  (QFIELD_OLD, QFIELD_NEW),
])
edit('lib/features/opinions/presentation/screen/edit_opinion_screen.dart', [
  ("import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';\n",
   "import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';\n" + IMPORTS),
  ("  bool _isSubmitting = false;\n",
   "  bool _isSubmitting = false;\n\n  /// Spec 1 W9a: the content filter's refusal, shown under the field.\n  ContentFilterReason? _filterReason;\n"),
  ("""    } catch (error) {
      if (mounted) {
        context.showInfoSnackbar(_editErrorMessage(error));
      }
""", """    } catch (error) {
      // Spec 1 W9a: a filter refusal shows under the field; the edit stays.
      final reason = ContentFilterReason.of(error);
      if (reason != null) {
        ref.read(metricCounterProvider).bump(reason.metric);
        if (mounted) setState(() => _filterReason = reason);
      } else if (mounted) {
        context.showInfoSnackbar(_editErrorMessage(error));
      }
"""),
  (QFIELD_OLD, QFIELD_NEW),
])
edit('lib/features/opinions/presentation/screen/comment_thread_screen.dart', [
  ("import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';\n",
   "import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';\n" + IMPORTS),
  ("  bool _isSavingEdit = false;\n",
   "  bool _isSavingEdit = false;\n\n  /// Spec 1 W9a: the content filter's refusal of a new comment (shown\n  /// above the field) and of an inline edit (under the editor).\n  ContentFilterReason? _commentFilterReason;\n  ContentFilterReason? _editFilterReason;\n"),
  ("""    setState(() {
      _editingCommentId = comment.id;
      _editController.text = comment.content;
    });""", """    setState(() {
      _editingCommentId = comment.id;
      _editController.text = comment.content;
      _editFilterReason = null;
    });"""),
  ("""    setState(() {
      _editingCommentId = null;
      _editController.clear();
    });""", """    setState(() {
      _editingCommentId = null;
      _editController.clear();
      _editFilterReason = null;
    });"""),
  ("""    } catch (error) {
      if (mounted) {
        final text = error.toString();
        context.showInfoSnackbar(""", """    } catch (error) {
      // Spec 1 W9a: a filter refusal shows under the editor; the edit stays.
      final reason = ContentFilterReason.of(error);
      if (reason != null) {
        ref.read(metricCounterProvider).bump(reason.metric);
        if (mounted) setState(() => _editFilterReason = reason);
      } else if (mounted) {
        final text = error.toString();
        context.showInfoSnackbar("""),
  ("""      _commentController.clear();
      _clearReplyTarget();""", """      _commentFilterReason = null;
      _commentController.clear();
      _clearReplyTarget();"""),
  ("""    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        print(e);
        context.showErrorSnackbar('Failed to post comment: $e');
      }
    }""", """    } catch (e) {
      setState(() => _isSubmitting = false);
      // Spec 1 W9a: a filter refusal shows above the field; the draft stays.
      final reason = ContentFilterReason.of(e);
      if (reason != null) {
        ref.read(metricCounterProvider).bump(reason.metric);
        setState(() => _commentFilterReason = reason);
      } else if (mounted) {
        print(e);
        context.showErrorSnackbar('Failed to post comment: $e');
      }
    }"""),
  ("""                        // Comment input, floating pill over the list instead
                        // of a full-width opaque bar.
                        ChatTextField(""", """                        if (_commentFilterReason != null)
                          ContentFilterNotice(reason: _commentFilterReason!),
                        // Comment input, floating pill over the list instead
                        // of a full-width opaque bar.
                        ChatTextField("""),
  ("""              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
              ),
            ),
          ),
          Gap(Spacing.xs.h),""", """              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
              ),
            ),
          ),
          if (_editFilterReason != null)
            ContentFilterNotice(reason: _editFilterReason!),
          Gap(Spacing.xs.h),"""),
])
print('W9a client edits applied')
PY
```

Expected: `W9a client edits applied`. With the flag off nothing here changes what anyone sees: a refusal can only come from the server while its flag is on (P-9), every other error takes today's path, and `setState(() => _filterReason = null)` rebuilds exactly as `setState(() {})` did.

- [ ] **Step 5: Run the tests, write the goldens, look at them**

```bash
flutter test --no-pub test/features/opinions/w9/opinion_filter_ui_test.dart --update-goldens 2>&1 | tail -1
flutter test --no-pub test/features/opinions/w9/ 2>&1 | tail -1
```

Expected: `All tests passed!` twice (the second run includes Task 1's flag-off goldens, unchanged). Open `test/features/opinions/w9/goldens/content_filter_notice.{scale1.0,scale1.3,scale2.0,rtl}.png`: the error icon and the words in a tinted box, the words wrapping inside it at 2.0, the icon on the right under RTL.

- [ ] **Step 6: Analyzer on the touched files**

```bash
flutter analyze --no-pub lib/features/opinions test/features/opinions/w9 2>&1 | grep -E '^\s*(error|warning) ' | grep -v -E 'following_feed_screen|opinions_tab.dart|bottom_sheet_header'
```

Expected: no output (the four pre-existing unused-import warnings in `following_feed_screen.dart`, `opinions_tab.dart` and `opinion_compose_screen.dart`'s `bottom_sheet_header.dart` import are filtered: they are today's).

- [ ] **Step 7: Mutation checks (each must turn the widget test red)**

```bash
python3 -I - <<'PY'
import pathlib, subprocess
TEST = 'test/features/opinions/w9/opinion_filter_ui_test.dart'
COMPOSE = 'lib/features/opinions/presentation/screen/opinion_compose_screen.dart'
THREAD = 'lib/features/opinions/presentation/screen/comment_thread_screen.dart'
ERROR = 'lib/features/opinions/domain/content_filter_error.dart'
muts = {
  'refusal_as_snackbar': (COMPOSE, "      if (reason != null) {\n        ref.read(metricCounterProvider).bump(reason.metric);\n        if (mounted) setState(() => _filterReason = reason);\n      } else if (mounted) {",
                          "      if (false) {\n      } else if (mounted) {"),
  'draft_cleared': (COMPOSE, "        if (mounted) setState(() => _filterReason = reason);\n      } else if (mounted) {",
                    "        if (mounted) setState(() { _filterReason = reason; _controller.clear(); });\n      } else if (mounted) {"),
  'not_counted': (COMPOSE, "        ref.read(metricCounterProvider).bump(reason.metric);\n        if (mounted) setState(() => _filterReason = reason);",
                  "        if (mounted) setState(() => _filterReason = reason);"),
  'never_cleared': (COMPOSE, "              onChanged: (_) => setState(() => _filterReason = null),", "              onChanged: (_) => setState(() {}),"),
  'comment_refusal_as_snackbar': (THREAD, "      if (reason != null) {\n        ref.read(metricCounterProvider).bump(reason.metric);\n        setState(() => _commentFilterReason = reason);\n      } else if (mounted) {",
                                  "      if (false) {\n      } else if (mounted) {"),
  'any_content_message': (ERROR, "      if (error.message == 'content:${r.wire}') return r;", "      if (error.message.startsWith('content:')) return r;"),
}
originals = {}
try:
    for name, (path, a, b) in muts.items():
        p = pathlib.Path(path)
        s = originals.setdefault(path, p.read_text())
        assert s.count(a) == 1, name
        p.write_text(s.replace(a, b))
        r = subprocess.run(['flutter', 'test', '--no-pub', TEST], capture_output=True, text=True)
        print(f"{name}: {'red' if r.returncode else 'GREEN (mutant survived)'}")
        p.write_text(s)
finally:
    for path, s in originals.items():
        pathlib.Path(path).write_text(s)
print('restored')
PY
```

Expected:
- `refusal_as_snackbar: red`
- `draft_cleared: red`
- `not_counted: red`
- `never_cleared: red`
- `comment_refusal_as_snackbar: red`
- `any_content_message: red`

then `restored`.

- [ ] **Step 8: W9a gate (run tests)**

```bash
D=.superpowers/sdd/2026-11-04-spec1-w9
dart format lib/features/opinions/domain/content_filter_error.dart lib/features/opinions/presentation/widgets/content_filter_notice.dart test/features/opinions/w9/opinion_filter_ui_test.dart
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env _shared/unicode_normaliser.test.ts analyse-journal-entry/ 2>&1 | grep -E '^(ok|FAILED) \|')
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-after-w9a.txt
grep '^FAIL' $D/sql-after-w9a.txt | comm -13 <(grep '^FAIL' $D/sql-baseline.txt) -
grep -E 'opinion_filter|forum_retirement|identity_foundation|account_deletion' $D/sql-after-w9a.txt
flutter test --no-pub 2>&1 | tail -1
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error ' | sort | comm -13 $D/analyze-baseline.txt -
sed -n '/if (isAuthenticated && !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - $D/latch.sha && echo latch-unchanged
shasum -c $D/flag_off.sha | grep -v ': OK$'
git status --short lib/features/games lib/features/auth/utility/auth_exports.dart lib/home ATTUNE_SOUL.md ATTUNE_THESIS.md supabase/sql/dev_enable_spec1_flags.sql
git status --short supabase/migrations | grep -v '^??'
```

Expected: `Formatted 3 files (0 changed)`; `ok | 10 passed | 0 failed`; no new SQL FAIL; `PASS` for the four named files; `All tests passed!`; no new analyzer `error`; `latch-unchanged`; no `shasum` line (the six flag-off goldens are byte-identical to Task 1's); no `git status` line from the last two commands.

**W9a gate (before `opinions_safety_v1` in production; spec §8 W9a):** the Ghanaian cultural reviewer supplies and signs the slur and explicit lists (English, Twi, Ga, Ewe, Hausa, Pidgin) and the local number words; they are loaded with `source = 'reviewed'` and their review reference (owner checklist 3). With W9b's gate, this is what the flag's production gate row records.

# W9b · At-risk reason, review queue, restored notices, removing your own (Tasks 5-8)

### Task 5: Migration 17: "Someone may be at risk" and review queue v0 (D13; §4.2, §4.3 W9b, §4.7 #17, §7.1, §7.4; P-12, P-13, P-15)

**Files:**
- Create: `supabase/migrations/20261104110000_opinion_at_risk_and_review_queue.sql`
- Create: `supabase/migrations/20261104110010_opinion_at_risk_and_review_queue_grants.sql`
- Modify: `supabase/tests/opinion_filter_contracts.sql` (appends section G)
- Modify: `scripts/local_pg_grants.sql` (one `\i` block; never run)

**Interfaces:**
- Consumes: the live `private.assert_valid_report_reason`, `private.is_priority_reason`, `report_opinion`, `report_opinion_comment` (Task 1's `before/`).
- Produces: the reason value `'Someone may be at risk'` (valid; priority; never moves `report_count`); `public.admin_list_priority_reports(p_limit int DEFAULT 50) → jsonb` `[{report_id, reason, reported_at, content_type ('opinion'|'comment'), content_id, excerpt (≤ 280), content_removed, hidden_pending_review}]`, oldest first, service role (and SQL editor) only.

- [ ] **Step 1: Write the failing contract section**

Append section G to `supabase/tests/opinion_filter_contracts.sql`, before its last two lines:

```bash
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('supabase/tests/opinion_filter_contracts.sql')
s = p.read_text()
anchor = "DO $$ BEGIN RAISE NOTICE 'opinion_filter_contracts: all held'; END $$;\nROLLBACK;\n"
assert s.count(anchor) == 1
g = pathlib.Path('.superpowers/sdd/2026-11-04-spec1-w9/section_g.sql').read_text()
p.write_text(s.replace(anchor, g + anchor))
print('section G added')
PY
```

after creating `.superpowers/sdd/2026-11-04-spec1-w9/section_g.sql` with exactly:

```sql
-- =====================================================================
-- G. (W9b) "Someone may be at risk": valid, priority, never moves
--    report_count or hides the post (D13); review queue v0 is the service
--    role's only, oldest first, with a 280-character excerpt and no
--    reporter (spec §4.3 W9b, §7.1).
-- =====================================================================
CREATE FUNCTION pg_temp.as_service() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
END $$;

DO $$
DECLARE
  v_author constant uuid := pg_temp.id('04');
  v_reporter constant uuid := pg_temp.id('02');
  v_other constant uuid := pg_temp.id('03');
  v_o uuid;
  v_c uuid;
  v_q jsonb;
  v_ids text[];
  v_msg text;
BEGIN
  INSERT INTO public.opinions (user_id, content, report_count, created_at)
  VALUES (v_author, 'W9b contract: I do not want to be here any more. ' || repeat('x', 400), 9, clock_timestamp())
  RETURNING id INTO v_o;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content)
  VALUES (v_o, v_author, 'W9b contract: a comment from someone who may be at risk.')
  RETURNING id INTO v_c;

  IF pg_temp.err_as(v_reporter, format('SELECT public.report_opinion(%L, %L)', v_o, 'Someone may be at risk')) IS NOT NULL
     OR pg_temp.err_as(v_reporter, format('SELECT public.report_opinion(%L, %L)', v_o, 'Someone may be at risk')) IS NOT NULL
     OR pg_temp.err_as(v_reporter, format('SELECT public.report_opinion_comment(%L, %L)', v_c, 'Someone may be at risk')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the at-risk reason was refused';
  END IF;
  IF (SELECT count(*) FROM public.forum_reports WHERE reported_by = v_reporter AND (opinion_id = v_o OR comment_id = v_c)
        AND reason = 'Someone may be at risk' AND priority) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the at-risk reports were not recorded once each, as priority';
  END IF;
  IF (SELECT report_count FROM public.opinions WHERE id = v_o) <> 9
     OR (SELECT hidden_pending_review FROM public.opinions WHERE id = v_o)
     OR (SELECT report_count FROM public.opinion_comments WHERE id = v_c) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an at-risk report moved report_count or hid the post';
  END IF;
  -- Another reason still counts (and the tenth report still hides).
  PERFORM pg_temp.err_as(v_other, format('SELECT public.report_opinion(%L, %L)', v_o, 'Spam'));
  IF (SELECT report_count FROM public.opinions WHERE id = v_o) <> 10
     OR NOT (SELECT hidden_pending_review FROM public.opinions WHERE id = v_o) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Spam report no longer counts toward auto-hide';
  END IF;
  IF pg_temp.err_as(v_other, format('SELECT public.report_opinion(%L, %L)', v_o, 'Someone may be at risk!'))
       IS DISTINCT FROM 'invalid_reason' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown reason was accepted';
  END IF;
  -- A priority report a person has already reviewed (it must leave the queue).
  PERFORM pg_temp.err_as(v_other, format('SELECT public.report_opinion_comment(%L, %L)', v_c, 'Hate speech or discrimination'));
  UPDATE public.forum_reports SET status = 'reviewed_kept' WHERE reported_by = v_other AND comment_id = v_c;

  -- Review queue v0: not for clients.
  v_msg := pg_temp.err_as(v_reporter, 'SELECT public.admin_list_priority_reports(50)');
  IF coalesce(v_msg, '') !~ 'permission denied' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in client could read review queue v0 (%)', v_msg;
  END IF;
  IF has_function_privilege('anon', 'public.admin_list_priority_reports(integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.admin_list_priority_reports(integer)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.admin_list_priority_reports(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 grants are wrong (service role only)';
  END IF;
  -- Oldest first: one transaction gives every row the same now().
  UPDATE public.forum_reports SET created_at = now() - interval '2 minutes' WHERE reported_by = v_reporter AND opinion_id = v_o;
  UPDATE public.forum_reports SET created_at = now() - interval '1 minute' WHERE reported_by = v_reporter AND comment_id = v_c;
  UPDATE public.forum_reports SET status = 'reviewed_kept'
   WHERE status = 'pending' AND opinion_id IS DISTINCT FROM v_o AND comment_id IS DISTINCT FROM v_c;
  PERFORM pg_temp.as_service();
  v_q := public.admin_list_priority_reports(50);
  RESET ROLE;
  SELECT array_agg(e->>'reason' ORDER BY ord) INTO v_ids FROM jsonb_array_elements(v_q) WITH ORDINALITY AS x(e, ord);
  IF v_ids IS DISTINCT FROM ARRAY['Someone may be at risk', 'Someone may be at risk'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 listed % (expected the two pending at-risk reports, not Spam)', v_ids;
  END IF;
  IF (v_q->0->>'content_type') <> 'opinion' OR (v_q->0->>'content_id')::uuid <> v_o
     OR char_length(v_q->0->>'excerpt') <> 280 OR (v_q->1->>'content_type') <> 'comment'
     OR (v_q->0) ? 'reported_by' OR v_q::text LIKE '%' || v_reporter::text || '%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 rows are wrong (oldest first, 280-character excerpt, no reporter): %', v_q;
  END IF;
  -- A client JWT is refused even by the owner role.
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.admin_list_priority_reports(50);
    RAISE EXCEPTION 'CONTRACT VIOLATED: review queue v0 answered an authenticated JWT';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'forbidden' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expected forbidden, got %', v_msg; END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_filter_contracts.sql 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  CONTRACT VIOLATED: the at-risk reason was refused`.

- [ ] **Step 3: Write migration 17 and its twin**

Create `supabase/migrations/20261104110000_opinion_at_risk_and_review_queue.sql` with exactly:

```sql
-- Spec 1 W9b, migration 17 (spec §4.7 #17): the "Someone may be at risk"
-- report reason and review queue v0.
--   * private.assert_valid_report_reason and private.is_priority_reason
--     re-created from their live bodies (20260802120000 and
--     20260716140000) with the one new reason added: valid, and priority.
--   * report_opinion and report_opinion_comment re-created from their live
--     bodies (20260802120000), adding only: an at-risk report is recorded
--     (priority) and never moves report_count, so it can never auto-hide
--     the post (D13: hiding a help-seeking post cuts the person off). Their
--     search_path (public, private) and grants are kept as live.
--   * admin_list_priority_reports(p_limit) (service role): pending priority
--     reports, oldest first, with the reason and a 280-character excerpt;
--     the named daily reviewer works it from the SQL editor (the W9b gate).
--     It never names the reporter.
-- Not gated: the server accepts the reason whatever opinions_safety_v1 is;
-- only the app offers it, and only with the flag on (plan P-12).
-- Nothing here tells the reported person anything.
-- Grants in 20261104110010_opinion_at_risk_and_review_queue_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.assert_valid_report_reason(p_reason text)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_reason IS NULL OR p_reason NOT IN (
    'Identifies a real person',
    'Harmful or dangerous content',
    'Explicit sexual content',
    'Hate speech or discrimination',
    'Spam',
    'Other',
    'Someone may be at risk' -- Spec 1 W9b
  ) THEN
    RAISE EXCEPTION 'invalid_reason' USING ERRCODE = '22023';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION private.is_priority_reason(p_reason text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT p_reason IN (
    'Identifies a real person',
    'Harmful or dangerous content',
    'Hate speech or discrimination',
    'Someone may be at risk' -- Spec 1 W9b
  );
$function$;

CREATE OR REPLACE FUNCTION public.report_opinion(p_opinion_id uuid, p_reason text DEFAULT 'Other')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_count int;
  v_inserted boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM private.assert_valid_report_reason(p_reason);

  INSERT INTO public.forum_reports (reported_by, opinion_id, reason, priority)
  VALUES (auth.uid(), p_opinion_id, p_reason, private.is_priority_reason(p_reason))
  ON CONFLICT (reported_by, opinion_id) WHERE opinion_id IS NOT NULL DO NOTHING
  RETURNING true INTO v_inserted;

  -- A repeat report from the same account is a silent no-op: the count must
  -- not move a second time for the same reporter.
  IF NOT v_inserted THEN
    RETURN;
  END IF;
  -- Spec 1 W9b (D13): an at-risk report reaches a person, never auto-hide.
  IF p_reason = 'Someone may be at risk' THEN RETURN; END IF;

  UPDATE public.opinions
  SET report_count = COALESCE(report_count, 0) + 1
  WHERE id = p_opinion_id
  RETURNING report_count INTO v_count;

  IF v_count >= 10 THEN
    UPDATE public.opinions SET hidden_pending_review = true WHERE id = p_opinion_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.report_opinion_comment(p_comment_id uuid, p_reason text DEFAULT 'Other')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_count int;
  v_inserted boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM private.assert_valid_report_reason(p_reason);

  INSERT INTO public.forum_reports (reported_by, comment_id, reason, priority)
  VALUES (auth.uid(), p_comment_id, p_reason, private.is_priority_reason(p_reason))
  ON CONFLICT (reported_by, comment_id) WHERE comment_id IS NOT NULL DO NOTHING
  RETURNING true INTO v_inserted;

  IF NOT v_inserted THEN
    RETURN;
  END IF;
  -- Spec 1 W9b (D13): an at-risk report reaches a person, never auto-hide.
  IF p_reason = 'Someone may be at risk' THEN RETURN; END IF;

  UPDATE public.opinion_comments
  SET report_count = COALESCE(report_count, 0) + 1
  WHERE id = p_comment_id
  RETURNING report_count INTO v_count;

  IF v_count >= 10 THEN
    UPDATE public.opinion_comments SET hidden_pending_review = true WHERE id = p_comment_id;
  END IF;
END;
$$;

-- Review queue v0 (spec §4.3 W9b).
CREATE OR REPLACE FUNCTION public.admin_list_priority_reports(p_limit int DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit constant int := least(greatest(coalesce(p_limit, 50), 1), 200);
BEGIN
  -- As admin_confirm_content_removal: a client JWT is refused; the
  -- service role and the SQL editor (no JWT, so no role) pass. EXECUTE is
  -- the service role's only.
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(q.item ORDER BY q.created_at, q.id)
      FROM (
        SELECT r.created_at, r.id,
               jsonb_build_object(
                 'report_id', r.id,
                 'reason', r.reason,
                 'reported_at', r.created_at,
                 'content_type', CASE WHEN r.opinion_id IS NOT NULL THEN 'opinion' ELSE 'comment' END,
                 'content_id', coalesce(r.opinion_id, r.comment_id),
                 'excerpt', left(coalesce(o.content, c.content), 280),
                 'content_removed', coalesce(o.removed_at, c.removed_at) IS NOT NULL,
                 'hidden_pending_review', coalesce(o.hidden_pending_review, c.hidden_pending_review, false)
               ) AS item
          FROM public.forum_reports AS r
          LEFT JOIN public.opinions AS o ON o.id = r.opinion_id
          LEFT JOIN public.opinion_comments AS c ON c.id = r.comment_id
         WHERE r.priority
           AND r.status = 'pending'
           AND (r.opinion_id IS NOT NULL OR r.comment_id IS NOT NULL)
         ORDER BY r.created_at, r.id
         LIMIT v_limit
      ) AS q
  ), '[]'::jsonb);
END;
$fn$;

REVOKE ALL ON FUNCTION private.assert_valid_report_reason(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.report_opinion(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.report_opinion_comment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_opinion(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_opinion_comment(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_list_priority_reports(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_priority_reports(int) TO service_role;

COMMIT;
```

Create `supabase/migrations/20261104110010_opinion_at_risk_and_review_queue_grants.sql` with exactly:

```sql
-- Spec 1 W9b: grants for 20261104110000_opinion_at_risk_and_review_queue.sql.
-- The two report RPCs keep their live grants (signed-in only); review queue
-- v0 is the service role's (and the SQL editor's) only.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.assert_valid_report_reason(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.report_opinion(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.report_opinion_comment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_opinion(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_opinion_comment(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_list_priority_reports(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_priority_reports(int) TO service_role;
COMMIT;
```

- [ ] **Step 4: Apply each file twice; diff the four functions against their live bodies; run the contract**

```bash
for i in 1 2; do
  for f in 20261104110000_opinion_at_risk_and_review_queue 20261104110010_opinion_at_risk_and_review_queue_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
D=.superpowers/sdd/2026-11-04-spec1-w9
for sig in 'public.report_opinion(uuid,text)' 'public.report_opinion_comment(uuid,text)' \
           'private.assert_valid_report_reason(text)' 'private.is_priority_reason(text)'; do
  echo "== $sig"
  n=$(echo "$sig" | sed 's/(.*//')
  diff "$D/before/$n.sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)") | grep '^[<>]'
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_filter_contracts.sql 2>&1 | tail -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0` lines; then exactly:

```text
== public.report_opinion(uuid,text)
>   -- Spec 1 W9b (D13): an at-risk report reaches a person, never auto-hide.
>   IF p_reason = 'Someone may be at risk' THEN RETURN; END IF;
== public.report_opinion_comment(uuid,text)
>   -- Spec 1 W9b (D13): an at-risk report reaches a person, never auto-hide.
>   IF p_reason = 'Someone may be at risk' THEN RETURN; END IF;
== private.assert_valid_report_reason(text)
<     'Other'
>     'Other',
>     'Someone may be at risk' -- Spec 1 W9b
== private.is_priority_reason(text)
<     'Hate speech or discrimination'
>     'Hate speech or discrimination',
>     'Someone may be at risk' -- Spec 1 W9b
```

and `NOTICE:  opinion_filter_contracts: all held`.

- [ ] **Step 5: Mutation checks (each must turn the contract red with the message quoted)**

Each mutant runs inside one transaction that the contract's own `ROLLBACK` ends, so `attune_spec3a` is never changed by a mutant.

```bash
M=supabase/migrations/20261104110000_opinion_at_risk_and_review_queue.sql
C=supabase/tests/opinion_filter_contracts.sql
D=.superpowers/sdd/2026-11-04-spec1-w9
python3 -I - "$M" "$D" <<'PY'
import pathlib, sys
m = pathlib.Path(sys.argv[1]).read_text()
d = pathlib.Path(sys.argv[2])
def body(m):
    # One transaction per mutant: the migration's own BEGIN/COMMIT go, so the
    # contract's ROLLBACK undoes the mutant too.
    assert m.count("\nBEGIN;\n") == 1 and m.count("\nCOMMIT;\n") == 1
    return m.replace("\nBEGIN;\n", "\n").replace("\nCOMMIT;\n", "\n")
m = body(m)
AR = "  -- Spec 1 W9b (D13): an at-risk report reaches a person, never auto-hide.\n  IF p_reason = 'Someone may be at risk' THEN RETURN; END IF;\n"
muts = {
  'at_risk_counts_opinion': (AR + "\n  UPDATE public.opinions\n", "\n  UPDATE public.opinions\n"),
  'at_risk_counts_comment': (AR + "\n  UPDATE public.opinion_comments\n", "\n  UPDATE public.opinion_comments\n"),
  'at_risk_invalid': ("    'Other',\n    'Someone may be at risk' -- Spec 1 W9b\n  ) THEN", "    'Other'\n  ) THEN"),
  'at_risk_not_priority': ("    'Hate speech or discrimination',\n    'Someone may be at risk' -- Spec 1 W9b\n  );", "    'Hate speech or discrimination'\n  );"),
  'queue_lists_everything': ("         WHERE r.priority\n           AND r.status = 'pending'", "         WHERE r.status = 'pending'"),
  'queue_lists_reviewed': ("         WHERE r.priority\n           AND r.status = 'pending'", "         WHERE r.priority"),
  'queue_no_role_check': ("  IF auth.role() <> 'service_role' THEN\n    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';\n  END IF;\n  RETURN coalesce((", "  RETURN coalesce(("),
  'queue_names_reporter': ("                 'reason', r.reason,", "                 'reason', r.reason, 'reported_by', r.reported_by,"),
  'queue_newest_first': ("jsonb_agg(q.item ORDER BY q.created_at, q.id)", "jsonb_agg(q.item ORDER BY q.created_at DESC, q.id)"),
}
for name, (a, b) in muts.items():
    assert m.count(a) == 1, (name, m.count(a))
    (d / f"mut_{name}.sql").write_text(m.replace(a, b))
(d / 'mut_queue_client_grant.sql').write_text("GRANT EXECUTE ON FUNCTION public.admin_list_priority_reports(int) TO authenticated;\n")
print(len(muts) + 1, 'mutants written')
PY
for f in $D/mut_*.sql; do
  m=$(basename $f .sql)
  echo "${m#mut_}: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f $f -f $C 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-150)"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | tail -1 | sed -E 's/^psql:[^ ]* //'
rm $D/mut_*.sql
```

Expected: `10 mutants written`, then:
- `at_risk_counts_comment`: `ERROR:  CONTRACT VIOLATED: an at-risk report moved report_count or hid the post`
- `at_risk_counts_opinion`: `ERROR:  CONTRACT VIOLATED: an at-risk report moved report_count or hid the post`
- `at_risk_invalid`: `ERROR:  CONTRACT VIOLATED: the at-risk reason was refused`
- `at_risk_not_priority`: `ERROR:  CONTRACT VIOLATED: the at-risk reports were not recorded once each, as priority`
- `queue_client_grant`: `ERROR:  CONTRACT VIOLATED: a signed-in client could read review queue v0 (forbidden)`
- `queue_lists_everything`: `ERROR:  CONTRACT VIOLATED: review queue v0 listed {"Someone may be at risk","Someone may be at risk",Spam} (expected the two pending at-risk reports, …`
- `queue_lists_reviewed`: `ERROR:  CONTRACT VIOLATED: review queue v0 listed {"Someone may be at risk","Someone may be at risk","Hate speech or discrimination"} (expected the tw …`
- `queue_names_reporter`: `ERROR:  CONTRACT VIOLATED: review queue v0 rows are wrong (oldest first, 280-character excerpt, no reporter): [{"reason": "Someone may be at risk", "e …`
- `queue_newest_first`: `ERROR:  CONTRACT VIOLATED: review queue v0 rows are wrong (oldest first, 280-character excerpt, no reporter): [{"reason": "Someone may be at risk", "e …`
- `queue_no_role_check`: `ERROR:  CONTRACT VIOLATED: review queue v0 answered an authenticated JWT`

then `NOTICE:  opinion_filter_contracts: all held`.

- [ ] **Step 6: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`, edit 1 of 1. Replace exactly:

```sql
\i supabase/migrations/20261104100010_opinion_content_filter_grants.sql
```

with:

```sql
\i supabase/migrations/20261104100010_opinion_content_filter_grants.sql

-- Spec 1 W9b: the report RPCs keep their grants; review queue v0 is the
-- service role's.
\i supabase/migrations/20261104110010_opinion_at_risk_and_review_queue_grants.sql
```

- [ ] **Step 7: Run tests**

```bash
D=.superpowers/sdd/2026-11-04-spec1-w9
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-after-task5.txt
grep '^FAIL' $D/sql-after-task5.txt | comm -13 <(grep '^FAIL' $D/sql-baseline.txt) -
grep -E 'opinion_filter|forum_retirement' $D/sql-after-task5.txt
```

Expected: no new FAIL line; `PASS forum_retirement_contracts.sql` (its section E reports with `Spam`, unchanged), `PASS opinion_filter_contracts.sql`.

### Task 6: Migration 18: the restored notices and the strike-3 fix (D17; OPN-BAN-42702; §4.3 W9b, §4.7 #18, §7.1, §7.4, §9; P-16)

**Files:**
- Create: `supabase/migrations/20261104120000_opinion_moderation_notices.sql`
- Create: `supabase/migrations/20261104120010_opinion_moderation_notices_grants.sql`
- Create: `supabase/tests/opinion_moderation_notice_contracts.sql`
- Modify: `scripts/local_pg_grants.sql` (one `\i` block; never run)

**Interfaces:**
- Consumes: the live `admin_confirm_content_removal` (Task 1's `before/public.admin_confirm_content_removal.sql`, identical to `20260802120000:205-267`); `private.enqueue_forum_notification`; W1a's `profiles_guard_moderation_columns`.
- Produces: `public.admin_confirm_content_removal(p_content_type text, p_content_id uuid) RETURNS TABLE (violation_count int, banned_until timestamptz)`, unchanged in shape and grants (service role; refused to clients), now reaching strike 3 and queueing `forum_content_removed` (`opinion_id` or `comment_id`) and `forum_posting_banned` to the author only. Spec 3 W3 later rewrites it from this body (removing only `forum_post`).

- [ ] **Step 1: Write the failing contract**

Create `supabase/tests/opinion_moderation_notice_contracts.sql` with exactly:

```sql
-- supabase/tests/opinion_moderation_notice_contracts.sql
-- Spec 1 W9b (D17, §4.3 W9b, §7.1, §7.4; OPN-BAN-42702): as the service
-- role, admin_confirm_content_removal queues "Post removed" for the author
-- of each removal it confirms (opinion_id or comment_id), nothing for
-- content already removed, and "Posting paused" when the 7-day ban starts
-- or moves. It reaches strike 3 without 42702, sets the first ban 7 days
-- ahead and moves a later one forward from the existing ban, never back,
-- with the W1a profiles guard in place. Strikes 1 and 2 return exactly what
-- the live function returned. Clients cannot call it. Nobody but the author
-- is told anything.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_moderation_notice_contracts.sql
-- Fixture ids 5f9b0000-0000-0000-0000-0000000000NN, phones +155586010NN
-- (spec §7.1's W9 range) on auth.users and public.users.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5f9b0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- The connecting (owner) role with a service-role JWT: how the SQL editor
-- and edge functions reach admin_confirm_content_removal.
CREATE FUNCTION pg_temp.as_service() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
END $$;

-- Pending notices of [p_type] for [p_user].
CREATE FUNCTION pg_temp.notices(p_user uuid, p_type text) RETURNS SETOF jsonb LANGUAGE sql AS $$
  SELECT n.metadata FROM public.scheduled_notifications AS n
   WHERE n.user_id = p_user AND n.metadata->>'type' = p_type
   ORDER BY n.created_at, n.id;
$$;

INSERT INTO auth.users (id, phone)
SELECT pg_temp.id(n), '155586010' || n FROM unnest(ARRAY['01', '02', '03']) AS n
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name)
SELECT pg_temp.id(n), '+155586010' || n, 'W9b notices ' || n FROM unnest(ARRAY['01', '02', '03']) AS n
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id)
SELECT pg_temp.id(n) FROM unnest(ARRAY['01', '02', '03']) AS n
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- A. Grants and the guard: service role only; the W1a moderation guard is
--    on profiles (the definer still moves both columns, below).
-- =====================================================================
DO $$
DECLARE
  v_msg text;
BEGIN
  IF has_function_privilege('anon', 'public.admin_confirm_content_removal(text,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.admin_confirm_content_removal(text,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.admin_confirm_content_removal(text,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: admin_confirm_content_removal must be the service role''s only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.profiles'::regclass
                  AND tgname = 'profiles_guard_moderation_columns' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the W1a profiles guard is missing, so this contract proves nothing about it';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', pg_temp.id('01'), 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.admin_confirm_content_removal('opinion', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in client ran admin_confirm_content_removal';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF coalesce(v_msg, '') !~ 'permission denied' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: expected permission denied (42501), got %', v_msg;
    END IF;
  END;
  RESET ROLE;
  -- The function's own gate: a client JWT is refused even for its owner.
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.admin_confirm_content_removal('opinion', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: admin_confirm_content_removal answered an authenticated JWT';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'forbidden' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expected forbidden, got %', v_msg; END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- =====================================================================
-- B. The ladder: A's four opinions removed one by one; B's comment once;
--    a repeat removal changes nothing.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.id('01');
  v_b constant uuid := pg_temp.id('02');
  v_bystander constant uuid := pg_temp.id('03');
  v_o uuid[] := ARRAY[]::uuid[];
  v_c uuid;
  v_id uuid;
  v_before_others int;
  v_first_ban timestamptz;
  r record;
  m jsonb;
  i int;
BEGIN
  FOR i IN 1 .. 4 LOOP
    INSERT INTO public.opinions (user_id, content) VALUES (v_a, 'W9b contract: post ' || i) RETURNING id INTO v_id;
    v_o := v_o || v_id;
  END LOOP;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content)
  VALUES (v_o[1], v_b, 'W9b contract: a comment to remove') RETURNING id INTO v_c;
  SELECT count(*) INTO v_before_others FROM public.scheduled_notifications WHERE user_id NOT IN (v_a, v_b);

  PERFORM pg_temp.as_service();

  -- Strike 1: exactly the live answer, and one removal notice with the opinion.
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o[1]);
  IF r.violation_count IS DISTINCT FROM 1 OR r.banned_until IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 1 returned (%, %), expected (1, NULL)', r.violation_count, r.banned_until;
  END IF;
  IF (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_content_removed')) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 1 queued % removal notices, expected 1', (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_content_removed'));
  END IF;
  m := (SELECT x FROM pg_temp.notices(v_a, 'forum_content_removed') AS x LIMIT 1);
  IF m->>'opinion_id' IS DISTINCT FROM v_o[1]::text OR m ? 'comment_id'
     OR m->>'title' IS DISTINCT FROM 'Post removed'
     OR m->>'body' IS DISTINCT FROM 'One of your posts was removed for breaking the Opinions guidelines.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the removal notice is wrong: %', m;
  END IF;

  -- The same opinion again: nothing.
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o[1]);
  IF r.violation_count IS DISTINCT FROM 0 OR r.banned_until IS NOT NULL
     OR (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_content_removed')) <> 1
     OR (SELECT confirmed_violation_count FROM public.profiles WHERE id = v_a) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: removing already-removed content changed something';
  END IF;

  -- A comment: one notice with the comment.
  SELECT * INTO r FROM public.admin_confirm_content_removal('comment', v_c);
  IF r.violation_count IS DISTINCT FROM 1
     OR (SELECT count(*) FROM pg_temp.notices(v_b, 'forum_content_removed')) <> 1
     OR (SELECT x->>'comment_id' FROM pg_temp.notices(v_b, 'forum_content_removed') AS x LIMIT 1) IS DISTINCT FROM v_c::text
     OR (SELECT x ? 'opinion_id' FROM pg_temp.notices(v_b, 'forum_content_removed') AS x LIMIT 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a comment removal did not queue one notice with comment_id';
  END IF;

  -- Strike 2: exactly the live answer; no ban notice yet.
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o[2]);
  IF r.violation_count IS DISTINCT FROM 2 OR r.banned_until IS NOT NULL
     OR (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned')) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 2 returned (%, %) or queued a ban notice', r.violation_count, r.banned_until;
  END IF;

  -- Strike 3 (OPN-BAN-42702): no 42702; the first ban, 7 days ahead.
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o[3]);
  IF r.violation_count IS DISTINCT FROM 3 OR r.banned_until IS DISTINCT FROM now() + interval '7 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 3 returned (%, %), expected (3, now() + 7 days)', r.violation_count, r.banned_until;
  END IF;
  IF (SELECT confirmed_violation_count FROM public.profiles WHERE id = v_a) <> 3
     OR (SELECT banned_until FROM public.profiles WHERE id = v_a) IS DISTINCT FROM now() + interval '7 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 3 did not leave count 3 and a ban 7 days ahead';
  END IF;
  IF (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned')) <> 1
     OR (SELECT x->>'body' FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x LIMIT 1) IS DISTINCT FROM 'You can''t post in Opinions for 7 days.'
     OR (SELECT x->>'title' FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x LIMIT 1) IS DISTINCT FROM 'Posting paused'
     OR (SELECT bool_or(x ? 'opinion_id' OR x ? 'comment_id') FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 3 did not queue one new-ban notice: %',
      (SELECT jsonb_agg(x) FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x);
  END IF;
  IF (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_content_removed')) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: A has % removal notices after three removals', (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_content_removed'));
  END IF;
  v_first_ban := (SELECT banned_until FROM public.profiles WHERE id = v_a);

  -- Strike 4, during the ban: forward 7 days from the ban, never back.
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o[4]);
  IF r.violation_count IS DISTINCT FROM 4 OR r.banned_until IS DISTINCT FROM v_first_ban + interval '7 days'
     OR (SELECT banned_until FROM public.profiles WHERE id = v_a) IS DISTINCT FROM v_first_ban + interval '7 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 4 gave a ban of %, expected % (the existing ban + 7 days)', r.banned_until, v_first_ban + interval '7 days';
  END IF;
  -- (One transaction gives both notices the same created_at, so they are
  -- counted by body, not ordered.)
  IF (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned')) <> 2
     OR (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x
          WHERE x->>'body' = 'Your pause on posting in Opinions has been extended.') <> 1
     OR (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x
          WHERE x->>'body' = 'You can''t post in Opinions for 7 days.') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 4 did not queue the extended-ban notice';
  END IF;

  -- The kept forum branch and the type check are unchanged.
  SELECT * INTO r FROM public.admin_confirm_content_removal('forum_post', gen_random_uuid());
  IF r.violation_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the forum_post branch changed';
  END IF;
  BEGIN
    PERFORM public.admin_confirm_content_removal('poll', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown content type was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  RESET ROLE;

  -- Only the authors were told anything.
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id NOT IN (v_a, v_b)) <> v_before_others
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = v_bystander) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone other than the author was notified';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'opinion_moderation_notice_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to make sure it fails, and see today's strike-3 bug**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_moderation_notice_contracts.sql 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' \
  -c 'GRANT EXECUTE ON FUNCTION public.admin_confirm_content_removal(text, uuid) TO service_role' \
  -f supabase/tests/opinion_moderation_notice_contracts.sql 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | head -1
```

Expected: `ERROR:  CONTRACT VIOLATED: admin_confirm_content_removal must be the service role's only` (the local database has no explicit service-role grant yet); then, with that grant given inside a rolled-back transaction, `ERROR:  CONTRACT VIOLATED: strike 1 queued 0 removal notices, expected 1` (the notices the 20260802 rewrite dropped, Spec 3 V8).

- [ ] **Step 3: Write migration 18 and its twin**

Create `supabase/migrations/20261104120000_opinion_moderation_notices.sql` with exactly:

```sql
-- Spec 1 W9b, migration 18 (spec §4.7 #18; D17; Spec 3 V8 and §10 F-1):
-- the two Opinions moderation notices restored, and OPN-BAN-42702 fixed.
-- public.admin_confirm_content_removal is re-created from its LIVE body
-- (20260802120000:205-267, checked identical to pg_get_functiondef on
-- attune_spec3a while writing the plan), keeping the service-role gate,
-- the three content-type branches (Spec 3 W3 removes forum_post later from
-- this body), the idempotent no-op, the strike count and the never-shorten
-- ban extension, with only:
--   * SET search_path = '' (every name was already schema-qualified);
--   * OPN-BAN-42702: the ban-extension SELECT qualifies the column
--     (public.profiles AS p ... p.banned_until). RETURNS TABLE
--     (violation_count int, banned_until timestamptz) declares an OUT
--     variable named banned_until, so the bare column raised 42702 at the
--     third confirmed removal and no ban was ever set. The same SELECT now
--     also reads the ban as it was (v_prev_ban), for the notice's wording;
--   * the two notices the 20260802 rewrite dropped, through the kept
--     private.enqueue_forum_notification, to the author only:
--     forum_content_removed after a removal that found an author (with
--     p_opinion_id or p_comment_id), and forum_posting_banned when the ban
--     starts ("You can't post in Opinions for 7 days.") or moves ("Your
--     pause on posting in Opinions has been extended."). Nothing is queued
--     when the content was already removed. Taps land on home
--     (notification_config.dart, unchanged).
-- Not gated: it restores live behaviour lost in 20260802 (spec §8 W9b). The
-- return shape is unchanged. Release note: the first real 7-day bans
-- follow this fix (spec §9).
-- Grants in 20261104120010_opinion_moderation_notices_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.admin_confirm_content_removal(p_content_type text, p_content_id uuid)
 RETURNS TABLE(violation_count integer, banned_until timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_author_id uuid;
  v_new_count int;
  v_ban_until timestamptz;
  v_prev_ban timestamptz; -- Spec 1 W9b
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  IF p_content_type = 'opinion' THEN
    UPDATE public.opinions SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSIF p_content_type = 'comment' THEN
    UPDATE public.opinion_comments SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSIF p_content_type = 'forum_post' THEN
    UPDATE public.forum_posts SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSE
    RAISE EXCEPTION 'invalid_content_type' USING ERRCODE = '22023';
  END IF;

  IF v_author_id IS NULL THEN
    RETURN QUERY SELECT 0, NULL::timestamptz;
    RETURN;
  END IF;

  UPDATE public.profiles
  SET confirmed_violation_count = confirmed_violation_count + 1
  WHERE id = v_author_id
  RETURNING confirmed_violation_count INTO v_new_count;

  -- Spec 1 W9b (D17): the removal notice, to the author only.
  PERFORM private.enqueue_forum_notification(
    p_user_id    => v_author_id,
    p_title      => 'Post removed',
    p_body       => 'One of your posts was removed for breaking the Opinions guidelines.',
    p_type       => 'forum_content_removed',
    p_opinion_id => CASE WHEN p_content_type = 'opinion' THEN p_content_id END,
    p_comment_id => CASE WHEN p_content_type = 'comment' THEN p_content_id END
  );

  IF v_new_count >= 3 THEN
    -- Never move the ban backward: a moderator confirming several
    -- violations in one sitting extends the ban past whichever is later
    -- (now, or an existing future banned_until), and never re-shortens or
    -- re-applies a ban that already ran its course before this confirmation.
    SELECT GREATEST(COALESCE(p.banned_until, now()), now()) + interval '7 days', p.banned_until -- Spec 1 W9b: OPN-BAN-42702
    INTO v_ban_until, v_prev_ban
    FROM public.profiles AS p WHERE p.id = v_author_id;

    UPDATE public.profiles
    SET banned_until = v_ban_until
    WHERE id = v_author_id;

    -- Spec 1 W9b (D17): the ban notice, new or extended.
    PERFORM private.enqueue_forum_notification(
      p_user_id => v_author_id,
      p_title   => 'Posting paused',
      p_body    => CASE WHEN v_prev_ban > now()
                        THEN 'Your pause on posting in Opinions has been extended.'
                        ELSE 'You can''t post in Opinions for 7 days.' END,
      p_type    => 'forum_posting_banned'
    );
  END IF;

  RETURN QUERY SELECT v_new_count, v_ban_until;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_content_removal(text, uuid) TO service_role;

COMMIT;
```

Create `supabase/migrations/20261104120010_opinion_moderation_notices_grants.sql` with exactly:

```sql
-- Spec 1 W9b: grants for 20261104120000_opinion_moderation_notices.sql.
-- admin_confirm_content_removal stays the service role's only (and the SQL
-- editor's, as its owner); no client may call it.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_content_removal(text, uuid) TO service_role;
COMMIT;
```

- [ ] **Step 4: Apply each file twice; diff against the live body; run the contract (three times: it must not depend on ordering luck)**

```bash
for i in 1 2; do
  for f in 20261104120000_opinion_moderation_notices 20261104120010_opinion_moderation_notices_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
D=.superpowers/sdd/2026-11-04-spec1-w9
diff $D/before/public.admin_confirm_content_removal.sql \
  <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('public.admin_confirm_content_removal(text,uuid)'::regprocedure)") | grep '^[<>]'
for i in 1 2 3; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_moderation_notice_contracts.sql 2>&1 | tail -1 | sed -E 's/^psql:[^ ]* //'
done
```

Expected: four `exit=0` lines; then exactly this diff (the `search_path`, `v_prev_ban`, the two notices, and the qualified ban `SELECT`; nothing else):

```text
<  SET search_path TO 'public'
>  SET search_path TO ''
>   v_prev_ban timestamptz; -- Spec 1 W9b
>   -- Spec 1 W9b (D17): the removal notice, to the author only.
>   PERFORM private.enqueue_forum_notification(
>     p_user_id    => v_author_id,
>     p_title      => 'Post removed',
>     p_body       => 'One of your posts was removed for breaking the Opinions guidelines.',
>     p_type       => 'forum_content_removed',
>     p_opinion_id => CASE WHEN p_content_type = 'opinion' THEN p_content_id END,
>     p_comment_id => CASE WHEN p_content_type = 'comment' THEN p_content_id END
>   );
> 
<     SELECT GREATEST(COALESCE(banned_until, now()), now()) + interval '7 days'
<     INTO v_ban_until
<     FROM public.profiles WHERE id = v_author_id;
>     SELECT GREATEST(COALESCE(p.banned_until, now()), now()) + interval '7 days', p.banned_until -- Spec 1 W9b: OPN-BAN-42702
>     INTO v_ban_until, v_prev_ban
>     FROM public.profiles AS p WHERE p.id = v_author_id;
> 
>     -- Spec 1 W9b (D17): the ban notice, new or extended.
>     PERFORM private.enqueue_forum_notification(
>       p_user_id => v_author_id,
>       p_title   => 'Posting paused',
>       p_body    => CASE WHEN v_prev_ban > now()
>                         THEN 'Your pause on posting in Opinions has been extended.'
>                         ELSE 'You can''t post in Opinions for 7 days.' END,
>       p_type    => 'forum_posting_banned'
>     );
```

then `NOTICE:  opinion_moderation_notice_contracts: all held` three times.

- [ ] **Step 5: Mutation checks (each must turn the contract red with the message quoted)**

```bash
M=supabase/migrations/20261104120000_opinion_moderation_notices.sql
C=supabase/tests/opinion_moderation_notice_contracts.sql
D=.superpowers/sdd/2026-11-04-spec1-w9
python3 -I - "$M" "$D" <<'PY'
import pathlib, sys
m = pathlib.Path(sys.argv[1]).read_text()
d = pathlib.Path(sys.argv[2])
def body(m):
    # One transaction per mutant: the migration's own BEGIN/COMMIT go, so the
    # contract's ROLLBACK undoes the mutant too.
    assert m.count("\nBEGIN;\n") == 1 and m.count("\nCOMMIT;\n") == 1
    return m.replace("\nBEGIN;\n", "\n").replace("\nCOMMIT;\n", "\n")
m = body(m)
muts = {
  'no_removal_notice': ("  -- Spec 1 W9b (D17): the removal notice, to the author only.\n  PERFORM private.enqueue_forum_notification(\n    p_user_id    => v_author_id,\n    p_title      => 'Post removed',\n    p_body       => 'One of your posts was removed for breaking the Opinions guidelines.',\n    p_type       => 'forum_content_removed',\n    p_opinion_id => CASE WHEN p_content_type = 'opinion' THEN p_content_id END,\n    p_comment_id => CASE WHEN p_content_type = 'comment' THEN p_content_id END\n  );\n", ""),
  'no_ban_notice': ("    -- Spec 1 W9b (D17): the ban notice, new or extended.\n    PERFORM private.enqueue_forum_notification(\n      p_user_id => v_author_id,\n      p_title   => 'Posting paused',\n      p_body    => CASE WHEN v_prev_ban > now()\n                        THEN 'Your pause on posting in Opinions has been extended.'\n                        ELSE 'You can''t post in Opinions for 7 days.' END,\n      p_type    => 'forum_posting_banned'\n    );\n", ""),
  'bare_banned_until': ("    SELECT GREATEST(COALESCE(p.banned_until, now()), now()) + interval '7 days', p.banned_until -- Spec 1 W9b: OPN-BAN-42702\n    INTO v_ban_until, v_prev_ban\n    FROM public.profiles AS p WHERE p.id = v_author_id;",
                        "    SELECT GREATEST(COALESCE(banned_until, now()), now()) + interval '7 days', banned_until\n    INTO v_ban_until, v_prev_ban\n    FROM public.profiles WHERE id = v_author_id;"),
  'ban_overwrites': ("GREATEST(COALESCE(p.banned_until, now()), now()) + interval '7 days'", "now() + interval '7 days'"),
  'always_new_ban_body': ("CASE WHEN v_prev_ban > now()", "CASE WHEN false"),
  'no_role_check': ("  IF auth.role() <> 'service_role' THEN\n    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';\n  END IF;\n\n  IF p_content_type", "  IF p_content_type"),
}
for name, (a, b) in muts.items():
    assert m.count(a) == 1, (name, m.count(a))
    (d / f"mut_{name}.sql").write_text(m.replace(a, b))
(d / 'mut_client_grant.sql').write_text("GRANT EXECUTE ON FUNCTION public.admin_confirm_content_removal(text, uuid) TO authenticated;\n")
print(len(muts) + 1, 'mutants written')
PY
for f in $D/mut_*.sql; do
  m=$(basename $f .sql)
  echo "${m#mut_}: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f $f -f $C 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-150)"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | tail -1 | sed -E 's/^psql:[^ ]* //'
rm $D/mut_*.sql
```

Expected: `7 mutants written`, then:
- `always_new_ban_body`: `ERROR:  CONTRACT VIOLATED: strike 4 did not queue the extended-ban notice`
- `ban_overwrites`: `ERROR:  CONTRACT VIOLATED: strike 4 gave a ban of 2026-11-11 04:01:01.813546+00, expected 2026-11-18 04:01:01.813546+00 (the existing ban + 7 days)`
- `bare_banned_until`: `ERROR:  column reference "banned_until" is ambiguous`
- `client_grant`: `ERROR:  CONTRACT VIOLATED: admin_confirm_content_removal must be the service role's only`
- `no_ban_notice`: `ERROR:  CONTRACT VIOLATED: strike 3 did not queue one new-ban notice: <NULL>`
- `no_removal_notice`: `ERROR:  CONTRACT VIOLATED: strike 1 queued 0 removal notices, expected 1`
- `no_role_check`: `ERROR:  CONTRACT VIOLATED: admin_confirm_content_removal answered an authenticated JWT`

then `NOTICE:  opinion_moderation_notice_contracts: all held`. (`bare_banned_until` is today's bug, OPN-BAN-42702: the contract reaches strike 3 and fails exactly as the live function does.)

- [ ] **Step 6: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`, edit 1 of 1. Replace exactly:

```sql
\i supabase/migrations/20261104110010_opinion_at_risk_and_review_queue_grants.sql
```

with:

```sql
\i supabase/migrations/20261104110010_opinion_at_risk_and_review_queue_grants.sql

-- Spec 1 W9b: admin_confirm_content_removal stays the service role's.
\i supabase/migrations/20261104120010_opinion_moderation_notices_grants.sql
```

- [ ] **Step 7: Run tests**

```bash
D=.superpowers/sdd/2026-11-04-spec1-w9
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-after-task6.txt
grep '^FAIL' $D/sql-after-task6.txt | comm -13 <(grep '^FAIL' $D/sql-baseline.txt) -
grep -E 'opinion_moderation|forum_retirement|identity_foundation' $D/sql-after-task6.txt
```

Expected: no new FAIL line; `PASS forum_retirement_contracts.sql` (section E's strikes 1 and 2 and its count-by-type notice check are unchanged), `PASS identity_foundation_contracts.sql` (the W1a guard), `PASS opinion_moderation_notice_contracts.sql`.

### Task 7: Migration 19 and the repository: removing your own opinion or comment (OPN-DELETE-RLS; §4.3 W9b, §4.7 #19, §5.2, §7.1, §9; P-17)

**Files:**
- Create: `supabase/migrations/20261104130000_opinion_remove_own.sql`
- Create: `supabase/migrations/20261104130010_opinion_remove_own_grants.sql`
- Create: `supabase/tests/opinion_remove_own_contracts.sql`
- Create: `test/features/opinions/w9/opinion_remove_own_repository_test.dart`
- Modify: `lib/features/opinions/data/repositories/opinion_repository.dart` (`deleteOpinion`, `deleteComment`; nothing else)
- Modify: `scripts/local_pg_grants.sql` (one `\i` block; never run)

**Interfaces:**
- Consumes: the `opinions_public_read` / `opinion_comments_public_read` SELECT policies (unchanged), the feed reads.
- Produces: `public.remove_my_opinion(p_opinion_id uuid) → void`, `public.remove_my_comment(p_comment_id uuid) → void` (authenticated; never anon; a non-owner, missing or already-removed id changes nothing and raises nothing; the comment one lowers `comment_count` once, never below 0). `OpinionRepository.deleteOpinion` / `deleteComment` call them and nothing else. Ungated.

- [ ] **Step 1: Write the failing contract and the failing repository test**

Create `supabase/tests/opinion_remove_own_contracts.sql` with exactly:

```sql
-- supabase/tests/opinion_remove_own_contracts.sql
-- Spec 1 W9b (§4.3 W9b, §7.1, §9; OPN-DELETE-RLS): as authenticated, the
-- author's remove_my_opinion sets removed_at and the opinion leaves
-- Discover, its tag page and the Following feed; remove_my_comment sets
-- removed_at and lowers the parent's comment_count by exactly 1, once; a
-- second call changes nothing; someone else's call changes nothing; a
-- banned author can still remove; anon is refused; comment_count never goes
-- below 0; and a direct client UPDATE of removed_at by the author is still
-- refused (the fix is the RPC, not a looser policy).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_remove_own_contracts.sql
-- Fixture ids 5f9c0000-0000-0000-0000-0000000000NN, phones +155586020NN
-- (spec §7.1's W9 range) on auth.users and public.users.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5f9c0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- The message raised by [p_sql] run as [p_user] (NULL when it ran).
CREATE FUNCTION pg_temp.err_as(p_user uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    v := SQLERRM;
  END;
  RESET ROLE;
  RETURN v;
END $$;

-- Does [p_viewer] see opinion [p_id] in Discover, on the tag page and in
-- Following?
CREATE FUNCTION pg_temp.seen(p_viewer uuid, p_id uuid, p_tag text)
RETURNS TABLE (discover boolean, tag boolean, following boolean) LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.as_user(p_viewer);
  discover := EXISTS (SELECT 1 FROM public.get_discover_opinions(200, 0, NULL) AS d WHERE d.id = p_id);
  tag := EXISTS (SELECT 1 FROM public.get_opinions_by_tag(p_tag, 200, 0) AS t WHERE t.id = p_id);
  following := EXISTS (SELECT 1 FROM public.get_following_opinions(200, 0) AS f WHERE f.id = p_id);
  RESET ROLE;
  RETURN NEXT;
END $$;

INSERT INTO auth.users (id, phone)
SELECT pg_temp.id(n), '155586020' || n FROM unnest(ARRAY['01', '02']) AS n
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name)
SELECT pg_temp.id(n), '+155586020' || n, 'W9b remove ' || n FROM unnest(ARRAY['01', '02']) AS n
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id)
SELECT pg_temp.id(n) FROM unnest(ARRAY['01', '02']) AS n
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- A. Grants: signed-in only; no SELECT policy was loosened.
-- =====================================================================
DO $$
BEGIN
  IF to_regprocedure('public.remove_my_opinion(uuid)') IS NULL
     OR to_regprocedure('public.remove_my_comment(uuid)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: remove_my_opinion / remove_my_comment are missing';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.remove_my_opinion(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.remove_my_comment(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.remove_my_opinion(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.remove_my_comment(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: remove_my_* grants are wrong (signed-in only, never anon)';
  END IF;
  IF (SELECT qual FROM pg_policies WHERE schemaname = 'public' AND tablename = 'opinions' AND policyname = 'opinions_public_read')
       IS DISTINCT FROM '((removed_at IS NULL) AND (hidden_pending_review = false))'
     OR (SELECT qual FROM pg_policies WHERE schemaname = 'public' AND tablename = 'opinion_comments' AND policyname = 'opinion_comments_public_read')
       IS DISTINCT FROM '((removed_at IS NULL) AND (hidden_pending_review = false))' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a SELECT policy on opinions or opinion_comments was changed';
  END IF;
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  BEGIN
    PERFORM public.remove_my_opinion(gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon ran remove_my_opinion';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.remove_my_comment(gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon ran remove_my_comment';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
END $$;

-- =====================================================================
-- B. Opinions and comments.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.id('01');
  v_b constant uuid := pg_temp.id('02');
  v_tag constant text := (SELECT slug FROM public.tags ORDER BY slug LIMIT 1);
  v_o uuid;
  v_o2 uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_handle text;
  v_msg text;
  s record;
BEGIN
  INSERT INTO public.opinions (user_id, content) VALUES (v_a, 'W9b contract: my post, to delete.') RETURNING id INTO v_o;
  INSERT INTO public.opinions (user_id, content, comment_count) VALUES (v_a, 'W9b contract: a post with comments.', 0) RETURNING id INTO v_o2;
  INSERT INTO public.opinion_tags (opinion_id, tag_id) SELECT v_o, t.id FROM public.tags AS t WHERE t.slug = v_tag;
  -- B follows A (by the opaque handle, as the app does).
  PERFORM pg_temp.as_user(v_b);
  SELECT d.author_handle INTO v_handle FROM public.get_discover_opinions(200, 0, NULL) AS d WHERE d.id = v_o;
  PERFORM public.follow_opinion_author(v_handle);
  RESET ROLE;
  SELECT * INTO s FROM pg_temp.seen(v_b, v_o, v_tag);
  IF NOT (s.discover AND s.tag AND s.following) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: B does not see the post before removal (%, %, %)', s.discover, s.tag, s.following;
  END IF;

  -- A direct client UPDATE of removed_at is still refused (RLS).
  v_msg := pg_temp.err_as(v_a, format('UPDATE public.opinions SET removed_at = now() WHERE id = %L', v_o));
  IF coalesce(v_msg, '') !~ 'row-level security' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a direct client UPDATE of removed_at was not refused by RLS (%)', v_msg;
  END IF;

  -- Someone else: nothing changes, nothing is raised. (Each call is its own
  -- statement: a check in the same statement would read the snapshot from
  -- before the call.)
  v_msg := pg_temp.err_as(v_b, format('SELECT public.remove_my_opinion(%L)', v_o));
  IF v_msg IS NOT NULL OR (SELECT removed_at FROM public.opinions WHERE id = v_o) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another user removed the opinion, or the call raised';
  END IF;

  -- A banned author still removes (removing is not posting).
  UPDATE public.profiles SET banned_until = now() + interval '7 days' WHERE id = v_a;
  v_msg := pg_temp.err_as(v_a, format('SELECT public.remove_my_opinion(%L)', v_o));
  IF v_msg IS NOT NULL OR (SELECT removed_at FROM public.opinions WHERE id = v_o) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author could not remove their own opinion';
  END IF;
  SELECT * INTO s FROM pg_temp.seen(v_b, v_o, v_tag);
  IF s.discover OR s.tag OR s.following THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a removed opinion still shows (discover %, tag %, following %)', s.discover, s.tag, s.following;
  END IF;
  -- Again: nothing, no error; a missing id: nothing.
  IF pg_temp.err_as(v_a, format('SELECT public.remove_my_opinion(%L)', v_o)) IS NOT NULL
     OR pg_temp.err_as(v_a, format('SELECT public.remove_my_opinion(%L)', gen_random_uuid())) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeat or missing remove_my_opinion raised';
  END IF;
  UPDATE public.profiles SET banned_until = NULL WHERE id = v_a;

  -- Comments: A's two comments on A's post, counted 2.
  INSERT INTO public.opinion_comments (opinion_id, user_id, content) VALUES (v_o2, v_a, 'W9b contract: first') RETURNING id INTO v_c1;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content) VALUES (v_o2, v_a, 'W9b contract: second') RETURNING id INTO v_c2;
  UPDATE public.opinions SET comment_count = 2 WHERE id = v_o2;
  v_msg := pg_temp.err_as(v_a, format('UPDATE public.opinion_comments SET removed_at = now() WHERE id = %L', v_c1));
  IF coalesce(v_msg, '') !~ 'row-level security' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a direct client UPDATE of a comment''s removed_at was not refused (%)', v_msg;
  END IF;
  v_msg := pg_temp.err_as(v_b, format('SELECT public.remove_my_comment(%L)', v_c1));
  IF v_msg IS NOT NULL
     OR (SELECT removed_at FROM public.opinion_comments WHERE id = v_c1) IS NOT NULL
     OR (SELECT comment_count FROM public.opinions WHERE id = v_o2) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another user''s remove_my_comment changed the comment or the count';
  END IF;
  v_msg := pg_temp.err_as(v_a, format('SELECT public.remove_my_comment(%L)', v_c1));
  IF v_msg IS NOT NULL
     OR (SELECT removed_at FROM public.opinion_comments WHERE id = v_c1) IS NULL
     OR (SELECT comment_count FROM public.opinions WHERE id = v_o2) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author''s remove_my_comment did not remove it and lower the count by 1 (count %)',
      (SELECT comment_count FROM public.opinions WHERE id = v_o2);
  END IF;
  v_msg := pg_temp.err_as(v_a, format('SELECT public.remove_my_comment(%L)', v_c1));
  IF v_msg IS NOT NULL OR (SELECT comment_count FROM public.opinions WHERE id = v_o2) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second remove_my_comment decremented again';
  END IF;
  -- Never below 0.
  UPDATE public.opinions SET comment_count = 0 WHERE id = v_o2;
  v_msg := pg_temp.err_as(v_a, format('SELECT public.remove_my_comment(%L)', v_c2));
  IF v_msg IS NOT NULL
     OR (SELECT comment_count FROM public.opinions WHERE id = v_o2) <> 0
     OR (SELECT removed_at FROM public.opinion_comments WHERE id = v_c2) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: comment_count went below 0, or the comment stayed';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'opinion_remove_own_contracts: all held'; END $$;
ROLLBACK;
```

Create `test/features/opinions/w9/opinion_remove_own_repository_test.dart` with exactly:

```dart
// Spec 1 W9b (OPN-DELETE-RLS, §5.2): deleting your own opinion or comment
// calls remove_my_opinion / remove_my_comment, and nothing else: no direct
// UPDATE of removed_at (refused by RLS), no opinion_id pre-select, no
// separate decrement_opinion_comment_count (the RPC lowers the count once).
import 'dart:convert';

import 'package:attune/features/opinions/data/repositories/opinion_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<http.Request> requests;
  late OpinionRepository repo;

  setUp(() {
    requests = [];
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', 204, request: request);
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repo = OpinionRepository(client);
  });

  String describe(http.Request r) => '${r.method} ${r.url.path} ${r.body}';

  test('deleting an opinion calls remove_my_opinion only', () async {
    await repo.deleteOpinion('o-1');
    expect(requests.map(describe), [
      'POST /rest/v1/rpc/remove_my_opinion ${jsonEncode({'p_opinion_id': 'o-1'})}',
    ]);
  });

  test('deleting a comment calls remove_my_comment only', () async {
    await repo.deleteComment('c-1');
    expect(requests.map(describe), [
      'POST /rest/v1/rpc/remove_my_comment ${jsonEncode({'p_comment_id': 'c-1'})}',
    ]);
  });
}
```

- [ ] **Step 2: Run them to make sure they fail**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_remove_own_contracts.sql 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //'
flutter test --no-pub test/features/opinions/w9/opinion_remove_own_repository_test.dart 2>&1 | grep -E 'Expected|Actual' | head -2
```

Expected: `ERROR:  CONTRACT VIOLATED: remove_my_opinion / remove_my_comment are missing`; `Expected: ['POST /rest/v1/rpc/remove_my_opinion {"p_opinion_id":"o-1"}']` and an `Actual:` naming `PATCH /rest/v1/opinions`.

- [ ] **Step 3: Write migration 19 and its twin**

Create `supabase/migrations/20261104130000_opinion_remove_own.sql` with exactly:

```sql
-- Spec 1 W9b, migration 19 (spec §4.7 #19; OPN-DELETE-RLS): removing your
-- own opinion or comment.
-- Today the app deletes with a direct UPDATE ... SET removed_at, which needs
-- SELECT on the row, so Postgres checks the new row against the SELECT
-- policies opinions_public_read / opinion_comments_public_read
-- (removed_at IS NULL ...) and refuses it ("new row violates row-level
-- security policy"). No policy is loosened: two owner-checked definer RPCs
-- do the removal instead, and the app calls them.
--   * remove_my_opinion(p_opinion_id): sets removed_at on the caller's own
--     live opinion. Someone else's, a missing or an already-removed one
--     changes nothing and raises nothing (today's client contract: a
--     non-owner delete is a no-op).
--   * remove_my_comment(p_comment_id): the same for a comment, and lowers
--     the parent opinion's comment_count by one (never below 0) only when
--     this call removed a live comment, so a repeat never decrements twice.
--     The app stops calling decrement_opinion_comment_count for a delete.
-- Neither is gated by the posting ban or opinions_safety_v1: removing your
-- own words is never a posting act. Not flagged (spec §8 W9b).
-- Grants in 20261104130010_opinion_remove_own_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.remove_my_opinion(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  UPDATE public.opinions AS o
     SET removed_at = pg_catalog.now()
   WHERE o.id = p_opinion_id
     AND o.user_id = auth.uid()
     AND o.removed_at IS NULL;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.remove_my_comment(p_comment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_opinion uuid;
BEGIN
  UPDATE public.opinion_comments AS c
     SET removed_at = pg_catalog.now()
   WHERE c.id = p_comment_id
     AND c.user_id = auth.uid()
     AND c.removed_at IS NULL
  RETURNING c.opinion_id INTO v_opinion;

  -- Only when this call removed a live comment: a repeat never decrements.
  IF v_opinion IS NOT NULL THEN
    UPDATE public.opinions AS o
       SET comment_count = GREATEST(COALESCE(o.comment_count, 0) - 1, 0)
     WHERE o.id = v_opinion;
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION public.remove_my_opinion(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_my_comment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_my_opinion(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_my_comment(uuid) TO authenticated;

COMMIT;
```

Create `supabase/migrations/20261104130010_opinion_remove_own_grants.sql` with exactly:

```sql
-- Spec 1 W9b: grants for 20261104130000_opinion_remove_own.sql. Signed-in
-- only; never anon.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.remove_my_opinion(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_my_comment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_my_opinion(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_my_comment(uuid) TO authenticated;
COMMIT;
```

- [ ] **Step 4: The repository**

```bash
python3 -I - <<'PY'
# W9b OPN-DELETE-RLS client edit, as exact replacements (run from the repo root).
import pathlib
def edit(path, pairs):
    p = pathlib.Path(path); s = p.read_text()
    for a, b in pairs:
        assert s.count(a) == 1, (path, a[:70], s.count(a))
        s = s.replace(a, b)
    p.write_text(s)

SAFETY_IMPORTS = """import 'package:attune/features/opinions/presentation/providers/opinions_safety_provider.dart';
import 'package:attune/features/opinions/presentation/widgets/need_support_link.dart';
"""

# OPN-DELETE-RLS (ungated): the owner-checked RPCs.
edit('lib/features/opinions/data/repositories/opinion_repository.dart', [
  ("""  Future<void> deleteOpinion(String opinionId) async {
    // RLS restricts UPDATE to the owner; a non-owner delete is a no-op.
    await _supabase
        .from('opinions')
        .update({'removed_at': DateTime.now().toIso8601String()})
        .eq('id', opinionId);
  }""", """  Future<void> deleteOpinion(String opinionId) async {
    // Spec 1 W9b (OPN-DELETE-RLS): the owner-checked RPC; a direct UPDATE
    // fails the SELECT policy. A non-owner delete is still a no-op.
    await _supabase.rpc(
      'remove_my_opinion',
      params: {'p_opinion_id': opinionId},
    );
  }"""),
  ("""  Future<void> deleteComment(String commentId) async {
    final comment =
        await _supabase
            .from('opinion_comments')
            .select('opinion_id')
            .eq('id', commentId)
            .single();

    await _supabase
        .from('opinion_comments')
        .update({'removed_at': DateTime.now().toIso8601String()})
        .eq('id', commentId);

    await _supabase.rpc(
      'decrement_opinion_comment_count',
      params: {'p_opinion_id': comment['opinion_id']},
    );
  }""", """  Future<void> deleteComment(String commentId) async {
    // Spec 1 W9b (OPN-DELETE-RLS): the owner-checked RPC, which also lowers
    // the opinion's comment_count once (only when it removed a live comment).
    await _supabase.rpc(
      'remove_my_comment',
      params: {'p_comment_id': commentId},
    );
  }"""),
])

print('OPN-DELETE-RLS repository edit applied')
PY
```

Expected: `OPN-DELETE-RLS repository edit applied`. `deleteComment`'s callers (`opinion_providers.dart:1330-1340`) already patch the list and the count locally; they are not edited.

- [ ] **Step 5: Apply each file twice; run the contract and the repository test**

```bash
for i in 1 2; do
  for f in 20261104130000_opinion_remove_own 20261104130010_opinion_remove_own_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_remove_own_contracts.sql 2>&1 | tail -1 | sed -E 's/^psql:[^ ]* //'
flutter test --no-pub test/features/opinions/w9/opinion_remove_own_repository_test.dart 2>&1 | tail -1
```

Expected: four `exit=0` lines; `NOTICE:  opinion_remove_own_contracts: all held`; `All tests passed!`.

- [ ] **Step 6: Mutation checks (each must turn the contract red with the message quoted; the last turns the repository test red)**

```bash
M=supabase/migrations/20261104130000_opinion_remove_own.sql
C=supabase/tests/opinion_remove_own_contracts.sql
D=.superpowers/sdd/2026-11-04-spec1-w9
python3 -I - "$M" "$D" <<'PY'
import pathlib, sys
m = pathlib.Path(sys.argv[1]).read_text()
def body(m):
    # One transaction per mutant: the migration's own BEGIN/COMMIT go, so the
    # contract's ROLLBACK undoes the mutant too.
    assert m.count("\nBEGIN;\n") == 1 and m.count("\nCOMMIT;\n") == 1
    return m.replace("\nBEGIN;\n", "\n").replace("\nCOMMIT;\n", "\n")
m = body(m)
d = pathlib.Path(sys.argv[2])
muts = {
  'opinion_no_owner_check': ("   WHERE o.id = p_opinion_id\n     AND o.user_id = auth.uid()\n", "   WHERE o.id = p_opinion_id\n"),
  'comment_no_owner_check': ("   WHERE c.id = p_comment_id\n     AND c.user_id = auth.uid()\n", "   WHERE c.id = p_comment_id\n"),
  'comment_repeat_decrements': ("     AND c.user_id = auth.uid()\n     AND c.removed_at IS NULL\n", "     AND c.user_id = auth.uid()\n"),
  'no_floor': ("GREATEST(COALESCE(o.comment_count, 0) - 1, 0)", "COALESCE(o.comment_count, 0) - 1"),
  'no_decrement': ("  IF v_opinion IS NOT NULL THEN\n", "  IF false THEN\n"),
}
for name, (a, b) in muts.items():
    assert m.count(a) == 1, (name, m.count(a))
    (d / f"mut_{name}.sql").write_text(m.replace(a, b))
(d / 'mut_anon_grant.sql').write_text("GRANT EXECUTE ON FUNCTION public.remove_my_opinion(uuid) TO anon;\n")
(d / 'mut_policy_loosened.sql').write_text("ALTER POLICY opinions_public_read ON public.opinions USING (hidden_pending_review = false);\n")
print(len(muts) + 2, 'mutants written')
PY
for f in $D/mut_*.sql; do
  m=$(basename $f .sql)
  echo "${m#mut_}: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f $f -f $C 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-150)"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | tail -1 | sed -E 's/^psql:[^ ]* //'
rm $D/mut_*.sql
python3 -I - <<'PY'
import pathlib, subprocess
p = pathlib.Path('lib/features/opinions/data/repositories/opinion_repository.dart')
s = p.read_text()
a = "    await _supabase.rpc(\n      'remove_my_comment',\n      params: {'p_comment_id': commentId},\n    );\n"
b = a + "    await _supabase.rpc('decrement_opinion_comment_count', params: {'p_opinion_id': ''});\n"
assert s.count(a) == 1
try:
    p.write_text(s.replace(a, b))
    r = subprocess.run(['flutter', 'test', '--no-pub', 'test/features/opinions/w9/opinion_remove_own_repository_test.dart'], capture_output=True, text=True)
    print('double_decrement:', 'red' if r.returncode else 'GREEN (mutant survived)')
finally:
    p.write_text(s)
PY
```

Expected: `7 mutants written`, then:
- `anon_grant`: `ERROR:  CONTRACT VIOLATED: remove_my_* grants are wrong (signed-in only, never anon)`
- `comment_no_owner_check`: `ERROR:  CONTRACT VIOLATED: another user's remove_my_comment changed the comment or the count`
- `comment_repeat_decrements`: `ERROR:  CONTRACT VIOLATED: a second remove_my_comment decremented again`
- `no_decrement`: `ERROR:  CONTRACT VIOLATED: the author's remove_my_comment did not remove it and lower the count by 1 (count 2)`
- `no_floor`: `ERROR:  CONTRACT VIOLATED: comment_count went below 0, or the comment stayed`
- `opinion_no_owner_check`: `ERROR:  CONTRACT VIOLATED: another user removed the opinion, or the call raised`
- `policy_loosened`: `ERROR:  CONTRACT VIOLATED: a SELECT policy on opinions or opinion_comments was changed`

then `NOTICE:  opinion_remove_own_contracts: all held`; `double_decrement: red`.

- [ ] **Step 7: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`, edit 1 of 1. Replace exactly:

```sql
\i supabase/migrations/20261104120010_opinion_moderation_notices_grants.sql
```

with:

```sql
\i supabase/migrations/20261104120010_opinion_moderation_notices_grants.sql

-- Spec 1 W9b: removing your own opinion or comment, signed in only.
\i supabase/migrations/20261104130010_opinion_remove_own_grants.sql
```

- [ ] **Step 8: Run tests**

```bash
D=.superpowers/sdd/2026-11-04-spec1-w9
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-after-task7.txt
grep '^FAIL' $D/sql-after-task7.txt | comm -13 <(grep '^FAIL' $D/sql-baseline.txt) -
grep -E 'opinion_|forum_retirement|account_deletion' $D/sql-after-task7.txt
flutter test --no-pub test/features/opinions/ 2>&1 | tail -1
```

Expected: no new FAIL line; `PASS account_deletion_contracts.sql`, `PASS forum_retirement_contracts.sql`, `PASS opinion_filter_contracts.sql`, `PASS opinion_moderation_notice_contracts.sql`, `PASS opinion_remove_own_contracts.sql`; `All tests passed!`.

### Task 8: "Need support now?", the at-risk reason in the app, the manual, and the W9b gate (§2.2, §2.3, §5.1-§5.3, §6.6, §8 W9b; P-14, P-18-P-21)

**Files:**
- Create: `lib/features/opinions/presentation/providers/opinions_safety_provider.dart`
- Create: `lib/features/opinions/presentation/widgets/need_support_link.dart`
- Create: `test/features/opinions/w9/opinions_safety_ui_test.dart` (+ 8 goldens)
- Modify: `lib/features/opinions/data/opinion_more_data.dart`, `lib/features/opinions/presentation/screen/comment_thread_screen.dart`, `opinion_compose_screen.dart`, `quote_compose_screen.dart`
- Modify: `lib/app/feature_flag_refresher.dart`, `lib/app/documentations/user_manual/data/opinions_docs.dart`, `lib/app/documentations/user_manual/data/manual_documentation_registry.dart`, `test/app/documentations/documentation_registry_flags_test.dart` (one line)
- Modify: `lib/i10n/app_en.arb` (+ `lib/i10n/generated/*`)

**Interfaces:**
- Consumes: Task 5's reason value; `OpinionRepository.reportOpinion` / `reportComment`; `RouteNames.safetyResources`; `ClientMetricKey.supportLinkOpened*`.
- Produces: `opinionsSafetyFlag = 'opinions_safety_v1'`, `opinionsSafetyReadProvider` (`FutureProvider<bool>`), `opinionsSafetyProvider` (`Provider<bool>`, §5.3); `enum SupportLinkSource { opinions, journal }` (`metric`); `atRiskReportReason = 'Someone may be at risk'`; `void openSupportNow(BuildContext, WidgetRef, SupportLinkSource)`; `NeedSupportLink({SupportLinkSource source = opinions})`; `Future<void> showAtRiskReportThanks(BuildContext, WidgetRef)`. Keys `support_needSupportNow`, `opinions_reportAtRisk`, `opinions_atRiskThanks`, `opinions_atRiskSeeNumbers`, `opinions_atRiskClose`, `opinions_reportFailed`. Task 10 reuses `openSupportNow`, `SupportLinkSource.journal` and `support_needSupportNow`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/opinions/w9/opinions_safety_ui_test.dart` with exactly:

```dart
// Spec 1 W9b (§8 W9b, §2.2, §2.3, §6.6): with opinions_safety_v1 on,
// "Need support now?" is in compose and in every post and comment menu and
// opens Support (counted); both report lists start with "Someone may be at
// risk", which reaches the server with that reason and thanks the reporter
// without animation, offering the emergency numbers; a failed at-risk report
// says so. The manual's passage shows only with the flag.
//   flutter test --update-goldens test/features/opinions/w9/opinions_safety_ui_test.dart
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/features/opinions/presentation/providers/opinions_safety_provider.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/features/opinions/presentation/screen/quote_compose_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/need_support_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import 'support/fake_opinions.dart';

final _on = [opinionsSafetyProvider.overrideWithValue(true)];

const _thanks =
    'Thank you. A person on our team will look at this soon. If someone is in danger right now, call your local emergency number.';

Future<FlowHarness> _thread(WidgetTester tester, FakeOpinionRepository repo) {
  final opinion = w9Opinion();
  return pumpOpinionScreen(
    tester,
    () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
    repo: repo,
    overrides: _on,
  );
}

void main() {
  testWidgets('compose and quote: "Need support now?" opens Support, counted', (
    tester,
  ) async {
    final repo = FakeOpinionRepository();
    var h = await pumpOpinionScreen(
      tester,
      () => const OpinionComposeScreen(),
      repo: repo,
      overrides: _on,
    );
    await tester.tap(find.text('Need support now?'));
    await tester.pumpAndSettle();
    expect(find.text('at /safety-resources'), findsOneWidget);
    expect(h.metrics, ['support_link_opened:opinions']);

    h = await pumpOpinionScreen(
      tester,
      () => QuoteComposeScreen(quotedOpinion: w9Opinion()),
      repo: repo,
      overrides: _on,
    );
    expect(find.text('Need support now?'), findsOneWidget);
  });

  testWidgets('the post menu: "Need support now?" first; the menu closes', (
    tester,
  ) async {
    final h = await _thread(tester, FakeOpinionRepository());
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    final support = find.text('Need support now?');
    final report = find.text('Report');
    expect(
      tester.getTopLeft(support).dy,
      lessThan(tester.getTopLeft(report).dy),
    );
    await tester.tap(support);
    await tester.pumpAndSettle();
    expect(find.text('at /safety-resources'), findsOneWidget);
    expect(h.metrics, ['support_link_opened:opinions']);
  });

  testWidgets('every comment menu has it, mine and others', (tester) async {
    await _thread(tester, FakeOpinionRepository());
    for (final i in [0, 1]) {
      await tester.tap(find.byIcon(Icons.more_horiz).at(i));
      await tester.pumpAndSettle();
      expect(
        find.text('Need support now?'),
        findsOneWidget,
        reason: 'comment $i',
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byIcon(Icons.more_horiz).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Need support now?'));
    await tester.pumpAndSettle();
    expect(find.text('at /safety-resources'), findsOneWidget);
  });

  testWidgets(
    'a post reported "Someone may be at risk": sent, thanked, numbers offered',
    (tester) async {
      final repo = FakeOpinionRepository();
      await _thread(tester, repo);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      final atRisk = find.text('Someone may be at risk');
      expect(
        tester.getTopLeft(atRisk).dy,
        lessThan(tester.getTopLeft(find.text('Identifies a real person')).dy),
      );
      await tester.tap(atRisk);
      await tester.pump(); // never animated: in place at once
      await tester.pump();
      expect(find.text(_thanks), findsOneWidget);
      expect(tester.getRect(find.text(_thanks)).bottom, lessThanOrEqualTo(844));
      expect(repo.reports, ['opinion:o1:Someone may be at risk']);
      expect(
        find.text('Thank you. We will review this within 24 hours.'),
        findsNothing,
      );
      await tester.tap(find.text('See emergency numbers'));
      await tester.pumpAndSettle();
      expect(find.text('at /safety-resources'), findsOneWidget);
    },
  );

  testWidgets('a comment reported "Someone may be at risk": sent and thanked', (
    tester,
  ) async {
    final repo = FakeOpinionRepository();
    await _thread(tester, repo);
    await tester.tap(find.byIcon(Icons.more_horiz).at(1)); // the other person's
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Someone may be at risk'));
    await tester.pumpAndSettle();
    expect(repo.reports, ['comment:c-other:Someone may be at risk']);
    expect(find.text(_thanks), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text(_thanks), findsNothing);
  });

  testWidgets('an at-risk report that fails says so', (tester) async {
    final repo = FakeOpinionRepository()..refuseWith = Exception('offline');
    await _thread(tester, repo);
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Someone may be at risk'));
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't send your report. Please try again."),
      findsOneWidget,
    );
    expect(find.text(_thanks), findsNothing);
  });

  testWidgets('the link and the thanks: guidelines and goldens', (
    tester,
  ) async {
    Widget link() => const Scaffold(body: Center(child: NeedSupportLink()));
    await pumpFlowScreen(tester, link);
    await expectFlowGuidelines(tester);
    await expectFlowGoldens(tester, 'need_support_link', link);

    Widget thanks() => Scaffold(
      body: Consumer(
        builder:
            (context, ref, _) => Center(
              child: TextButton(
                onPressed: () => showAtRiskReportThanks(context, ref),
                child: const Text('open'),
              ),
            ),
      ),
    );
    Future<void> open(WidgetTester t) async {
      await t.tap(find.text('open'));
      await t.pump();
    }

    await pumpFlowScreen(tester, thanks);
    await open(tester);
    await expectFlowGuidelines(tester);
    await expectFlowGoldens(tester, 'at_risk_thanks', thanks, before: open);
  });

  test('the manual passage shows only with the flag', () {
    expect(
      DocumentationRegistry.passageVisible('opinionsSafety', const {}),
      isFalse,
    );
    expect(
      DocumentationRegistry.passageVisible('opinionsSafety', const {
        'opinions_safety_v1',
      }),
      isTrue,
    );
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
flutter test --no-pub test/features/opinions/w9/opinions_safety_ui_test.dart 2>&1 | grep -o "Error when reading '[^']*'" | head -1
```

Expected: `Error when reading 'lib/features/opinions/presentation/providers/opinions_safety_provider.dart'`.

- [ ] **Step 3: The copy**

Create `.superpowers/sdd/2026-11-04-spec1-w9/arb_w9b.txt` with exactly:

```text
  "support_needSupportNow": "Need support now?",
  "@support_needSupportNow": {
    "description": "The link to Support, in Opinions compose and every post and comment menu (Spec 1 W9b), and in the journal entry menu (W9c). Shown whatever anyone typed."
  },
  "opinions_reportAtRisk": "Someone may be at risk",
  "@opinions_reportAtRisk": {
    "description": "A report reason in both Opinions report lists (Spec 1 W9b). It goes to a person and never hides the post."
  },
  "opinions_atRiskThanks": "Thank you. A person on our team will look at this soon. If someone is in danger right now, call your local emergency number.",
  "@opinions_atRiskThanks": {
    "description": "Shown after an at-risk report (Spec 1 W9b)."
  },
  "opinions_atRiskSeeNumbers": "See emergency numbers",
  "@opinions_atRiskSeeNumbers": {
    "description": "Opens Support from the at-risk report's thank-you (Spec 1 W9b)."
  },
  "opinions_atRiskClose": "Close",
  "@opinions_atRiskClose": {
    "description": "Closes the at-risk report's thank-you (Spec 1 W9b)."
  },
  "opinions_reportFailed": "Couldn't send your report. Please try again.",
  "@opinions_reportFailed": {
    "description": "An at-risk report that did not reach the server (Spec 1 W9b)."
  }
```

```bash
grep -cP '[^\x00-\x7F]' .superpowers/sdd/2026-11-04-spec1-w9/arb_w9b.txt
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py .superpowers/sdd/2026-11-04-spec1-w9/arb_w9b.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null
grep -cE 'support_needSupportNow|opinions_reportAtRisk|opinions_atRisk|opinions_reportFailed' lib/i10n/generated/app_localizations_en.dart
```

Expected: `0`; `added 6 keys`; `6`.

- [ ] **Step 4: The flag, the link and the thank-you; then the menus, the lists, compose, the refresher and the manual**

Create `lib/features/opinions/presentation/providers/opinions_safety_provider.dart` with exactly:

```dart
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The flag key (Spec 1 §2.5).
const opinionsSafetyFlag = 'opinions_safety_v1';

/// opinions_safety_v1, as read (signed in: feature_flags is not readable
/// signed out, so a guest reads off). Re-read on resume with the app's other
/// flags (FeatureFlagRefresher).
final opinionsSafetyReadProvider = FutureProvider<bool>((ref) async {
  try {
    return await ChatFeatureFlags.isEnabled(
      Supabase.instance.client,
      opinionsSafetyFlag,
    );
  } catch (_) {
    return false;
  }
});

/// Spec 1 §5.3 `opinionsSafetyProvider`: the support link and the at-risk
/// reason show only while this is true. Off until the read answers, off when
/// unreadable, so with the flag off Opinions looks exactly as before.
final opinionsSafetyProvider = Provider<bool>(
  (ref) => ref.watch(opinionsSafetyReadProvider).valueOrNull ?? false,
);
```

Create `lib/features/opinions/presentation/widgets/need_support_link.dart` with exactly:

```dart
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Where "Need support now?" was opened from (its count, Spec 1 §4.8).
enum SupportLinkSource {
  opinions(ClientMetricKey.supportLinkOpenedOpinions),
  journal(ClientMetricKey.supportLinkOpenedJournal);

  const SupportLinkSource(this.metric);

  final ClientMetricKey metric;
}

/// The reason value the report RPCs take (Spec 1 §4.3 W9b).
const atRiskReportReason = 'Someone may be at risk';

/// Opens Support (W7a's screen and route; with support_resources_v2 off,
/// today's Safety resources screen) and counts the tap. Nothing else about
/// it is stored on the phone.
void openSupportNow(
  BuildContext context,
  WidgetRef ref,
  SupportLinkSource source,
) {
  ref.read(metricCounterProvider).bump(source.metric);
  context.push(RouteNames.safetyResources);
}

/// "Need support now?" (Spec 1 §8 W9b): always there, whatever anyone typed.
class NeedSupportLink extends ConsumerWidget {
  const NeedSupportLink({super.key, this.source = SupportLinkSource.opinions});

  final SupportLinkSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return AllowLargeText(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: scheme.onSurface,
            padding: Spacing.horizontalSm,
          ),
          onPressed: () => openSupportNow(context, ref, source),
          icon: const Icon(Icons.support_outlined, size: 20),
          label: Text(loc.support_needSupportNow),
        ),
      ),
    );
  }
}

/// After an at-risk report (Spec 1 §8 W9b): never animated (§2.2), large
/// text let through (the shell clamps sheets to 1.0).
Future<void> showAtRiskReportThanks(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    sheetAnimationStyle: AnimationStyle.noAnimation,
    builder: (sheetContext) {
      final loc = AppLocalizations.of(sheetContext)!;
      final theme = Theme.of(sheetContext);
      return AllowLargeText(
        child: SingleChildScrollView(
          padding: Spacing.allLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  loc.opinions_atRiskThanks,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  openSupportNow(context, ref, SupportLinkSource.opinions);
                },
                child: Text(loc.opinions_atRiskSeeNumbers),
              ),
              const SizedBox(height: Spacing.sm),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: theme.colorScheme.onSurface,
                ),
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(loc.opinions_atRiskClose),
              ),
            ],
          ),
        ),
      );
    },
  );
}
```

Then the edits (exact replacements; each anchor must occur once):

```bash
python3 -I - <<'PY'
# W9b client edits, as exact replacements (run from the repo root).
import pathlib
def edit(path, pairs):
    p = pathlib.Path(path); s = p.read_text()
    for a, b in pairs:
        assert s.count(a) == 1, (path, a[:70], s.count(a))
        s = s.replace(a, b)
    p.write_text(s)

SAFETY_IMPORTS = """import 'package:attune/features/opinions/presentation/providers/opinions_safety_provider.dart';
import 'package:attune/features/opinions/presentation/widgets/need_support_link.dart';
"""

# 1. The post menu and the post report list.
edit('lib/features/opinions/data/opinion_more_data.dart', [
  ("import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';\n",
   "import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';\n" + SAFETY_IMPORTS),
  ("""        title: 'Opinion',
        items: [
""", """        title: 'Opinion',
        items: [
          // Spec 1 W9b: "Need support now?" on every post, whatever it says
          // (opinions_safety_v1 only). The menu closes first.
          if (ref.read(opinionsSafetyProvider))
            SettingsConfig(
              id: 'need_support',
              title: AppLocalizations.of(context)!.support_needSupportNow,
              subtitle: '',
              icon: Icons.support_outlined,
              type: SettingsItemType.action,
              iconColor: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              onTap: () {
                Navigator.of(context).pop();
                openSupportNow(context, ref, SupportLinkSource.opinions);
              },
              order: 0,
            ),
"""),
  ("""      'Spam',
      'Other',
    ];
    showModalBottomSheet<void>(""", """      'Spam',
      'Other',
    ];
    // Spec 1 W9b: the at-risk reason, first (opinions_safety_v1 only).
    final shown = [
      if (ref.read(opinionsSafetyProvider)) atRiskReportReason,
      ...reasons,
    ];
    showModalBottomSheet<void>("""),
  ("""                for (final reason in reasons)
                  ListTile(
                    title: Text(reason),
                    onTap: () async {
                      Navigator.pop(sheetContext);
""", """                for (final reason in shown)
                  ListTile(
                    title: Text(
                      reason == atRiskReportReason
                          ? AppLocalizations.of(
                            sheetContext,
                          )!.opinions_reportAtRisk
                          : reason,
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      if (reason == atRiskReportReason) {
                        await _reportAtRisk(context, ref, opinionId);
                        return;
                      }
"""),
  ("""                      if (context.mounted) {
                        context.showInfoSnackbar(
                          'Thank you. We will review this within 24 hours.',
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
    );
  }
}""", """                      if (context.mounted) {
                        context.showInfoSnackbar(
                          'Thank you. We will review this within 24 hours.',
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
    );
  }

  /// Spec 1 W9b: an at-risk report goes to a person (priority, never
  /// auto-hide), then the thank-you with the emergency numbers.
  static Future<void> _reportAtRisk(
    BuildContext context,
    WidgetRef ref,
    String opinionId,
  ) async {
    try {
      await ref
          .read(opinionRepositoryProvider)
          .reportOpinion(opinionId: opinionId, reason: atRiskReportReason);
    } catch (_) {
      if (context.mounted) {
        context.showErrorSnackbar(
          AppLocalizations.of(context)!.opinions_reportFailed,
        );
      }
      return;
    }
    if (context.mounted) await showAtRiskReportThanks(context, ref);
  }
}"""),
])

edit('lib/features/opinions/data/opinion_more_data.dart', [
  ('''      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.all(Spacing.md.w),
                  child: Text(
                    'Report this opinion',''', '''      builder:
          (sheetContext) => SafeArea(
            // Spec 1 W9b: seven reasons scroll; six render exactly as before.
            child: _scrollIf(
              shown.length > reasons.length,
              Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.all(Spacing.md.w),
                  child: Text(
                    'Report this opinion','''),
  ('''                    },
                  ),
              ],
            ),
          ),
    );
  }

  /// Spec 1 W9b: an at-risk report''', '''                    },
                  ),
              ],
            ),
            ),
          ),
    );
  }

  static Widget _scrollIf(bool scroll, Widget child) =>
      scroll ? SingleChildScrollView(child: child) : child;

  /// Spec 1 W9b: an at-risk report'''),
])

# 2. The comment menu, the comment report list, and the thread's post menu
#    (built by OpinionMoreData above).
edit('lib/features/opinions/presentation/screen/comment_thread_screen.dart', [
  ("import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';\n",
   "import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';\n" + SAFETY_IMPORTS),
  ("""                        } else if (value == 'delete' && isOwnComment) {
                          await deleteComment(
                            ref,
                            commentId: comment.id,
                            opinionId: widget.opinionId,
                          );
                        }
                      },""", """                        } else if (value == 'delete' && isOwnComment) {
                          await deleteComment(
                            ref,
                            commentId: comment.id,
                            opinionId: widget.opinionId,
                          );
                        } else if (value == 'support') {
                          openSupportNow(
                            context,
                            ref,
                            SupportLinkSource.opinions,
                          );
                        }
                      },"""),
  ("""                            if (isOwnComment)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                          ],""", """                            if (isOwnComment)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            // Spec 1 W9b: on every comment (flag on only).
                            if (ref.read(opinionsSafetyProvider))
                              PopupMenuItem(
                                value: 'support',
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.support_needSupportNow,
                                ),
                              ),
                          ],"""),
  ("""            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildReportOption(
                  context,
                  ref,
                  commentId,
                  'Identifies a real person',
                ),""", """            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Spec 1 W9b: the at-risk reason, first (flag on only).
                if (ref.read(opinionsSafetyProvider))
                  _buildReportOption(
                    context,
                    ref,
                    commentId,
                    atRiskReportReason,
                  ),
                _buildReportOption(
                  context,
                  ref,
                  commentId,
                  'Identifies a real person',
                ),"""),
  ("""    return ListTile(
      title: Text(reason),
      onTap: () async {
        Navigator.pop(context);
        // Implement comment report provider""", """    return ListTile(
      title: Text(
        reason == atRiskReportReason
            ? AppLocalizations.of(context)!.opinions_reportAtRisk
            : reason,
      ),
      onTap: () async {
        Navigator.pop(context);
        // Spec 1 W9b: an at-risk report goes to a person (the RPC records
        // it as priority; it never hides the comment). The other reasons
        // are unchanged.
        if (reason == atRiskReportReason) {
          final screen = this.context;
          try {
            await ref
                .read(opinionRepositoryProvider)
                .reportComment(commentId: commentId, reason: reason);
          } catch (_) {
            if (screen.mounted) {
              screen.showErrorSnackbar(
                AppLocalizations.of(screen)!.opinions_reportFailed,
              );
            }
            return;
          }
          if (screen.mounted) await showAtRiskReportThanks(screen, ref);
          return;
        }
        // Implement comment report provider"""),
])

# 3. "Need support now?" in compose (both compose screens).
edit('lib/features/opinions/presentation/screen/opinion_compose_screen.dart', [
  ("import 'package:attune/features/opinions/presentation/widgets/content_filter_notice.dart';\n",
   "import 'package:attune/features/opinions/presentation/widgets/content_filter_notice.dart';\n" + SAFETY_IMPORTS),
  ("            if (_filterReason != null) ContentFilterNotice(reason: _filterReason!),\n",
   "            if (_filterReason != null) ContentFilterNotice(reason: _filterReason!),\n            // Spec 1 W9b: in compose, whatever is typed (flag on only).\n            if (ref.watch(opinionsSafetyProvider)) const NeedSupportLink(),\n"),
])
edit('lib/features/opinions/presentation/screen/quote_compose_screen.dart', [
  ("import 'package:attune/features/opinions/presentation/widgets/content_filter_notice.dart';\n",
   "import 'package:attune/features/opinions/presentation/widgets/content_filter_notice.dart';\n" + SAFETY_IMPORTS),
  ("""              if (_filterReason != null)
                ContentFilterNotice(reason: _filterReason!),
""", """              if (_filterReason != null)
                ContentFilterNotice(reason: _filterReason!),
              // Spec 1 W9b: in compose, whatever is typed (flag on only).
              if (ref.watch(opinionsSafetyProvider)) const NeedSupportLink(),
"""),
])

# 4. The flag is re-read on resume with the others, and read from the start.
edit('lib/app/feature_flag_refresher.dart', [
  ("import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';\n",
   "import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';\nimport 'package:attune/features/opinions/presentation/providers/opinions_safety_provider.dart';\n"),
  ("  flowFlagsProvider,\n];", "  flowFlagsProvider,\n  // Spec 1 W9b.\n  opinionsSafetyReadProvider,\n];"),
  ("    ref.listen(currentUserProvider.select((u) => u?.id), (previous, next) {\n",
   "    // Spec 1 W9b: read from the start, so the first post or comment menu\n    // (which reads it once, when it opens) already knows.\n    ref.listen(opinionsSafetyReadProvider, (_, __) {});\n    ref.listen(currentUserProvider.select((u) => u?.id), (previous, next) {\n"),
])

# 5. The manual: one gated passage (B7 ruling M-3).
edit('lib/app/documentations/user_manual/data/opinions_docs.dart', [
  ("import 'package:flutter/material.dart';\n",
   "import 'package:flutter/material.dart';\nimport 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';\nimport 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';\n"),
  ("""        ManualContent(
          id: 'opinions_no_own_like',""", """        // Spec 1 W9b: only while Opinions safety is on.
        if (DocumentationRegistry.passageVisible(
          'opinionsSafety',
          documentationFlagsOf(context),
        ))
          ManualContent(
            id: 'opinions_safety',
            title: 'Keeping Opinions safe',
            content:
                "Posts, comments and edits can't include phone numbers, emails, links or usernames, words that attack people for who they are, or sexual content. If something is held back, you'll see why, and your words stay there for you to change. \\"Need support now?\\" is in compose and in every post and comment menu. If you're worried about someone, report it with \\"Someone may be at risk\\": a person on our team looks at it, and it never hides the post.",
            numberPrefix: '4',
            type: ManualContentType.text,
          ),
        ManualContent(
          id: 'opinions_no_own_like',"""),
])
edit('lib/app/documentations/user_manual/data/manual_documentation_registry.dart', [
  ("""    'supportResourcesV2': ['support_resources_v2'],
  };""", """    'supportResourcesV2': ['support_resources_v2'],
    // Spec 1 W9b: the content filter, the support link, the at-risk reason.
    'opinionsSafety': ['opinions_safety_v1'],
  };"""),
])
edit('test/app/documentations/documentation_registry_flags_test.dart', [
  ("""          // Spec 1 W7a: Support resources v2.
          'support_resources_v2',
""", """          // Spec 1 W7a: Support resources v2.
          'support_resources_v2',
          // Spec 1 W9b: Opinions safety.
          'opinions_safety_v1',
"""),
])
print('W9b client edits applied')
PY
```

Expected: `W9b client edits applied`. Every addition sits behind `opinionsSafetyProvider` (the comment report's other six reasons, the snackbars and the six-reason sheet are untouched); the refresher listens to the flag from app start (P-19); the manual passage is gated (P-20).

- [ ] **Step 5: Run the tests, write the goldens, look at them**

```bash
flutter test --no-pub test/features/opinions/w9/opinions_safety_ui_test.dart --update-goldens 2>&1 | tail -1
flutter test --no-pub test/features/opinions/w9/ test/app/documentations/ test/app/feature_flag_refresher_test.dart 2>&1 | tail -1
```

Expected: `All tests passed!` twice (the second includes Task 1's flag-off goldens, unchanged). Open `goldens/need_support_link.*.png` (the support icon and "Need support now?", start-aligned, mirrored under RTL) and `goldens/at_risk_thanks.*.png` (the sheet: the thank-you, "See emergency numbers" filled, "Close" below; at 2.0 the words wrap and the sheet scrolls).

- [ ] **Step 6: Analyzer on the touched files**

```bash
flutter analyze --no-pub lib/features/opinions lib/app/feature_flag_refresher.dart lib/app/documentations/user_manual/data test/features/opinions/w9 test/app/documentations 2>&1 | grep -E '^\s*(error|warning) ' | grep -v -E 'following_feed_screen|opinions_tab.dart|bottom_sheet_header'
```

Expected: no output.

- [ ] **Step 7: Mutation checks (each must turn a test red)**

```bash
python3 -I - <<'PY'
import pathlib, subprocess
OFF = 'test/features/opinions/w9/opinions_flag_off_test.dart'
ON = 'test/features/opinions/w9/opinions_safety_ui_test.dart'
MORE = 'lib/features/opinions/data/opinion_more_data.dart'
THREAD = 'lib/features/opinions/presentation/screen/comment_thread_screen.dart'
COMPOSE = 'lib/features/opinions/presentation/screen/opinion_compose_screen.dart'
LINK = 'lib/features/opinions/presentation/widgets/need_support_link.dart'
muts = {
  'support_row_with_flag_off': (MORE, "          if (ref.read(opinionsSafetyProvider))\n            SettingsConfig(\n              id: 'need_support',", "          if (true)\n            SettingsConfig(\n              id: 'need_support',", OFF),
  'at_risk_reason_with_flag_off': (MORE, "      if (ref.read(opinionsSafetyProvider)) atRiskReportReason,", "      atRiskReportReason,", OFF),
  'compose_link_with_flag_off': (COMPOSE, "            if (ref.watch(opinionsSafetyProvider)) const NeedSupportLink(),", "            const NeedSupportLink(),", OFF),
  'at_risk_sent_as_other': (MORE, "          .reportOpinion(opinionId: opinionId, reason: atRiskReportReason);", "          .reportOpinion(opinionId: opinionId, reason: 'Other');", ON),
  'comment_at_risk_not_sent': (THREAD, "            await ref\n                .read(opinionRepositoryProvider)\n                .reportComment(commentId: commentId, reason: reason);", "            await Future<void>.value();", ON),
  'thanks_animated': (LINK, "    sheetAnimationStyle: AnimationStyle.noAnimation,\n", "", ON),
  'link_not_counted': (LINK, "  ref.read(metricCounterProvider).bump(source.metric);\n", "", ON),
}
originals = {}
try:
    for name, (path, a, b, test) in muts.items():
        p = pathlib.Path(path)
        s = originals.setdefault(path, p.read_text())
        assert s.count(a) == 1, name
        p.write_text(s.replace(a, b))
        r = subprocess.run(['flutter', 'test', '--no-pub', test], capture_output=True, text=True)
        print(f"{name}: {'red' if r.returncode else 'GREEN (mutant survived)'}")
        p.write_text(s)
finally:
    for path, s in originals.items():
        pathlib.Path(path).write_text(s)
print('restored')
PY
```

Expected:
- `support_row_with_flag_off: red`
- `at_risk_reason_with_flag_off: red`
- `compose_link_with_flag_off: red`
- `at_risk_sent_as_other: red`
- `comment_at_risk_not_sent: red`
- `thanks_animated: red`
- `link_not_counted: red`

then `restored`.

- [ ] **Step 8: W9b gate (run tests)**

```bash
D=.superpowers/sdd/2026-11-04-spec1-w9
dart format lib/features/opinions/presentation/providers/opinions_safety_provider.dart lib/features/opinions/presentation/widgets/need_support_link.dart test/features/opinions/w9/opinions_safety_ui_test.dart test/features/opinions/w9/opinion_remove_own_repository_test.dart
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-after-w9b.txt
grep '^FAIL' $D/sql-after-w9b.txt | comm -13 <(grep '^FAIL' $D/sql-baseline.txt) -
grep -E 'opinion_|forum_retirement|identity_foundation|account_deletion' $D/sql-after-w9b.txt
flutter test --no-pub test/core/notifications/retired_forum_push_routing_test.dart 2>&1 | tail -1
flutter test --no-pub 2>&1 | tail -1
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error ' | sort | comm -13 $D/analyze-baseline.txt -
shasum -c $D/flag_off.sha | grep -v ': OK$'
sed -n '/if (isAuthenticated && !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - $D/latch.sha && echo latch-unchanged
git status --short lib/features/games lib/features/auth/utility/auth_exports.dart lib/home lib/core/notifications lib/features/opinions/presentation/widgets/opinion_card.dart ATTUNE_SOUL.md ATTUNE_THESIS.md supabase/sql/dev_enable_spec1_flags.sql
git status --short supabase/migrations | grep -v '^??'
```

Expected: `Formatted 4 files (0 changed)`; no new SQL FAIL; `PASS` for the six named files; `All tests passed!` (Spec 3's routing test: both kept types land on home); `All tests passed!`; no new analyzer `error`; no `shasum` line (the flag-off goldens are byte-identical to Task 1's); `latch-unchanged`; no `git status` line.

**W9b gate (before `opinions_safety_v1` in production; spec §8 W9b):** a named daily reviewer works review queue v0 (owner checklist 6). With W9a's gate, this is what the flag's production gate row records. The restored notices, OPN-BAN-42702 and OPN-DELETE-RLS have no gate: they ship with migrations 18-19 and the app release (owner checklist 2).

# W9c · Journal crisis check (Tasks 9-10)

### Task 9: `analyse-journal-entry`: `self_disclosure` first (D12; §4.5, §6.6, §7.2, §7.4; review A-4; P-22-P-24)

**Files:**
- Create: `supabase/functions/analyse-journal-entry/journal_handlers.ts`
- Create: `supabase/functions/analyse-journal-entry/journal_handlers.test.ts`
- Modify: `supabase/functions/analyse-journal-entry/index.ts` (whole file rewritten below; `serve`, the pause check, the dispatch lines and `RUNTIME_PATTERNS` stay as they are)

**Interfaces:**
- Consumes: `detectSelfDisclosure`, `featureFlagEnabled` + `DRAFT_SAFETY_CONTENT_FLAG`, `callGeminiJson`, `STATIC_PROHIBITED_PATTERNS`, `journalInsightsPaused` / `PAUSED_BODY`, `bump_metric_server`.
- Produces: `SUPPORT_OFFERED_BODY = {status: 'support_offered'}`, `SUPPORT_CARD_METRIC = 'support_card_shown:journal'`, `type JournalModel`, `interface JournalDeps {model, runtimePatterns, victimisationOn, bumpMetric}`, `handleAnalyseEntry(userClient, adminClient, userId, entryId, deps)`, `handleGetPatterns(adminClient, userId, deps)`, `corsHeaders`, `json(body, status)`. The app sees one new status, `support_offered`, for either action (Task 10).

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/analyse-journal-entry/journal_handlers.test.ts` with exactly:

```ts
// Spec 1 W9c (spec 4.5, 7.2, 7.4): the journal's crisis check runs first.
// With a spy on the provider: a matching entry never reaches it (whatever
// private_safety_check says), the check runs before the cache read, nothing
// about the match is written (the entry's earlier reflection is removed),
// one support_card_shown:journal count; the [DRAFT] victimisation list only
// with private_safety_check on; get_patterns leaves matched entries out and
// answers support_offered when the newest entry matches; an unreadable
// journal never reaches the provider.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  handleAnalyseEntry,
  handleGetPatterns,
  type JournalDeps,
  type JournalModel,
  SUPPORT_CARD_METRIC,
} from "./journal_handlers.ts";

type Call = { table: string; op: string; filters: Array<[string, string, unknown]> };

/// A supabase-js-shaped fake: every chain is recorded; [answer] decides what
/// a finished chain resolves to.
function fakeClient(answer: (call: Call) => { data: unknown; error: unknown }) {
  const calls: Call[] = [];
  const rpcs: Array<{ fn: string; params: Record<string, unknown> }> = [];
  function chain(call: Call) {
    const done = () => Promise.resolve(answer(call));
    const c: Record<string, unknown> = {
      select(_cols: string) {
        call.op = call.op === "delete" ? "delete" : "select";
        return c;
      },
      delete() {
        call.op = "delete";
        return c;
      },
      eq(col: string, v: unknown) {
        call.filters.push(["eq", col, v]);
        return c;
      },
      is(col: string, v: unknown) {
        call.filters.push(["is", col, v]);
        return c;
      },
      in(col: string, v: unknown) {
        call.filters.push(["in", col, v]);
        return c;
      },
      order(col: string, _o: unknown) {
        call.filters.push(["order", col, null]);
        return c;
      },
      limit(n: number) {
        call.filters.push(["limit", "", n]);
        return c;
      },
      single: done,
      maybeSingle: done,
      then(resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) {
        return done().then(resolve, reject);
      },
    };
    return c;
  }
  return {
    calls,
    rpcs,
    client: {
      from(table: string) {
        const call: Call = { table, op: "", filters: [] };
        calls.push(call);
        return chain(call);
      },
      rpc(fn: string, params: Record<string, unknown>) {
        rpcs.push({ fn, params });
        return Promise.resolve({ data: null, error: null });
      },
    },
  };
}

function spyDeps(opts: { victimisation?: boolean; reply?: Record<string, unknown> | null } = {}) {
  const prompts: string[] = [];
  const metrics: string[] = [];
  const model: JournalModel = (params) => {
    prompts.push(params.userPrompt);
    return Promise.resolve(opts.reply === undefined ? { tone: "settled", observation: "You sound settled.", confidence: "medium" } : opts.reply);
  };
  const deps: JournalDeps = {
    model,
    runtimePatterns: [/\b(toxic|narcissist|codependent|disorder|broken)\b/i],
    victimisationOn: () => Promise.resolve(opts.victimisation ?? false),
    bumpMetric: (key) => {
      metrics.push(key);
      return Promise.resolve();
    },
  };
  return { deps, prompts, metrics };
}

const LONG = "Work was long today and I kept thinking about the weekend plans we made, the market and the walk by the lagoon.";
const CRISIS = "I want to kill myself";
const VICTIM = "he hit me last night and I don't know what to do";

function entryUser(entry: { title?: string | null; content: string }) {
  return fakeClient((call) =>
    call.table === "reflection_journal_entries"
      ? { data: { id: "e1", title: entry.title ?? null, content: entry.content }, error: null }
      : { data: null, error: null }
  );
}

Deno.test("a crisis entry never reaches the provider, or the cache, and stores nothing", async () => {
  for (const victimisation of [true, false]) {
    for (const entry of [{ content: CRISIS }, { title: CRISIS, content: LONG }]) {
      const user = entryUser(entry);
      const admin = fakeClient(() => ({ data: null, error: null }));
      const spy = spyDeps({ victimisation });
      const res = await handleAnalyseEntry(user.client, admin.client, "u1", "e1", spy.deps);
      assertEquals(await res.json(), { status: "support_offered" });
      assertEquals(spy.prompts.length, 0, "the provider was called");
      assertEquals(admin.rpcs.length, 0, "something was written");
      assertEquals(admin.calls.filter((c) => c.op === "select").length, 0, "the cache was read");
      // Only the entry's earlier reflection is removed.
      assertEquals(admin.calls.map((c) => [c.table, c.op]), [["reflection_journal_analysis", "delete"]]);
      assertEquals(admin.calls[0].filters, [["eq", "entry_id", "e1"], ["eq", "user_id", "u1"]]);
      assertEquals(spy.metrics, [SUPPORT_CARD_METRIC]);
    }
  }
});

Deno.test("the [DRAFT] victimisation list runs only with private_safety_check on", async () => {
  const on = spyDeps({ victimisation: true });
  const resOn = await handleAnalyseEntry(entryUser({ content: VICTIM }).client, fakeClient(() => ({ data: null, error: null })).client, "u1", "e1", on.deps);
  assertEquals((await resOn.json()).status, "support_offered");
  assertEquals(on.prompts.length, 0);

  const off = spyDeps({ victimisation: false });
  const resOff = await handleAnalyseEntry(
    entryUser({ content: `${VICTIM} ${LONG}` }).client,
    fakeClient(() => ({ data: null, error: null })).client,
    "u1",
    "e1",
    off.deps,
  );
  assertEquals((await resOff.json()).status, "completed");
  assertEquals(off.prompts.length, 1);
});

Deno.test("an ordinary entry reads the cache first, then the provider, as before", async () => {
  const admin = fakeClient(() => ({ data: null, error: null }));
  const spy = spyDeps();
  const res = await handleAnalyseEntry(entryUser({ content: LONG }).client, admin.client, "u1", "e1", spy.deps);
  assertEquals((await res.json()).status, "completed");
  assertEquals(admin.calls[0].table, "reflection_journal_analysis");
  assertEquals(admin.calls[0].op, "select");
  assertEquals(spy.prompts.length, 1);
  assertEquals(admin.rpcs.map((r) => r.fn), ["upsert_journal_analysis"]);
  assertEquals(spy.metrics, []);
});

/// get_patterns' admin client: the newest entry, the analyses, and the
/// entries they belong to.
function patternsAdmin(opts: {
  newest: { id: string; title?: string | null; content: string } | null;
  analyses: Array<{ entry_id: string; observation: string }>;
  entries: Array<{ id: string; title?: string | null; content: string }>;
  entriesError?: boolean;
}) {
  return fakeClient((call) => {
    if (call.table === "reflection_journal_entries" && call.filters.some(([k]) => k === "in")) {
      return opts.entriesError ? { data: null, error: { message: "down" } } : { data: opts.entries, error: null };
    }
    if (call.table === "reflection_journal_entries") return { data: opts.newest, error: null };
    return {
      data: opts.analyses.map((a, i) => ({ ...a, tone: "settled", created_at: `2026-11-0${9 - i}T10:00:00Z` })),
      error: null,
    };
  });
}

Deno.test("get_patterns: the newest entry matches, so support and no provider call", async () => {
  const admin = patternsAdmin({ newest: { id: "e9", content: CRISIS }, analyses: [], entries: [] });
  const spy = spyDeps();
  const res = await handleGetPatterns(admin.client, "u1", spy.deps);
  assertEquals(await res.json(), { status: "support_offered" });
  assertEquals(spy.prompts.length, 0);
  assertEquals(spy.metrics, [SUPPORT_CARD_METRIC]);
  assertEquals(admin.calls.filter((c) => c.table === "reflection_journal_analysis").length, 0);
});

Deno.test("get_patterns leaves matched entries out of what the provider sees", async () => {
  const admin = patternsAdmin({
    newest: { id: "e1", content: LONG },
    analyses: [
      { entry_id: "e1", observation: "obs one" },
      { entry_id: "e2", observation: "obs two crisis" },
      { entry_id: "e3", observation: "obs three" },
      { entry_id: "e4", observation: "obs four" },
    ],
    entries: [
      { id: "e1", content: LONG },
      { id: "e2", title: CRISIS, content: LONG },
      { id: "e3", content: LONG },
      { id: "e4", content: LONG },
    ],
  });
  const spy = spyDeps({ reply: { summary: "A summary." } });
  const res = await handleGetPatterns(admin.client, "u1", spy.deps);
  const body = await res.json();
  assertEquals(body, { status: "completed", summary: "A summary.", entry_count: 3 });
  assertEquals(spy.prompts.length, 1);
  assert(!spy.prompts[0].includes("obs two crisis"), "a matched entry reached the provider");
  assert(!spy.prompts[0].includes("entry_id"), "entry ids reached the provider");
});

Deno.test("get_patterns: too few left after leaving matches out", async () => {
  const admin = patternsAdmin({
    newest: { id: "e1", content: LONG },
    analyses: [
      { entry_id: "e1", observation: "a" },
      { entry_id: "e2", observation: "b" },
      { entry_id: "e3", observation: "c" },
    ],
    entries: [{ id: "e1", content: LONG }, { id: "e2", content: CRISIS }, { id: "e3", content: LONG }],
  });
  const spy = spyDeps();
  const res = await handleGetPatterns(admin.client, "u1", spy.deps);
  assertEquals(await res.json(), { status: "insufficient_evidence", summary: null, entry_count: 2 });
  assertEquals(spy.prompts.length, 0);
});

Deno.test("get_patterns: an unreadable journal never reaches the provider", async () => {
  const admin = patternsAdmin({
    newest: { id: "e1", content: LONG },
    analyses: [{ entry_id: "e1", observation: "a" }, { entry_id: "e2", observation: "b" }, { entry_id: "e3", observation: "c" }],
    entries: [],
    entriesError: true,
  });
  const spy = spyDeps();
  const res = await handleGetPatterns(admin.client, "u1", spy.deps);
  assertEquals(res.status, 503);
  assertEquals(spy.prompts.length, 0);

  const down = fakeClient(() => ({ data: null, error: { message: "down" } }));
  const res2 = await handleGetPatterns(down.client, "u1", spy.deps);
  assertEquals(res2.status, 503);
  assertEquals(spy.prompts.length, 0);
});

Deno.test("index.ts wires the live provider, the flag and the count", async () => {
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(index.includes("model: callGeminiJson,"), "the provider is not callGeminiJson");
  assert(index.includes("runtimePatterns: RUNTIME_PATTERNS,"), "the output filter is not index.ts's RUNTIME_PATTERNS");
  assert(index.includes("featureFlagEnabled(adminClient, DRAFT_SAFETY_CONTENT_FLAG)"), "private_safety_check is not read");
  assert(index.includes('adminClient.rpc("bump_metric_server", { p_key: key })'), "the count does not go through bump_metric_server");
  const pause = index.indexOf("if (await journalInsightsPaused(adminClient))");
  assert(pause > 0 && pause < index.indexOf("const deps: JournalDeps"), "the pause is no longer first");
});
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env analyse-journal-entry/ 2>&1 | grep -E 'TS2307|error:' | head -2)
```

Expected: `TS2307 [ERROR]: Cannot find module '…/analyse-journal-entry/journal_handlers.ts'.` and `error: Type checking failed.`

- [ ] **Step 3: Move the two actions into `journal_handlers.ts`, with the check first**

Create `supabase/functions/analyse-journal-entry/journal_handlers.ts` with exactly the content below. Everything from `function globalConstraintHeader()` to `function buildPatternsPrompt`, and `buildFallback`, is today's `index.ts` text, moved verbatim (it keeps today's em dashes in the prompts; Step 5 diffs it):

```ts
// supabase/functions/analyse-journal-entry/journal_handlers.ts
//
// The two actions of analyse-journal-entry, moved out of index.ts unchanged
// except for Spec 1 W9c (spec 4.5; D12; research 10 F-7): the hard-coded
// self_disclosure check runs FIRST, before the cache and before any provider
// call. Self-harm (the reviewed sessions corpus) always runs; the [DRAFT]
// victimisation list only where private_safety_check is on (review A-4). A
// match answers {status: 'support_offered'}: no provider call, no cache read,
// nothing about the match stored; the entry's earlier reflection (an AI note
// about older words) is removed so none sits beside it (plan P-20); one
// support_card_shown:journal count. get_patterns leaves matched entries out,
// and answers support_offered without a provider call when the newest entry
// matches. Nothing here depends on the model: the check is deterministic.
// The provider, the output filter (index.ts keeps RUNTIME_PATTERNS, where
// the permanent-constraints test reads it), the flag read and the count are
// injected (JournalDeps), so the tests can spy on them.
import { STATIC_PROHIBITED_PATTERNS } from "../_shared/gemini_json.ts";
import { detectSelfDisclosure } from "../_shared/self_disclosure.ts";

export const corsHeaders = {
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

export const SUPPORT_OFFERED_BODY = { status: "support_offered" } as const;
export const SUPPORT_CARD_METRIC = "support_card_shown:journal";

export type JournalModel = (params: {
  promptId: string;
  systemPrompt: string;
  userPrompt: string;
  maxOutputTokens: number;
  runtimeProhibitedPatterns?: RegExp[];
  attribution: { fn: string; userId: string };
}) => Promise<Record<string, unknown> | null>;

export interface JournalDeps {
  /// callGeminiJson in production.
  model: JournalModel;
  /// index.ts's output filter (it stays defined there, where
  /// test/architecture/permanent_constraints_test.dart reads it).
  runtimePatterns: RegExp[];
  /// private_safety_check, read the way ai-assist reads it (off on doubt).
  victimisationOn: () => Promise<boolean>;
  /// bump_metric_server; never throws, never blocks the answer.
  bumpMetric: (key: string) => Promise<void>;
}

type EntryText = { title?: string | null; content?: string | null };

function disclosed(entry: EntryText, victimisation: boolean): boolean {
  const text = `${entry.title ?? ""}\n${entry.content ?? ""}`;
  return detectSelfDisclosure(text, { victimisation }) !== null;
}

async function offerSupport(deps: JournalDeps) {
  try {
    await deps.bumpMetric(SUPPORT_CARD_METRIC);
  } catch {
    // A count never changes the answer.
  }
  return json(SUPPORT_OFFERED_BODY);
}

export async function handleAnalyseEntry(
  // deno-lint-ignore no-explicit-any
  userClient: any,
  // deno-lint-ignore no-explicit-any
  adminClient: any,
  userId: string,
  entryId: string,
  deps: JournalDeps,
) {
  if (!entryId) {
    return json({ error: "entry_id_required" }, 400);
  }

  const entryRes = await userClient
    .from("reflection_journal_entries")
    .select("id, title, content")
    .eq("id", entryId)
    .is("deleted_at", null)
    .single();
  if (entryRes.error || !entryRes.data) {
    return json({ error: "entry_not_found" }, 404);
  }

  // Spec 1 W9c: the crisis check, first.
  if (disclosed(entryRes.data, await deps.victimisationOn())) {
    await adminClient
      .from("reflection_journal_analysis")
      .delete()
      .eq("entry_id", entryId)
      .eq("user_id", userId);
    return await offerSupport(deps);
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

  let output = await maybeGenerate(deps, content, userId);
  if (!output) {
    output = buildFallback();
  }

  validateOutput(output, deps.runtimePatterns);
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

export async function handleGetPatterns(
  // deno-lint-ignore no-explicit-any
  adminClient: any,
  userId: string,
  deps: JournalDeps,
) {
  // Spec 1 W9c: the crisis check, first. Unreadable entries: no provider
  // call (fail closed).
  const victimisation = await deps.victimisationOn();
  const newest = await adminClient
    .from("reflection_journal_entries")
    .select("id, title, content")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (newest.error) {
    return json({ error: "journal_unavailable" }, 503);
  }
  if (newest.data && disclosed(newest.data, victimisation)) {
    return await offerSupport(deps);
  }

  const rows = await adminClient
    .from("reflection_journal_analysis")
    .select("entry_id, observation, tone, created_at")
    .eq("user_id", userId)
    .eq("status", "completed")
    .order("created_at", { ascending: false })
    .limit(MAX_ENTRIES_FOR_PATTERNS);

  const found: Array<{ entry_id: string; observation: string; tone: string | null; created_at: string }> =
    rows.data ?? [];
  const ids = [...new Set(found.map((a) => a.entry_id))];
  const matched = new Set<string>();
  if (ids.length > 0) {
    const entries = await adminClient
      .from("reflection_journal_entries")
      .select("id, title, content")
      .in("id", ids);
    if (entries.error) {
      return json({ error: "journal_unavailable" }, 503);
    }
    for (const e of entries.data ?? []) {
      if (disclosed(e, victimisation)) matched.add(e.id);
    }
  }
  const analyses = found
    .filter((a) => !matched.has(a.entry_id))
    .map(({ observation, tone, created_at }) => ({ observation, tone, created_at }));
  if (analyses.length < MIN_ENTRIES_FOR_PATTERNS) {
    return json({
      status: "insufficient_evidence",
      summary: null,
      entry_count: analyses.length,
    });
  }

  const prompt = buildPatternsPrompt(analyses);
  const result = await deps.model({
    promptId: "journal_patterns",
    attribution: { fn: "analyse-journal-entry", userId },
    systemPrompt: patternsSystemPrompt(),
    userPrompt: prompt,
    maxOutputTokens: 220,
    runtimeProhibitedPatterns: deps.runtimePatterns,
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

async function maybeGenerate(deps: JournalDeps, content: string, userId: string) {
  const result = await deps.model({
    promptId: "journal_entry_analysis",
    attribution: { fn: "analyse-journal-entry", userId },
    systemPrompt: analysisSystemPrompt(),
    userPrompt: buildAnalysisPrompt(content),
    maxOutputTokens: 220,
    runtimeProhibitedPatterns: deps.runtimePatterns,
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

function validateOutput(
  output: { tone: string; observation: string; confidence: string },
  runtimePatterns: RegExp[],
) {
  if (!output || typeof output !== "object") {
    throw new Error("invalid_output");
  }
  const outputText = JSON.stringify(output);
  for (const pattern of [...STATIC_PROHIBITED_PATTERNS, ...runtimePatterns]) {
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

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
```

Replace `supabase/functions/analyse-journal-entry/index.ts` with exactly:

```ts
// supabase/functions/analyse-journal-entry/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callGeminiJson } from "../_shared/gemini_json.ts";
import { DRAFT_SAFETY_CONTENT_FLAG, featureFlagEnabled } from "../_shared/feature_flag.ts";
import { journalInsightsPaused, PAUSED_BODY } from "./journal_pause.ts";
import { corsHeaders, handleAnalyseEntry, handleGetPatterns, type JournalDeps, json } from "./journal_handlers.ts";

const RUNTIME_PATTERNS = [
  /you should (tell|confront|ask|leave)/i,
  // §11 #8: permanently banned from all AI outputs. The prompt already
  // asks for this, but a prompt is a request -- the model can still emit
  // one. This summary is returned straight to the caller, so it needs the
  // guarantee rather than the request. A match makes callGeminiJson return
  // null and the caller falls back to fixed boilerplate, so filtering here
  // fails closed.
  /\b(toxic|narcissist|codependent|disorder|broken)\b/i,
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
    // Spec 1 W1c (D12): paused until the self_disclosure check runs first
    // (W9c). Off means no provider call for either action.
    if (await journalInsightsPaused(adminClient)) {
      return json(PAUSED_BODY);
    }
    // Spec 1 W9c: the provider, the draft-list flag and the count, injected
    // so journal_handlers.test.ts can spy on them.
    const deps: JournalDeps = {
      model: callGeminiJson,
      runtimePatterns: RUNTIME_PATTERNS,
      victimisationOn: () => featureFlagEnabled(adminClient, DRAFT_SAFETY_CONTENT_FLAG),
      bumpMetric: async (key) => {
        await adminClient.rpc("bump_metric_server", { p_key: key });
      },
    };
    if (body.action === "get_patterns") {
      return await handleGetPatterns(adminClient, user.id, deps);
    }
    if (body.action === "analyse_entry") {
      return await handleAnalyseEntry(userClient, adminClient, user.id, body.entry_id, deps);
    }
    return json({ error: "unknown_action" }, 400);
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
```

- [ ] **Step 4: Run the tests and type-check**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env analyse-journal-entry/ 2>&1 | grep -E '^(ok|FAILED) \|')
(cd supabase/functions && NO_COLOR=1 deno check analyse-journal-entry/index.ts 2>&1 | tail -1)
```

Expected: `ok | 14 passed | 0 failed` (8 new; W1c's 2 pause tests and 4 runtime-pattern tests unchanged); `Check analyse-journal-entry/index.ts`.

- [ ] **Step 5: Nothing of the old behaviour moved by accident**

```bash
B=.superpowers/sdd/2026-11-04-spec1-w9/journal_index_before.ts
git show HEAD:supabase/functions/analyse-journal-entry/index.ts > $B
H=supabase/functions/analyse-journal-entry/journal_handlers.ts
diff <(sed -n '/^function globalConstraintHeader/,/^function buildPatternsPrompt/p' $B) <(sed -n '/^function globalConstraintHeader/,/^function buildPatternsPrompt/p' $H) && echo prompts-verbatim
diff <(sed -n '/^function buildFallback/,/^}/p' $B) <(sed -n '/^function buildFallback/,/^}/p' $H) && echo fallback-verbatim
diff <(sed -n '/^const RUNTIME_PATTERNS = \[/,/^\];/p' $B) <(sed -n '/^const RUNTIME_PATTERNS = \[/,/^\];/p' supabase/functions/analyse-journal-entry/index.ts) && echo output-filter-verbatim
flutter test --no-pub test/architecture/permanent_constraints_test.dart 2>&1 | tail -1
```

Expected: `prompts-verbatim`, `fallback-verbatim`, `output-filter-verbatim`, `All tests passed!` (the §11 #8 tests still read `RUNTIME_PATTERNS` in `index.ts` and the banned words across the function's folder).

- [ ] **Step 6: Mutation checks (each must turn the test red)**

```bash
(cd supabase/functions && python3 -I - <<'PY'
import os, pathlib, subprocess
p = pathlib.Path('analyse-journal-entry/journal_handlers.ts')
orig = p.read_text()
check = """  // Spec 1 W9c: the crisis check, first.
  if (disclosed(entryRes.data, await deps.victimisationOn())) {
    await adminClient
      .from("reflection_journal_analysis")
      .delete()
      .eq("entry_id", entryId)
      .eq("user_id", userId);
    return await offerSupport(deps);
  }

"""
cache = """  if (existing.data) {
    return json({ status: "completed", ...existing.data });
  }

"""
muts = {
 # (anchor, replacement); check_after_cache moves the check below the cache read.
 'check_after_cache': [(check, ""), (cache, cache + check)],
 'no_check': [(check, "")],
 'victimisation_always': [("disclosed(entryRes.data, await deps.victimisationOn())", "disclosed(entryRes.data, true)")],
 'patterns_newest_unchecked': [("  if (newest.data && disclosed(newest.data, victimisation)) {\n    return await offerSupport(deps);\n  }\n", "")],
 'patterns_no_exclusion': [("    .filter((a) => !matched.has(a.entry_id))\n", "")],
 'patterns_fail_open': [("    if (entries.error) {\n      return json({ error: \"journal_unavailable\" }, 503);\n    }\n", "")],
 'no_metric': [("    await deps.bumpMetric(SUPPORT_CARD_METRIC);\n", "")],
 'keeps_stale_reflection': [("    await adminClient\n      .from(\"reflection_journal_analysis\")\n      .delete()\n      .eq(\"entry_id\", entryId)\n      .eq(\"user_id\", userId);\n", "")],
}
try:
    for name, pairs in muts.items():
        m = orig
        for a, b in pairs:
            assert m.count(a) == 1, name
            m = m.replace(a, b)
        p.write_text(m)
        r = subprocess.run(['deno', 'test', '--allow-read', '--allow-env', 'analyse-journal-entry/'],
                           capture_output=True, text=True, env={**os.environ, 'NO_COLOR': '1'})
        print(name, [l for l in r.stdout.splitlines() if l.startswith(('ok |', 'FAILED |'))])
finally:
    p.write_text(orig)
PY
)
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env analyse-journal-entry/ 2>&1 | grep -E '^(ok|FAILED) \|')
```

Expected:
- `check_after_cache`: `FAILED | 13 passed | 1 failed`
- `no_check`: `FAILED | 12 passed | 2 failed`
- `victimisation_always`: `FAILED | 13 passed | 1 failed`
- `patterns_newest_unchecked`: `FAILED | 13 passed | 1 failed`
- `patterns_no_exclusion`: `FAILED | 12 passed | 2 failed`
- `patterns_fail_open`: `FAILED | 13 passed | 1 failed`
- `no_metric`: `FAILED | 12 passed | 2 failed`
- `keeps_stale_reflection`: `FAILED | 13 passed | 1 failed`

then `ok | 14 passed | 0 failed`. (`check_after_cache` and `no_check` are §7.4's "remove the `self_disclosure` call or move it after the cache read".)

- [ ] **Step 7: Run tests**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env _shared/unicode_normaliser.test.ts _shared/self_disclosure.test.ts _shared/assistant_input.test.ts analyse-journal-entry/ 2>&1 | grep -E '^(ok|FAILED) \|')
```

Expected: `ok | 28 passed | 0 failed`.

### Task 10: The writer's card, the journal's "Need support now?", and the W9c gate (§2.2, §2.3, §5.1, §5.2, §6.6, §8 W9c; P-25, P-26)

**Files:**
- Create: `lib/features/reflection_journal/presentation/widgets/journal_support_card.dart`
- Create: `test/features/reflection_journal/w9/journal_support_test.dart` (+ 4 goldens)
- Modify: `lib/features/reflection_journal/data/models/journal_analysis.dart`, `lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart`, `lib/features/reflection_journal/presentation/screens/reflection_journal_screen.dart`
- Modify: `lib/app/feature_flag_refresher.dart`, `lib/app/documentations/user_manual/data/reflection_journal_docs.dart`, `lib/app/documentations/user_manual/data/manual_documentation_registry.dart`, `test/app/documentations/documentation_registry_flags_test.dart` (one line), `test/features/reflection_journal/support/journal_test_app.dart`
- Modify: `lib/i10n/app_en.arb` (+ `lib/i10n/generated/*`)

**Interfaces:**
- Consumes: Task 9's `support_offered`; Task 8's `openSupportNow`, `SupportLinkSource.journal`, `support_needSupportNow`.
- Produces: `JournalAnalysis.isSupportOffered`; `journalInsightsReadProvider` / `journalInsightsEnabledProvider`; `JournalSupportOffers` / `journalSupportOffersProvider` (`Set<String>` of entry ids, this run only: `offer`, `dismiss`, `dismissAll`); `JournalSupportCard({required VoidCallback onNotNow})`. Keys `journal_supportCardBody`, `journal_supportSeeSupport`, `journal_supportNotNow`.

- [ ] **Step 1: Extend the journal test app, then write the failing test**

The journal test app gains the app's localisations (the card and the link read its strings), a `/safety-resources` route and optional overrides; existing journal tests are unchanged by these additions:

```bash
python3 -I - <<'PY'
# W9c client edits, as exact replacements (run from the repo root).
import pathlib
def edit(path, pairs):
    p = pathlib.Path(path); s = p.read_text()
    for a, b in pairs:
        assert s.count(a) == 1, (path, a[:70], s.count(a))
        s = s.replace(a, b)
    p.write_text(s)

# The journal test app: localisations (the card and link read the app's
# strings), a /safety-resources route, and optional overrides. Existing
# tests are unchanged by these additions.
edit('test/features/reflection_journal/support/journal_test_app.dart', [
  ("import 'package:flutter/material.dart';\n", "import 'package:attune/i10n/generated/app_localizations.dart';\nimport 'package:flutter/material.dart';\n"),
  ("""  String initial = '/reflectionJournal',
  Object? extra,
}) async {""", """  String initial = '/reflectionJournal',
  Object? extra,
  List<Override> overrides = const [],
}) async {"""),
  ("""          return JournalEntryScreen(entryId: a.entryId, isNew: a.isNew, prompt: a.prompt);
        },
      ),
    ],""", """          return JournalEntryScreen(entryId: a.entryId, isNew: a.isNew, prompt: a.prompt);
        },
      ),
      // Spec 1 W9c: where "Need support now?" and "See support" go.
      GoRoute(path: '/safety-resources', builder: (_, __) => const Text('Support resources screen')),
    ],"""),
  ("""        (ImageSource source, int limit) async => (photos: [for (final p in photos) Uint8List.fromList(p)], rejected: 0),
      ),
    ],""", """        (ImageSource source, int limit) async => (photos: [for (final p in photos) Uint8List.fromList(p)], rejected: 0),
      ),
      ...overrides,
    ],"""),
  ("""      builder: (_, __) => MaterialApp.router(routerConfig: router),""",
   """      // Spec 1 W9c: the support card and link read the app's strings.
      builder: (_, __) => MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),"""),
])
print('journal test app extended')
PY
```

Expected: `journal test app extended`.

Create `test/features/reflection_journal/w9/journal_support_test.dart` with exactly:

```dart
// Spec 1 W9c (§8 W9c, §6.6, §2.2, §2.3): when the crisis check answers
// support_offered, the writer sees the support card instead of a
// reflection: on the journal list when they leave the entry, in the entry
// when they open it again, and on the Patterns tab. "See support" opens
// Support (counted); "Not now" puts it away. Nothing about it is stored on
// the phone. "Need support now?" is in the entry menu with
// journal_ai_insights (W9c's flag).
//   flutter test --update-goldens test/features/reflection_journal/w9/journal_support_test.dart
import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_screen.dart';
import 'package:attune/features/reflection_journal/presentation/widgets/journal_support_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/flow_harness.dart';
import '../support/fake_journal.dart';
import '../support/journal_test_app.dart';

const _card =
    "If things feel heavy right now, you don't have to carry it alone. Support is here if you want it.";

/// The server's crisis check matched every entry.
class _SupportOffered extends FakeJournalRepository {
  _SupportOffered() : super(now: DateTime.now());

  @override
  Future<JournalAnalysis> analyseEntry(String entryId) async {
    analysed.add(entryId);
    return JournalAnalysis.fromJson(const {'status': 'support_offered'});
  }

  @override
  Future<({String status, String? summary, int entryCount})>
  getPatterns() async => (
    status: 'support_offered',
    summary: null,
    entryCount: 0,
  );
}

Future<void> _type(WidgetTester t, String text) async {
  t
      .state<NoteTextBlockState>(find.byType(NoteTextBlock).first)
      .controller
      .replaceText(0, 0, text, TextSelection.collapsed(offset: text.length));
  await t.pump();
}

Future<void> _back(WidgetTester t) async {
  t.state<NavigatorState>(find.byType(Navigator).first).pop();
  await t.pumpAndSettle();
}

void main() {
  test('support_offered is read as such', () {
    final a = JournalAnalysis.fromJson(const {'status': 'support_offered'});
    expect(a.isSupportOffered, isTrue);
    expect(a.isComplete, isFalse);
  });

  testWidgets(
    'leaving an entry that reads as a crisis: the card, never a reflection',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final repo =
          _SupportOffered()
            ..analysisFor = JournalAnalysis.fromJson(const {
              'status': 'completed',
              'tone': 'heavy',
              'observation': 'An older reflection.',
              'confidence': 'low',
            });
      final e = repo.addEntry(title: 'Tonight', text: '');
      await pumpJournal(t, repo: repo);
      expect(find.text(_card), findsNothing);
      await t.tap(find.text('Tonight'));
      await t.pumpAndSettle();
      await _type(t, 'Words the check reads as a crisis');
      await _back(t);
      await t.pumpAndSettle();
      expect(repo.analysed, [e.id]);
      expect(find.text(_card), findsOneWidget); // on the list

      await t.tap(find.text('Tonight'));
      await t.pumpAndSettle();
      expect(find.text(_card), findsOneWidget); // in the entry, instead of
      expect(find.text('An older reflection.'), findsNothing); // the reflection
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      expect(find.text(_card), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.contains('support')), isEmpty);
    },
  );

  testWidgets('"Not now" on the list puts it away', (t) async {
    final repo = _SupportOffered();
    repo.addEntry(title: 'Late', text: '');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Late'));
    await t.pumpAndSettle();
    await _type(t, 'More words');
    await _back(t);
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(find.text(_card), findsNothing);
  });

  testWidgets('Patterns: support instead of a summary', (t) async {
    final repo = _SupportOffered();
    repo.addEntry(title: 'One', text: 'x');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Patterns'));
    await t.pumpAndSettle();
    expect(find.text(_card), findsOneWidget);
  });

  testWidgets('the entry menu, journal_ai_insights off: no support link', (
    t,
  ) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Menu', text: 'x');
    await pumpJournal(
      t,
      repo: repo,
      initial: '/journalEntry',
      extra: JournalEntryArgs(entryId: e.id),
    );
    await t.tap(find.byTooltip('Entry options'));
    await t.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Need support now?'), findsNothing);
  });

  testWidgets(
    'the entry menu, journal_ai_insights on: "Need support now?" opens Support',
    (t) async {
      final repo = FakeJournalRepository(now: DateTime.now());
      final e = repo.addEntry(title: 'Menu', text: 'x');
      await pumpJournal(
        t,
        repo: repo,
        initial: '/journalEntry',
        extra: JournalEntryArgs(entryId: e.id),
        overrides: [journalInsightsEnabledProvider.overrideWithValue(true)],
      );
      await t.tap(find.byTooltip('Entry options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Need support now?'));
      await t.pumpAndSettle();
      expect(find.text('Support resources screen'), findsOneWidget);
    },
  );

  testWidgets(
    'the card: See support is counted and opens Support; guidelines and goldens',
    (t) async {
      var notNow = 0;
      Widget card() => Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: JournalSupportCard(onNotNow: () => notNow++),
        ),
      );
      final h = await pumpFlowScreen(t, card);
      await expectFlowGuidelines(t);
      await t.tap(find.text('Not now'));
      expect(notNow, 1);
      await t.tap(find.text('See support'));
      await t.pumpAndSettle();
      expect(find.text('at /safety-resources'), findsOneWidget);
      expect(h.metrics, ['support_link_opened:journal']);
      await expectFlowGoldens(t, 'journal_support_card', card);
    },
  );
}
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
flutter test --no-pub test/features/reflection_journal/w9/journal_support_test.dart 2>&1 | grep -o "Error when reading '[^']*'" | head -1
flutter test --no-pub test/features/reflection_journal/ 2>&1 | grep -c "\[E\]"
```

Expected: `Error when reading 'lib/features/reflection_journal/presentation/widgets/journal_support_card.dart'`; then `1` (the only `[E]` is the new file, which can't load yet: the 43 existing journal tests pass with the extended test app).

- [ ] **Step 3: The copy**

Create `.superpowers/sdd/2026-11-04-spec1-w9/arb_w9c.txt` with exactly:

```text
  "journal_supportCardBody": "If things feel heavy right now, you don't have to carry it alone. Support is here if you want it.",
  "@journal_supportCardBody": {
    "description": "The writer's card, shown instead of a reflection when an entry reads as a crisis (Spec 1 W9c). Only the writer sees it."
  },
  "journal_supportSeeSupport": "See support",
  "@journal_supportSeeSupport": {
    "description": "Opens Support from the journal's writer card (Spec 1 W9c)."
  },
  "journal_supportNotNow": "Not now",
  "@journal_supportNotNow": {
    "description": "Dismisses the journal's writer card (Spec 1 W9c)."
  }
```

```bash
grep -cP '[^\x00-\x7F]' .superpowers/sdd/2026-11-04-spec1-w9/arb_w9c.txt
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py .superpowers/sdd/2026-11-04-spec1-w9/arb_w9c.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package > /dev/null
grep -c 'journal_support' lib/i10n/generated/app_localizations_en.dart
```

Expected: `0`; `added 3 keys`; `3`.

- [ ] **Step 4: The card and its providers; the model, the two screens, the refresher and the manual**

Create `lib/features/reflection_journal/presentation/widgets/journal_support_card.dart` with exactly:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/opinions/presentation/widgets/need_support_link.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// journal_ai_insights (Spec 1 §2.5), as read: W9c's flag. The entry menu's
/// "Need support now?" shows with it, so production sees W9c only after its
/// clinician gate (plan P-22). Off until read, off when unreadable.
final journalInsightsReadProvider = FutureProvider<bool>((ref) async {
  try {
    return await ChatFeatureFlags.isEnabled(
      Supabase.instance.client,
      'journal_ai_insights',
    );
  } catch (_) {
    return false;
  }
});

final journalInsightsEnabledProvider = Provider<bool>(
  (ref) => ref.watch(journalInsightsReadProvider).valueOrNull ?? false,
);

/// The entries the crisis check answered `support_offered` for, this run
/// only: never stored on the phone, never sent anywhere (Spec 1 §6.6).
class JournalSupportOffers extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void offer(String entryId) => state = {...state, entryId};

  void dismiss(String entryId) => state = {...state}..remove(entryId);

  void dismissAll() => state = const {};
}

final journalSupportOffersProvider =
    NotifierProvider<JournalSupportOffers, Set<String>>(
      JournalSupportOffers.new,
    );

/// The writer's card (Spec 1 §8 W9c), shown instead of a reflection. Only
/// the writer sees it; never animated (§2.2); large text let through.
class JournalSupportCard extends ConsumerWidget {
  const JournalSupportCard({super.key, required this.onNotNow});

  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AllowLargeText(
      child: Semantics(
        container: true,
        child: Container(
          margin: const EdgeInsets.only(top: Spacing.md),
          padding: Spacing.allMd,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadiusTokens.mdAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.journal_supportCardBody,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: theme.colorScheme.onSurface,
                    ),
                    onPressed: onNotNow,
                    child: Text(loc.journal_supportNotNow),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed:
                        () => openSupportNow(
                          context,
                          ref,
                          SupportLinkSource.journal,
                        ),
                    child: Text(loc.journal_supportSeeSupport),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Then the edits (exact replacements; each anchor must occur once):

```bash
python3 -I - <<'PY'
# W9c client edits, as exact replacements (run from the repo root).
import pathlib
def edit(path, pairs):
    p = pathlib.Path(path); s = p.read_text()
    for a, b in pairs:
        assert s.count(a) == 1, (path, a[:70], s.count(a))
        s = s.replace(a, b)
    p.write_text(s)

edit('lib/features/reflection_journal/data/models/journal_analysis.dart', [
  ("  // 'pending' | 'completed' | 'insufficient_evidence' | 'failed' | 'paused'\n",
   "  // 'pending' | 'completed' | 'insufficient_evidence' | 'failed' | 'paused'\n  // | 'support_offered'\n"),
  ("  bool get isPaused => status == 'paused';\n",
   "  bool get isPaused => status == 'paused';\n\n  /// Spec 1 W9c: the crisis check matched; no reflection, the writer's\n  /// card instead (nothing about it is stored).\n  bool get isSupportOffered => status == 'support_offered';\n"),
])

edit('lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart', [
  ("import '../widgets/journal_photo_block.dart';\n",
   "import '../widgets/journal_photo_block.dart';\nimport '../widgets/journal_support_card.dart';\nimport 'package:attune/features/opinions/presentation/widgets/need_support_link.dart';\n"),
  ("enum _EntryMenu { pin, unpin, delete }\n", "enum _EntryMenu { pin, unpin, delete, support }\n"),
  ("    final async = ref.watch(journalEntryDetailProvider(widget.entryId));\n    _last = async.valueOrNull ?? _last;\n",
   "    final async = ref.watch(journalEntryDetailProvider(widget.entryId));\n    _last = async.valueOrNull ?? _last;\n    final supportLink = ref.watch(journalInsightsEnabledProvider);\n"),
  ("  late final JournalListNotifier _list;\n",
   "  late final JournalListNotifier _list;\n  late final JournalSupportOffers _offers;\n"),
  ("    _list = ref.read(journalListProvider.notifier);\n",
   "    _list = ref.read(journalListProvider.notifier);\n    _offers = ref.read(journalSupportOffersProvider.notifier);\n"),
  ("""    final list = _list;
    final id = widget.entryId;
    scheduleMicrotask(() async {
      await visit.settled();
      if (visit.textChanged) unawaited(repo.analyseEntry(id).then((_) {}, onError: (Object _) {}));""",
   """    final list = _list;
    final offers = _offers;
    final id = widget.entryId;
    scheduleMicrotask(() async {
      await visit.settled();
      // Spec 1 W9c: support_offered shows the writer's card (this run only).
      if (visit.textChanged) {
        unawaited(repo.analyseEntry(id).then((a) {
          if (a.isSupportOffered) offers.offer(id);
        }, onError: (Object _) {}));
      }"""),
  ("""                      _EntryMenu.delete => _confirmDelete(),
                    },""", """                      _EntryMenu.delete => _confirmDelete(),
                      _EntryMenu.support => openSupportNow(context, ref, SupportLinkSource.journal),
                    },"""),
  ("""                      const PopupMenuItem(value: _EntryMenu.delete, child: Text('Delete')),
                    ],""", """                      const PopupMenuItem(value: _EntryMenu.delete, child: Text('Delete')),
                      // Spec 1 W9c: with journal_ai_insights (its gate) only.
                      if (supportLink)
                        PopupMenuItem(
                          value: _EntryMenu.support,
                          child: Text(AppLocalizations.of(context)!.support_needSupportNow),
                        ),
                    ],"""),
  ("""      footer: Column(children: [
        if (d.analysis case final a? when a.status == 'completed' && (a.observation ?? '').isNotEmpty)
          _ReflectionCard(tone: a.tone, observation: a.observation!),""", """      footer: Column(children: [
        // Spec 1 W9c: the writer's card instead of any reflection.
        if (ref.watch(journalSupportOffersProvider).contains(widget.entryId))
          JournalSupportCard(onNotNow: () => _offers.dismiss(widget.entryId))
        else if (d.analysis case final a? when a.status == 'completed' && (a.observation ?? '').isNotEmpty)
          _ReflectionCard(tone: a.tone, observation: a.observation!),"""),
])

edit('lib/features/reflection_journal/presentation/screens/reflection_journal_screen.dart', [
  ("import 'package:attune/features/reflection_journal/presentation/widgets/journal_entry_row.dart';\n",
   "import 'package:attune/features/reflection_journal/presentation/widgets/journal_entry_row.dart';\nimport 'package:attune/features/reflection_journal/presentation/widgets/journal_support_card.dart';\n"),
  ("""              children: [
                if (s.pinned.isNotEmpty) section('Pinned', s.pinned),""", """              children: [
                // Spec 1 W9c: the entry just closed read as a crisis.
                if (ref.watch(journalSupportOffersProvider).isNotEmpty)
                  JournalSupportCard(
                    onNotNow:
                        () =>
                            ref
                                .read(journalSupportOffersProvider.notifier)
                                .dismissAll(),
                  ),
                if (s.pinned.isNotEmpty) section('Pinned', s.pinned),"""),
  ("""        // Spec 1 W1c (D12): insights are paused (journal_ai_insights off);""", """        // Spec 1 W9c: the newest entry read as a crisis: support, no summary.
        if (patterns.status == 'support_offered') {
          return SingleChildScrollView(
            padding: EdgeInsets.all(Spacing.md.w),
            child: JournalSupportCard(
              onNotNow: () => ref.invalidate(journalPatternsProvider),
            ),
          );
        }
        // Spec 1 W1c (D12): insights are paused (journal_ai_insights off);"""),
])

edit('lib/app/feature_flag_refresher.dart', [
  ("import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';\n",
   "import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';\nimport 'package:attune/features/reflection_journal/presentation/widgets/journal_support_card.dart';\n"),
  ("  opinionsSafetyReadProvider,\n];", "  opinionsSafetyReadProvider,\n  // Spec 1 W9c.\n  journalInsightsReadProvider,\n];"),
  ("    ref.listen(opinionsSafetyReadProvider, (_, __) {});\n",
   "    ref.listen(opinionsSafetyReadProvider, (_, __) {});\n    // Spec 1 W9c: the same for the journal entry menu.\n    ref.listen(journalInsightsReadProvider, (_, __) {});\n"),
])

edit('lib/app/documentations/user_manual/data/manual_documentation_registry.dart', [
  ("""    'opinionsSafety': ['opinions_safety_v1'],
  };""", """    'opinionsSafety': ['opinions_safety_v1'],
    // Spec 1 W9c: support first, in the journal.
    'journalSupport': ['journal_ai_insights'],
  };"""),
])
edit('test/app/documentations/documentation_registry_flags_test.dart', [
  ("""          // Spec 1 W9b: Opinions safety.
          'opinions_safety_v1',
""", """          // Spec 1 W9b: Opinions safety.
          'opinions_safety_v1',
          // Spec 1 W9c: the journal's support-first check.
          'journal_ai_insights',
"""),
])
print('W9c client edits applied')
edit('lib/app/documentations/user_manual/data/reflection_journal_docs.dart', [
  ("""              'Once you\\'ve written a handful of entries, a Patterns view becomes available, gently pointing out themes that have shown up more than once across your writing — always sourced to specific entries, never invented.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
""", """              'Once you\\'ve written a handful of entries, a Patterns view becomes available, gently pointing out themes that have shown up more than once across your writing — always sourced to specific entries, never invented.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
        // Spec 1 W9c: only while journal insights are on.
        if (DocumentationRegistry.passageVisible(
          'journalSupport',
          documentationFlagsOf(context),
        ))
          ManualContent(
            id: 'journal_support_first',
            title: 'When an entry sounds very hard',
            content:
                "If an entry sounds like you may be going through something very hard, Attune doesn't write a reflection. It shows you a way to reach support instead. Only you see it, and nothing about it is kept.",
            numberPrefix: '3',
            type: ManualContentType.text,
          ),
"""),
])
print('W9c manual passage added')
PY
```

Expected: `W9c client edits applied`, `W9c manual passage added`. The entry screen captures the offers notifier in `initState` (its `dispose` runs after `ref` is gone, as `_repo` and `_list` already are), so the answer of the reflection call that `dispose` starts can still raise the card.

- [ ] **Step 5: Run the tests, write the goldens, look at them**

```bash
flutter test --no-pub test/features/reflection_journal/w9/journal_support_test.dart --update-goldens 2>&1 | tail -1
flutter test --no-pub test/features/reflection_journal/ test/app/ 2>&1 | tail -1
```

Expected: `All tests passed!` twice. Open `test/features/reflection_journal/w9/goldens/journal_support_card.*.png`: the card's words, then "Not now" and the filled "See support" at the end of the row (on the left under RTL); at 2.0 the words wrap and the buttons may wrap to two lines.

- [ ] **Step 6: Analyzer on the touched files**

```bash
flutter analyze --no-pub lib/features/reflection_journal lib/app/feature_flag_refresher.dart lib/app/documentations/user_manual/data test/features/reflection_journal test/app/documentations 2>&1 | grep -E '^\s*(error|warning) '
```

Expected: no output.

- [ ] **Step 7: Mutation checks (each must turn the test red)**

```bash
python3 -I - <<'PY'
import pathlib, subprocess
TEST = 'test/features/reflection_journal/w9/journal_support_test.dart'
ENTRY = 'lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart'
LIST = 'lib/features/reflection_journal/presentation/screens/reflection_journal_screen.dart'
CARD = 'lib/features/reflection_journal/presentation/widgets/journal_support_card.dart'
muts = {
  'never_offered': (ENTRY, "          if (a.isSupportOffered) offers.offer(id);\n", ""),
  'reflection_not_replaced': (ENTRY, "        if (ref.watch(journalSupportOffersProvider).contains(widget.entryId))", "        if (false)"),
  'menu_link_ungated': (ENTRY, "                      if (supportLink)", "                      if (true)"),
  'patterns_summary_on_support': (LIST, "        if (patterns.status == 'support_offered') {", "        if (false) {"),
  'card_counted_as_opinions': (CARD, "                          SupportLinkSource.journal,", "                          SupportLinkSource.opinions,"),
}
originals = {}
try:
    for name, (path, a, b) in muts.items():
        p = pathlib.Path(path)
        s = originals.setdefault(path, p.read_text())
        assert s.count(a) == 1, name
        p.write_text(s.replace(a, b))
        r = subprocess.run(['flutter', 'test', '--no-pub', TEST], capture_output=True, text=True)
        print(f"{name}: {'red' if r.returncode else 'GREEN (mutant survived)'}")
        p.write_text(s)
finally:
    for path, s in originals.items():
        pathlib.Path(path).write_text(s)
print('restored')
PY
```

Expected:
- `never_offered: red`
- `reflection_not_replaced: red`
- `menu_link_ungated: red`
- `patterns_summary_on_support: red`
- `card_counted_as_opinions: red`

then `restored`.

- [ ] **Step 8: W9c gate (run tests)**

```bash
D=.superpowers/sdd/2026-11-04-spec1-w9
dart format lib/features/reflection_journal/presentation/widgets/journal_support_card.dart test/features/reflection_journal/w9/journal_support_test.dart
(cd supabase/functions && NO_COLOR=1 deno test --allow-read --allow-env _shared/unicode_normaliser.test.ts _shared/self_disclosure.test.ts _shared/assistant_input.test.ts analyse-journal-entry/ 2>&1 | grep -E '^(ok|FAILED) \|')
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-after-w9c.txt
grep '^FAIL' $D/sql-after-w9c.txt | comm -13 <(grep '^FAIL' $D/sql-baseline.txt) -
grep -c PASS $D/sql-after-w9c.txt
flutter test --no-pub 2>&1 | tail -1
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error ' | sort | comm -13 $D/analyze-baseline.txt -
shasum -c $D/flag_off.sha | grep -v ': OK$'
sed -n '/if (isAuthenticated && !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - $D/latch.sha && echo latch-unchanged
git status --short lib/features/games lib/features/auth/utility/auth_exports.dart lib/home lib/core/notifications ATTUNE_SOUL.md ATTUNE_THESIS.md supabase/sql/dev_enable_spec1_flags.sql supabase/functions/_shared/self_disclosure.ts supabase/functions/_shared/chat_safety.ts supabase/functions/analyse-journal-entry/journal_pause.ts
git status --short supabase/migrations | grep -v '^??'
```

Expected: `Formatted 2 files (0 changed)`; `ok | 28 passed | 0 failed`; no new SQL FAIL; `145` (Task 1's 142 and the three W9 contracts); `All tests passed!`; no new analyzer `error`; no `shasum` line; `latch-unchanged`; no `git status` line.

**W9c gate (before `journal_ai_insights` in production; spec §8 W9c):** the couples clinician and the suicide-prevention reviewer sign the journal card's words and confirm the self-harm corpus (`_shared/ai_session_safety.ts`'s `self_harm` tier, which `detectSelfDisclosure` reuses); only then is the flag's gate evidence recorded and the flag switched on in production (owner checklist 7). Until then, production keeps answering `paused` (W1c).

---

## Owner deploy checklist (the plan never runs any of this)

1. **Before `db push`: Postgres 17.** On the development project (and later production): `select current_setting('server_version_num')::int >= 170000;` → `t`. Migration 16 uses the `pg_c_utf8` collation (PG17), and fails loudly on an older server: upgrade first. The same holds for CI's `sql-contracts` job: `supabase/config.toml` sets no `[db] major_version`, so the CLI's default image runs; check it reports 17 (`select version()` in the job, or set `major_version = 17` if the owner prefers to pin it).
2. **Order.** W1-W7 are deployed first (their checklists). Then, in one `supabase db push`: `20261104100000`, `…100010` (W9a), `20261104110000`, `…110010`, `20261104120000`, `…120010`, `20261104130000`, `…130010` (W9b). Deploy `analyse-journal-entry` (W9c; it adds `journal_handlers.ts`). Ship the app build with Tasks 4, 8 and 10.
   - **What changes at once, whatever the flags (release note).** The two moderation notices come back ("Post removed", "Posting paused"); **the third confirmed removal now really bans for 7 days** (today it errors at strike 3, so no Opinions ban has ever been set: the first real bans follow this release, and the author is told, spec §9); deleting your own opinion or comment works again (OPN-DELETE-RLS; the new app calls the RPCs, and an older app's delete keeps failing as it does today).
   - **Accounts already past strike 3 (W9 final M-5).** An account whose `confirmed_violation_count` is already 2 or more was never banned (42702), so its **next** confirmed removal bans it at once, not its third. Count them before the push and say so in the release note: `select count(*) from public.profiles where confirmed_violation_count >= 2;`.
   - **Old builds and Patterns (W9 final M-4).** Once `analyse-journal-entry` deploys, a pre-W9 build whose newest entry matches the crisis check shows an empty Patterns page (it reads any unknown status as a summary) and no support card. Deploy the function and the Task 10 build together, or say so in the release note.
   - **Release-order note for OPN-DELETE-RLS:** push migration 19 before the app build reaches testers (the new app calls `remove_my_opinion`/`remove_my_comment`; on a project without them its delete fails with "function not found" instead of today's RLS error).
3. **Server, right after `db push`** (SQL editor):
   - `select has_function_privilege('authenticated','public.create_opinion(text)','EXECUTE'), has_function_privilege('anon','public.remove_my_opinion(uuid)','EXECUTE'), has_function_privilege('authenticated','public.admin_list_priority_reports(integer)','EXECUTE'), has_function_privilege('authenticated','public.admin_confirm_content_removal(text,uuid)','EXECUTE'), has_function_privilege('service_role','public.admin_confirm_content_removal(text,uuid)','EXECUTE');` → `t | f | f | f | t`.
   - `select has_table_privilege('authenticated','public.forum_reports','INSERT'), has_function_privilege('authenticated','public.increment_opinion_report_count(uuid)','EXECUTE'), has_function_privilege('anon','public.increment_opinion_report_count(uuid)','EXECUTE');` → `f | f | f` (migration 17: the report RPCs are `forum_reports`' only writers, B4 C-1; the unowned report-count helper is no client's, batch-6 ruling).
   - `select private.match_form('K' || chr(596) || 'k' || chr(596) || chr(596) || ' B@st4rd'), private.content_filter_verdict('call me on 024 412 3456', null), private.content_filter_verdict('We met in 1999 and married in 2004.', null);` → `kokoo bastard | contact_info | ` (NULL).
   - `select count(*) from private.content_filter_terms;` → `0` (nothing is loaded by a migration).
   - **Development only:** `\i supabase/sql/load_content_filter_terms.sql` (or paste it into the SQL editor) loads the `[DRAFT]` English terms; it refuses with `env:not_development` anywhere else. `dev_enable_spec1_flags.sql` already turned `opinions_safety_v1` and `journal_ai_insights` on in development.
4. **The reviewed term lists (W9a gate).** The Ghanaian cultural reviewer supplies and signs slur and explicit terms in English, Twi, Ga, Ewe, Hausa and Pidgin, and local number words with their digits. Load them on each project (SQL editor, as the owner), never as a migration:
   `insert into private.content_filter_terms (family, term, match_mode, digit, locale, source, review_ref) values ('slur', private.match_form('<term as typed>'), 'token', null, 'tw', 'reviewed', '<review ref>'), … ;` (`match_mode = 'squashed'` only for distinctive terms of 5+ letters; `family = 'number_word'` rows carry their `digit`). Then: `select family, locale, count(*) from private.content_filter_terms where active and source = 'reviewed' group by 1, 2 order by 1, 2;`. The reviewer also says whether the West African fold needs more letters (ɖ, ẹ, ọ, ƴ): that is a developer change to the fold table, the migration's two functions and the goldens, together.
   - **W9a gate:** the reviewed slur and explicit lists are loaded and signed (above). The flag also needs W9b's gate (item 6); item 8 checks both.
   - **Cultural reviewer sign-off on the widened fold (batch 1, I-2 ruling).** The match form now goes beyond the spec's eight: it strips combining accents after decomposition, folds ɖ→d, ɣ→g, ƴ→y, ẹ→e, ọ→o, ṣ→s (beside ɛ/ɔ), small capitals, and a second confusables pass after the strip; the base form gains NFC. The reviewer confirms each, and in particular **whether ɣ should fold to `g` or `gh`** (today: `g`); ʒ (Dagbani) is not folded. Any change is a developer change to `unicode_fold_table.json`, migration 16's two functions and the goldens, together.
   - **Known v0 gaps, accepted (PF-C5).** Not read as contact details: a number typed in **score or date shape** (`0-2 4-4 1-2 3-4 5-6`); a run with no `+` padded past 15 digits; digits split by `,` `_` `:` or by a letter or emoji (`024,412,3456`, `024x412x3456`); letters for digits (`O244l23456`); dingbat digits; bare domains outside the ending list (`kofi.de`, `kofi.app`); a platform name with no `:` or `@` (`kofi99 on insta`). The filter is a floor; reports and the reviewed lists back it up. The reviewer also confirms the platform-word heuristic (`signal: kofi` passes) and whether score lists starting with `0` (`0-0 1-1 2-2`, still refused) are an acceptable false positive.
   - **"@" read as "at" (W9 final I-1, M-10).** Before a time, "@" is not a handle: `@5pm`, `dinner @10am tomorrow`, `@7p.m.`, `dinner @5pm.` pass (the time must end the token, so `@5pmkofi`, `@1pm.kofi` and `@10am10` are still refused). **Known false positive, for the reviewer to rule on:** `@` before a word, with no space (`I am @home now`, `we met @church`, `@work`), cannot be told from a handle and is still refused as contact details: a real handle can be any plain word, so an exempt word list would let real handles through. `see you @ home`, with a space, passes.
   - **Before the switch-on, on production (batch 2, M-7):** `select private.attune_environment();` → `production` (P-6's draft-term fail-safe rests on it), and `select count(*) from private.content_filter_terms where source = 'draft';` → `0`.
   - **After any fold-table change or a Postgres 18 upgrade (batch 2, M-8):** `select id from private.content_filter_terms where term <> private.match_form(term);` → no rows; when it returns rows, re-load the lists (a re-created `match_form` does not re-validate stored terms).
   - **Spec amendments (batch 2, M-6):** carried to the W9 final, not an owner step (the batch-6 report lists every one).
5. **Spot checks on development (filter on):** post "call me on 0 2 4 4 1 2 3 4 5 6" → refused with the contact reason, the words still in the box; post "We met in 2015 and married in 2019" → posted; a poll whose option is "ig: kofi.99" → refused; edit a post to add a `[DRAFT]` term → refused. In the database: `select count(*) from public.metric_counters where key like 'opinion_blocked:%';` grows; no post row was written for a refused post.
6. **Review queue v0 (W9b gate).** Name the daily reviewer **and a named backup**: the queue is worked every day, weekends and holidays included (the at-risk thank-you promises "a person on our team will look at this soon", which is true only if it is). Daily, in the SQL editor: `select jsonb_pretty(public.admin_list_priority_reports(50));`. For each item: read it in context, then either `select * from public.admin_confirm_content_removal('<opinion|comment>', '<content_id>');` (removal: the author is told, strikes count) or keep it, and mark the report: `update public.forum_reports set status = '<reviewed_removed|reviewed_kept|escalated>', reviewed_at = now() where id = '<report_id>';`. An at-risk report is about a person who may need help: the reviewer follows the safety runbook (the support resources, and the emergency route where someone is in danger now); nothing tells the author that a report was made. Before the flag, the app still promises "We will review this within 24 hours" for every reason (O1, flag-off behaviour is unchanged); **with `opinions_safety_v1` on, the other reasons say only "Thank you. Your report has been sent."** (batch 6: review queue v0 lists only the priority reasons, so the app promises no review time), and every comment reason now reaches the server (owner ruling (c)).
   - **At-risk items are never removed with `admin_confirm_content_removal` (PF-C2)** unless the post or comment independently breaks a rule: that path counts a strike and tells the author their post was removed, which punishes someone who may be asking for help. The default for an at-risk item is **keep** (`reviewed_kept`) or **escalate** (`escalated`), with the safety runbook followed for the person.
   - **Context for a comment (W9 final M-9).** Every queue item carries `opinion_id`: for a comment it is the post it sits under, so read the thread with `select id, content, removed_at from public.opinions where id = '<opinion_id>';` and `select id, user_id, content, removed_at from public.opinion_comments where opinion_id = '<opinion_id>' order by created_at;`.
   - **A report is lost if its reporter deletes their account first (W9 final M-1).** `forum_reports.reported_by` is `ON DELETE CASCADE` (20260716120000), so an at-risk report disappears if the reporter deletes their account, or is purged, before review. Work the queue daily so this window stays short; a later migration should make `reported_by` nullable with `ON DELETE SET NULL` (the partial unique indexes tolerate NULL), with a contract probe.
   - **One account flooding the queue (W9 final M-8).** The report RPCs have no per-reporter limit and the queue never names the reporter, so one account can file at-risk reports on many posts and push real ones down. Once a day, run (owner only; it shows the reporter id, so never share its output): `select reported_by, count(*) from public.forum_reports where status = 'pending' and priority and created_at > now() - interval '24 hours' group by 1 having count(*) > 10;`. A row is a flood: review a sample, and mark the rest `reviewed_kept` if they are not genuine. A per-reporter limit or a non-identifying count per item is a later wave.
   - **An at-risk report may have replaced an earlier report from the same account (B4 M-3).** The upgrade (PF-C1) overwrites that row's reason and decision; the earlier reason is not kept. Check the item against every rule, as PF-C2 says, and treat the reason as the latest concern, not the only one.
7. **Journal (W9c gate): a clinician before `journal_ai_insights` is switched on in production.** Until every line below is done, production keeps answering `paused` for reflections (W1c); the crisis check itself already runs, flag or not (batch-7 ruling R-2).
   - **The words.** The couples clinician and the suicide-prevention reviewer sign the card ("If things feel heavy right now, you don't have to carry it alone. Support is here if you want it.", "See support", "Not now"), the Patterns line after "Not now" ("Patterns will show here again later", ruling PF-C6) and the manual passage "When an entry sounds very hard" (shown to everyone, batch-8 ruling I-4), and confirm the reviewed self-harm corpus (`_shared/ai_session_safety.ts`'s `self_harm` tier, which `detectSelfDisclosure` reuses). **Timing:** because the check runs before the pause (R-2), the card reaches production writers as soon as `analyse-journal-entry` (item 2) and the Task 10 build ship, whatever `journal_ai_insights` says, and so do the entry menu's "Need support now?" and the manual passage (batch-8 ruling I-4: support never waits for the AI flag). So the card's words, the away line, the passage and the corpus are signed **before that deploy**, or the owner accepts them going out unsigned until then. Only AI reflections and Patterns summaries wait for `journal_ai_insights`.
   - **The pending phrases (batch-7 ruling R-3; Spec 8 carry).** The reviewer rules on each of the **52** phrases in `supabase/functions/analyse-journal-entry/journal_self_harm_pending.ts` (`journal_self_harm_pending-0.3.0`, marked `PENDING CLINICIAN REVIEW (W9c gate)`; they already run, always), **and on its 4 patterns** (W9 final re-review N-1: "took / take / taking / swallowed all (of) my pills / tablets", "overdose" with or without a space or hyphen, "burden to everyone / everybody", "nobody / no one would (even) miss me"; known accepted false positive: "I took all my pills today" about a daily dose): batch-7's 31, plus 21 added by the W9 final (I-2), which include the re-review's 3 misses (batch-7 re-review N-3): "end it all", "ending it all", "took / take / taking all my pills", "overdose", "overdosed", "overdosing", "no point living", "no point in living", "no reason to live", "nobody would miss me", "no one would miss me", "burden to everyone", "dont / don't / do not want to exist", "dont / don't / do not want to be here any more" ("any more" as two words) and "don't want to be here anymore". **Open question for the clinician (W9 final I-2): "I can't do this anymore"** is not in the list, because it is a common non-crisis phrase; the clinician rules whether it belongs. Known false positives, accepted (a false positive only shows a card; batch-7 M-2): "suicide squad", "I want it to end" about a meeting, negated and past-tense uses. **After the review, the reviewed phrases move into the shared reviewed corpus** (`_shared/ai_session_safety.ts`, so AI Sessions and ai-assist get them too, with the typographic-apostrophe fold), and leave the journal-local file: a developer change carried to Spec 8, re-running the Sessions and ai-assist goldens.
   - **Victimisation `[DRAFT]` list gaps → the DV reviewer.** The `[DRAFT]` victimisation list (on only where `private_safety_check` is on) misses the batch-7 review's I-5 probes ("my husband hit me", "he beat me" and the like). The domestic-violence specialist supplies and signs that list; it was never in the W9 build's scope.
   - **One-off backfill (batch 7, I-4(b)), after deploying `analyse-journal-entry` and before the switch-on.** A reflection written before W9c on an entry whose words match today stays until that entry is next closed with a change (`get_patterns` leaves such entries out but deletes nothing, ruling I-4(a)). The approach: an operator script that runs the function's own check (same fold, same two invisible-character passes, reviewed corpus plus the pending list, victimisation only with `private_safety_check` on) over every entry that has a reflection, and deletes those reflections exactly as `analyse_entry` does (`entry_id` and `user_id`). It prints counts only, never text or ids. Save it as `supabase/functions/_operator/journal_w9c_backfill.ts` (never committed; delete it afterwards), then from the repo root, in the owner's own shell with the project's URL and service-role key exported (never written to a file in the repo): `deno run --allow-env --allow-net --allow-read supabase/functions/_operator/journal_w9c_backfill.ts` (dry run: "entries with a reflection: N; matching today: M"), then the same with `--apply` ("deleted for M entries; failed 0"; re-run to retry any failure). Run it once on development first and check one known crisis entry: `select count(*) from public.reflection_journal_analysis where entry_id = '<that entry>';` → `0`. (Checked while writing: `deno check` and `deno lint` pass, and its matcher answers as the function does on the review's probes.)
     ```ts
     // One-off W9c backfill (batch 7, I-4(b)); operator only, never committed.
     // Removes the AI reflection from every journal entry whose words the W9c
     // check matches today, with analyse-journal-entry's own pieces: the same
     // typographic fold, the same two passes over invisible characters, the
     // reviewed corpus and the pending-review list, and the victimisation list
     // only where private_safety_check is on. Prints counts only (no text, no
     // ids). Dry run by default; --apply deletes.
     import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
     import { DRAFT_SAFETY_CONTENT_FLAG, featureFlagEnabled } from "../_shared/feature_flag.ts";
     import { detectSelfDisclosure } from "../_shared/self_disclosure.ts";
     import { foldTypography } from "../analyse-journal-entry/journal_handlers.ts";
     import { matchesPendingSelfHarm } from "../analyse-journal-entry/journal_self_harm_pending.ts";

     const INVISIBLE = /[\u200B-\u200D\u2060\uFEFF\u00AD]/g;
     const PAGE = 500;

     export function matches(title: string | null, content: string | null, victim: boolean): boolean {
       try {
         const folded = foldTypography(`${title ?? ""}\n${content ?? ""}`);
         for (const text of [folded.replace(INVISIBLE, ""), folded.replace(INVISIBLE, " ")]) {
           if (detectSelfDisclosure(text, { victimisation: victim }) !== null) return true;
           if (matchesPendingSelfHarm(text)) return true; // the pending phrases and patterns (W9 final N-1)
         }
         return false;
       } catch {
         return true; // as the function: a check that cannot run counts as a match
       }
     }

     async function main() {
       const apply = Deno.args.includes("--apply");
       const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
         auth: { persistSession: false },
       });
       const victimisation = await featureFlagEnabled(admin, DRAFT_SAFETY_CONTENT_FLAG);

       // 1. Every entry that has a reflection row (collected first; nothing is
       //    deleted while paging).
       const withReflection = new Map<string, string>(); // entry_id -> user_id
       for (let from = 0; ; from += PAGE) {
         const { data, error } = await admin
           .from("reflection_journal_analysis")
           .select("entry_id, user_id")
           .order("entry_id")
           .range(from, from + PAGE - 1);
         if (error) throw error;
         for (const r of data) withReflection.set(r.entry_id, r.user_id);
         if (data.length < PAGE) break;
       }

       // 2. Their words, checked as analyse_entry checks them.
       const hits: Array<{ entry_id: string; user_id: string }> = [];
       const ids = [...withReflection.keys()];
       for (let i = 0; i < ids.length; i += 100) {
         const { data, error } = await admin
           .from("reflection_journal_entries")
           .select("id, user_id, title, content")
           .in("id", ids.slice(i, i + 100));
         if (error) throw error;
         for (const e of data) {
           if (matches(e.title, e.content, victimisation)) hits.push({ entry_id: e.id, user_id: e.user_id });
         }
       }
       console.log(`victimisation list: ${victimisation ? "on" : "off"}`);
       console.log(`entries with a reflection: ${ids.length}; matching today: ${hits.length}`);

       // 3. --apply: the same delete as analyse_entry (entry and owner), checked.
       if (apply) {
         let failed = 0;
         for (const h of hits) {
           const { error } = await admin
             .from("reflection_journal_analysis")
             .delete()
             .eq("entry_id", h.entry_id)
             .eq("user_id", h.user_id);
           if (error) failed++;
         }
         console.log(`deleted for ${hits.length - failed} entries; failed ${failed} (re-run to retry)`);
       }
     }

     if (import.meta.main) await main();
     ```
     The entry row's `tone` (the reflection's one-word tone, which `upsert_journal_analysis` copies onto `reflection_journal_entries.tone`) is not cleared by `analyse_entry`'s delete or by this script; the app shows it nowhere today (W9 final: decide whether the match should null it too).
   - **Owner decision (batch 7, I-1(c); not built; W9 final M-2 recommends yes):** should `get_journal_entry` hide a reflection whose `input_hash` no longer matches the entry's text? **It also closes a race (W9 final M-2):** with `journal_ai_insights` on, a writer who closes an entry, quickly reopens it, adds crisis words and closes it again can have the first call's model answer land after the second call's delete; on the next app start `get_journal_entry` would show that reflection beside the crisis text. Filtering by `input_hash` hides it. Today it returns the latest reflection for the entry whatever text it was written for, so after an edit (until the reflection call on close answers) the entry shows a reflection about older words. If yes: a migration re-creating `get_journal_entry` from its live body (`20261014190000_journal_notes.sql`) adds `AND a.input_hash = encode(sha256(convert_to(e.content, 'UTF8')), 'hex')` to the analysis sub-select (the function hashes `content` the same way, SHA-256 as lower-case hex), with a contract case. The app already hides any reflection for an entry the check matched, for the rest of the run (batch-7 ruling R-1, Task 10).
   - **Then**, in production, `select public.record_flag_gate_evidence('journal_ai_insights', '<ref>');` and switch it on (AI reflections and Patterns summaries; the support card, the entry menu's "Need support now?", which opens Support and counts `support_link_opened:journal`, and the manual passage are already there).
   - **Device check on development:** write a crisis phrase in an entry, leave it → the card on the journal list, no reflection in the entry (also after "Not now", and after reopening it); Patterns shows the card when the newest entry matches (also if it showed a summary earlier in the run), and after its "Not now" says "Patterns will show here again later" / "Your entries are saved and stay private to you." until the app restarts, the account changes, quick exit, or a new crisis answer; an edited entry older than the first page (30 entries) still brings the card to the top of the list; `select count(*) from public.metric_counters where key = 'support_card_shown:journal';` grows (it counts every `support_offered` answer, each close of a matching entry and each Patterns read while the newest entry matches, not cards drawn on screen: batch-7 M-5); `select count(*) from public.reflection_journal_analysis where entry_id = '<that entry>';` → `0`. Sign out and in as another account on the same phone: no card, none of the first account's entries on the list and none of its Patterns summary (the support state, the list and Patterns are the signed-in account's only, and the support state also goes on quick exit, iOS included; D8, batch-8 I-1). The Conversations "Reflection journal" row shows the new account's latest entry, never the last account's title, also while the new account's first read is out or after it fails: check on a slow network (`journalEntriesProvider` is account-scoped and its readers take only the signed-in account's rows; the journal list shows its loading or error state while the new account's first read is out; batch-8 fix rounds 1 and 2).
   - **Screen-reader device check (W9 final M-7):** with VoiceOver on iOS, leave a crisis entry and return to the list → the support card is noticed (VoiceOver ignores the card's `liveRegion`, which covers TalkBack only); if it is not, announce `journal_supportCardBody` once when an offer is added (developer change). With TalkBack on Android, the card is read when it arrives.
8. **Opinions production switch-on (after 4, 6 and 10).**
   - **Both gates:** the reviewed lists are loaded and signed (item 4, W9a) **and** the named daily reviewer and backup work review queue v0 (item 6, W9b). They are what the flag's gate row records; neither alone is enough.
   - **Precondition (owner ruling (b)): the W9 client is the minimum supported build, then revoke client writes on the two tables.** The W9 client creates, edits and deletes only through the RPCs (`remove_my_opinion` / `remove_my_comment` for deletes; `opinion_write_routing_test.dart` pins it), and no trigger or invoker function writes either table as `authenticated` (checked on the scratch copy). While the grants stay, a modified client can write content past the filter, the ban and the rate limits, and can **hard-delete its own post**: `opinion_comments.opinion_id` and `forum_reports.opinion_id` / `comment_id` are `ON DELETE CASCADE`, so one direct `DELETE` erases every comment on the post (other people's too) and every report on it, at-risk reports included, before a reviewer sees them (batch-6 review I-2). Pre-W9 builds still write these tables directly, so the revoke waits for the minimum build. In the SQL editor:
     ```sql
     REVOKE INSERT, UPDATE, DELETE ON public.opinions, public.opinion_comments FROM PUBLIC, anon, authenticated;
     select has_table_privilege('authenticated','public.opinions','INSERT'), has_table_privilege('authenticated','public.opinions','UPDATE'), has_table_privilege('authenticated','public.opinions','DELETE'), has_table_privilege('authenticated','public.opinion_comments','INSERT'), has_table_privilege('authenticated','public.opinion_comments','UPDATE'), has_table_privilege('authenticated','public.opinion_comments','DELETE'), has_table_privilege('authenticated','public.opinions','SELECT');
     ```
     → `f | f | f | f | f | f | t`. Then a later migration records the revoke (so a fresh project matches), with a contract probe: an author's direct `DELETE` is refused and the report rows survive.
   - **Release note (owner ruling (c), batch-6 review M-8).** With the flag on, every comment report reaches the server, so `opinion_comments.report_count` moves for the first time and **a comment auto-hides at 10 reports** (`hidden_pending_review`), as posts already do. Before the flag, no comment report ever reached the server, so no comment was ever hidden this way.
   - **Guests.** Signed-out readers get no "Need support now?" (they can't read `feature_flags`, so they read the flag as off; P-2). Accepted for launch; add the flag to `get_public_app_config()` in W10 if guests should have the link.
   - Then `select public.record_flag_gate_evidence('opinions_safety_v1', '<ref>');`, then `update public.feature_flags set enabled = true where key = 'opinions_safety_v1';`. Device check: "Need support now?" in compose and in the post and comment menus (the feed card's and the thread's) opens Support; the post report sheet opens in place (no slide; the comment report dialog keeps the system's short fade, W7 ruling B2 D4); reporting with "Someone may be at risk" shows the thank-you at once (no slide) and the report appears in the queue; reporting a comment for "Spam" says "Thank you. Your report has been sent." and `select report_count from public.opinion_comments where id = '<that comment>';` went up by 1; on a slow network "Sending your report" shows first.
   - **Screen-reader device check (W9 final M-6, skipped in code):** with TalkBack on Android, make a report fail (airplane mode) → "Couldn't send your report. Please try again." is read **once** (`need_support_link.dart` both announces it and shows a SnackBar, which TalkBack may read again); with VoiceOver on iOS, the same failure is read once. If TalkBack reads it twice, drop the announce on Android only (a small developer change with its own test).
9. **Owner decisions to confirm** (questions 1-6 above): Healing's pause as its own wave (S1 W9e, straight after W9c; W9 final I-3); the report-dedup fix; revoking client writes on `opinions`/`opinion_comments` before the switch-on; sending every comment report to the server; guests and the link; the P-5, P-23, P-25 nods.
10. **A one-off recount, right after migration 17 and before the switch-on (owner ruling (a)).** The live dedup bug let one account's repeat reports raise `report_count`; migration 17 stops new inflation but does not lower old counts. Every report row is one account on one item (the unique index), and an at-risk report never counts, so the true count is the number of other-reason rows. **Caveat, accepted:** `forum_reports.reported_by` is `ON DELETE CASCADE`, so reports from accounts deleted since were already removed; the recount drops those from the count too, not only the dedup inflation. The Supabase SQL editor shows only the last statement's result, so **run each step on its own** and save its output (Download CSV) before the next:
    - **10a. Precondition** → `0` (no at-risk report exists before the flag goes on; if not 0, stop and ask):
      ```sql
      SELECT count(*) AS at_risk_rows FROM public.forum_reports WHERE reason = 'Someone may be at risk';
      ```
    - **10b. What will be lowered** (read-only; save the CSV, the only record of the old counts):
      ```sql
      SELECT kind, id, stored, recounted, hidden_pending_review FROM (
        SELECT 'opinion' AS kind, o.id, o.report_count AS stored, count(r.id)::int AS recounted, o.hidden_pending_review
        FROM public.opinions AS o
        LEFT JOIN public.forum_reports AS r ON r.opinion_id = o.id AND r.reason <> 'Someone may be at risk'
        GROUP BY o.id
        UNION ALL
        SELECT 'comment', c.id, c.report_count, count(r.id)::int, c.hidden_pending_review
        FROM public.opinion_comments AS c
        LEFT JOIN public.forum_reports AS r ON r.comment_id = c.id AND r.reason <> 'Someone may be at risk'
        GROUP BY c.id
      ) AS x WHERE stored > recounted ORDER BY 1, 2;
      ```
    - **10c. Lower** (one statement, so it is atomic and shows what it did; lowers only, never raises). Its two counts must equal 10b's opinion and comment rows:
      ```sql
      WITH o AS (
        UPDATE public.opinions AS o SET report_count = x.n
        FROM (SELECT o2.id, count(r.id)::int AS n FROM public.opinions AS o2
              LEFT JOIN public.forum_reports AS r ON r.opinion_id = o2.id AND r.reason <> 'Someone may be at risk'
              GROUP BY o2.id) AS x
        WHERE x.id = o.id AND o.report_count > x.n
        RETURNING o.id
      ), c AS (
        UPDATE public.opinion_comments AS c SET report_count = x.n
        FROM (SELECT c2.id, count(r.id)::int AS n FROM public.opinion_comments AS c2
              LEFT JOIN public.forum_reports AS r ON r.comment_id = c2.id AND r.reason <> 'Someone may be at risk'
              GROUP BY c2.id) AS x
        WHERE x.id = c.id AND c.report_count > x.n
        RETURNING c.id
      )
      SELECT (SELECT count(*) FROM o) AS opinions_lowered, (SELECT count(*) FROM c) AS comments_lowered;
      ```
    - **10d. Hidden by a count that is now under 10** (read-only). A reviewer reads each item and, only if it breaks no rule, un-hides it by hand, one at a time: `update public.opinions set hidden_pending_review = false where id = '<id>';` (or `public.opinion_comments` for a comment). Never automatically.
      ```sql
      SELECT 'opinion' AS kind, id, report_count FROM public.opinions WHERE hidden_pending_review AND removed_at IS NULL AND report_count < 10
      UNION ALL
      SELECT 'comment', id, report_count FROM public.opinion_comments WHERE hidden_pending_review AND removed_at IS NULL AND report_count < 10;
      ```
    (Each step was checked on the scratch copy inside a rolled-back transaction; neither table has a trigger, so nothing else changes.)
11. **Once the W9 client is the minimum supported build (batch 5, I-3):** revoke the unowned comment-count helpers. Until then any signed-in account can zero or inflate any post's `comment_count` (it counts ×2 in Discover's rank); pre-W9 builds still call `decrement_opinion_comment_count` on delete, so revoking earlier leaves their deleted comment on screen with an uncaught error.
    ```sql
    REVOKE ALL ON FUNCTION public.increment_opinion_comment_count(uuid) FROM PUBLIC, anon, authenticated;
    REVOKE ALL ON FUNCTION public.decrement_opinion_comment_count(uuid) FROM PUBLIC, anon, authenticated;
    select has_function_privilege('authenticated','public.increment_opinion_comment_count(uuid)','EXECUTE'), has_function_privilege('authenticated','public.decrement_opinion_comment_count(uuid)','EXECUTE');
    ```
    → `f | f`. The migration that records it flips `opinion_remove_own_contracts.sql` section A's helper check to "authenticated has no EXECUTE". The like/dislike/comment-like counter RPCs (B5 M-4) need the counting moved into the reaction write first, then the same revoke.
12. **`increment_opinion_report_count(uuid)`: done by migration 17** (batch-6 ruling, ungated). It was SECURITY DEFINER with no owner check and `EXECUTE` for `authenticated` (20260716120000), unused by the app since 2026-07-17 (87b4173a), and let any signed-in account raise any post's `report_count` without a report row, past owner ruling (a). Migration 17 and its twin revoke it from PUBLIC, anon and authenticated; `opinion_filter_contracts.sql` (G3) pins it; item 3 checks it after the push. Nothing for the owner to run; item 10's recount runs after migration 17 as before.
13. **Spec 2 carry (PF-C9).** `dating_chat_safety` calls `private.content_filter_verdict` only through its own SECURITY DEFINER wrapper (never a direct grant on the verdict), and re-runs its goldens against the widened folds (batch 1, batch 2) before its own gate.

## Spec coverage (self-review)

| Spec item | Where |
|---|---|
| §1.3 Q9 (no redesign), Q10 (filter, link, at-risk reason, journal check) | the whole plan; Global Constraints (owner ruling 2026-11-04) |
| §1.4 D12 (journal check in W9), D13 (at-risk never auto-hides), D17 (notices restored) | Task 9; Task 5 (G, mutants `at_risk_counts_*`); Task 6 |
| §1.5 never touch (Games, latch, SOUL/THESIS, quick exit) | Global Constraints; gates in Tasks 4, 8, 10 |
| §2.1 copy (`opinions_*`, `support_*`, `journal_*`; no partner named; dates) | Tasks 4, 8, 10 (P-21) |
| §2.2 never animated (support, report sheets) | Task 8 (`thanks_animated` mutant), Task 10 (plain card) |
| §2.3 accessibility (AllowLargeText, goldens 1.0/1.3/2.0/RTL, guidelines, announced errors) | Tasks 4, 8, 10 |
| §2.5 `opinions_safety_v1` (server assert, client), `journal_ai_insights`, `private_safety_check` | P-2; Task 3 (F flag off), Task 8 (P-19), Task 9 (victimisation only with the flag), Task 10 (P-26) |
| §4.2 `private.content_filter_terms`; `forum_reports` W9b behaviour | Task 3 (P-5, E); Task 5 |
| §4.3 W9a: fold table, TS port, goldens, two forms, digits, verdict, assert, six writers | Tasks 2, 3 (P-3, P-4, P-7) |
| §4.3 W9b: reasons, report RPCs, `admin_confirm_content_removal` (live body, notices, OPN-BAN-42702), review queue v0, `remove_my_*` | Tasks 5, 6, 7 |
| §4.5 `analyse-journal-entry` (check first, flag-gated victimisation, no provider/cache/persist, patterns, count) | Task 9 (P-22-P-24) |
| §4.7 #16-#19 (+ grants twins) | Tasks 3, 5, 6, 7 |
| §4.8 (blocks and journal matches not stored; only counts) | P-8, P-23; Task 4 (metric), Task 9 (metric) |
| §5.1/§5.2 W9 rows (`unicode_*`, `need_support_link.dart`, `content_filter_error.dart`, `journal_support_card.dart`, the four screens and `opinion_more_data.dart`, `opinion_repository.dart`, `journal_entry_screen.dart`, `journal_analysis.dart`, the manual, `feature_flag_refresher.dart`, `app_en.arb`, `local_pg_grants.sql`) | Tasks 2-10; P-10 and P-25 for the files the table doesn't list |
| §5.3 `opinionsSafetyProvider` | Task 8 |
| §5.6 R10 (one added line per writer; live bodies) | Task 3 Step 4 diff; Task 5 Step 4 diff; Task 6 Step 4 diff |
| §5.7 shared with Spec 3 (no rename, `forum_post` branch kept, notices restored before W3) | Task 6 (P-16); Spec 3 contract E stays green |
| §6.6 crisis routing never depends on an LLM; link always there; at-risk to a person | Global Constraints; Tasks 8, 9 |
| §7.1 the three contracts (every listed case) | Tasks 3, 5, 6, 7 |
| §7.2 `analyse-journal-entry` (spy, order, flag), `unicode_normaliser.test.ts` | Tasks 9, 2 |
| §7.3 content-filter error mapping, journal card, "Need support now?" in compose and menus | Tasks 4, 8, 10 |
| §7.4 mutants: `self_disclosure` removed or after the cache; `assert_opinion_content_ok` out of one writer; at-risk counted; a notice call removed | Task 9 (`no_check`, `check_after_cache`); Task 3 (six `no_assert_*`); Task 5 (`at_risk_counts_*`); Task 6 (`no_removal_notice`, `no_ban_notice`) |
| §7.5 device checks (journal crisis phrase; phone, e-mail, `[DRAFT]` slur refused) | checklist 5, 7 |
| §8 W9a-c contents and gates | Tasks 1-10; checklist 4, 6, 7 |
| §9 risks (ordinary posts blocked; first real bans; owner delete double-decrement) | Review Focus 1; checklist 2; Task 7 (contract and `double_decrement`) |
| §10 outside parties (cultural reviewer, clinician and suicide-prevention reviewer, named daily reviewer) | checklist 4, 6, 7 |
| §11 I-17, OPN-BAN-42702, OPN-DELETE-RLS; owner approval O2 (Healing), O4 (W9d) | Tasks 2, 6, 7; owner question 1 (O2: Healing's pause is S1 W9e, straight after W9c, W9 final I-3); O4 is S1 W9d, after S2 W1, not in this plan |

Placeholder scan: no "TBD", "TODO", "later", "similar to" or undefined name; every code step has its full text; `<term>`, `<ref>`, `<review ref>`, `<content_id>`, `<report_id>` and `<that entry>` in the owner checklist are values only the owner has. Type consistency: `ContentFilterReason`, `ContentFilterNotice`, `opinionsSafetyProvider`, `opinionsSafetyReadProvider`, `SupportLinkSource`, `atRiskReportReason`, `openSupportNow`, `showAtRiskReportThanks`, `NeedSupportLink`, `JournalSupportCard`, `journalSupportOffersProvider`, `journalInsightsEnabledProvider`, `JournalDeps` (`model`, `runtimePatterns`, `victimisationOn`, `bumpMetric`), `handleAnalyseEntry`, `handleGetPatterns`, and every SQL signature are used as they are defined (each file was compiled, type-checked or applied while writing this plan).
