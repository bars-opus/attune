# Spec 1 W10 (large text, motion and RTL, first frame and size, dead code and doc amendments) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the phone's text size into the app without breaking any screen: audit and fix the six named surfaces at 1.3, 1.6 and 2.0 (W10a), then add the root clamp behind `text_scale_v2` that keeps Games routes at 1.0; check reduce motion, right-to-left layout, the first frame and the app size (W10b); delete the dead auth code and apply the approved doc amendments (W10c).

**Architecture:** Fourteen tasks in three sub-waves. **W10a (Tasks 1-8).** Task 1 records the baselines and adds the audit itself: a `LARGE_TEXT_AUDIT` hook in `test/flutter_test_config.dart` (off unless the define is passed) that runs any existing test on a 390 x 844 phone at a chosen text size, `scripts/large_text_audit.py` that lists every overflow by the widget that overflowed, and one golden test per audited surface at 1.0, 1.3 and 2.0 on two phones, whose 1.0 goldens are drawn from today's code before any fix. Task 2 adds five small large-text helpers (`lib/core/ui/text/large_text.dart`), every one inert at 1.0, and pins ScreenUtil's behaviour. Tasks 3-6 fix the 36 overflow sites the audit found, in the spec's order (chat, Opinions, Together/Planning, Settings, Healing, journal), each fix inert at the normal size so every existing golden stays byte-identical. Task 7 is the light-theme error colour (owner question 3: built only on a yes). Task 8 adds `TextScalePolicy` (the root cap from `text_scale_v2`, Games and not-yet-audited routes at 1.0, an architecture test against `app_router.dart`), wires it into `app_shell.dart`, and sets the cap from the measured in-chat Games surfaces: **1.0 while no Games file may be edited** (P-8), 2.0 once the owner allows the two-line Games fix. **W10b (Tasks 9-12).** Task 9 cuts the quiz deck's 900 ms advance to 320 ms and guards reduce motion on every Spec 1 widget; Task 10 guards right-to-left layout on every Spec 1 widget and adds the missing RTL goldens; Task 11 instruments the first frame (`BootTimeline`); Task 12 measures the release size against the 1.5 MB budget. **W10c (Tasks 13-14).** Task 13 deletes the dead auth code as its own changeset (Games grep first, Games tests after); Task 14 applies the Q20 doc amendments, writes the `ATTUNE_SOUL.md` proposal and runs the W10 gate. Every Dart, Python and shell block below was run while writing this plan in a scratch copy of the tree at HEAD `8753f112`: each new test red before its code and green after, every fix checked by the audit at 1.3, 1.6 and 2.0 and by the full suite at 1.0 (no golden changed), the analyzer clean on every touched file, the doc script applied to copies of the three docs, the dead files deleted and the Games tests green.

**Tech Stack:** Flutter 3.29.1 (Dart 3.7), Riverpod 2.6, GoRouter 10.2.0, flutter_screenutil 5.9.3, supabase_flutter 2.14.1, Python 3 (edit, audit and doc scripts). No new Dart package, no migration, no new flag, no new ARB key.

**Spec:** `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md`: §8 W10a-c (line ~1264) with the W10 group gate, §2.2 (the 900 ms card advance cut to `kMakeRoomDuration`), §2.3 (accessibility), §2.5 (`text_scale_v2`: client (anon), "root clamp stays 1.0", gate "W10 group gate (W10c)"), §3.14 (first frame, app size), §4.7 ("W10 has no migration"), §5.1/§5.2 rows tagged W10 (`lib/app/text_scale_policy.dart`; `lib/app/app.dart`, `lib/app/app_shell.dart`; `lib/main.dart`; `onboarding_deck_card.dart`), §5.6 R11 and R15, §5.7 (Master Spec line from Spec 3), §6 item 6 ("W10 may add the flag to `get_public_app_config()`"), §7.3, §7.5 (device checklist), §9 ("Every screen reflows", "Games touched"), §11 C-9 and N-1. Owner rulings: Q11 (raise the clamp in stages), Q20 (the amendments). Research: `11-synthesis-decisions.md` §2.13, §10 Q20; `06-attune-flow-audit.md` §2.1.6, §2.1.7; `2026-10-16-couples-research/06-synthesis-roadmap.md` §5.3. Format reference: `docs/superpowers/plans/2026-11-04-spec1-w9-opinions-safety.md`.

## Global Constraints

- Work in the main working tree on `main` (`/Users/user/attune`). W1-W9e are committed (HEAD `8753f112`); the owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql` at the time of writing): never revert, stash, stage, checkout or reformat them. Every edit to an existing file is an exact-string replacement made by a script that asserts each anchor occurs once (`$D/edit_lib.py`, Task 1); if an anchor has moved because a later change touched it, apply the same change to the current text and say so in the task report.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm`. Tasks end with "Run tests", not "Commit". Task 13's deletions are listed as their own changeset for the owner to commit separately; nothing is committed here.
- Never `dart format` a pre-existing file (the repo predates the 3.7 formatter). The Dart files this plan creates are given already formatted; each task's last step runs `dart format --output=none --set-exit-if-changed` on exactly those paths (it changes nothing).
- **No migration, no new flag, no SQL.** `text_scale_v2` exists from W1c (`20261025100400_spec1_flags_and_public_config.sql`): inserted false, its production gate row `'W10 group gate (W10c): the device matrix passes on the chosen cap'`, returned to anon by `get_public_app_config()`, turned on in development by `supabase/sql/dev_enable_spec1_flags.sql`, and already parsed by `PublicAppConfig.textScaleV2`. Spec §4.7: "W10 has no migration." If a later change does need one, the usual rules hold: a timestamp later than every migration in the tree (today the newest is `20261104140010_healing_ai_insights_flag_grants.sql`), one `BEGIN; ... COMMIT;`, `SET LOCAL lock_timeout = '5s'`, applied twice (`exit=0` both times), explicit grants in its `_grants` twin, SQL only on `attune_spec3a` with `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`; never `attune_test`, never `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`.
- **Never touch:** `lib/features/games/**` (no Games file is edited; `test/architecture/games_untouched_test.dart` stays green), `ChatScreen`'s Games entry points and use sites, `lib/features/auth/utility/auth_exports.dart` (byte-identical), `AuthService`, `AuthUiService`, every Games `GoRoute` in `app_router.dart` (`app_router.dart` is not edited at all), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, every applied migration, `supabase/sql/dev_enable_spec1_flags.sql`, `lib/home/home_screen.dart` (its latch block, from `if (isAuthenticated && !_gateData.isComplete) {` to `_redirectingToOnboarding = false;`, stays byte-identical: Task 1 saves its hash, Tasks 8 and 14 compare).
- **Opinions:** only the three large-text fixes the audit found (Task 4: the comment row, the post report list, the card menu), each inert at 1.0. W9's flag-off goldens (`test/features/opinions/w9/goldens/flag_off_*.png`) do not change: the suite runs them unchanged after Tasks 4 and 7. The only Opinions golden that may change is `content_filter_notice.*` (four files), and only if the owner says yes to Task 7 (the error colour).
- **Normal size untouched.** Every fix in Tasks 3-6 leaves the layout at text size 1.0 pixel-identical: Task 1 draws each audited surface's 1.0 golden from today's code, and every later task runs those goldens and every existing golden in the repo unchanged. Fixes switch on only above 1.0 (`isTextScaledUp`, or `Flexible(flex: isTextScaledUp(context) ? 1 : 0, ...)`, which is no flex at all at 1.0), or are inert by construction (`Flexible` around the only flexible child of a row). The exceptions are named where they happen: Task 6's journal reflection header, which already overflows at 1.0 on a 360-wide phone; Task 7 (the owner's choice). Above 1.0, existing Spec 1 goldens change only where a fix reaches them: Task 6 regenerates W3's four Me goldens at 1.3 and 2.0 (`me_just_me.scale{1.3,2.0}`, `me_dating_open.scale{1.3,2.0}`: their rows wrap to more lines).
- **Copy:** W10 adds no ARB key and no user-facing string. If a later change needs one, append it with `.superpowers/sdd/2026-10-26-spec1-w3/arb_append.py` and generate with `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package`; never W2 P-9's perl fix. Never "they" for the partner (two existing lines do it; P-20 lists them for the owner and does not change them). Dates go through `MyDateFormat`; W10 shows none.
- **Docs:** only the Q20 amendments review C-9 assigns to Spec 1 (Task 14): `lib/architecture/attune/ATTUNE_MASTER_SPEC.md` (decisions 11, 18, 20, 21, 22, 23 and 25; §2; §8.8 Track A; §9; Spec 3's line "Forums retired 2026-10, Spec 3"), `lib/architecture/AUTH_ONBOARDING_ENGINE.md` (order, voice OTP, no Ask 2 preview) and CR-06 §5.3 rule 6 (`docs/superpowers/research/2026-10-16-couples-research/06-synthesis-roadmap.md`). The `ATTUNE_SOUL.md:73` wording goes to a proposal file; the Dating docs are Spec 2's, `FORUM.md` Spec 3's.
- **No deploys.** No `supabase db push`, no function deploy, no flag switch, no store upload. Release builds for the size measurement (Task 12) are local and unsigned. The device matrix, the first-frame measurement on a phone and the store-console size checks are owner checklist items. Don't read `.env*`, credentials or the keychain. No `flutter pub get` in the working tree (Task 12 runs `flutter pub get --offline` only inside its extracted baseline copy).
- **Working folder** for baselines and scripts: `D=.superpowers/sdd/2026-11-04-spec1-w10` (git-ignored); set `D` in every shell, at the repo root. Every script below is saved there first, exactly as given.
- **Regression gate at the end of each sub-wave (Tasks 8, 12, 14):** the full `flutter test` passes with Task 1's count plus the tests each task adds; `flutter analyze --no-pub lib test` shows no `error` or `warning` line that Task 1's baseline didn't; the Games tests pass; `auth_exports.dart` is byte-identical; the latch is unchanged; `git status --short lib/features/games lib/features/auth/utility/auth_exports.dart lib/app/routing/app_router.dart lib/architecture/attune/ATTUNE_SOUL.md lib/architecture/attune/ATTUNE_THESIS.md supabase/migrations` prints nothing.

## Review Focus

1. **A phone text size between the candidates** (Android's 1.15, iOS's 1.12 and 1.24, Android 14's non-linear 1.5 and 1.8). Expect the same no-overflow result as at 1.3, 1.6 and 2.0: every fix switches on above 1.0, not at a threshold. Test: the in-chat Games measurement steps every 0.05 from 1.0 to 2.0 (Task 8); the helpers' tests check 1.05 (Task 2, `isTextScaledUp is false at 1.0 and true above it`).
2. **`text_scale_v2` flipping while the app is open** (the flag is re-read on resume). Expect the screens to reflow in place, with no route, scroll position or draft lost. Test: Task 8 `switching the cap keeps the screen below (no rebuild)`, `a deep link straight into a Games route settles at 1.0`.
3. **A Games screen pushed from the chat while the cap is on, then popped.** Expect the game at 1.0 and the chat back at the cap. Test: Task 8 `a pushed Games route keeps 1.0, and popping restores`; mutant `top_from_uri` (GoRouter 10 leaves `uri` on the last `go`, so a pushed route would be missed).
4. **A narrow Android phone (360 x 800, the Android Go class) at 1.0.** Expect it to look exactly as today: no fix may move a pixel at 1.0. Test: every audited surface runs at 360 wide as well as 390 (Tasks 3-6), and Task 1's 1.0 goldens are compared after every task; the in-chat Games sheet's existing overflow at 1.0 on 360-wide phones is reported, not fixed (Games are frozen).
5. **An empty or error state inside a feed that sizes itself by intrinsic height** (Opinions' Discover `SliverFillRemaining`). Expect no crash: the scroll-when-tall fix is not put inside the core empty and error widgets, only at the two call sites that overflow. Test: `test/features/opinions/opinions_tab_shell_test.dart` (`the header lays out at text scale 2.0`) stays green after Task 5; it failed while this plan was being written, when the fix sat in `EmptyStateWidget`.

## Decisions found while verifying the code (read before Task 1)

Each is a verified fact about today's code (HEAD `8753f112`), the packages or the runtime, with the smallest change that keeps the spec's intent. *Changes spec intent* marks the ones the owner should see.

**W10a**

- **P-1 (nothing on the server).** `text_scale_v2`, its gate row, its anon read and its dev switch all exist from W1c, and the client already parses it (Global Constraints). W10 adds no migration and no flag. Spec §6 item 6 ("W10 may add `opinions_safety_v1` to `get_public_app_config()`") is not done: W9's owner question 5 recommended accepting the guest gap for launch, and nothing since asks for it.
- **P-2 (how the audit runs).** Two instruments. (a) **The suite at large text:** with `--dart-define=LARGE_TEXT_AUDIT=<scale>`, `test/flutter_test_config.dart` runs every existing test on a 390 x 844 phone at that text size, and `pumpFlowScreen` sets its root clamp to the same value; `scripts/large_text_audit.py` lists each overflow by the widget that overflowed (`file:line`), how many tests hit it and one of them, with Games sites listed apart. The ~7,000 existing tests become the audit's coverage, and the hook changes nothing without the define. (b) **Surface goldens:** one test file per audited surface pumps its main screens at 1.0, 1.3, 1.6 and 2.0 on 390 x 844 and 360 x 800, collects every overflow instead of failing at the first, and takes goldens on the 390 phone at 1.0, 1.3 and 2.0 (§2.3). "Passes" means no overflow at any of those sizes and nothing that carries meaning cut off; the goldens are looked at for the second.
- **P-3 (the sites).** At 2.0, the suite found 36 overflowing widgets outside Games and Pulse; Tasks 3-6 fix 35 of them, plus one more that only the 1.6 run reaches (`log_moment_details_screen.dart:408`, the mood scale's two ends in Together's "Log a moment" sheet), in the spec's order: chat 13 (`voice_recording_bar.dart` counter, `app_days_count.dart`, `confirmation_dialog.dart` (a chat test reaches it), `attune_assist_bubble.dart` x2, `ask_attune_mode_sheet.dart`, `intro_guide_widget.dart`, `message_bubble.dart` "Video expired", `voice_message_player.dart`, `new_device_notice.dart`, `relationship_ended_sheet.dart`, `appreciation_sheet.dart`, `share_win_sheet.dart`), Opinions 3 (`comment_thread_screen.dart` comment row, `opinion_more_data.dart` report list, `opinion_card.dart` menu), Together/Planning 14 (the moment sheet's mood scale, Together's error state, Planning's category empty state, `calendar_strip.dart` day cells, `add_moment_or_reminder_sheet.dart`, `moment_card.dart`, `arc_gauge.dart`, `info_row_widget.dart` trailing, `planning_entry_screen.dart` "Mark settled", `expenses_block_view.dart`, `link_block_view.dart` x2, `planning_block_picker.dart`, `planning_spend_chart.dart`), Settings 1 (`quiet_states_screen.dart` sheet; and the truncation, P-4), Healing 3 (`healing_journey_screen.dart` stages, `healing_portrait_screen.dart`, `healing_post_mortem_screen.dart`), journal 2 (the reflection header in `journal_entry_screen.dart`, J3's time picker). The 36th, `relationship_lifecycle_card.dart:131`, overflows only in its own test, which shows the card alone on a non-scrolling page; in the app it sits in scrolling lists (Me, the relationship space, chat home). At 1.3, before the fixes, the suite found 8 of them (the recording timer, the days count, the gauge, the row's trailing slot, the assist bubble's header, the report list, the expenses swipe label, the journal's reflection header).
- **P-4 (truncation).** At 2.0, `InfoRowWidget` cuts titles at 2 lines and subtitles at 3 (Settings, Planning, Together rows). Once the text is scaled up a row gets twice the lines before it ellipsizes (Task 6). The widget's `titleMaxLines`/`subTitleMaxLines` parameters are unchanged, so Spec 5's `large_text_test.dart` (which reads them) stays green.
- **P-5 (shared widgets).** `InfoRowWidget`, `AppDaysCount`, `ArcGauge`, `ConfirmationDialog` and `AnimatedRollingCounter`'s callers are app-wide. Each change is inert at 1.0 and switches on above it; the full suite at 1.0 is the regression check. `EmptyStateWidget` and `ErrorStateWidget` are **not** changed: wrapping them in a scroll-when-tall made Discover's `SliverFillRemaining` ask a `LayoutBuilder` for its intrinsic height and crash (Review Focus 5), so the two overflowing call sites are fixed instead.
- **P-6 (the root clamp keeps its shape).** `RootTextScaleClamp` (Task 8) is the same two widgets whatever the cap (a stateful listener and `MediaQuery.withClampedTextScaling`), so a flag change mid-session rebuilds no Navigator. It listens to `router.routerDelegate` and changes the scale after the current frame when the router announces a route during a build (the first route, a redirect). `AllowLargeText` reads the view, not its parent, so its 25 call sites keep reaching 2.0 under any root cap (test).
- **P-7 (pushed routes).** In GoRouter 10.2.0, `currentConfiguration.uri` "only reflects RouteMatches that are not ImperativeRouteMatch": a Games route opened with `pushNamed` from the chat (`openGameRoute`) doesn't change it. The policy reads `currentConfiguration.last.matchedLocation`, which a push does change. Pageless routes (dialogs, sheets, and This or That's `MaterialPageRoute`s) take the route under them, so a sheet over a Games route stays at 1.0 and a sheet over the chat gets the cap.
- **P-8 (the in-chat Games surfaces decide the cap).** *Changes spec intent.* The in-chat Games surfaces (the games sheet from the composer, the game card, its trail, the staged game) get the root cap, because they open over the chat. Measured while writing this plan (Task 8's test, every 0.05 from 1.0 to 2.0): the card, trail and staged bar never overflow, but the games sheet's tiles (`game_grid_tile.dart:50`) overflow from 1.3 on 390 and 393 wide, from 1.15 on 375 x 667, and already at 1.0 on 360-wide phones; its section label (`chat_games_sheet.dart:625`) overflows from 1.3-1.5 depending on the width. With no Games file edited, none of 2.0, 1.6 or 1.3 passes, so **`TextScalePolicy.v2Cap` is 1.0** and `text_scale_v2` changes nothing yet. Two lines in those Games files (a `Flexible` around the section label; the tile's large layout above 1.0 instead of above 1.3) make the Games surfaces pass up to 2.0 on every phone measured; owner question 1. Everything else in W10a is built and green either way.
- **P-9 (routes outside the audit keep 1.0).** *Changes spec intent.* The spec's audit covers six surfaces, but the root cap would reach every screen. At 1.3 the suite already finds 22 Pulse tests overflowing (`dimension_row.dart`, `trend_chart.dart`, `visualisation_switcher.dart`, `pulse_screen.dart`, `your_week_card.dart`). So the policy lets the cap through only on routes the audit covered (`auditedRoutePrefixes`: home, the Spec 1 screens, chat, Opinions, Together/Planning, Settings, Healing, the journal) and keeps 1.0 on every other route, a new one included: Pulse, the quizzes, the Dating v1 screens, the community feed, the inbox, chat insights and import, the weekly check-in, logging a moment, previous relationships, the legacy intro, login and profile. The architecture test names them. Owner question 2.
- **P-10 (ScreenUtil).** Verified in `flutter_screenutil` 5.9.3: `setSp` returns `fontSizeResolver(fontSize)` when a resolver is set, so with the identity resolver `.sp` ignores both the screen size and `minTextAdapt` (which only feeds `scaleText`); the phone's text size is applied once, by Flutter's `TextScaler`; the iPad 1.25x cap (`designSizeFor`) moves `.w`/`.h`/`.r` only. Nothing changes; Task 2 pins all three with a test and a mutant.
- **P-11 (the light error colour).** `LightColors.error` `#F44336` gives 3.68:1 with white (`onError`) and 3.38:1 as text on the light background `#F5F5F7`, below 4.5:1, wherever it is used: error lines, snackbars, destructive actions, the support cards' emergency accents. `#C62828` (Material Red 800) gives 5.62:1 and 5.16:1. Changing it restyles every error state, snackbar and destructive action in light mode, so it is owner question 3 and its own task (7), built only on a yes: not behind a flag (the theme is built once, statically), with the 36 goldens it changes listed and regenerated. Dark mode is unaffected.
- **P-12 (`AppButton` labels never scale).** `AppButton` draws its label with `TextScaler.noScaling` in a fixed-height box (164 call sites), so button labels outside Spec 1 stay at 1.0 under any cap. Nothing overflows, but the words don't grow. Changing it needs a height that grows with the text and a pass over every call site; not in W10 (owner question 4). Spec 1's own buttons (`flow_buttons.dart`) scale.

**W10b**

- **P-13 (the deck).** `onboarding_deck_card.dart`'s `_advanceDuration` (900 ms) becomes `kMakeRoomDuration` (320 ms). Reduce motion already skips the advance (`didUpdateWidget` checks `_reduceMotion`).
- **P-14 (reduce motion, the rest).** Every Spec 1 widget that animates already reads reduce motion (or uses `SharedAxisStep`/`SettleIn`, which do). Sheets and other default-behaviour `AnimationController`s run 20 times faster when the platform's reduce-motion setting is on (`AnimationBehavior.normal`); the two `AnimationBehavior.preserve` controllers (`shared_axis_step.dart`, `path_preview_sheet.dart`) pick the 150 ms fade themselves. Task 9 adds a guard test over the 71 Spec 1 presentation files and changes nothing else.
- **P-15 (RTL, the rest).** The 71 Spec 1 presentation files already lay out by direction: no `EdgeInsets.only(left:/right:)`, no left/right `Alignment` or `TextAlign`, no `Positioned(left:/right:)`, every `EdgeInsets.fromLTRB` symmetric; the directional icons they use (`chevron_right`, `open_in_new`) have `matchTextDirection: true`, so they mirror. 66 RTL goldens exist (W2-W9e). Task 10 adds the guard, RTL goldens for the two sheets that had none (J4 "More ways to use Attune", the Dating to Just-for-me switch) and a look at all 68.
- **P-16 (the first frame; the bounded boot not built).** Verified in `supabase_flutter` 2.14.1: `Supabase.initialize` reads the stored session and sets it locally (`setInitialSession`), and `recoverSession()`, the only network step, runs unawaited (`CancelableOperation.fromFuture`); the only other network path is an auth-callback deep link (`getSessionFromUrl`), which phone sign-in never produces. So an airplane-mode cold start with an expired session doesn't wait on the network before `runApp`. The awaited steps before the first frame are the Supabase init (local), the chat cache (bounded 8 s), prefs, the age-block restore (bounded 1 s) and the lock seed (bounded 3 s): a slow keystore, not the network, is what could hold the splash. Task 11 adds `BootTimeline` (one `[startup]` line after the first frame, each step's own time) and the owner measures on a phone. The bounded boot (`Supabase.initialize` at 2 s) is **not** built: dozens of providers read `Supabase.instance.client` at first use and would throw if `initialize` were still running. If the owner's measurement shows more than 1 s after the splash, the contingency in the owner checklist applies.
- **P-17 (app size).** The baseline is `360db8d1~1` (`29070139`, the tree before W1). Task 12's script builds the Android arm64 release APK (what Play delivers per ABI) and the iOS release app (unsigned, zipped) from both trees and compares them with the 1.5 MB budget; the store consoles' download sizes are the owner's confirmation. Measured while writing this plan (Android, HEAD `8753f112`): +1.27 MB, within the budget but close to it.

**W10c**

- **P-18 (the dead code).** The spec's list is exactly 11 files: `username_creation_screen.dart`, `verify_email_screen.dart`, `forgot_password_screen.dart`, `update_password_screen.dart`, `password_reset_email_sent_screen.dart`, `login_screen_options.dart`, `email_signup_attempt.dart` with its `.freezed.dart` and `.g.dart` parts, `lib/app/splash_screen.dart`, `lib/features/shell/presentation/attune_shell.dart`. No file outside them uses any symbol they declare (deleting them in a scratch copy left the analyzer with no new error and removed one warning); the only references are the `export_screens.dart:43` export and a doc comment in `supabase_profile_repository.dart:30`. `auth_exports.dart` re-exports `export_screens.dart`, so its bytes stay the same and its surface loses `LoginScreenOptions`, which no Games file uses (Task 13's grep proves it). The `RouteNames` constants for those never-routed screens stay: they are in `app_router.dart`, which W10 doesn't edit.
- **P-19 (the doc amendments).** The Master Spec records a revision as a new numbered decision that names what it revises, with "*(revised by decision N)*" on the old rows (decisions 30 and 31 do this). So the Q20 amendments become **decision 34**, with the seven rows marked; §2, §8.8 and §9 are rewritten to match, the version line becomes 2.28 and the update log gets its entry. Decision 21 is amended to what is built, a stable keyed pseudonym per author; the per-post handles of the deferred Q9 redesign are named as deferred (11 §5.1 had proposed "unlinkable per post"). *Changes spec intent* (that one line). `AUTH_ONBOARDING_ENGINE.md` gets exactly the three areas Q20 names (the launch order and basic setup, the voice line, the Ask 2 reward); its Single track and its "Data Writes" table (which still writes `users.mode`, retired in W1a) are also stale but not in Q20 (owner question 5).
- **P-20 (found, not changed).** Two existing lines call the partner "them"/"they", against the copy rule: `quiet_states_screen.dart:191` ("Want to let them know? You can send this, once:") and `share_win_sheet.dart:85` ("It goes on your timeline, and they can ask you about it."). Both are Spec 7 copy outside W10; owner question 7.

## Owner questions (open; the plan builds the recommendation where it builds anything)

1. **Let the in-chat Games surfaces take large text (P-8).** *Recommendation:* approve a two-line Games change as its own Games changeset, outside Spec 1: in `lib/features/games/presentation/widgets/chat_games_sheet.dart` wrap the section label's `Text(label, ...)` in `Flexible`, and in `lib/features/games/presentation/widgets/game_grid_tile.dart` take the large layout above 1.0 (`> 1.0` for `> 1.3`). Measured while writing this plan: with both, the sheet, card, trail and staged bar show no new overflow up to 2.0 on 360, 375, 390 and 412-wide phones. Then re-run Task 8 Step 6, which sets `v2Cap` to 2.0. Without it, `v2Cap` stays 1.0 (text_scale_v2 does nothing) and Spec 1 screens keep reaching 2.0 through `AllowLargeText`.
2. **Routes outside the audit keep 1.0 (P-9).** *Recommendation:* yes. Turning `text_scale_v2` on then never reflows a screen nobody checked (Pulse overflows at 1.3 today); each later audit adds its routes to `auditedRoutePrefixes`.
3. **Fix the light error colour app-wide (P-11).** *Recommendation:* yes, `#C62828`, unflagged, as Task 7. It is a contrast fix (3.68:1 to 5.62:1), the app has no real users yet (Q19b), and the 36 changed goldens are listed.
4. **`AppButton` labels (P-12).** *Recommendation:* a follow-up wave after W10 (a growing height and a pass over the 164 call sites), not W10.
5. **The rest of `AUTH_ONBOARDING_ENGINE.md` (P-19).** Two parts are stale but not in Q20: the Onboarding section's "Single (Track A) — the quiz stays up front" (now Just for me, quiz optional) and the Data Writes table (`users.mode` is retired). *Recommendation:* approve both in the next doc pass ("Just for me lands on Me; the quiz is optional"; "`complete_sign_up` writes the account in one call; the client never writes `users.phone`, `users.mode` or `users.path`").
6. **`ATTUNE_SOUL.md:73` (Q20).** *Recommendation:* the wording in `docs/superpowers/proposals/2026-11-04-attune-soul-line-73.md` (Task 14): "a forum" becomes "Opinions". The owner edits SOUL; no wave does.
7. **Partner copy (P-20).** *Recommendation:* name the partner in both lines in Spec 7's next copy pass ("Want to let {name} know?", "... and {name} can ask you about it.").

## W1-W9e interfaces this plan consumes (adjust here if a later fix renames one)

- Dart: `PublicAppConfig.textScaleV2`, `publicAppConfigProvider` (`FutureProvider<PublicAppConfig>`), `cachedPublicAppConfigProvider` (`Provider<PublicAppConfig?>`), `PublicAppConfigCache.key` (`'attune.public_config.v1'`), `publicAppConfigGatewayProvider`, `PublicAppConfigGateway.fetch()`, `sharedPreferencesProvider` (`lib/core/flags/public_app_config.dart`, `lib/core/providers/shared_prefs_provider.dart`); `appShell({required GoRouter router, required Widget child})` (`lib/app/app_shell.dart`); `AllowLargeText({required Widget child, double maxScaleFactor = 2.0})`; `reduceMotionOf(BuildContext)`; `kMakeRoomDuration` (320 ms); `ScreenUtilConfig` (`designSize`, `minTextAdapt`, `resolveFontSize`, `maxScale`, `designSizeFor`, `builder`); `createAppRouter(RoutingNotifier)`; `showChatGamesPicker(BuildContext, {required String relationshipId, void Function(String)? onStageNewGame})` (`chat_screen.dart`); `GameCardState`, `gameCardProvider`, `activeGamesProvider`, `recentGamesProvider`, `gameSessionEventsProvider`, `GameTrailLine`, `GameComposerBar`, `MessageBubble` (read, never edited, by the in-chat Games test).
- Test helpers: `pumpFlowScreen(tester, screen, {textScale, direction, reduceMotion, prefsValues, overrides, routing, openCountries, size})`, `flowGoldenVariants`, `expectFlowGoldens` (`test/helpers/flow_harness.dart`); `FakeChatRepository`, `buildChatContainer`, `activeConversation`, `withScreenUtil` (`test/features/chat/support/chat_test_harness.dart`); `w9Opinion`, `w9Comment`, `FakeOpinionRepository`, `opinionOverrides` (`test/features/opinions/w9/support/fake_opinions.dart`); `FakePlanningGateway`, `fakeCategoryJson`, `planningTestApp` (`test/features/planning/support/`); `testJourney`, `FakeHealingGeneration`, `FakeHealingRepository` (`test/features/healing/w9e/support/healing_fakes.dart`); `FakeJournalRepository`, `pumpJournal` (`test/features/reflection_journal/support/`); `homeJson`, `FakeHomeStateGateway`, `snapshotOf`, `FakeHomeAuth`, `testUser` (`test/helpers/fake_home_state.dart`, `test/helpers/home_harness.dart`).

## File map

**W10a (Tasks 1-8)**
- Modify `test/flutter_test_config.dart` (the `LARGE_TEXT_AUDIT` hook), `test/helpers/flow_harness.dart` (`rootTextScaleCap`, the hook); create `scripts/large_text_audit.py`, `test/accessibility/w10/support/large_text_audit.dart`, `test/accessibility/w10/{chat,opinions,together_planning,settings,healing_journal}_large_text_test.dart` with their 1.0 goldens (Task 1).
- Create `lib/core/ui/text/large_text.dart`, `test/core/ui/text/large_text_test.dart`, `test/core/utils/screen_util_large_text_test.dart` (Task 2).
- Modify `voice_recording_bar.dart`, `voice_message_player.dart`, `message_bubble.dart` (`lib/features/chat/presentation/widgets/`), `lib/core/widgets/app_days_count.dart`, `lib/features/ai_assistant/presentation/widgets/attune_assist_bubble.dart`, `lib/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart`, `lib/features/auth/intro/widgets/intro_guide_widget.dart`, `lib/features/account/presentation/new_device_notice.dart`, `lib/features/relationships/presentation/widgets/relationship_ended_sheet.dart`, `lib/features/appreciation/presentation/appreciation_sheet.dart`, `lib/features/wins/presentation/share_win_sheet.dart`, `lib/core/widgets/feedback/confirmation_dialog.dart`; chat goldens at 1.3/2.0 (Task 3).
- Modify `lib/features/opinions/presentation/screen/comment_thread_screen.dart`, `lib/features/opinions/data/opinion_more_data.dart`, `lib/features/opinions/presentation/widgets/opinion_card.dart`; Opinions goldens (Task 4).
- Modify `lib/features/together/presentation/screens/together_screen.dart`, `lib/features/planning/presentation/screens/planning_category_screen.dart`, `lib/features/timeline/presentation/widgets/{calendar_strip,add_moment_or_reminder_sheet,moment_card}.dart`, `lib/features/timeline/presentation/screens/log_moment_details_screen.dart`, `lib/core/widgets/charts/arc_gauge.dart`, `lib/core/widgets/info_row_widget.dart` (trailing), `lib/features/planning/presentation/screens/planning_entry_screen.dart`, `lib/features/planning/presentation/widgets/{expenses_block_view,link_block_view,planning_block_picker,planning_spend_chart}.dart`; Together/Planning goldens (Task 5).
- Modify `lib/core/widgets/info_row_widget.dart` (lines), `lib/features/quiet_states/presentation/quiet_states_screen.dart`, `lib/features/healing/presentation/screens/{healing_journey,healing_portrait,healing_post_mortem}_screen.dart`, `lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart`, `lib/features/me/presentation/widgets/journal_reminder_row.dart`; Settings, Healing and journal goldens; regenerate W3's four Me goldens at 1.3/2.0 (Task 6).
- Modify `lib/app/theme/app_colors.dart` (one line) and regenerate the 36 goldens it changes, only on the owner's yes (Task 7).
- Create `lib/app/text_scale_policy.dart`, `test/app/text_scale_policy_test.dart`, `test/app/app_shell_text_scale_test.dart`, `test/architecture/text_scale_routes_test.dart`, `test/accessibility/w10/in_chat_games_large_text_test.dart`; modify `lib/app/app_shell.dart`, `lib/app/app.dart`, `test/accessibility/large_text_test.dart` (one test added) (Task 8).

**W10b (Tasks 9-12)**
- Modify `lib/features/onboarding/presentation/widgets/onboarding_deck_card.dart`; create `test/accessibility/w10/deck_advance_motion_test.dart` (Task 9).
- Create `test/architecture/spec1_rtl_motion_test.dart`, `test/accessibility/w10/spec1_rtl_goldens_test.dart` (+ 8 goldens) (Tasks 9 and 10: the motion half in 9, the RTL half in 10).
- Create `lib/app/boot_timeline.dart`, `test/app/boot_timeline_test.dart`; modify `lib/main.dart` (Task 11).
- Create `scripts/app_size_report.sh`; the report goes to `$D/size/size-report.txt` (Task 12).

**W10c (Tasks 13-14)**
- Delete the 11 dead files (P-18); modify `lib/core/utils/exports/export_screens.dart` (one export), `lib/features/profile/repositories/supabase_profile_repository.dart` (one comment) (Task 13).
- Modify `lib/architecture/attune/ATTUNE_MASTER_SPEC.md`, `lib/architecture/AUTH_ONBOARDING_ENGINE.md`, `docs/superpowers/research/2026-10-16-couples-research/06-synthesis-roadmap.md`; create `docs/superpowers/proposals/2026-11-04-attune-soul-line-73.md` (Task 14).

**Not edited:** `lib/features/games/**`, `lib/features/chat/presentation/screens/chat_screen.dart`, `lib/features/chat/presentation/widgets/chat_text_field.dart`, `lib/app/routing/app_router.dart`, `lib/features/auth/utility/auth_exports.dart`, `lib/features/auth/services/auth_service.dart`, `auth_ui_service.dart`, `lib/home/home_screen.dart`, `lib/core/ui/text/allow_large_text.dart`, `lib/core/widgets/feedback/empty_state.dart`, `error_state.dart`, `lib/core/widgets/buttons/app_button.dart`, `lib/core/flags/public_app_config.dart`, every migration and SQL file, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, `DATING_MODE_SPEC.md`, `DATING_CHAT_SAFETY_SPEC.md`, `FORUM.md`, every existing test except `test/flutter_test_config.dart`, `test/helpers/flow_harness.dart` and `test/accessibility/large_text_test.dart` (one test added), every existing golden (except Task 6's four Me goldens at 1.3/2.0 and Task 7's, on a yes).

---

# W10a · Large text (Tasks 1-8)

### Task 1: Baselines, the audit, and the 1.0 goldens drawn from today's code (§8 W10a; P-2, P-3)

**Files:**
- Modify: `test/flutter_test_config.dart`, `test/helpers/flow_harness.dart` (by `$D/t1_audit_hook.py`)
- Create: `scripts/large_text_audit.py`, `test/accessibility/w10/support/large_text_audit.dart`, `test/accessibility/w10/chat_large_text_test.dart`, `test/accessibility/w10/opinions_large_text_test.dart`, `test/accessibility/w10/together_planning_large_text_test.dart`, `test/accessibility/w10/settings_large_text_test.dart`, `test/accessibility/w10/healing_journal_large_text_test.dart`, and their eleven `*.scale1.0.png` goldens
- Scratch: `$D/edit_lib.py`, `$D/mutants.py`, `$D/t1_audit_hook.py`, the baselines

**Interfaces:**
- Consumes: `pumpFlowScreen`, the chat, Opinions, Planning, Healing and journal test helpers (interfaces section).
- Produces: `pumpFlowScreen(..., double rootTextScaleCap = 1.0)`; the `LARGE_TEXT_AUDIT` define; `python3 scripts/large_text_audit.py --scale S [--baseline B] <test paths>` (exit 1 when a non-Games site overflows that the baseline size doesn't); in `support/large_text_audit.dart`: `auditScales` (`[1.0, 1.3, 1.6, 2.0]`), `goldenScales` (`[1.0, 1.3, 2.0]`), `auditPhones` (`[Size(390, 844), Size(360, 800)]`), `scaleName(double)` (`scale1.0`), `setPhone(WidgetTester, Size, double)`, `collectOverflows(Future<void> Function()) -> Future<List<String>>` (each overflowing widget as `lib/...:line`), `scrollToEnd(WidgetTester)`, `settle(WidgetTester, [Duration])`. Every surface test is named `<surface>, <width> wide, text <scale>` so `--plain-name "390 wide, text 1.0"` picks the 1.0 goldens.

- [ ] **Step 1: Record the baselines**

```bash
D=.superpowers/sdd/2026-11-04-spec1-w10; mkdir -p $D
git status --short > $D/status-before.txt; cat $D/status-before.txt
git rev-parse --short HEAD
sed -n '/if (isAuthenticated && !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum > $D/latch.sha; cat $D/latch.sha
shasum -a 256 lib/features/auth/utility/auth_exports.dart | tee $D/auth_exports.sha
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*(error|warning) ' | sed 's/:[0-9]*:[0-9]* / /' | sort > $D/analyze-baseline.txt; wc -l < $D/analyze-baseline.txt
flutter test --no-pub 2>&1 | tail -1 | tee $D/flutter-baseline.txt
flutter test --no-pub test/architecture/games_untouched_test.dart test/features/games 2>&1 | tail -1
```

Expected: the status lists only the owner's two entries; `8753f112`; `8fe95dbcc4e4e825401daaf612409114e5bed421  -`; `c615dbed9246f7a4582b9e8c072a8258378f769eb62de54b6960f31c356c63f2  lib/features/auth/utility/auth_exports.dart`; the analyzer line count (59 at the time of writing: all warnings, no error); `All tests passed!` with the count (`+7051` at the time of writing) that later tasks add to; `All tests passed!`.

- [ ] **Step 2: Save the edit helper and the mutant runner** (every later script imports the first)

Create `$D/edit_lib.py` with exactly:

```python
# Exact-anchor edits for the W10 plan (run from the repo root).
#   replace(path, old, new): `old` must occur exactly once.
#   wrap(path, anchor, call, prefix, suffix): `anchor` must occur exactly
#     once and contain `call` (e.g. "Column("); the whole call expression
#     starting at `call` (parentheses matched, strings and // comments
#     skipped) becomes prefix + call-expression + suffix.
#   add_import(path, line): adds `line` after the file's last import.
import pathlib, sys

def _read(path):
    return pathlib.Path(path).read_text()

def _write(path, text):
    pathlib.Path(path).write_text(text)

def _once(src, needle, path):
    n = src.count(needle)
    if n != 1:
        sys.exit(f'{path}: anchor found {n} times:\n{needle}')

def replace(path, old, new):
    src = _read(path)
    _once(src, old, path)
    _write(path, src.replace(old, new))

def _call_end(src, start):
    i = src.index('(', start)
    depth = 0
    while i < len(src):
        c = src[i]
        if src.startswith('//', i):
            i = src.index('\n', i)
            continue
        if c in '\'"':
            q = c
            i += 1
            while src[i] != q:
                if src[i] == '\\':
                    i += 1
                i += 1
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    sys.exit('unbalanced call')

def wrap(path, anchor, call, prefix, suffix):
    src = _read(path)
    _once(src, anchor, path)
    a = src.index(anchor)
    start = a + anchor.index(call)
    end = _call_end(src, start)
    _write(path, src[:start] + prefix + src[start:end] + suffix + src[end:])

def add_import(path, line):
    src = _read(path)
    if line in src:
        return
    lines = src.split('\n')
    last = max(i for i, l in enumerate(lines) if l.startswith('import '))
    # A multi-line import ends at the next line ending with ';'.
    while not lines[last].rstrip().endswith(';'):
        last += 1
    lines.insert(last + 1, line)
    _write(path, '\n'.join(lines))
```

Create `$D/mutants.py` with exactly (every task runs its own mutants with it; each must print `RED (caught)`, and the file is always restored):

```python
# Spec 1 W10 mutants. Each: (name, file, old, new, check). The check must
# FAIL with the mutant in place; the file is restored afterwards, whatever
# happens. A check is a test path for `flutter test`, or "audit:<paths>"
# for `scripts/large_text_audit.py --scale 2.0 <paths>` (which exits 1 on a
# site to fix). Run from the repo root:
#   python3 $D/mutants.py <name> [<name> ...]
import pathlib, signal, subprocess, sys

# A timeout or Ctrl-C still restores the file (the finally below runs).
signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))

MUTANTS = [
  # Task 2: the helpers and ScreenUtil.
  ('scaled_up_at_one', 'lib/core/ui/text/large_text.dart',
   "MediaQuery.textScalerOf(context).scale(10) > 10;", "MediaQuery.textScalerOf(context).scale(10) >= 10;",
   'test/core/ui/text/large_text_test.dart'),
  ('scroll_always', 'lib/core/ui/text/large_text.dart',
   "      isTextScaledUp(context) ? SingleChildScrollView(child: child) : child;",
   "      SingleChildScrollView(child: child);",
   'test/core/ui/text/large_text_test.dart'),
  ('resolver_scales', 'lib/core/utils/screen_util_config.dart',
   "    return fontSize.toDouble();", "    return fontSize * instance.scaleText;",
   'test/core/utils/screen_util_large_text_test.dart'),
  ('cap_off', 'lib/core/utils/screen_util_config.dart',
   "  static const double maxScale = 1.25;", "  static const double maxScale = 2.75;",
   'test/core/utils/screen_util_large_text_test.dart'),
  # Task 3: chat.
  ('message_bubble_no_flexible', 'lib/features/chat/presentation/widgets/message_bubble.dart',
   "            Flexible(\n              child: Text(\n              'Video expired',",
   "            SizedBox(\n              child: Text(\n              'Video expired',",
   'audit:test/features/chat/presentation/widgets/message_bubble_test.dart'),
  # Task 4: Opinions.
  ('comment_time_never_flexes', 'lib/features/opinions/presentation/screen/comment_thread_screen.dart',
   "                      flex: isTextScaledUp(context) ? 1 : 0,", "                      flex: 0,",
   'test/accessibility/w10/opinions_large_text_test.dart'),
  # Task 5: Together and Planning.
  ('strip_no_fit', 'lib/features/timeline/presentation/widgets/calendar_strip.dart',
   "                  child: ScaleDownToFit(\n                    alignment: Alignment.center,",
   "                  child: Align(\n                    alignment: Alignment.center,",
   'audit:test/features/timeline'),
  ('trailing_never_flexes', 'lib/core/widgets/info_row_widget.dart',
   "                  flex: isTextScaledUp(context) ? 1 : 0,\n                  child: Center(child: effectiveTrailing),",
   "                  flex: 0,\n                  child: Center(child: effectiveTrailing),",
   'audit:test/features/planning'),
  ('error_state_no_scroll', 'lib/features/together/presentation/screens/together_screen.dart',
   "                child: ScrollWhenScaledUp(\n                  child: ErrorStateWidget(",
   "                child: Center(\n                  child: ErrorStateWidget(",
   'audit:test/features/together/together_screen_test.dart'),
  # Task 6: Settings, Healing, the journal.
  ('rows_never_grow', 'lib/core/widgets/info_row_widget.dart',
   "                              (subTitleMaxLines ?? 3) *\n                              (isTextScaledUp(context) ? 2 : 1),",
   "                              (subTitleMaxLines ?? 3) *\n                              1,",
   'test/accessibility/w10/settings_large_text_test.dart'),
  ('support_card_scrolls_inside', 'lib/core/ui/text/large_text.dart',
   "      isTextScaledUp(context)\n          ? child\n          : Expanded(",
   "      false\n          ? child\n          : Expanded(",
   'test/accessibility/w10/healing_journal_large_text_test.dart'),
  ('picker_unclamped', 'lib/features/me/presentation/widgets/journal_reminder_row.dart',
   "            maxScaleFactor: 1.6,", "            maxScaleFactor: 2.0,",
   'audit:test/features/me/journal_reminder_test.dart'),
  # Task 8: the policy and the clamp.
  ('no_lovemap_prefix', 'lib/app/text_scale_policy.dart', "    '/loveMap',\n", "",
   'test/architecture/text_scale_routes_test.dart'),
  ('games_prefix_too_wide', 'lib/app/text_scale_policy.dart', "    '/games/',\n", "    '/games/',\n    '/c',\n",
   'test/architecture/text_scale_routes_test.dart'),
  ('pulse_marked_audited', 'lib/app/text_scale_policy.dart', "    '/journalEntry',\n", "    '/journalEntry',\n    '/pulse',\n",
   'test/architecture/text_scale_routes_test.dart'),
  ('cap_everywhere', 'lib/app/text_scale_policy.dart',
   "    return keepsDefaultSize(topLocation) ? offCap : cap;", "    return cap;",
   'test/app/text_scale_policy_test.dart'),
  ('top_from_uri', 'lib/app/text_scale_policy.dart',
   "    return matches.last.matchedLocation;", "    return matches.uri.path;",
   'test/app/text_scale_policy_test.dart'),
  ('set_state_in_build', 'lib/app/text_scale_policy.dart',
   "    if (SchedulerBinding.instance.schedulerPhase ==\n        SchedulerPhase.persistentCallbacks) {",
   "    if (false) {",
   'test/app/text_scale_policy_test.dart'),
  ('no_cached_flag', 'lib/app/text_scale_policy.dart',
   "  return live ?? ref.watch(cachedPublicAppConfigProvider)?.textScaleV2 ?? false;", "  return live ?? false;",
   'test/app/text_scale_policy_test.dart'),
  # Task 9: motion.
  ('deck_900', 'lib/features/onboarding/presentation/widgets/onboarding_deck_card.dart',
   "  static const Duration _advanceDuration = kMakeRoomDuration;",
   "  static const Duration _advanceDuration = Duration(milliseconds: 900);",
   'test/accessibility/w10/deck_advance_motion_test.dart'),
  ('motion_ignores_reduce', 'lib/features/auth/sign_up/presentation/widgets/one_time_code_field.dart',
   "if (widget.shakeCount != oldWidget.shakeCount && !reduceMotionOf(context)) {",
   "if (widget.shakeCount != oldWidget.shakeCount) {",
   'test/architecture/spec1_rtl_motion_test.dart'),
  # Task 10: RTL.
  ('rtl_physical_side', 'lib/features/me/presentation/widgets/more_ways_sheet.dart',
   "          padding: const EdgeInsets.fromLTRB(\n            Spacing.lg,\n            0,\n            Spacing.lg,",
   "          padding: const EdgeInsets.fromLTRB(\n            Spacing.lg,\n            0,\n            Spacing.md,",
   'test/architecture/spec1_rtl_motion_test.dart'),
  # Task 11: the first frame.
  ('boot_no_prefs_mark', 'lib/main.dart', "  bootTimeline.mark('prefs');\n", "",
   'test/app/boot_timeline_test.dart'),
]

only = sys.argv[1:]
known = {m[0] for m in MUTANTS}
for name in only:
    if name not in known:
        sys.exit(f'unknown mutant: {name}')
for name, path, old, new, check in MUTANTS:
    if only and name not in only:
        continue
    p = pathlib.Path(path)
    src = p.read_text()
    if src.count(old) != 1:
        print(f'{name}: ANCHOR FOUND {src.count(old)} TIMES', flush=True)
        continue
    p.write_text(src.replace(old, new))
    try:
        if check.startswith('audit:'):
            cmd = ['python3', 'scripts/large_text_audit.py', '--scale', '2.0', *check[6:].split()]
        else:
            cmd = ['flutter', 'test', '--no-pub', check]
        r = subprocess.run(cmd, capture_output=True, text=True)
        print(f"{name}: {'RED (caught)' if r.returncode != 0 else 'GREEN (MISSED)'}", flush=True)
    finally:
        p.write_text(src)
```

- [ ] **Step 3: Add the audit hook**

Create `$D/t1_audit_hook.py` with exactly:

```python
# Spec 1 W10a Task 1: the large-text audit hook in the test config, and the
# flow harness's root clamp as a parameter. Run from the repo root.
import sys
sys.path.insert(0, sys.argv[1])
from edit_lib import replace

p = 'test/flutter_test_config.dart'
replace(p, "import 'package:flutter/widgets.dart' show FlutterError;",
        "import 'package:flutter/widgets.dart' show FlutterError, Size;")
replace(p, "Future<void> testExecutable(FutureOr<void> Function() testMain) async {\n",
"""/// Spec 1 W10a, the large-text audit (scripts/large_text_audit.py): with
/// `--dart-define=LARGE_TEXT_AUDIT=2.0` (or any size) every test runs on a
/// 390 x 844 phone with the phone's text size at that size. Without it
/// nothing changes.
const _largeTextAudit = String.fromEnvironment('LARGE_TEXT_AUDIT');

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (_largeTextAudit.isNotEmpty) {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.textScaleFactorTestValue = double.parse(
        _largeTextAudit,
      );
      binding.platformDispatcher.views.first.physicalSize = const Size(
        1170,
        2532,
      );
      binding.platformDispatcher.views.first.devicePixelRatio = 3;
    });
  }
""")

p = 'test/helpers/flow_harness.dart'
replace(p, """  List<String> openCountries = const [],
  Size size = const Size(390, 844),
}) async {""", """  List<String> openCountries = const [],
  Size size = const Size(390, 844),
  // Spec 1 W10a: the root clamp app_shell.dart applies (1.0 unless
  // text_scale_v2 is on). The audit passes the cap it is checking.
  double rootTextScaleCap = 1.0,
}) async {""")
replace(p, "  tester.platformDispatcher.textScaleFactorTestValue = textScale;",
"""  // Spec 1 W10a: under the large-text audit every flow screen runs at the
  // audit's text size, with the root clamp at the same cap.
  const audit = String.fromEnvironment('LARGE_TEXT_AUDIT');
  if (audit.isNotEmpty) {
    textScale = double.parse(audit);
    rootTextScaleCap = textScale;
  }
  tester.platformDispatcher.textScaleFactorTestValue = textScale;""")
replace(p, """                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.0,
                      child: child!,""", """                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: rootTextScaleCap,
                      child: child!,""")
print('audit hook added')
```

Run: `python3 $D/t1_audit_hook.py $D && flutter analyze --no-pub test/flutter_test_config.dart test/helpers/flow_harness.dart`
Expected: `audit hook added`; `No issues found!`.

- [ ] **Step 4: Create `scripts/large_text_audit.py`** with exactly:

```python
#!/usr/bin/env python3
"""Spec 1 W10a: the large-text audit.

Runs the given Flutter test paths with the phone's text size at SCALE on a
390 x 844 phone (test/flutter_test_config.dart's LARGE_TEXT_AUDIT hook) and
lists every layout overflow by the widget that overflowed (file:line), with
how many tests hit it and one of them. Games sites, surfaces outside the
audit (they keep 1.0) and test-only sites are listed apart (below).

  python3 scripts/large_text_audit.py --scale 2.0 test/features/opinions
  python3 scripts/large_text_audit.py --scale 1.3 --baseline 1.0 test/features/chat

With --baseline, sites that already overflow at the baseline size are
marked "(already at <baseline>)" and don't count. Exit status 1 when any
other site outside Games overflows, else 0. Test failures other than
overflows (goldens drawn at 1.0, finders) are expected and ignored.
"""
import argparse
import collections
import json
import re
import subprocess
import sys

SITE = re.compile(
    r'A RenderFlex overflowed by ([0-9.]+) pixels on the (\w+)\.'
    r'(?:.*\n){0,4}?.*The relevant error-causing widget was:\s*\n\s*\S+\s*\n'
    r'\s*\S+:file://(\S+?:\d+)')


def where(path):
    """lib/... or test/... in this repo; package:<name>/... for a package."""
    m = re.search(r'/pub\.dev/([^/]+)/(.*)$', path)
    if m:
        return f'package:{m.group(1)}/{m.group(2)}'
    m = re.search(r'/packages/(flutter\w*)/lib/(.*)$', path)
    if m:
        return f'package:{m.group(1)}/{m.group(2)}'
    m = re.search(r'/((?:lib|test)/.*)$', path)
    return m.group(1) if m else path


# Listed apart, never counted as a site to fix:
# - Games files are never edited (Spec 1 section 1.5); Games routes keep 1.0.
# - Surfaces outside the W10a audit keep 1.0 through TextScalePolicy (P-9).
# - A site that overflows only in its own test, never in the app.
NOT_AUDITED = {
    'lib/features/pulse/': 'not audited: keeps 1.0 (TextScalePolicy)',
}
TEST_ONLY = {
    'lib/features/relationships/presentation/widgets/relationship_lifecycle_card.dart:131':
        'test only: the card alone on a page that does not scroll; '
        'in the app it sits in scrolling lists',
}

PROGRESS = re.compile(r'^\d\d:\d\d \+\d+(?: ~\d+)?(?: -\d+)?: (.*)$')


def run(scale, paths):
    out = subprocess.run(
        ['flutter', 'test', '--no-pub', '--reporter', 'expanded',
         f'--dart-define=LARGE_TEXT_AUDIT={scale}', *paths],
        capture_output=True, text=True, errors='replace')
    text = (out.stdout + out.stderr).replace('\r', '\n')
    sites = collections.defaultdict(list)
    test = ''
    for block in re.split(r'\n(?=\d\d:\d\d \+\d+)', text):
        m = PROGRESS.match(block.split('\n', 1)[0])
        if m:
            test = m.group(1)
        for s in SITE.finditer(block):
            sites[where(s.group(3))].append((float(s.group(1)), test))
    return sites


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--scale', required=True)
    ap.add_argument('--baseline')
    ap.add_argument('--json', help='also write every site and the tests '
                    'that hit it to this file')
    ap.add_argument('paths', nargs='+')
    a = ap.parse_args()
    sites = run(a.scale, a.paths)
    before = run(a.baseline, a.paths) if a.baseline else {}
    if a.json:
        with open(a.json, 'w') as f:
            json.dump({k: [t for _, t in v] for k, v in sites.items()}, f,
                      indent=1, sort_keys=True)
    failing = 0
    for site in sorted(sites):
        hits = sites[site]
        worst = max(px for px, _ in hits)
        note = ''
        not_audited = [v for k, v in NOT_AUDITED.items() if site.startswith(k)]
        if site.startswith('lib/features/games/'):
            note = ' (Games: never edited)'
        elif not_audited:
            note = f' ({not_audited[0]})'
        elif site in TEST_ONLY:
            note = f' ({TEST_ONLY[site]})'
        elif site in before:
            note = f' (already at {a.baseline})'
        else:
            failing += 1
        example = re.sub(r'^.*?(?=test/)', '', hits[0][1])[:160]
        print(f'{len(hits):4d} {site} up to {worst:.0f}px{note}')
        print(f'       e.g. {example}')
    print(f'SCALE {a.scale}: {failing} site(s) to fix, '
          f'{len(sites) - failing} listed apart')
    sys.exit(1 if failing else 0)


if __name__ == '__main__':
    main()
```

Run: `chmod +x scripts/large_text_audit.py && python3 -m py_compile scripts/large_text_audit.py && echo ok`
Expected: `ok`.

- [ ] **Step 5: Run the audit on today's code (the red list)**

```bash
python3 scripts/large_text_audit.py --scale 2.0 test | tee $D/audit-2.0-before.txt | tail -1
python3 scripts/large_text_audit.py --scale 1.3 test | tee $D/audit-1.3-before.txt | tail -1
grep -E '^ +[0-9]+ (lib|package)' $D/audit-2.0-before.txt | grep -v -e '(Games' -e '(not audited' -e '(test only' | awk '{print $2}' | sort
```

Expected (each run about 20 minutes): `SCALE 2.0: 35 site(s) to fix, 25 listed apart` and `SCALE 1.3: 8 site(s) to fix, 6 listed apart` (listed apart: Games sites, Pulse's, which P-9 keeps at 1.0, and the test-only lifecycle card); the third command prints exactly these 35 sites (P-3; `animated_rolling_counter.dart` is reached through `voice_recording_bar.dart`'s fixed 52-wide timer, `empty_state.dart` and `error_state.dart` through Planning's category screen and Together's agenda, the `go_router` line is J3's time picker, a dialog on the root Navigator):

```
lib/core/widgets/animated_rolling_counter.dart:248
lib/core/widgets/app_days_count.dart:40
lib/core/widgets/charts/arc_gauge.dart:106
lib/core/widgets/feedback/confirmation_dialog.dart:58
lib/core/widgets/feedback/empty_state.dart:62
lib/core/widgets/feedback/error_state.dart:118
lib/core/widgets/info_row_widget.dart:337
lib/features/account/presentation/new_device_notice.dart:232
lib/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart:385
lib/features/ai_assistant/presentation/widgets/attune_assist_bubble.dart:102
lib/features/ai_assistant/presentation/widgets/attune_assist_bubble.dart:243
lib/features/appreciation/presentation/appreciation_sheet.dart:95
lib/features/auth/intro/widgets/intro_guide_widget.dart:48
lib/features/chat/presentation/widgets/message_bubble.dart:1919
lib/features/chat/presentation/widgets/voice_message_player.dart:270
lib/features/healing/presentation/screens/healing_journey_screen.dart:80
lib/features/healing/presentation/screens/healing_portrait_screen.dart:231
lib/features/healing/presentation/screens/healing_post_mortem_screen.dart:300
lib/features/opinions/data/opinion_more_data.dart:197
lib/features/opinions/presentation/screen/comment_thread_screen.dart:1001
lib/features/opinions/presentation/widgets/opinion_card.dart:370
lib/features/planning/presentation/screens/planning_entry_screen.dart:740
lib/features/planning/presentation/widgets/expenses_block_view.dart:235
lib/features/planning/presentation/widgets/link_block_view.dart:250
lib/features/planning/presentation/widgets/link_block_view.dart:61
lib/features/planning/presentation/widgets/planning_block_picker.dart:60
lib/features/planning/presentation/widgets/planning_spend_chart.dart:101
lib/features/quiet_states/presentation/quiet_states_screen.dart:185
lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart:473
lib/features/relationships/presentation/widgets/relationship_ended_sheet.dart:72
lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart:99
lib/features/timeline/presentation/widgets/calendar_strip.dart:195
lib/features/timeline/presentation/widgets/moment_card.dart:188
lib/features/wins/presentation/share_win_sheet.dart:76
package:go_router-10.2.0/lib/src/builder.dart:316
```

If a later change moved a line, compare the files: that is what must match. The test failures an audit run prints (goldens drawn at 1.0, finders that expect one line) are expected; only overflow sites count.

- [ ] **Step 6: Create the audit's shared pieces**

Create `test/accessibility/w10/support/large_text_audit.dart` with exactly:

```dart
// Spec 1 W10a: the large-text audit's shared pieces. Every audited surface
// is pumped at each text size below on two phones; every layout overflow
// is collected (file:line) instead of failing at the first; goldens are
// taken on the common phone at 1.0, 1.3 and 2.0 (§2.3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Normal text and the three candidate caps (§8 W10a).
const auditScales = <double>[1.0, 1.3, 1.6, 2.0];

/// The golden sizes (§2.3).
const goldenScales = <double>[1.0, 1.3, 2.0];

/// A common phone, and a narrow Android one (Android Go class).
const auditPhones = <Size>[Size(390, 844), Size(360, 800)];

/// `scale1.0`, `scale1.3`, `scale2.0`: the flow goldens' naming.
String scaleName(double scale) => 'scale${scale.toStringAsFixed(1)}';

/// Sets the phone's size and text size for one test.
void setPhone(WidgetTester t, Size size, double scale) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
}

/// Every layout overflow reported while [body] runs, as `file:line`
/// (`lib/...`), one entry per overflowing widget.
Future<List<String>> collectOverflows(Future<void> Function() body) async {
  final found = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    if (!text.contains('overflowed by')) {
      previous?.call(details);
      return;
    }
    final at = RegExp(
      r'The relevant error-causing widget was:\s*\n\s*\S+\s*\n\s*\S+:file://\S*?/(lib/[^:\s]+:\d+)',
    ).firstMatch(text);
    found.add(at?.group(1) ?? text.split('\n').first);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return found;
}

/// Drags every vertical scrollable on screen to its end, a screen at a
/// time, so rows below the fold are laid out too.
Future<void> scrollToEnd(WidgetTester t) async {
  final scrollables = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  for (var i = 0; i < 6; i++) {
    if (scrollables.evaluate().isEmpty) return;
    await t.drag(scrollables.first, const Offset(0, -500), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 300));
  }
}

/// Pumps frames for [duration] without waiting for every animation to end
/// (some surfaces animate forever).
Future<void> settle(
  WidgetTester t, [
  Duration duration = const Duration(seconds: 2),
]) async {
  for (
    var elapsed = Duration.zero;
    elapsed < duration;
    elapsed += const Duration(milliseconds: 100)
  ) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
```

- [ ] **Step 7: Create the five surface tests** (each written once, used unchanged by Tasks 3-6)

Create `test/accessibility/w10/chat_large_text_test.dart` with exactly:

```dart
// Spec 1 W10a: the chat at large text (audit order: 1st). The thread with
// a long message, a reply, a game card and its trail, the typing dots and
// a long draft. The in-chat Games sheet is audited by
// in_chat_games_large_text_test.dart (Games files are never edited).
//   flutter test --update-goldens test/accessibility/w10/chat_large_text_test.dart
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/chat/support/chat_test_harness.dart';
import 'support/large_text_audit.dart';

FakeChatRepository _thread() {
  final repo = FakeChatRepository(currentUserId: 'user-a');
  // A fixed evening long ago: the bubbles' times and the date chip never
  // change from run to run.
  final now = DateTime(2026, 6, 1, 19, 30);
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
  repo.seedIncoming(
    id: 'm1',
    relationshipId: 'rel-1',
    senderId: 'partner',
    content:
        'Are we still on for dinner at the place by the water on Saturday evening?',
    createdAt: ago(9),
  );
  repo.seedIncoming(
    id: 'm2',
    relationshipId: 'rel-1',
    senderId: 'user-a',
    content: 'Yes! I booked it for seven. Can you pick up the cake on the way?',
    createdAt: ago(8),
  );
  repo.seedIncoming(
    id: 'm3',
    relationshipId: 'rel-1',
    senderId: 'partner',
    content: 'Of course',
    createdAt: ago(7),
    replyToMessageId: 'm2',
    quotedText: 'Can you pick up the cake on the way?',
  );
  repo.seedIncoming(
    id: 'm4',
    relationshipId: 'rel-1',
    senderId: 'partner',
    content: 'Snakes and Ladders',
    createdAt: ago(6),
    mediaType: 'game',
    gameSessionId: 'gs1',
  );
  repo.seedIncoming(
    id: 'm5',
    relationshipId: 'rel-1',
    senderId: 'user-a',
    content: 'You moved to square 42',
    createdAt: ago(5),
    mediaType: 'game_trail',
  );
  return repo;
}

void main() {
  for (final phone in auditPhones) {
    for (final scale in auditScales) {
      testWidgets('chat, ${phone.width.toInt()} wide, text $scale', (t) async {
        setPhone(t, phone, scale);
        final repo = _thread();
        final container = buildChatContainer(
          repository: repo,
          userId: 'user-a',
          extraOverrides: [
            gameCardProvider.overrideWith(
              (ref, id) => Stream.value(
                const GameCardState(
                  gameType: 'snakes_and_ladders',
                  status: 'active',
                  currentTurnUserId: 'user-a',
                  winnerUserId: null,
                  currentRound: null,
                  totalRounds: null,
                ),
              ),
            ),
          ],
        );
        final convo = activeConversation('rel-1');
        repo.conversationOverride = convo;
        final overflows = await collectOverflows(() async {
          await t.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: withScreenUtil(
                MaterialApp(
                  theme: AppTheme.lightTheme,
                  debugShowCheckedModeBanner: false,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  // What app_shell.dart does with the cap under audit.
                  builder:
                      (context, child) => MediaQuery.withClampedTextScaling(
                        maxScaleFactor: scale,
                        child: child!,
                      ),
                  home: ChatScreen(conversation: convo),
                ),
              ),
            ),
          );
          await settle(t);
          repo.emitPartnerTyping('partner', true);
          await settle(t, const Duration(milliseconds: 600));
          await t.enterText(
            find.byType(TextField).last,
            'A longer draft that wraps onto a few lines in the composer box',
          );
          await settle(t, const Duration(milliseconds: 600));
          if (phone == auditPhones.first && goldenScales.contains(scale)) {
            // The wallpaper tile decodes off the test clock: wait for it,
            // so every golden has it drawn.
            await t.runAsync(
              () => precacheImage(
                const AssetImage(
                  'assets/images/attune_chat_wallpaper_tile_refined.png',
                ),
                t.element(find.byType(ChatScreen)),
              ),
            );
            await t.pump();
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('goldens/chat.${scaleName(scale)}.png'),
            );
          }
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(milliseconds: 100));
        });
        container.dispose();
        expect(overflows, isEmpty);
      });
    }
  }
}
```

Create `test/accessibility/w10/opinions_large_text_test.dart` with exactly:

```dart
// Spec 1 W10a: Opinions at large text (audit order: 2nd). A thread with
// two comments, then its post menu and the post report list, with
// opinions_safety_v1 off (W9's flag-off goldens stay as they are).
//   flutter test --update-goldens test/accessibility/w10/opinions_large_text_test.dart
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/opinions/w9/support/fake_opinions.dart';
import '../../helpers/flow_harness.dart';
import 'support/large_text_audit.dart';

void main() {
  for (final phone in auditPhones) {
    for (final scale in auditScales) {
      testWidgets('Opinions, ${phone.width.toInt()} wide, text $scale', (
        t,
      ) async {
        final golden =
            phone == auditPhones.first && goldenScales.contains(scale);
        final opinion = w9Opinion();
        final overflows = await collectOverflows(() async {
          await pumpFlowScreen(
            t,
            () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
            textScale: scale,
            rootTextScaleCap: scale,
            size: phone,
            overrides: opinionOverrides(FakeOpinionRepository()),
          );
          if (golden) {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                'goldens/opinions_thread.${scaleName(scale)}.png',
              ),
            );
          }
          await scrollToEnd(t);
          await t.tap(find.byIcon(Icons.more_vert_rounded));
          await t.pumpAndSettle();
          if (golden) {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                'goldens/opinions_post_menu.${scaleName(scale)}.png',
              ),
            );
          }
          await t.tapAt(const Offset(20, 20));
          await t.pumpAndSettle();
        });
        expect(overflows, isEmpty);
      });
    }
  }
}
```

Create `test/accessibility/w10/together_planning_large_text_test.dart` with exactly:

```dart
// Spec 1 W10a: Together and Planning at large text (audit order: 3rd).
// Planning's home on its Planning tab and its Calendar tab (the Together
// screen). The month grid (calendar_strip.dart) follows today's date, so it
// has no golden; the audit reaches it through the timeline's own tests.
//   flutter test --update-goldens test/accessibility/w10/together_planning_large_text_test.dart
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/planning/support/fake_planning_gateway.dart';
import '../../features/planning/support/planning_test_app.dart';
import 'support/large_text_audit.dart';

FakePlanningGateway _gateway() => FakePlanningGateway({
  'get_planning_home':
      (_) => {
        'categories': [
          fakeCategoryJson(
            id: 'c1',
            seedKey: 'goals',
            name: 'Goals',
            icon: 'flag',
            color: 'rose',
            entryCount: 2,
            hasNew: true,
          ),
          fakeCategoryJson(
            id: 'c2',
            seedKey: 'trips',
            name: 'Trips we keep meaning to take',
            icon: 'plane',
            color: 'teal',
          ),
        ],
      },
});

void main() {
  for (final tab in [PlanningHomeTab.planning, PlanningHomeTab.calendar]) {
    for (final phone in auditPhones) {
      for (final scale in auditScales) {
        testWidgets('${tab.name}, ${phone.width.toInt()} wide, text $scale', (
          t,
        ) async {
          setPhone(t, phone, scale);
          final overflows = await collectOverflows(() async {
            await t.pumpWidget(
              planningTestApp(
                _gateway(),
                PlanningHomeScreen(relationshipId: 'r1', initialTab: tab),
                coupleName: 'The Mensahs',
              ),
            );
            await settle(t);
            if (phone == auditPhones.first && goldenScales.contains(scale)) {
              await expectLater(
                find.byType(MaterialApp),
                matchesGoldenFile(
                  'goldens/${tab.name}.${scaleName(scale)}.png',
                ),
              );
            }
            await scrollToEnd(t);
            await t.pumpWidget(const SizedBox());
            await settle(t, const Duration(milliseconds: 300));
          });
          expect(overflows, isEmpty);
        });
      }
    }
  }
}
```

Create `test/accessibility/w10/settings_large_text_test.dart` with exactly:

```dart
// Spec 1 W10a: Settings at large text (audit order: 4th).
//   flutter test --update-goldens test/accessibility/w10/settings_large_text_test.dart
import 'package:attune/features/settings/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/flow_harness.dart';
import 'support/large_text_audit.dart';

void main() {
  for (final phone in auditPhones) {
    for (final scale in auditScales) {
      testWidgets('Settings, ${phone.width.toInt()} wide, text $scale', (
        t,
      ) async {
        final overflows = await collectOverflows(() async {
          await pumpFlowScreen(
            t,
            () => const SettingsScreen(currentUserId: 'me'),
            textScale: scale,
            rootTextScaleCap: scale,
            size: phone,
          );
          if (phone == auditPhones.first && goldenScales.contains(scale)) {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('goldens/settings.${scaleName(scale)}.png'),
            );
          }
          await scrollToEnd(t);
        });
        expect(overflows, isEmpty);
      });
    }
  }
}
```

Create `test/accessibility/w10/healing_journal_large_text_test.dart` with exactly:

```dart
// Spec 1 W10a: Healing and the journal at large text (audit order: 5th and
// 6th). Healing's reflection stage before and after the reflection comes
// back, and with the support card; the journal list and an entry with a
// reflection under it.
//   flutter test --update-goldens test/accessibility/w10/healing_journal_large_text_test.dart
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/screens/healing_post_mortem_screen.dart';
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/healing/w9e/support/healing_fakes.dart';
import '../../features/reflection_journal/support/fake_journal.dart';
import '../../features/reflection_journal/support/journal_test_app.dart';
import '../../helpers/flow_harness.dart';
import 'support/large_text_audit.dart';

const _observation =
    'You both seemed to wait for the other to start the hard conversations, '
    'and the quiet between you grew a little each time.';

Future<void> _golden(String name, Size phone, double scale) async {
  if (phone != auditPhones.first || !goldenScales.contains(scale)) return;
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.${scaleName(scale)}.png'),
  );
}

void main() {
  for (final phone in auditPhones) {
    for (final scale in auditScales) {
      final where = '${phone.width.toInt()} wide, text $scale';

      testWidgets('Healing reflection stage, $where', (t) async {
        for (final (name, answer) in [
          ('healing_ready', <String, dynamic>{}),
          (
            'healing_done',
            <String, dynamic>{
              'status': 'completed',
              'observation': _observation,
            },
          ),
          ('healing_support', <String, dynamic>{'status': 'support_offered'}),
        ]) {
          final overflows = await collectOverflows(() async {
            await pumpFlowScreen(
              t,
              () => HealingPostMortemScreen(journey: testJourney()),
              textScale: scale,
              rootTextScaleCap: scale,
              size: phone,
              overrides: [
                healingGenerationServiceProvider.overrideWithValue(
                  FakeHealingGeneration([answer]),
                ),
                healingRepositoryProvider.overrideWithValue(
                  FakeHealingRepository(),
                ),
                healingAccountProvider.overrideWith((ref) => 'ama'),
              ],
            );
            if (name != 'healing_ready') {
              await t.tap(find.text('Generate reflection'));
              await t.pumpAndSettle();
            }
            await _golden(name, phone, scale);
            await scrollToEnd(t);
          });
          expect(overflows, isEmpty, reason: name);
        }
      });

      testWidgets('journal list and entry, $where', (t) async {
        final repo = FakeJournalRepository();
        final entry = repo.addEntry(
          title: 'Sunday walk by the lagoon',
          text: 'We talked about moving closer to my mother next year.',
        );
        repo.addEntry(text: 'A short note.');
        repo.analysisFor = JournalAnalysis(
          status: 'completed',
          observation: _observation,
          tone: 'hopeful',
        );
        setPhone(t, phone, scale);
        final overflows = await collectOverflows(() async {
          final router = await pumpJournal(t, repo: repo);
          setPhone(t, phone, scale);
          await t.pumpAndSettle();
          await _golden('journal_list', phone, scale);
          await scrollToEnd(t);
          router.push(
            '/journalEntry',
            extra: JournalEntryArgs(entryId: entry.id, isNew: false),
          );
          await t.pumpAndSettle();
          await _golden('journal_entry', phone, scale);
          await scrollToEnd(t);
        });
        expect(overflows, isEmpty);
      });
    }
  }
}
```

- [ ] **Step 8: Draw the 1.0 goldens from today's code, before any fix**

```bash
flutter test --no-pub --update-goldens --plain-name "390 wide, text 1.0" test/accessibility/w10
ls test/accessibility/w10/goldens
flutter test --no-pub --plain-name "390 wide, text 1.0" test/accessibility/w10 2>&1 | tail -1
```

Expected: eleven files, `calendar.scale1.0.png chat.scale1.0.png healing_done.scale1.0.png healing_ready.scale1.0.png healing_support.scale1.0.png journal_entry.scale1.0.png journal_list.scale1.0.png opinions_post_menu.scale1.0.png opinions_thread.scale1.0.png planning.scale1.0.png settings.scale1.0.png`; `All tests passed!` (`+7`). Open three of them (Read tool: `chat`, `opinions_thread`, `journal_entry`) and check they show the screen, not a blank page. **These eleven files are never regenerated by a later task**: they are the "exactly as before at 1.0" check.

- [ ] **Step 9: Record the red list** (what Tasks 3-6 turn green)

```bash
flutter test --no-pub test/accessibility/w10 2>&1 | grep -E '^\s+.lib/' | sort | uniq -c | tee $D/surfaces-red.txt
flutter test --no-pub test/accessibility/w10 2>&1 | tail -1
```

Expected: overflow sites from `comment_thread_screen.dart:1001`, `healing_post_mortem_screen.dart:300` and `journal_entry_screen.dart:473` (the last already at 1.0 on the 360-wide phone, P-3), plus failures for the 1.3 and 2.0 goldens that don't exist yet; `+28 -28: Some tests failed.`

- [ ] **Step 10: Format check and the default run unchanged**

```bash
dart format --output=none --set-exit-if-changed test/accessibility/w10
flutter test --no-pub test/features/opinions test/features/auth/sign_up test/home 2>&1 | tail -1
```

Expected: `0 changed`; `All tests passed!` (the flow harness change and the hook do nothing without the define).

### Task 2: The large-text helpers and the ScreenUtil check (§8 W10a "checking ScreenUtil"; P-4, P-10)

**Files:**
- Create: `lib/core/ui/text/large_text.dart`, `test/core/ui/text/large_text_test.dart`, `test/core/utils/screen_util_large_text_test.dart`

**Interfaces:**
- Consumes: `ScreenUtilConfig` (`minTextAdapt`, `maxScale`, `builder`).
- Produces (`package:attune/core/ui/text/large_text.dart`): `bool isTextScaledUp(BuildContext context)` (true above 1.0); `ScrollWhenTall({required Widget child})` (a fixed-height column scrolls once scaled up; never inside an intrinsic-measuring parent); `ScaleDownToFit({required Widget child, AlignmentGeometry alignment = AlignmentDirectional.centerStart})`; `ScrollWhenScaledUp({required Widget child})` (a sheet's column); `ScrollsInPlaceUnlessScaledUp({required Widget child})` (an `Expanded` scroll view at 1.0, the child in place once `ScrollWhenTall` scrolls the column). Every one returns its child unchanged at 1.0.

- [ ] **Step 1: Write the failing tests**

Create `test/core/ui/text/large_text_test.dart` with exactly:

```dart
// Spec 1 W10a: the large-text helpers are inert at the normal text size
// (the same layout, no extra scroll view) and fix the overflow once the
// phone's text is scaled up.
import 'package:attune/core/ui/text/large_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget child, double scale) async {
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 200, height: 120, child: child),
          ),
        ),
      ),
    ),
  );
}

Widget _tallColumn() => const Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    Text('Nothing here yet', key: ValueKey('title')),
    Spacer(),
    Text('Add your first plan to get started', key: ValueKey('body')),
  ],
);

Widget _wideRow() => const Row(
  mainAxisSize: MainAxisSize.min,
  children: [Text('12 days to go', key: ValueKey('count'))],
);

Rect _rect(WidgetTester t, String key) => t.getRect(find.byKey(ValueKey(key)));

void main() {
  test('isTextScaledUp is false at 1.0 and true above it', () {
    // Checked through a widget below; this pins the threshold's meaning.
    expect(TextScaler.linear(1.0).scale(10) > 10, isFalse);
    expect(TextScaler.linear(1.05).scale(10) > 10, isTrue);
  });

  testWidgets('ScrollWhenTall: the same layout and no scroll view at 1.0', (
    t,
  ) async {
    await _pump(t, _tallColumn(), 1.0);
    final title = _rect(t, 'title');
    final body = _rect(t, 'body');
    await _pump(t, ScrollWhenTall(child: _tallColumn()), 1.0);
    expect(_rect(t, 'title'), title);
    expect(_rect(t, 'body'), body);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('ScrollWhenTall: scrolls instead of overflowing at 2.0', (
    t,
  ) async {
    await _pump(t, _tallColumn(), 2.0);
    expect(t.takeException(), isA<FlutterError>(), reason: 'the bug');
    await _pump(t, ScrollWhenTall(child: _tallColumn()), 2.0);
    expect(t.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('ScaleDownToFit: the same size at 1.0, fits at 2.0', (t) async {
    await _pump(t, _wideRow(), 1.0);
    final count = _rect(t, 'count');
    await _pump(t, ScaleDownToFit(child: _wideRow()), 1.0);
    expect(_rect(t, 'count'), count);
    expect(find.byType(FittedBox), findsNothing);
    await _pump(
      t,
      const SizedBox(
        width: 60,
        child: ScaleDownToFit(child: Text('12 days to go')),
      ),
      2.0,
    );
    expect(t.takeException(), isNull);
    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets('ScrollWhenScaledUp: nothing at 1.0, a scroll view above', (
    t,
  ) async {
    const sheet = Column(
      mainAxisSize: MainAxisSize.min,
      children: [Text('Report this opinion'), Text('Spam')],
    );
    await _pump(t, const ScrollWhenScaledUp(child: sheet), 1.0);
    expect(find.byType(SingleChildScrollView), findsNothing);
    await _pump(t, const ScrollWhenScaledUp(child: sheet), 1.3);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('ScrollsInPlaceUnlessScaledUp: Expanded scroll at 1.0, in '
      'place once the column scrolls', (t) async {
    Widget column() => ScrollWhenTall(
      child: Column(
        children: [
          const Text('Stage 2 of 5'),
          ScrollsInPlaceUnlessScaledUp(
            child: Container(height: 400, color: const Color(0xFF00FF00)),
          ),
        ],
      ),
    );
    await _pump(t, column(), 1.0);
    expect(find.byType(Expanded), findsOneWidget);
    expect(t.takeException(), isNull);
    await _pump(t, column(), 2.0);
    expect(find.byType(Expanded), findsNothing);
    expect(t.takeException(), isNull);
  });
}
```

Create `test/core/utils/screen_util_large_text_test.dart` with exactly:

```dart
// Spec 1 W10a: ScreenUtil never scales text a second time. .sp is the
// identity (fontSizeResolver), so minTextAdapt has no effect on fonts, the
// phone's text size is applied once (by Flutter's TextScaler), and the iPad
// 1.25x cap moves spacing only, never text.
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, double>> _measure(
  WidgetTester t, {
  required Size screen,
  required double textScale,
}) async {
  t.view.physicalSize = screen;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
  late double sp;
  late double w;
  await t.pumpWidget(
    ScreenUtilConfig.builder(
      builder: (context) {
        sp = 16.sp;
        w = 100.w;
        return const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(
                'Aa',
                key: ValueKey('probe'),
                style: TextStyle(fontSize: 16, height: 1),
              ),
            ),
          ),
        );
      },
    ),
  );
  return {
    'sp': sp,
    'w': w,
    'height': t.getSize(find.byKey(const ValueKey('probe'))).height,
  };
}

void main() {
  test('the resolver is the identity and minTextAdapt stays on', () {
    expect(ScreenUtilConfig.minTextAdapt, isTrue);
    expect(ScreenUtilConfig.maxScale, 1.25);
  });

  testWidgets('.sp ignores the screen size (phone and iPad)', (t) async {
    final phone = await _measure(t, screen: const Size(390, 844), textScale: 1);
    final pad = await _measure(t, screen: const Size(1024, 1366), textScale: 1);
    expect(phone['sp'], 16);
    expect(pad['sp'], 16);
  });

  testWidgets('the iPad cap moves spacing by at most 1.25x', (t) async {
    final pad = await _measure(t, screen: const Size(1024, 1366), textScale: 1);
    expect(pad['w'], closeTo(125, 0.01));
  });

  testWidgets('the phone text size is applied once, and not to spacing', (
    t,
  ) async {
    final one = await _measure(t, screen: const Size(390, 844), textScale: 1);
    final two = await _measure(t, screen: const Size(390, 844), textScale: 2);
    expect(two['sp'], one['sp'], reason: '.sp never reads the text scale');
    expect(two['w'], one['w'], reason: '.w never reads the text scale');
    expect(two['height'], closeTo(one['height']! * 2, 0.5));
  });
}
```

- [ ] **Step 2: Run them**

Run: `flutter test --no-pub test/core/ui/text/large_text_test.dart test/core/utils/screen_util_large_text_test.dart`
Expected: the first fails to compile (`Error: Error when reading 'lib/core/ui/text/large_text.dart'`); the ScreenUtil tests pass already (`+4`): they pin today's behaviour (P-10), which W10 keeps.

- [ ] **Step 3: Create `lib/core/ui/text/large_text.dart`** with exactly:

```dart
import 'package:flutter/widgets.dart';

/// Large-text layout helpers (Spec 1 W10a). Each one is inert at the normal
/// text size, so a screen that uses them looks exactly as it was designed
/// until the phone's text size is turned up.

/// Whether the text here is scaled above 1.0.
bool isTextScaledUp(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 10;

/// A fixed-height column (an empty state, a stage screen's body) that
/// scrolls instead of overflowing once large text makes it taller than its
/// space. The column still fills the height, so its Spacers and centring
/// behave as before. Not for a child that holds a scrollable or a
/// LayoutBuilder (the column is measured by its intrinsic height), and not
/// where a parent measures intrinsic sizes itself (a sliver that fills the
/// rest of a feed, IntrinsicHeight, a Table): it lays out with a
/// LayoutBuilder, which can't answer them.
class ScrollWhenTall extends StatelessWidget {
  const ScrollWhenTall({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isTextScaledUp(context)) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return child;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(child: child),
          ),
        );
      },
    );
  }
}

/// A short readout in a fixed space (a timer, a count, a day number, a
/// gauge's figures) that shrinks to fit once large text makes it bigger
/// than its space, rather than overflowing or wrapping mid-number.
class ScaleDownToFit extends StatelessWidget {
  const ScaleDownToFit({
    super.key,
    required this.child,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (!isTextScaledUp(context)) return child;
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: child,
      ),
    );
  }
}

/// A sheet's column that scrolls once large text makes it taller than the
/// sheet allows; at the normal size it is returned as it is.
class ScrollWhenScaledUp extends StatelessWidget {
  const ScrollWhenScaledUp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      isTextScaledUp(context) ? SingleChildScrollView(child: child) : child;
}

/// The part of a fixed-height column that scrolls on its own at the normal
/// size (an Expanded scroll view). Once [ScrollWhenTall] scrolls the whole
/// column (large text) it is laid out in place instead: a column measured
/// by its intrinsic height can't hold a scroll view.
class ScrollsInPlaceUnlessScaledUp extends StatelessWidget {
  const ScrollsInPlaceUnlessScaledUp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      isTextScaledUp(context)
          ? child
          : Expanded(child: SingleChildScrollView(child: child));
}
```

- [ ] **Step 4: Run the tests, then the mutants**

Run: `flutter test --no-pub test/core/ui/text/large_text_test.dart test/core/utils/screen_util_large_text_test.dart`
Expected: `All tests passed!` (`+10`).

Run: `python3 $D/mutants.py scaled_up_at_one scroll_always resolver_scales cap_off`
Expected: four lines, each `RED (caught)` (`scaled_up_at_one`: the 1.0 layout gains a scroll view; `scroll_always`: a sheet scrolls at 1.0; `resolver_scales`: `.sp` follows the iPad's width; `cap_off`: spacing grows 2.75x on an iPad).

- [ ] **Step 5: Format and analyze**

```bash
dart format --output=none --set-exit-if-changed lib/core/ui/text/large_text.dart test/core/ui/text/large_text_test.dart test/core/utils/screen_util_large_text_test.dart
flutter analyze --no-pub lib/core/ui/text/large_text.dart test/core/ui/text test/core/utils/screen_util_large_text_test.dart
```

Expected: `0 changed`; `No issues found!`

### Task 3: Chat (audit order 1; §8 W10a; P-3, P-5)

**Files:**
- Modify (by `$D/t3_chat_fixes.py`): `lib/features/chat/presentation/widgets/voice_recording_bar.dart`, `lib/core/widgets/app_days_count.dart`, `lib/features/ai_assistant/presentation/widgets/attune_assist_bubble.dart`, `lib/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart`, `lib/features/auth/intro/widgets/intro_guide_widget.dart`, `lib/features/chat/presentation/widgets/message_bubble.dart`, `lib/features/chat/presentation/widgets/voice_message_player.dart`, `lib/features/account/presentation/new_device_notice.dart`, `lib/features/relationships/presentation/widgets/relationship_ended_sheet.dart`, `lib/features/appreciation/presentation/appreciation_sheet.dart`, `lib/features/wins/presentation/share_win_sheet.dart`, `lib/core/widgets/feedback/confirmation_dialog.dart`
- Create: `test/accessibility/w10/goldens/chat.scale1.3.png`, `chat.scale2.0.png`

**Interfaces:**
- Consumes: Task 2's `isTextScaledUp`, `ScaleDownToFit`, `ScrollWhenTall`, `ScrollWhenScaledUp`; Task 1's audit and `chat_large_text_test.dart`.
- Produces: nothing new; the thirteen sites the chat's tests reach fit at every size.

How each site is fixed (P-3): a label in a row that has no other flexible child gets `Flexible` (inert when it fits); a row whose free space a `Spacer` takes gets `Flexible(flex: isTextScaledUp(context) ? 1 : 0, ...)` (no flex at 1.0); a fixed-size readout (the recording timer, the days count, the voice note's time) gets `ScaleDownToFit`; a sheet's column gets `ScrollWhenScaledUp`; the intro card's fixed-size column gets `ScrollWhenTall`; the confirmation dialog's 350 maximum grows with the text (350 at 1.0, as before).

- [ ] **Step 1: The audit on the chat's tests (red)**

```bash
CHAT="test/features/chat test/features/ai_assistant test/features/account test/features/relationships test/features/appreciation test/features/wins"
python3 scripts/large_text_audit.py --scale 2.0 $CHAT | tee $D/t3-before.txt | tail -1
```

Expected: `SCALE 2.0: 13 site(s) to fix, 1 listed apart` (the test-only lifecycle card, P-3); the thirteen, with how many tests hit each:

```
  11 lib/core/widgets/animated_rolling_counter.dart:248     (voice_recording_bar.dart's 52-wide timer)
   5 lib/core/widgets/app_days_count.dart:40               (the days-together card)
   1 lib/core/widgets/feedback/confirmation_dialog.dart:58
   1 lib/features/account/presentation/new_device_notice.dart:232
   1 lib/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart:385
  11 lib/features/ai_assistant/presentation/widgets/attune_assist_bubble.dart:102
   3 lib/features/ai_assistant/presentation/widgets/attune_assist_bubble.dart:243
   2 lib/features/appreciation/presentation/appreciation_sheet.dart:95
  10 lib/features/auth/intro/widgets/intro_guide_widget.dart:48   (the empty chat's cards)
   1 lib/features/chat/presentation/widgets/message_bubble.dart:1919
   1 lib/features/chat/presentation/widgets/voice_message_player.dart:270
   5 lib/features/relationships/presentation/widgets/relationship_ended_sheet.dart:72
   1 lib/features/wins/presentation/share_win_sheet.dart:76
```

- [ ] **Step 2: Save and run the fixes**

Create `$D/t3_chat_fixes.py` with exactly:

```python
# Spec 1 W10a Task 3: the chat surface (P-3). Run from the repo root:
#   python3 $D/t3_chat_fixes.py $D
import sys
sys.path.insert(0, sys.argv[1])
from edit_lib import replace, wrap, add_import

IMP = "import 'package:attune/core/ui/text/large_text.dart';"

def chat():
    p = 'lib/features/chat/presentation/widgets/voice_recording_bar.dart'
    wrap(p, "              child: AnimatedRollingCounter(\n                // Rolls rather than jumps",
         "AnimatedRollingCounter(", "ScaleDownToFit(\n                child: ", ",\n              )")
    add_import(p, IMP)
    p = 'lib/core/widgets/app_days_count.dart'
    wrap(p, "      child: Row(\n        mainAxisSize: MainAxisSize.min,\n        children: [\n          roll",
         "Row(", "ScaleDownToFit(\n        child: ", ",\n      )")
    add_import(p, IMP)
    p = 'lib/features/ai_assistant/presentation/widgets/attune_assist_bubble.dart'
    wrap(p, "              Text(\n                'Attune suggestion',", "Text(",
         "Flexible(\n                child: ", ",\n              )")
    wrap(p, "                  Text('Added to Planning',", "Text(",
         "Flexible(\n                    child: ", ",\n                  )")
    p = 'lib/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart'
    wrap(p, "        child: Column(\n          mainAxisSize: MainAxisSize.min,\n          children: [\n            ListTile(\n              key: const ValueKey('assist-kind-ideas'),",
         "Column(", "ScrollWhenScaledUp(\n          child: ", ",\n        )")
    add_import(p, IMP)
    p = 'lib/features/auth/intro/widgets/intro_guide_widget.dart'
    wrap(p, "        child: Column(\n          mainAxisAlignment: MainAxisAlignment.center,\n          children: [\n            // Icon",
         "Column(", "ScrollWhenTall(\n          child: ", ",\n        )")
    add_import(p, IMP)
    p = 'lib/features/chat/presentation/widgets/message_bubble.dart'
    wrap(p, "            Text(\n              'Video expired',", "Text(",
         "Flexible(\n              child: ", ",\n            )")
    p = 'lib/features/chat/presentation/widgets/voice_message_player.dart'
    wrap(p, "                        RollingDuration(\n                          keyPrefix: 'voice-playback-duration',",
         "RollingDuration(",
         "// Spec 1 W10a: flex 0 (no flex) at the normal size, so the\n"
         "                        // row is exactly as before; above it the time\n"
         "                        // shrinks to fit beside the speed pill.\n"
         "                        Flexible(\n"
         "                          flex: isTextScaledUp(context) ? 1 : 0,\n"
         "                          child: ScaleDownToFit(\n"
         "                            child: ",
         ",\n                          ),\n                        )")
    add_import(p, IMP)
    p = 'lib/features/account/presentation/new_device_notice.dart'
    wrap(p, "                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),",
         "TextButton(", "Flexible(\n                  flex: isTextScaledUp(context) ? 1 : 0,\n                  child: ", ",\n                )")
    wrap(p, "                FilledButton(onPressed: onReview, child: const Text('Review')),",
         "FilledButton(", "Flexible(\n                  flex: isTextScaledUp(context) ? 1 : 0,\n                  child: ", ",\n                )")
    add_import(p, IMP)
    p = 'lib/features/relationships/presentation/widgets/relationship_ended_sheet.dart'
    wrap(p, "        child: Column(\n          mainAxisSize: MainAxisSize.min,\n          crossAxisAlignment: CrossAxisAlignment.stretch,\n          children: [\n            Text('$name has ended your shared space.'",
         "Column(", "ScrollWhenScaledUp(\n          child: ", ",\n        )")
    add_import(p, IMP)
    p = 'lib/features/appreciation/presentation/appreciation_sheet.dart'
    wrap(p, "                Text('I noticed…', style: text.titleMedium),", "Text(",
         "Flexible(child: ", ")")
    p = 'lib/features/wins/presentation/share_win_sheet.dart'
    wrap(p, "                Text('Share a win', style: text.titleMedium),", "Text(",
         "Flexible(child: ", ")")

    # The confirmation dialog (used across the app; a chat test hits it).
    p = 'lib/core/widgets/feedback/confirmation_dialog.dart'
    replace(p, "        maxHeight: 350.h, // Limit maximum height",
            "        // Spec 1 W10a: grows with the phone's text size (350 at the\n"
            "        // normal size, as before), so large text never overflows it.\n"
            "        maxHeight: 350.h * MediaQuery.textScalerOf(context).scale(10) / 10,")


chat()
print('t3_chat_fixes applied')
```

Run: `python3 $D/t3_chat_fixes.py $D`
Expected: `t3_chat_fixes applied`.

- [ ] **Step 3: The audit again, at every candidate size (green)**

```bash
for s in 2.0 1.6 1.3; do python3 scripts/large_text_audit.py --scale $s $CHAT | tail -1; done
```

Expected: `SCALE 2.0: 0 site(s) to fix, 1 listed apart` (the test-only lifecycle card), `SCALE 1.6: 0 site(s) to fix, 0 listed apart`, `SCALE 1.3: 0 site(s) to fix, 0 listed apart`.

- [ ] **Step 4: The chat goldens at 1.3 and 2.0, and the 1.0 golden unchanged**

```bash
flutter test --no-pub --update-goldens --plain-name "chat, 390 wide, text 1.3" test/accessibility/w10/chat_large_text_test.dart
flutter test --no-pub --update-goldens --plain-name "chat, 390 wide, text 2.0" test/accessibility/w10/chat_large_text_test.dart
flutter test --no-pub test/accessibility/w10/chat_large_text_test.dart 2>&1 | tail -1
git status --short test/accessibility/w10/goldens
```

Expected: `All tests passed!` (`+8`: two phones, four sizes, no overflow, the 1.0 golden from Task 1 unchanged); the status shows only new files (`??`), never a modified Task 1 golden. Open `chat.scale2.0.png`: the long message, the quoted reply, the game card and the draft wrap; nothing is cut.

- [ ] **Step 5: Mutant**

Run: `python3 $D/mutants.py message_bubble_no_flexible`
Expected: `message_bubble_no_flexible: RED (caught)` ("Video expired" without its `Flexible` overflows the bubble at 2.0).

- [ ] **Step 6: Regression at the normal size**

```bash
flutter test --no-pub $CHAT test/home test/accessibility/large_text_test.dart test/accessibility/w10/chat_large_text_test.dart 2>&1 | tail -1
flutter analyze --no-pub lib/features/chat lib/core/widgets/app_days_count.dart lib/features/ai_assistant lib/features/auth/intro lib/features/account lib/features/relationships lib/features/appreciation lib/features/wins 2>&1 | grep -E '^\s*(error|warning) ' | sed 's/:[0-9]*:[0-9]* / /' | sort | comm -13 $D/analyze-baseline.txt -
git status --short lib/features/games lib/features/chat/presentation/screens/chat_screen.dart lib/features/chat/presentation/widgets/chat_text_field.dart
```

Expected: `All tests passed!`; no line from `comm` (no new analyzer warning or error); nothing from the scoped status (no Games file, `chat_screen.dart` or `chat_text_field.dart` touched).

### Task 4: Opinions (audit order 2; §8 W10a; P-3; the W9 owner ruling)

**Files:**
- Modify (by `$D/t4_opinions_fixes.py`): `lib/features/opinions/presentation/screen/comment_thread_screen.dart` (the comment row's time), `lib/features/opinions/data/opinion_more_data.dart` (`_safetySheet`'s flag-off branch), `lib/features/opinions/presentation/widgets/opinion_card.dart` (the card menu's column)
- Create: `test/accessibility/w10/goldens/opinions_thread.scale1.3.png`, `opinions_thread.scale2.0.png`, `opinions_post_menu.scale1.3.png`, `opinions_post_menu.scale2.0.png`

**Interfaces:**
- Consumes: Task 2's `isTextScaledUp`, `ScrollWhenScaledUp`.
- Produces: nothing new. With `opinions_safety_v1` off, Opinions at 1.0 is byte-for-byte as before (W9's six `flag_off_*` goldens, run unchanged).

- [ ] **Step 1: The audit on Opinions' tests (red)**

```bash
python3 scripts/large_text_audit.py --scale 2.0 test/features/opinions | tee $D/t4-before.txt | tail -1
```

Expected: `SCALE 2.0: 3 site(s) to fix, 0 listed apart`:

```
   1 lib/features/opinions/data/opinion_more_data.dart:197          (the post report list, flag off)
  42 lib/features/opinions/presentation/screen/comment_thread_screen.dart:1001   (the comment row)
   1 lib/features/opinions/presentation/widgets/opinion_card.dart:370   (the card menu)
```

- [ ] **Step 2: Save and run the fixes**

Create `$D/t4_opinions_fixes.py` with exactly:

```python
# Spec 1 W10a Task 4: Opinions (P-3), three large-text fixes and nothing
# else. Run from the repo root: python3 $D/t4_opinions_fixes.py $D
import sys
sys.path.insert(0, sys.argv[1])
from edit_lib import replace, wrap, add_import

IMP = "import 'package:attune/core/ui/text/large_text.dart';"

def opinions():
    p = 'lib/features/opinions/presentation/screen/comment_thread_screen.dart'
    wrap(p, "                    Text(\n                      timeAgo,", "Text(",
         "// Spec 1 W10a: flex 0 (no flex) at the normal size, so\n"
         "                    // the row is exactly as before; above it the time\n"
         "                    // gives way instead of pushing the menu off.\n"
         "                    Flexible(\n"
         "                      flex: isTextScaledUp(context) ? 1 : 0,\n"
         "                      child: ",
         ",\n                    )")
    add_import(p, IMP)
    p = 'lib/features/opinions/data/opinion_more_data.dart'
    replace(p, "      on ? AllowLargeText(child: SingleChildScrollView(child: child)) : child;",
            "      on\n          ? AllowLargeText(child: SingleChildScrollView(child: child))\n"
            "          // Spec 1 W10a: flag off, the six reasons scroll only once the\n"
            "          // phone's text is scaled up; at the normal size, as before.\n"
            "          : ScrollWhenScaledUp(child: child);")
    add_import(p, IMP)
    p = 'lib/features/opinions/presentation/widgets/opinion_card.dart'
    wrap(p, "            child: Column(\n              mainAxisSize: MainAxisSize.min,\n              children: [\n                for (final section in sections)",
         "Column(", "ScrollWhenScaledUp(\n              child: ", ",\n            )")
    add_import(p, IMP)


opinions()
print('t4_opinions_fixes applied')
```

Run: `python3 $D/t4_opinions_fixes.py $D`
Expected: `t4_opinions_fixes applied`.

- [ ] **Step 3: The audit again (green)**

```bash
for s in 2.0 1.6 1.3; do python3 scripts/large_text_audit.py --scale $s test/features/opinions | tail -1; done
```

Expected: `SCALE 2.0: 0 site(s) to fix, 0 listed apart`, and the same at 1.6 and 1.3.

- [ ] **Step 4: Goldens, and W9's flag-off goldens unchanged**

```bash
for s in 1.3 2.0; do flutter test --no-pub --update-goldens --plain-name "Opinions, 390 wide, text $s" test/accessibility/w10/opinions_large_text_test.dart; done
flutter test --no-pub test/accessibility/w10/opinions_large_text_test.dart test/features/opinions 2>&1 | tail -1
git status --short test/features/opinions
```

Expected: `All tests passed!`; nothing from the status (no Opinions golden or test changed: `flag_off_thread`, `flag_off_post_menu`, `flag_off_report_reasons` and the rest pass as they are). Open `opinions_thread.scale2.0.png`: each comment's like count, "Reply", time and menu fit on the row; the time shortens rather than pushing the menu off.

- [ ] **Step 5: Mutant**

Run: `python3 $D/mutants.py comment_time_never_flexes`
Expected: `comment_time_never_flexes: RED (caught)` (the comment row overflows at 1.6 and 2.0).

- [ ] **Step 6: Regression**

```bash
flutter analyze --no-pub lib/features/opinions 2>&1 | grep -E '^\s*(error|warning) ' | sed 's/:[0-9]*:[0-9]* / /' | sort | comm -13 $D/analyze-baseline.txt -
git diff --stat lib/features/opinions
```

Expected: no line from `comm`; three files changed.

### Task 5: Together and Planning (audit order 3; §8 W10a; P-3, P-5)

**Files:**
- Modify (by `$D/t5_together_planning_fixes.py`): `lib/features/together/presentation/screens/together_screen.dart` (the agenda's error state), `lib/features/planning/presentation/screens/planning_category_screen.dart` (the empty state's fixed height), `lib/features/timeline/presentation/widgets/calendar_strip.dart` (the day cell), `add_moment_or_reminder_sheet.dart`, `moment_card.dart` (same folder), `lib/features/timeline/presentation/screens/log_moment_details_screen.dart` (the mood scale's ends; only the 1.6 run reaches it), `lib/core/widgets/charts/arc_gauge.dart`, `lib/core/widgets/info_row_widget.dart` (the trailing slot), `lib/features/planning/presentation/screens/planning_entry_screen.dart` ("Mark settled"), `lib/features/planning/presentation/widgets/expenses_block_view.dart`, `link_block_view.dart` (two rows), `planning_block_picker.dart`, `planning_spend_chart.dart`
- Create: `test/accessibility/w10/goldens/{planning,calendar}.scale{1.3,2.0}.png`

**Interfaces:**
- Consumes: Task 2's helpers.
- Produces: nothing new. `EmptyStateWidget` and `ErrorStateWidget` are not changed (P-5).

- [ ] **Step 1: The audit on Together's and Planning's tests (red)**

```bash
TP="test/features/together test/features/planning test/features/timeline test/core/widgets"
python3 scripts/large_text_audit.py --scale 2.0 $TP | tee $D/t5-before.txt | tail -1
```

Expected: `SCALE 2.0: 13 site(s) to fix, 0 listed apart` (Task 3 already fixed `app_days_count.dart`, which Planning's countdown also reaches):

```
  13 lib/core/widgets/charts/arc_gauge.dart:106
   5 lib/core/widgets/feedback/empty_state.dart:62        (Planning's category screen)
   1 lib/core/widgets/feedback/error_state.dart:118       (Together's agenda error)
  84 lib/core/widgets/info_row_widget.dart:337            (the trailing slot)
   1 lib/features/planning/presentation/screens/planning_entry_screen.dart:740
   3 lib/features/planning/presentation/widgets/expenses_block_view.dart:235
   5 lib/features/planning/presentation/widgets/link_block_view.dart:250
   2 lib/features/planning/presentation/widgets/link_block_view.dart:61
   1 lib/features/planning/presentation/widgets/planning_block_picker.dart:60
   4 lib/features/planning/presentation/widgets/planning_spend_chart.dart:101
   1 lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart:99
 508 lib/features/timeline/presentation/widgets/calendar_strip.dart:195
   1 lib/features/timeline/presentation/widgets/moment_card.dart:188
```

- [ ] **Step 2: Save and run the fixes**

Create `$D/t5_together_planning_fixes.py` with exactly:

```python
# Spec 1 W10a Task 5: Together and Planning (P-3, P-5). Run from the repo
# root: python3 $D/t5_together_planning_fixes.py $D
import sys
sys.path.insert(0, sys.argv[1])
from edit_lib import replace, wrap, add_import

IMP = "import 'package:attune/core/ui/text/large_text.dart';"

def together():
    # The error and empty states are fixed where they sit, not in the core
    # widgets: those are also measured by intrinsic height (a sliver that
    # fills the rest of a feed), where a scroll view can't go.
    p = 'lib/features/together/presentation/screens/together_screen.dart'
    wrap(p, "              (e, _) => Center(\n                child: ErrorStateWidget(\n                  title: 'Could not load your plans',",
         "ErrorStateWidget(", "ScrollWhenScaledUp(\n                  child: ", ",\n                )")
    add_import(p, IMP)
    p = 'lib/features/planning/presentation/screens/planning_category_screen.dart'
    replace(p, """                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.6,
                        child: Center(
                          child: PlanningEmptyState(""", """                      SizedBox(
                        // Spec 1 W10a: at large text the empty state takes
                        // the height it needs and scrolls with the list.
                        height:
                            isTextScaledUp(context)
                                ? null
                                : MediaQuery.sizeOf(context).height * 0.6,
                        child: Center(
                          child: PlanningEmptyState(""")
    add_import(p, IMP)
    p = 'lib/features/timeline/presentation/widgets/calendar_strip.dart'
    wrap(p, "                  child: Column(\n                    mainAxisAlignment: MainAxisAlignment.center,\n                    children: [\n                      Text(\n                        '$dayNumber',",
         "Column(", "ScaleDownToFit(\n                    alignment: Alignment.center,\n                    child: ", ",\n                  )")
    add_import(p, IMP)
    p = 'lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart'
    wrap(p, "            child: Column(\n              mainAxisSize: MainAxisSize.min,\n              crossAxisAlignment: CrossAxisAlignment.start,\n              children: [\n                Gap(Spacing.md),\n                if (day != null) ...[",
         "Column(", "ScrollWhenScaledUp(\n              child: ", ",\n            )")
    add_import(p, IMP)
    p = 'lib/features/timeline/presentation/widgets/moment_card.dart'
    wrap(p, "                  Text(\n                    'Only you can see this',", "Text(",
         "Flexible(\n                    child: ", ",\n                  )")
    p = 'lib/core/widgets/charts/arc_gauge.dart'
    wrap(p, "            child: Center(\n              child: Column(mainAxisSize: MainAxisSize.min, children: [",
         "Column(", "ScaleDownToFit(\n                alignment: Alignment.center,\n                child: ", ",\n              )")
    add_import(p, IMP)
    p = 'lib/core/widgets/info_row_widget.dart'
    replace(p, "              if (effectiveTrailing != null) ...[\n                Gap(Spacing.md.w),\n                Center(child: effectiveTrailing),\n              ]",
            "              if (effectiveTrailing != null) ...[\n                Gap(Spacing.md.w),\n"
            "                // Spec 1 W10a: flex 0 (no flex) at the normal size, so\n"
            "                // the row is exactly as before; above it the trailing\n"
            "                // content shares the row instead of overflowing it.\n"
            "                Flexible(\n                  flex: isTextScaledUp(context) ? 1 : 0,\n"
            "                  child: Center(child: effectiveTrailing),\n                ),\n              ]")
    add_import(p, IMP)
    p = 'lib/features/planning/presentation/screens/planning_entry_screen.dart'
    wrap(p, "          if (!split.isEven) TextButton(onPressed: () => _settle(context, ref), child: const Text('Mark settled')),",
         "TextButton(", "Flexible(\n              flex: isTextScaledUp(context) ? 1 : 0,\n              child: ", ",\n            )")
    add_import(p, IMP)
    p = 'lib/features/planning/presentation/widgets/expenses_block_view.dart'
    wrap(p, "                            Text(\n                              item.isChecked\n                                  ? 'Mark as unpaid'",
         "Text(", "Flexible(\n                              child: ", ",\n                            )")
    p = 'lib/features/planning/presentation/widgets/link_block_view.dart'
    wrap(p, "              Text('Open in YouTube',", "Text(", "Flexible(child: ", ")")
    wrap(p, "        InkWell(\n          borderRadius: BorderRadiusTokens.smAll,\n          onTap: uri == null ? null : () => launchUrl(uri, mode: LaunchMode.externalApplication),",
         "InkWell(", "Flexible(\n          flex: isTextScaledUp(context) ? 1 : 0,\n          child: ", ",\n        )")
    wrap(p, "          TextButton.icon(\n              icon: const Icon(Icons.add_link_rounded),",
         "TextButton.icon(", "Flexible(\n            flex: isTextScaledUp(context) ? 1 : 0,\n            child: ", ",\n          )")
    add_import(p, IMP)
    p = 'lib/features/planning/presentation/widgets/planning_block_picker.dart'
    wrap(p, "    return Column(\n      crossAxisAlignment: CrossAxisAlignment.stretch,\n      children: [\n        BottomSheetHeader(title: title),",
         "Column(", "ScrollWhenScaledUp(\n      child: ", ",\n    )")
    add_import(p, IMP)
    p = 'lib/features/planning/presentation/widgets/planning_spend_chart.dart'
    wrap(p, "      Text(label, style: Theme.of(context).textTheme.labelSmall),", "Text(",
         "Flexible(child: ", ")")

    # The mood scale's two ends in the moment sheet (Together's "Log a
    # moment"), found at 1.6.
    p = 'lib/features/timeline/presentation/screens/log_moment_details_screen.dart'
    replace(p, """                    Text('Difficult', style: textTheme.bodySmall),
                    Text('Amazing', style: textTheme.bodySmall),""", """                    Flexible(
                      child: Text('Difficult', style: textTheme.bodySmall),
                    ),
                    Flexible(
                      child: Text(
                        'Amazing',
                        style: textTheme.bodySmall,
                        textAlign: TextAlign.end,
                      ),
                    ),""")


together()
print('t5_together_planning_fixes applied')
```

Run: `python3 $D/t5_together_planning_fixes.py $D`
Expected: `t5_together_planning_fixes applied`.

- [ ] **Step 3: The audit again (green)**

```bash
for s in 2.0 1.6 1.3; do python3 scripts/large_text_audit.py --scale $s $TP | tail -1; done
```

Expected: `SCALE 2.0: 0 site(s) to fix, 0 listed apart`, and the same at 1.6 and 1.3 (at 1.6 only because of the moment sheet's fix).

- [ ] **Step 4: Goldens**

```bash
for s in 1.3 2.0; do flutter test --no-pub --update-goldens --plain-name "390 wide, text $s" test/accessibility/w10/together_planning_large_text_test.dart; done
flutter test --no-pub test/accessibility/w10/together_planning_large_text_test.dart 2>&1 | tail -1
```

Expected: `All tests passed!` (`+16`). Open `planning.scale2.0.png` and `calendar.scale2.0.png`. (The month grid has no golden: it follows today's date; Step 3's audit covers it through the timeline's tests.)

- [ ] **Step 5: Mutants**

Run: `python3 $D/mutants.py strip_no_fit trailing_never_flexes error_state_no_scroll`
Expected: three lines, each `RED (caught)`. Also run, once, `flutter test --no-pub test/features/opinions/opinions_tab_shell_test.dart`: `All tests passed!` (Review Focus 5: the core empty state is untouched, so Discover's sliver still measures it).

- [ ] **Step 6: Regression**

```bash
flutter test --no-pub $TP test/features/opinions test/home 2>&1 | tail -1
flutter analyze --no-pub lib/features/together lib/features/planning lib/features/timeline lib/core/widgets 2>&1 | grep -E '^\s*(error|warning) ' | sed 's/:[0-9]*:[0-9]* / /' | sort | comm -13 $D/analyze-baseline.txt -
```

Expected: `All tests passed!`; no line from `comm`.

### Task 6: Settings, Healing and the journal (audit order 4-6; §8 W10a; P-3, P-4)

**Files:**
- Modify (by `$D/t6_settings_healing_journal_fixes.py`): `lib/core/widgets/info_row_widget.dart` (twice the lines when scaled up), `lib/features/quiet_states/presentation/quiet_states_screen.dart` (the line sheet), `lib/features/healing/presentation/screens/healing_journey_screen.dart` (the five stages), `healing_portrait_screen.dart`, `healing_post_mortem_screen.dart` (the body scrolls once scaled up; the support card's own scroll view gives way), `lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart` (the reflection header wraps), `lib/features/me/presentation/widgets/journal_reminder_row.dart` (J3's time picker at most 1.6)
- Create: `test/accessibility/w10/goldens/{settings,healing_ready,healing_done,healing_support,journal_list,journal_entry}.scale{1.3,2.0}.png`
- Regenerate: `test/features/me/goldens/me_just_me.scale1.3.png`, `me_just_me.scale2.0.png`, `me_dating_open.scale1.3.png`, `me_dating_open.scale2.0.png` (W3's Me home at large text: its rows now wrap to more lines; the 1.0 and RTL ones don't change)

**Interfaces:**
- Consumes: Task 2's helpers.
- Produces: nothing new.

- [ ] **Step 1: The audit on these tests (red)**

```bash
SHJ="test/features/settings test/features/quiet_states test/features/safety test/features/healing test/features/reflection_journal test/features/me"
python3 scripts/large_text_audit.py --scale 2.0 $SHJ | tee $D/t6-before.txt | tail -1
```

Expected: `SCALE 2.0: 6 site(s) to fix, 0 listed apart`:

```
   1 lib/features/healing/presentation/screens/healing_journey_screen.dart:80
   5 lib/features/healing/presentation/screens/healing_portrait_screen.dart:231
  13 lib/features/healing/presentation/screens/healing_post_mortem_screen.dart:300
   1 lib/features/quiet_states/presentation/quiet_states_screen.dart:185
   3 lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart:473
   1 package:go_router-10.2.0/lib/src/builder.dart:316    (J3's time picker, a dialog on the root Navigator)
```

(The Settings rows themselves don't overflow; they are cut, P-4.)

- [ ] **Step 2: Save and run the fixes**

Create `$D/t6_settings_healing_journal_fixes.py` with exactly:

```python
# Spec 1 W10a Task 6: Settings, Healing and the journal (P-3, P-4). Run
# from the repo root: python3 $D/t6_settings_healing_journal_fixes.py $D
import sys
sys.path.insert(0, sys.argv[1])
from edit_lib import replace, wrap, add_import

IMP = "import 'package:attune/core/ui/text/large_text.dart';"

def unwrap_support(p):
    # Expanded(child: SingleChildScrollView(child: HealingSupportCard(...)))
    # becomes ScrollsInPlaceUnlessScaledUp(child: HealingSupportCard(...)).
    import pathlib
    from edit_lib import _call_end
    src = pathlib.Path(p).read_text()
    anchor = "              Expanded(\n                child: SingleChildScrollView(\n                  child: HealingSupportCard("
    assert src.count(anchor) == 1, p
    a = src.index(anchor)
    e_start = a + anchor.index('Expanded(')
    e_end = _call_end(src, e_start)
    c_start = a + anchor.index('HealingSupportCard(')
    c_end = _call_end(src, c_start)
    card = src[c_start:c_end]
    pathlib.Path(p).write_text(src[:e_start] + 'ScrollsInPlaceUnlessScaledUp(child: ' + card + ')' + src[e_end:])


def settings():
    # Truncation: a scaled-up row gets twice the lines before it ellipsizes.
    p = 'lib/core/widgets/info_row_widget.dart'
    replace(p, "                          maxLines: titleMaxLines ?? 2,",
            "                          // Spec 1 W10a: twice the lines once the text is\n"
            "                          // scaled up, so large text wraps instead of being cut.\n"
            "                          maxLines:\n"
            "                              (titleMaxLines ?? 2) *\n"
            "                              (isTextScaledUp(context) ? 2 : 1),")
    replace(p, "                          maxLines: subTitleMaxLines ?? 3,",
            "                          maxLines:\n"
            "                              (subTitleMaxLines ?? 3) *\n"
            "                              (isTextScaledUp(context) ? 2 : 1),")
    add_import(p, IMP)
    p = 'lib/features/quiet_states/presentation/quiet_states_screen.dart'
    wrap(p, "        child: Column(\n          mainAxisSize: MainAxisSize.min,\n          crossAxisAlignment: CrossAxisAlignment.stretch,\n          children: [\n            Text(\n              canSend",
         "Column(", "ScrollWhenScaledUp(\n          child: ", ",\n        )")
    add_import(p, IMP)


def healing():
    p = 'lib/features/healing/presentation/screens/healing_journey_screen.dart'
    wrap(p, "                          return Column(\n                            children: [\n                              AnimatedScaleFade(",
         "Column(", "Flexible(\n                            flex: isTextScaledUp(context) ? 1 : 0,\n                            child: ", ",\n                          )")
    add_import(p, IMP)
    for p, anchor in [
        ('lib/features/healing/presentation/screens/healing_portrait_screen.dart', "      body: Padding(\n        padding: EdgeInsets.all(Spacing.lg.w),\n        child: Column(\n          crossAxisAlignment: CrossAxisAlignment.start,\n          children: [\n            Text(\n              'Stage 4 of 5',"),
        ('lib/features/healing/presentation/screens/healing_post_mortem_screen.dart', "      body: Padding(\n        padding: EdgeInsets.all(Spacing.lg.w),\n        child: Column(\n          crossAxisAlignment: CrossAxisAlignment.start,\n          children: [\n            Text(\n              'Stage 2 of 5',"),
    ]:
        wrap(p, anchor, "Column(", "ScrollWhenTall(\n          child: ", ",\n        )")
        unwrap_support(p)
        add_import(p, IMP)


def journal():
    # J3's time picker is Flutter's own dialog, which overflows at 2.0 on a
    # phone (input mode); 1.6 is the most it fits.
    p = 'lib/features/me/presentation/widgets/journal_reminder_row.dart'
    replace(p, "    final picked = await showTimePicker(context: context, initialTime: current);",
            "    final picked = await showTimePicker(\n"
            "      context: context,\n"
            "      initialTime: current,\n"
            "      // Spec 1 W10a: Flutter's own picker overflows a phone at 2.0.\n"
            "      builder:\n"
            "          (context, child) => MediaQuery.withClampedTextScaling(\n"
            "            maxScaleFactor: 1.6,\n"
            "            child: child!,\n"
            "          ),\n"
            "    );")
    p = 'lib/features/reflection_journal/presentation/screens/journal_entry_screen.dart'
    replace(p, "        Row(children: [\n          Text('A reflection', style: text.titleSmall),",
            "        // Spec 1 W10a: the tone chip moves under the title when they\n"
            "        // no longer fit side by side.\n"
            "        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [\n          Text('A reflection', style: text.titleSmall),")


settings()
healing()
journal()
print('t6_settings_healing_journal_fixes applied')
```

Run: `python3 $D/t6_settings_healing_journal_fixes.py $D`
Expected: `t6_settings_healing_journal_fixes applied`.

- [ ] **Step 3: The audit again (green)**

```bash
for s in 2.0 1.6 1.3; do python3 scripts/large_text_audit.py --scale $s $SHJ | tail -1; done
```

Expected: `SCALE 2.0: 0 site(s) to fix, 0 listed apart`, and the same at 1.6 and 1.3.

- [ ] **Step 4: Goldens; the journal's 1.0 golden is unchanged; W3's Me goldens at large text**

```bash
for f in settings healing_journal; do for s in 1.3 2.0; do flutter test --no-pub --update-goldens --plain-name "390 wide, text $s" test/accessibility/w10/${f}_large_text_test.dart; done; done
flutter test --no-pub test/accessibility/w10 2>&1 | tail -1
flutter test --no-pub test/features/me/dating_slot_test.dart test/features/me/me_home_screen_test.dart 2>&1 | tail -1
flutter test --no-pub --update-goldens test/features/me/dating_slot_test.dart test/features/me/me_home_screen_test.dart
git status --short test/features/me/goldens
```

Expected: `All tests passed!` (`+56`: the five surface files, every phone and size). The journal entry at 1.0 on the 390 phone (Task 1's golden, a short tone) is unchanged; the 360-wide run at 1.0 now passes too (it overflowed before, P-3: the one place a fix changes 1.0, and only where 1.0 was already broken). Open `settings.scale2.0.png` (subtitles run to six lines instead of three), `healing_done.scale2.0.png` (the reflection and the field scroll as one page) and `journal_entry.scale2.0.png`. The two Me tests first fail (`Me goldens`, `me_dating_open goldens`: `me_just_me.scale1.3.png` and `me_dating_open.scale1.3.png` differ, 22% and 11%), then pass after the update; the status shows exactly the four modified Me goldens listed under Files, never their `scale1.0` or `rtl` files. Open `me_just_me.scale2.0.png`: the rows' subtitles now wrap instead of stopping at three lines.

- [ ] **Step 5: Mutants**

Run: `python3 $D/mutants.py rows_never_grow support_card_scrolls_inside picker_unclamped`
Expected: three lines, each `RED (caught)` (`rows_never_grow`: Settings' 2.0 golden cuts subtitles at three lines; `support_card_scrolls_inside`: the Healing stage asks a scroll view for its intrinsic height at 1.3 and up; `picker_unclamped`: J3's time picker overflows at 2.0).

- [ ] **Step 6: Regression**

```bash
flutter test --no-pub $SHJ test/accessibility 2>&1 | tail -1
flutter analyze --no-pub lib/core/widgets lib/features/quiet_states lib/features/healing lib/features/reflection_journal lib/features/me 2>&1 | grep -E '^\s*(error|warning) ' | sed 's/:[0-9]*:[0-9]* / /' | sort | comm -13 $D/analyze-baseline.txt -
```

Expected: `All tests passed!`; no line from `comm`.

### Task 7: The light error colour (owner question 3; P-11) — build only on the owner's yes

**Files:**
- Modify: `lib/app/theme/app_colors.dart` (one line)
- Regenerate: the 36 goldens listed in Step 3

**Interfaces:**
- Consumes: nothing new.
- Produces: `LightColors.error == Color(0xFFC62828)`; `colorScheme.error` in light mode follows it; `onError` stays white.

If the owner hasn't answered yes, skip this task and say so in the task report; nothing else depends on it.

- [ ] **Step 1: Write the failing test**

Create `test/app/theme/error_contrast_test.dart` with exactly:

```dart
// Spec 1 W10a (owner question 3): the light theme's error colour reads at
// least 4.5:1 with its onError text and as text on the light surfaces
// (WCAG 1.4.3). The dark theme's pair is checked too, unchanged.
import 'package:attune/app/theme/app_colors.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final light = AppTheme.lightTheme.colorScheme;
  final dark = AppTheme.darkTheme.colorScheme;

  for (final (name, a, b) in [
    ('light error with onError', light.error, light.onError),
    ('light error on the surface', light.error, light.surface),
    ('light error on the background', light.error, LightColors.background),
    ('dark error with onError', dark.error, dark.onError),
  ]) {
    test('$name: at least 4.5:1', () {
      final ratio = _contrast(a, b);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '$name: ${ratio.toStringAsFixed(2)}',
      );
    });
  }
}
```

Run: `flutter test --no-pub test/app/theme/error_contrast_test.dart`
Expected: FAIL: `light error with onError: 3.68` (`Expected: a value greater than or equal to <4.5>`).

- [ ] **Step 2: Change the colour**

```bash
python3 - <<'PY'
import sys; sys.path.insert(0, '.superpowers/sdd/2026-11-04-spec1-w10')
from edit_lib import replace
replace('lib/app/theme/app_colors.dart',
        "  static const Color error = Color(0xFFF44336);",
        "  // Spec 1 W10a: 5.6:1 with white and 5.2:1 on the light background\n"
        "  // (#F44336 was 3.7:1 and 3.4:1, under WCAG's 4.5:1).\n"
        "  static const Color error = Color(0xFFC62828);")
print('error colour changed')
PY
flutter test --no-pub test/app/theme/error_contrast_test.dart 2>&1 | tail -1
```

Expected: `error colour changed`; `All tests passed!`.

- [ ] **Step 3: Regenerate exactly the goldens it changes**

```bash
flutter test --no-pub --update-goldens test/features/auth/sign_up/account_check_step_test.dart test/features/auth/sign_up/w2a_goldens_test.dart test/features/auth/sign_up/w2b_goldens_test.dart test/features/auth/sign_up/w6/sign_up_dormancy_flow_test.dart test/features/opinions/w9/opinion_filter_ui_test.dart test/features/safety/w7/support_resources_v2_test.dart
git status --short -- '*.png' | grep '^ M' | sort
```

Expected: exactly these 36 modified files (the error lines and the support cards' emergency accents, now darker red), and no other golden:

```
 M test/features/auth/sign_up/goldens/guest_age_gate_error.rtl.png
 M test/features/auth/sign_up/goldens/guest_age_gate_error.scale1.0.png
 M test/features/auth/sign_up/goldens/guest_age_gate_error.scale1.3.png
 M test/features/auth/sign_up/goldens/guest_age_gate_error.scale2.0.png
 M test/features/auth/sign_up/goldens/step_account_check.rtl.png
 M test/features/auth/sign_up/goldens/step_account_check.scale1.0.png
 M test/features/auth/sign_up/goldens/step_account_check.scale1.3.png
 M test/features/auth/sign_up/goldens/step_account_check.scale2.0.png
 M test/features/auth/sign_up/goldens/step_code.rtl.png
 M test/features/auth/sign_up/goldens/step_code.scale1.0.png
 M test/features/auth/sign_up/goldens/step_code.scale1.3.png
 M test/features/auth/sign_up/goldens/step_code.scale2.0.png
 M test/features/auth/sign_up/goldens/step_phone.rtl.png
 M test/features/auth/sign_up/goldens/step_phone.scale1.0.png
 M test/features/auth/sign_up/goldens/step_phone.scale1.3.png
 M test/features/auth/sign_up/w6/goldens/step_dormant_error.rtl.png
 M test/features/auth/sign_up/w6/goldens/step_dormant_error.scale1.0.png
 M test/features/auth/sign_up/w6/goldens/step_dormant_error.scale1.3.png
 M test/features/auth/sign_up/w6/goldens/step_dormant_error.scale2.0.png
 M test/features/opinions/w9/goldens/content_filter_notice.rtl.png
 M test/features/opinions/w9/goldens/content_filter_notice.scale1.0.png
 M test/features/opinions/w9/goldens/content_filter_notice.scale1.3.png
 M test/features/opinions/w9/goldens/content_filter_notice.scale2.0.png
 M test/features/safety/w7/goldens/support_v2_ghana.rtl.png
 M test/features/safety/w7/goldens/support_v2_ghana.scale1.0.png
 M test/features/safety/w7/goldens/support_v2_ghana.scale1.3.png
 M test/features/safety/w7/goldens/support_v2_ghana_cards.rtl.png
 M test/features/safety/w7/goldens/support_v2_ghana_cards.scale1.0.png
 M test/features/safety/w7/goldens/support_v2_ghana_cards.scale2.0.png
 M test/features/safety/w7/goldens/support_v2_grief.rtl.png
 M test/features/safety/w7/goldens/support_v2_grief.scale1.0.png
 M test/features/safety/w7/goldens/support_v2_grief.scale1.3.png
 M test/features/safety/w7/goldens/support_v2_grief.scale2.0.png
 M test/features/safety/w7/goldens/support_v2_unsupported.rtl.png
 M test/features/safety/w7/goldens/support_v2_unsupported.scale1.0.png
 M test/features/safety/w7/goldens/support_v2_unsupported.scale1.3.png
```

Open three (Read tool): `step_code.scale1.0.png`, `content_filter_notice.scale1.0.png`, `support_v2_ghana.scale1.0.png`: only the red changed. `content_filter_notice` is a W9 Opinions golden but not a flag-off one; W9's `flag_off_*` goldens don't change.

- [ ] **Step 4: Regression**

```bash
flutter test --no-pub 2>&1 | tail -1
```

Expected: `All tests passed!` with Task 1's count plus every test added so far.

### Task 8: `TextScalePolicy`, the root clamp, and the cap (§2.5 `text_scale_v2`; §5.1, §5.2; §8 W10a; P-6 to P-9)

**Files:**
- Create: `lib/app/text_scale_policy.dart`, `test/app/text_scale_policy_test.dart`, `test/app/app_shell_text_scale_test.dart`, `test/architecture/text_scale_routes_test.dart`, `test/accessibility/w10/in_chat_games_large_text_test.dart`
- Modify: `lib/app/app_shell.dart`, `lib/app/app.dart` (by `$D/t8_shell_edits.py`), `test/accessibility/large_text_test.dart` (one test, by `$D/t8_large_text_test.py`)

**Interfaces:**
- Consumes: `publicAppConfigProvider`, `cachedPublicAppConfigProvider`, `GoRouter.routerDelegate`, Task 1's audit helpers, the in-chat Games widgets (read only).
- Produces (`package:attune/app/text_scale_policy.dart`): `TextScalePolicy.offCap` (1.0), `TextScalePolicy.v2Cap` (1.0 until owner question 1, then 2.0), `candidateCaps` (`[2.0, 1.6, 1.3]`), `gameRoutePrefixes`, `auditedRoutePrefixes`, `keepsDefaultSize(String location) -> bool`, `capFor({required double cap, required String? topLocation}) -> double`, `topLocation(GoRouter) -> String?`; `textScaleV2Provider` (`Provider<bool>`), `textScaleCapProvider` (`Provider<double>`); `RootTextScaleClamp({required GoRouter router, required double cap, required Widget child})`; `appShell({required GoRouter router, required Widget child, double maxTextScale = TextScalePolicy.offCap})`.

- [ ] **Step 1: Write the failing tests**

Create `test/app/text_scale_policy_test.dart` with exactly:

```dart
// Spec 1 §2.3, §2.5 (W10a): the root text clamp follows text_scale_v2,
// keeps 1.0 on Games routes and on routes the audit hasn't checked, and
// never stops AllowLargeText reaching 2.0.
import 'package:attune/app/text_scale_policy.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Gateway implements PublicAppConfigGateway {
  _Gateway(this.on);
  final bool on;
  @override
  Future<Map<String, dynamic>> fetch() async => {
    'flags': {'text_scale_v2': on},
    'config': <String, dynamic>{},
  };
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => taps++),
    child: Text('taps $taps'),
  );
}

double _scaleOf(WidgetTester t, Finder f) =>
    MediaQuery.textScalerOf(t.element(f)).scale(10) / 10;

class _App extends StatelessWidget {
  const _App({required this.router, required this.cap});
  final GoRouter router;
  final double cap;
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    builder:
        (context, child) =>
            RootTextScaleClamp(router: router, cap: cap, child: child!),
  );
}

Future<GoRouter> _pump(
  WidgetTester t,
  double cap, {
  double system = 2.0,
  String initial = '/home',
}) async {
  t.platformDispatcher.textScaleFactorTestValue = system;
  addTearDown(t.platformDispatcher.clearAllTestValues);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: _Counter()),
      ),
      GoRoute(
        path: '/games/snakes/:relationshipId',
        builder: (_, __) => const Scaffold(body: Text('board')),
      ),
      GoRoute(
        path: '/pulse',
        builder: (_, __) => const Scaffold(body: Text('pulse')),
      ),
      GoRoute(
        path: '/communityFeed',
        builder:
            (_, __) =>
                const Scaffold(body: AllowLargeText(child: Text('large'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(_App(router: router, cap: cap));
  await t.pumpAndSettle();
  return router;
}

void main() {
  group('TextScalePolicy.capFor', () {
    test('off keeps 1.0 everywhere', () {
      for (final at in ['/home', '/chatScreen', null]) {
        expect(TextScalePolicy.capFor(cap: 1.0, topLocation: at), 1.0);
      }
    });

    test('on: the audited routes get the cap', () {
      for (final at in [
        '/home',
        '/chatScreen',
        '/chat-channel',
        '/commentThread',
        '/planning/entry',
        '/together',
        '/settings/quiet',
        '/healingStage',
        '/journalEntry',
        '/about-us/r1',
      ]) {
        expect(
          TextScalePolicy.capFor(cap: 1.6, topLocation: at),
          1.6,
          reason: at,
        );
      }
      expect(TextScalePolicy.capFor(cap: 1.6, topLocation: null), 1.6);
    });

    test('on: Games routes keep 1.0', () {
      for (final at in [
        '/games/snakes/r1',
        '/games/paint-ball/battle/s1',
        '/thirtySixQuestion',
        '/thirtySixQuestions',
        '/truthOrDareGame',
        '/customTruthOrDareList',
        '/truthReveal',
        '/dareReveal',
        '/thisOrThatGamesHub',
        '/customQuestionCreate',
        '/mirrorGame',
        '/slidingScaleGame',
        '/scenarioGame',
        '/loveMap',
      ]) {
        expect(
          TextScalePolicy.capFor(cap: 2.0, topLocation: at),
          1.0,
          reason: at,
        );
      }
    });

    test('on: routes not audited yet keep 1.0, a new one included', () {
      for (final at in [
        '/pulse',
        '/communityFeed',
        '/quizEntry',
        '/dating-mode',
        '/chatInsights',
        '/notificationInbox',
        '/somewhere-new',
      ]) {
        expect(
          TextScalePolicy.capFor(cap: 2.0, topLocation: at),
          1.0,
          reason: at,
        );
      }
    });

    test('the cap is one of the candidates, or off', () {
      expect([
        ...TextScalePolicy.candidateCaps,
        TextScalePolicy.offCap,
      ], contains(TextScalePolicy.v2Cap));
    });
  });

  testWidgets('cap 1.0: the phone size never reaches a route', (t) async {
    await _pump(t, 1.0);
    expect(_scaleOf(t, find.byType(_Counter)), 1.0);
  });

  testWidgets('cap on: an audited route gets the phone size up to the cap', (
    t,
  ) async {
    await _pump(t, 1.6);
    expect(_scaleOf(t, find.byType(_Counter)), 1.6);
    await _pump(t, 1.6, system: 1.15);
    expect(_scaleOf(t, find.byType(_Counter)), 1.15);
  });

  testWidgets('a pushed Games route keeps 1.0, and popping restores', (
    t,
  ) async {
    final router = await _pump(t, 2.0);
    router.push('/games/snakes/r1');
    await t.pumpAndSettle();
    expect(_scaleOf(t, find.text('board')), 1.0);
    router.pop();
    await t.pumpAndSettle();
    expect(_scaleOf(t, find.byType(_Counter)), 2.0);
    router.go('/pulse');
    await t.pumpAndSettle();
    expect(_scaleOf(t, find.text('pulse')), 1.0, reason: 'not audited');
  });

  testWidgets('a deep link straight into a Games route settles at 1.0', (
    t,
  ) async {
    // The first route arrives while the Navigator below is building; the
    // clamp above it changes after that frame, without an error.
    await _pump(t, 2.0, initial: '/games/snakes/r1');
    expect(t.takeException(), isNull);
    expect(_scaleOf(t, find.text('board')), 1.0);
  });

  testWidgets('AllowLargeText still reaches 2.0, whatever the root says', (
    t,
  ) async {
    for (final cap in [1.0, 1.3]) {
      final router = await _pump(t, cap);
      router.go('/communityFeed');
      await t.pumpAndSettle();
      expect(_scaleOf(t, find.text('large')), 2.0, reason: 'cap $cap');
    }
  });

  testWidgets('switching the cap keeps the screen below (no rebuild)', (
    t,
  ) async {
    final router = await _pump(t, 1.0);
    await t.tap(find.byType(TextButton));
    await t.pump();
    expect(find.text('taps 1'), findsOneWidget);
    await t.pumpWidget(_App(router: router, cap: 2.0));
    await t.pump();
    expect(find.text('taps 1'), findsOneWidget, reason: 'state kept');
    expect(_scaleOf(t, find.byType(_Counter)), 2.0);
  });

  group('textScaleCapProvider', () {
    Future<ProviderContainer> container({
      required bool live,
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          publicAppConfigGatewayProvider.overrideWithValue(_Gateway(live)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('off until read, then follows the flag', () async {
      final c = await container(live: true);
      expect(c.read(textScaleV2Provider), isFalse);
      await c.read(publicAppConfigProvider.future);
      expect(c.read(textScaleV2Provider), isTrue);
      expect(c.read(textScaleCapProvider), TextScalePolicy.v2Cap);
    });

    test('the flag off keeps 1.0', () async {
      final c = await container(live: false);
      await c.read(publicAppConfigProvider.future);
      expect(c.read(textScaleV2Provider), isFalse);
      expect(c.read(textScaleCapProvider), TextScalePolicy.offCap);
    });

    test('the cached copy decides before the first answer', () async {
      final c = await container(
        live: false,
        prefs: {
          PublicAppConfigCache.key:
              '{"flags":{"text_scale_v2":true},"storefronts":[],"open_countries":[]}',
        },
      );
      expect(c.read(textScaleV2Provider), isTrue);
      await c.read(publicAppConfigProvider.future);
      expect(c.read(textScaleV2Provider), isFalse);
    });
  });
}
```

Create `test/architecture/text_scale_routes_test.dart` with exactly:

```dart
// Spec 1 §8 W10a: TextScalePolicy keeps every Games route at 1.0 through its
// route prefixes, and every route the audit hasn't checked; every other
// route gets the cap. The Games routes are found from app_router.dart itself
// (every GoRoute whose builder uses a class imported from
// lib/features/games/), so a Games route added later fails here until its
// prefix is listed. No Games file is edited.
import 'dart:io';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/text_scale_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Routes outside the W10a audit (they keep 1.0 until they are audited and
/// their prefix is added to TextScalePolicy.auditedRoutePrefixes).
const _notYetAudited = {
  'intro',
  'login',
  'profile',
  'pulse',
  'chatInsights',
  'chatImport',
  'weeklyCheckin',
  'checkinComplete',
  'logMomentType',
  'logMomentDetails',
  'quizEntry',
  'attachmentQuiz',
  'attachmentQuizLoading',
  'attachmentQuizResult',
  'conflictStyleQuiz',
  'conflictStyleLoading',
  'conflictStyleResult',
  'loveLanguageQuiz',
  'loveLanguageResult',
  'communicationStyleQuiz',
  'communicationStyleLoading',
  'communicationStyleResult',
  'partnerQuizResult',
  'datingConsent',
  'datingProfile',
  'datingMatches',
  'datingGuidedDate',
  'datingPhotos',
  'datingVerification',
  'datingMode',
  'communityFeed',
  'notificationInbox',
  'previousRelationships',
};

/// Every class declared in the Games files app_router.dart imports.
Set<String> _gamesClasses(String router) {
  final classes = <String>{};
  final imports = RegExp(
    r"import 'package:attune/(features/games/[^']+)';",
  ).allMatches(router);
  for (final m in imports) {
    final src = File('lib/${m.group(1)}').readAsStringSync();
    classes.addAll(
      RegExp(
        r'^class (\w+)',
        multiLine: true,
      ).allMatches(src).map((c) => c.group(1)!),
    );
  }
  return classes;
}

/// Every `GoRoute(...)` call in [src], whole (parentheses matched; string
/// literals and // comments skipped); nested routes are found too.
List<String> _goRouteBlocks(String src) {
  final blocks = <String>[];
  var from = 0;
  while (true) {
    final start = src.indexOf('GoRoute(', from);
    if (start < 0) return blocks;
    var i = start + 'GoRoute'.length;
    var depth = 0;
    while (i < src.length) {
      final c = src[i];
      if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
        i = src.indexOf('\n', i);
        if (i < 0) i = src.length;
        continue;
      }
      if (c == "'" || c == '"') {
        i++;
        while (i < src.length && src[i] != c) {
          if (src[i] == r'\') i++;
          i++;
        }
        i++;
        continue;
      }
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) break;
      }
      i++;
    }
    blocks.add(src.substring(start, i + 1));
    from = start + 'GoRoute('.length;
  }
}

Map<String, String> _namedPaths(List<RouteBase> routes) => {
  for (final route in routes) ...{
    if (route is GoRoute && route.name != null) route.name!: route.path,
    ..._namedPaths(route.routes),
  },
};

/// A concrete location for [path] (`:id` filled in).
String _location(String path) => path.replaceAll(RegExp(r':\w+'), 'x');

bool _gamesPrefix(String location) =>
    TextScalePolicy.gameRoutePrefixes.any(location.startsWith);

void main() {
  final src = File('lib/app/routing/app_router.dart').readAsStringSync();
  final games = _gamesClasses(src);
  final gamesRouteNames = <String>{};
  for (final block in _goRouteBlocks(src)) {
    final name = RegExp(r"name:\s*'([^']+)'").firstMatch(block)?.group(1);
    final usesGames = games.any(
      (c) => RegExp('\\b${RegExp.escape(c)}\\(').hasMatch(block),
    );
    if (name != null && usesGames) gamesRouteNames.add(name);
  }
  final router = createAppRouter(RoutingNotifier());
  final paths = _namedPaths(router.configuration.routes);
  router.dispose();

  test('the Games routes are found (39 today)', () {
    expect(games, isNotEmpty);
    expect(gamesRouteNames.length, greaterThanOrEqualTo(39));
    expect(paths.keys, containsAll(gamesRouteNames));
    expect(paths.keys, containsAll(_notYetAudited));
  });

  test('every Games route keeps 1.0 through a Games prefix', () {
    for (final name in gamesRouteNames) {
      final at = _location(paths[name]!);
      expect(_gamesPrefix(at), isTrue, reason: '$name ($at): add its prefix');
      expect(TextScalePolicy.keepsDefaultSize(at), isTrue, reason: name);
    }
  });

  test('no Games prefix matches a route that is not a Games route', () {
    for (final MapEntry(key: name, value: path) in paths.entries) {
      if (gamesRouteNames.contains(name)) continue;
      expect(_gamesPrefix(_location(path)), isFalse, reason: '$name ($path)');
    }
  });

  test('only the routes not audited yet keep 1.0; the rest get the cap', () {
    for (final MapEntry(key: name, value: path) in paths.entries) {
      if (gamesRouteNames.contains(name)) continue;
      expect(
        TextScalePolicy.keepsDefaultSize(_location(path)),
        _notYetAudited.contains(name),
        reason: '$name ($path)',
      );
    }
  });
}
```

Create `test/app/app_shell_text_scale_test.dart` with exactly:

```dart
// Spec 1 W10a (§5.2): the root shell's text clamp is RootTextScaleClamp with
// the cap from textScaleCapProvider; the fixed 1.0 clamp is gone.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app_shell.dart clamps through RootTextScaleClamp', () {
    final shell = File('lib/app/app_shell.dart').readAsStringSync();
    expect(shell, contains('RootTextScaleClamp('));
    expect(shell, contains('cap: maxTextScale,'));
    expect(shell, isNot(contains('maxScaleFactor: 1.0')));
  });

  test('app.dart passes the cap from textScaleCapProvider', () {
    final app = File('lib/app/app.dart').readAsStringSync();
    expect(app, contains('ref.watch(textScaleCapProvider)'));
    expect(app, contains('maxTextScale: textScaleCap,'));
  });
}
```

Run: `flutter test --no-pub test/app/text_scale_policy_test.dart test/architecture/text_scale_routes_test.dart test/app/app_shell_text_scale_test.dart`
Expected: the first two fail to compile (`Error when reading 'lib/app/text_scale_policy.dart'`); the third fails (`Expected: contains 'RootTextScaleClamp('`).

- [ ] **Step 2: Create `lib/app/text_scale_policy.dart`** with exactly:

```dart
import 'package:attune/core/flags/public_app_config.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// How far the phone's own text size reaches the app (Spec 1 §2.3, §2.5,
/// §5.1, W10a).
///
/// With `text_scale_v2` off the root clamps every route to 1.0, as it always
/// has. With it on, the root lets the phone's text size through up to
/// [v2Cap] on the routes the W10a audit checked, and keeps 1.0 everywhere
/// else: on the Games routes (no Games file is edited, so their screens keep
/// the size they were built for) and on any route not audited yet (a new
/// route is audited before it gets large text). Screens wrapped in
/// `AllowLargeText` read the phone's size themselves either way.
abstract final class TextScalePolicy {
  /// The root clamp while `text_scale_v2` is off: today's.
  static const double offCap = 1.0;

  /// The root clamp while `text_scale_v2` is on: the highest of 2.0, 1.6 and
  /// 1.3 at which every audited surface, the in-chat Games surfaces
  /// included, passed (W10a Task 8). 1.0 while none of them does.
  static const double v2Cap = 1.0;

  /// The caps the audit tries, highest first.
  static const List<double> candidateCaps = [2.0, 1.6, 1.3];

  /// Location prefixes of the Games routes in `app_router.dart`: always 1.0.
  /// `test/architecture/text_scale_routes_test.dart` checks this list
  /// against every Games route in the router.
  static const List<String> gameRoutePrefixes = [
    '/thirtySix',
    '/truthOrDare',
    '/customTruthOrDare',
    '/truthReveal',
    '/dareReveal',
    '/thisOrThat',
    '/customQuestion',
    '/mirrorGame',
    '/slidingScaleGame',
    '/scenarioGame',
    '/loveMap',
    '/games/',
  ];

  /// Location prefixes of the routes the W10a audit checked: home (Opinions,
  /// Chat or Me), the Spec 1 screens, chat, Opinions, Together and Planning,
  /// Settings, Healing and the journal. Every other route keeps 1.0.
  static const List<String> auditedRoutePrefixes = [
    '/home',
    '/welcome',
    '/signup',
    '/guest-age',
    '/invite',
    '/age-stop',
    '/onboarding',
    '/join-invite',
    '/about-us/',
    '/chatScreen',
    '/chat-',
    '/starred-messages',
    '/image-caption',
    '/video-trim',
    '/ephemeral-camera',
    '/streak-camera',
    '/image-viewer',
    '/video-viewer',
    '/ephemeral-video-viewer',
    '/commentThread',
    '/editOpinion',
    '/quoteCompose',
    '/opinionEngagement',
    '/tagBrowse',
    '/opinionLoader',
    '/anonymousProfile',
    '/together',
    '/planning',
    '/timeline',
    '/couples-calendar/',
    '/appreciation-jar',
    '/settings',
    '/language',
    '/theme',
    '/licenses',
    '/safety-resources',
    '/support/',
    '/allLegalDocumentation',
    '/appInfoScreen',
    '/blockedAccountsScreen',
    '/mutedAuthorsScreen',
    '/neutralScreen',
    '/healingJourney',
    '/healingStage',
    '/reflectionJournal',
    '/journalEntry',
  ];

  /// Whether [location] (a matched location such as `/games/snakes/abc`)
  /// keeps 1.0 whatever the flag says: a Games route, or one not audited.
  static bool keepsDefaultSize(String location) =>
      gameRoutePrefixes.any(location.startsWith) ||
      !auditedRoutePrefixes.any(location.startsWith);

  /// The root clamp for the route on top: [cap] (from [textScaleCapProvider])
  /// on an audited route, else 1.0. Before the first route is matched (the
  /// very first frame) it is [cap], so the usual start on home doesn't
  /// reflow a frame later.
  static double capFor({required double cap, required String? topLocation}) {
    if (cap <= offCap) return offCap;
    if (topLocation == null) return cap;
    return keepsDefaultSize(topLocation) ? offCap : cap;
  }

  /// The matched location of the route on top of [router], pushed routes
  /// included (GoRouter 10 leaves `uri` on the last `go`, so a pushed Games
  /// route would not show there). Null while nothing is matched.
  static String? topLocation(GoRouter router) {
    final matches = router.routerDelegate.currentConfiguration;
    if (matches.isEmpty) return null;
    return matches.last.matchedLocation;
  }
}

/// `text_scale_v2`, effective (the server applies no dependency to it): the
/// live public config, else its cached copy, else off.
final textScaleV2Provider = Provider<bool>((ref) {
  final live = ref.watch(
    publicAppConfigProvider.select((config) => config.valueOrNull?.textScaleV2),
  );
  return live ?? ref.watch(cachedPublicAppConfigProvider)?.textScaleV2 ?? false;
});

/// The root cap: [TextScalePolicy.v2Cap] while `text_scale_v2` is on, else
/// 1.0.
final textScaleCapProvider = Provider<double>(
  (ref) =>
      ref.watch(textScaleV2Provider)
          ? TextScalePolicy.v2Cap
          : TextScalePolicy.offCap,
);

/// The root shell's text clamp. The same widgets whatever the cap (only the
/// number changes), so a flag change mid-session never rebuilds the
/// Navigator below it. It follows the route on top: a pushed Games route
/// gets 1.0, and popping it brings the cap back.
class RootTextScaleClamp extends StatefulWidget {
  const RootTextScaleClamp({
    super.key,
    required this.router,
    required this.cap,
    required this.child,
  });

  final GoRouter router;
  final double cap;
  final Widget child;

  @override
  State<RootTextScaleClamp> createState() => _RootTextScaleClampState();
}

class _RootTextScaleClampState extends State<RootTextScaleClamp> {
  late double _scale = _compute();

  double _compute() => TextScalePolicy.capFor(
    cap: widget.cap,
    topLocation: TextScalePolicy.topLocation(widget.router),
  );

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_routeChanged);
  }

  @override
  void didUpdateWidget(covariant RootTextScaleClamp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_routeChanged);
      widget.router.routerDelegate.addListener(_routeChanged);
    }
    _scale = _compute();
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_routeChanged);
    super.dispose();
  }

  /// The router can announce a new route while the Navigator below is
  /// building (the first route, a redirect); this widget is above it, so the
  /// change waits for the end of that frame.
  void _routeChanged() {
    if (!mounted || _compute() == _scale) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _scale = _compute());
      });
      return;
    }
    setState(() => _scale = _compute());
  }

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: _scale,
    child: widget.child,
  );
}
```

- [ ] **Step 3: Wire it into the shell**

Create `$D/t8_shell_edits.py` with exactly:

```python
# Spec 1 W10a Task 8: the root clamp follows TextScalePolicy.
import sys
sys.path.insert(0, sys.argv[1])
from edit_lib import replace, add_import
p = 'lib/app/app_shell.dart'
replace(p, "Widget appShell({required GoRouter router, required Widget child}) {",
        "///\n"
        "/// [maxTextScale] is the root text clamp (Spec 1 W10a): 1.0 unless\n"
        "/// `text_scale_v2` is on (textScaleCapProvider); RootTextScaleClamp keeps\n"
        "/// Games and not-yet-audited routes at 1.0 whatever it says.\n"
        "Widget appShell({\n"
        "  required GoRouter router,\n"
        "  required Widget child,\n"
        "  double maxTextScale = TextScalePolicy.offCap,\n"
        "}) {")
replace(p, """              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.0,
                child: child,
              ),""", """              child: RootTextScaleClamp(
                router: router,
                cap: maxTextScale,
                child: child,
              ),""")
add_import(p, "import 'package:attune/app/text_scale_policy.dart';")
p = 'lib/app/app.dart'
replace(p, "    final locale = ref.watch(currentLocaleProvider);\n",
        "    final locale = ref.watch(currentLocaleProvider);\n"
        "    // Spec 1 W10a: the root text clamp (1.0 unless text_scale_v2 is on).\n"
        "    final textScaleCap = ref.watch(textScaleCapProvider);\n")
replace(p, """                child: appShell(
                  router: router,
                  child: child ?? const SizedBox.shrink(),
                ),""", """                child: appShell(
                  router: router,
                  maxTextScale: textScaleCap,
                  child: child ?? const SizedBox.shrink(),
                ),""")
add_import(p, "import 'package:attune/app/text_scale_policy.dart';")
print('shell wired')
```

Run: `python3 $D/t8_shell_edits.py $D && flutter test --no-pub test/app/text_scale_policy_test.dart test/architecture/text_scale_routes_test.dart test/app/app_shell_text_scale_test.dart test/architecture/games_untouched_test.dart test/features/safety/quick_exit_wiring_test.dart 2>&1 | tail -1`
Expected: `shell wired`; `All tests passed!` (the 20 new tests, the Games guard and the quick-exit wiring test, which still finds `appShell(` in `app.dart`).

- [ ] **Step 4: Extend Spec 5's large-text test**

Create `$D/t8_large_text_test.py` with exactly:

```python
# Spec 1 W10a Task 8: extend Spec 5's large_text_test.dart (§8 W10a "Tests").
import sys
sys.path.insert(0, sys.argv[1])
from edit_lib import replace
p = 'test/accessibility/large_text_test.dart'
replace(p, "  testWidgets('Stagger renders at rest under reduced motion (I7)', (t) async {",
"""  testWidgets('W10a: a row keeps a long trailing value and wraps at 2x', (t) async {
    Widget row() => InfoRowWidget(
      icon: Icons.notifications_none,
      title: 'Remind me to write',
      subtitle: _long,
      trailing: const Text('Sundays at 9:45 PM'),
      onTap: () {},
    );
    await _pump(t, row());
    expect(t.takeException(), isNull);
    expect(t.widget<Text>(find.text(_long)).maxLines, 6);
    await _pump(t, row(), scale: 1.0);
    expect(t.widget<Text>(find.text(_long)).maxLines, 3);
  });

  testWidgets('Stagger renders at rest under reduced motion (I7)', (t) async {""")
print('large_text_test extended')
```

Run: `python3 $D/t8_large_text_test.py $D && flutter test --no-pub test/accessibility/large_text_test.dart 2>&1 | tail -1`
Expected: `large_text_test extended`; `All tests passed!` (`+7`; red before Tasks 5 and 6, green after).

- [ ] **Step 5: Measure the in-chat Games surfaces**

Create `test/accessibility/w10/in_chat_games_large_text_test.dart` with exactly:

```dart
// Spec 1 §8 W10a: the in-chat Games surfaces (the games sheet from the
// composer, the game card and its trail in the thread, the staged game
// above the composer) get the root cap, because they open over the chat,
// not on a Games route. No Games file is edited, so the cap may only be
// one at which they show no overflow they don't already show at 1.0.
//
// "the measurement" prints, for each phone and text size, the overflows
// that 1.0 doesn't already have (Task 9 reads it to choose the cap); it
// never fails. "the chosen cap" fails if TextScalePolicy.v2Cap lets them
// overflow.
import 'package:attune/app/text_scale_policy.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/games/invites/presentation/game_composer_bar.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:attune/features/games/presentation/widgets/game_trail_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/chat/support/chat_test_harness.dart';
import 'support/large_text_audit.dart';

/// Every size from 1.0 to the highest candidate in 0.05 steps (the phone's
/// own sizes fall between the candidates: Android 1.15, iOS 1.12, 1.24...).
final _steps = [for (var i = 0; i <= 20; i++) 1.0 + i * 0.05];

/// Phones the sheet is checked on, narrowest first.
const _phones = [
  Size(360, 800),
  Size(375, 667),
  Size(390, 844),
  Size(412, 915),
];

Message _game(String id, {required bool mine}) => Message(
  id: id,
  clientMessageId: 'c-$id',
  relationshipId: 'r1',
  senderId: mine ? 'me' : 'partner',
  content: 'Snakes and Ladders',
  createdAt: DateTime(2026, 11, 1),
  status: MessageStatus.delivered,
  isMine: mine,
  mediaType: 'game',
  gameSessionId: 's-$id',
);

Future<Set<String>> _overflowsAt(WidgetTester t, Size phone, double scale) {
  setPhone(t, phone, scale);
  return collectOverflows(() async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          activeGamesProvider.overrideWith(
            (ref) async => [
              {
                'id': 'a1',
                'game_type': 'snakes_and_ladders',
                'status': 'active',
                'current_turn_user_id': 'me',
                'updated_at': '2026-11-01T10:00:00Z',
                'created_at': '2026-11-01T10:00:00Z',
              },
            ],
          ),
          recentGamesProvider.overrideWith((ref) async => const []),
          gameSessionEventsProvider.overrideWith((ref) => const Stream.empty()),
          gameCardProvider.overrideWith(
            (ref, id) => Stream.value(
              const GameCardState(
                gameType: 'snakes_and_ladders',
                status: 'active',
                currentTurnUserId: 'me',
                winnerUserId: null,
                currentRound: 3,
                totalRounds: 10,
              ),
            ),
          ),
        ],
        child: withScreenUtil(
          MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // The root cap under check, as app_shell.dart applies it.
            builder:
                (context, child) => MediaQuery.withClampedTextScaling(
                  maxScaleFactor: scale,
                  child: child!,
                ),
            home: Builder(
              builder:
                  (context) => Scaffold(
                    body: ListView(
                      children: [
                        TextButton(
                          onPressed:
                              () => showChatGamesPicker(
                                context,
                                relationshipId: 'r1',
                                onStageNewGame: (_) {},
                              ),
                          child: const Text('open games'),
                        ),
                        MessageBubble(
                          message: _game('g1', mine: true),
                          currentUserId: 'me',
                          viewerUserId: 'me',
                        ),
                        MessageBubble(
                          message: _game('g2', mine: false),
                          currentUserId: 'me',
                          viewerUserId: 'me',
                        ),
                        const GameTrailLine(
                          label: 'You moved to square 42 in Snakes and Ladders',
                          isMine: true,
                        ),
                        GameComposerBar(
                          relationshipId: 'r1',
                          gameType: 'snakes_and_ladders',
                          onCancel: () {},
                        ),
                      ],
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    await settle(t, const Duration(milliseconds: 500));
    await t.tap(find.text('open games'));
    await settle(t, const Duration(milliseconds: 1200));
    await scrollToEnd(t);
    await t.pumpWidget(const SizedBox());
    await settle(t, const Duration(seconds: 1));
  }).then((list) => list.toSet());
}

void main() {
  group('the measurement', () {
    for (final phone in _phones) {
      testWidgets('${phone.width.toInt()} x ${phone.height.toInt()}', (
        t,
      ) async {
        final atOne = await _overflowsAt(t, phone, 1.0);
        final lines = <String>[];
        for (final scale in _steps.skip(1)) {
          final extra = (await _overflowsAt(t, phone, scale)).difference(atOne);
          if (extra.isNotEmpty) {
            lines.add('  ${scale.toStringAsFixed(2)}: ${extra.join(', ')}');
          }
        }
        // ignore: avoid_print
        print(
          'IN-CHAT GAMES ${phone.width.toInt()}x${phone.height.toInt()} '
          '(at 1.0: ${atOne.isEmpty ? 'none' : atOne.join(', ')})\n'
          '${lines.isEmpty ? '  no new overflow up to 2.0' : lines.join('\n')}',
        );
      });
    }
  });

  group('the chosen cap', () {
    for (final phone in _phones) {
      testWidgets(
        '${phone.width.toInt()} wide: nothing new up to ${TextScalePolicy.v2Cap}',
        (t) async {
          final atOne = await _overflowsAt(t, phone, 1.0);
          for (final scale in _steps.where((s) => s <= TextScalePolicy.v2Cap)) {
            final extra = (await _overflowsAt(
              t,
              phone,
              scale,
            )).difference(atOne);
            expect(extra, isEmpty, reason: 'at ${scale.toStringAsFixed(2)}');
          }
        },
      );
    }
  });
}
```

Run: `flutter test --no-pub test/accessibility/w10/in_chat_games_large_text_test.dart 2>&1 | grep -E 'IN-CHAT|^  [0-9]\.|no new|All tests|Some tests' | tee $D/in-chat-games.txt`
Expected (P-8), with no Games file edited:

```
IN-CHAT GAMES 360x800 (at 1.0: lib/features/games/presentation/widgets/game_grid_tile.dart:50)
  1.30: lib/features/games/presentation/widgets/chat_games_sheet.dart:625
  ... (every step to 2.00, the same line)
IN-CHAT GAMES 375x667 (at 1.0: none)
  1.15: lib/features/games/presentation/widgets/game_grid_tile.dart:50
  ... (1.20-1.30 the tile, 1.35-2.00 the section label)
IN-CHAT GAMES 390x844 (at 1.0: none)
  1.30: lib/features/games/presentation/widgets/game_grid_tile.dart:50
  1.40: lib/features/games/presentation/widgets/chat_games_sheet.dart:625
  ...
IN-CHAT GAMES 412x915 (at 1.0: none)
  1.50: lib/features/games/presentation/widgets/chat_games_sheet.dart:625
  ...
All tests passed!
```

("the chosen cap" passes because `v2Cap` is 1.0.)

- [ ] **Step 6: Choose the cap**

The rule (§8 W10a): the highest of 2.0, 1.6 and 1.3 at which every audited surface passes (Tasks 3-6: all pass at all three) **and** the in-chat Games surfaces show no overflow they don't already show at 1.0 at any size up to it (Step 5). With Step 5's result, none passes: `v2Cap` stays `1.0` as Step 2 wrote it, and the task report says "cap 1.0: the in-chat Games sheet (P-8); owner question 1". Only if the owner has approved and applied owner question 1's Games change (in its own Games changeset, never by this plan) and Step 5 then prints `no new overflow up to 2.0` for every phone, set the cap:

```bash
python3 - <<'PY'
import sys; sys.path.insert(0, '.superpowers/sdd/2026-11-04-spec1-w10')
from edit_lib import replace
replace('lib/app/text_scale_policy.dart', "  static const double v2Cap = 1.0;", "  static const double v2Cap = 2.0;")
print('cap 2.0')
PY
flutter test --no-pub test/accessibility/w10/in_chat_games_large_text_test.dart test/app/text_scale_policy_test.dart 2>&1 | tail -1
```

Expected then: `cap 2.0`; `All tests passed!` ("the chosen cap" now steps to 2.0 on every phone).

- [ ] **Step 7: Mutants**

Run: `python3 $D/mutants.py no_lovemap_prefix games_prefix_too_wide pulse_marked_audited cap_everywhere top_from_uri set_state_in_build no_cached_flag`
Expected: seven lines, each `RED (caught)`.

- [ ] **Step 8: Format, analyze, and the W10a gate**

```bash
dart format --output=none --set-exit-if-changed lib/app/text_scale_policy.dart test/app/text_scale_policy_test.dart test/app/app_shell_text_scale_test.dart test/architecture/text_scale_routes_test.dart test/accessibility/w10/in_chat_games_large_text_test.dart
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*(error|warning) ' | sed 's/:[0-9]*:[0-9]* / /' | sort | comm -13 $D/analyze-baseline.txt -
flutter test --no-pub 2>&1 | tail -1
for s in 2.0 1.6 1.3; do python3 scripts/large_text_audit.py --scale $s test | tail -1; done
sed -n '/if (isAuthenticated && !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - $D/latch.sha && echo latch-unchanged
shasum -a 256 lib/features/auth/utility/auth_exports.dart | diff - $D/auth_exports.sha && echo auth-exports-unchanged
git status --short lib/features/games lib/app/routing/app_router.dart lib/features/auth/utility/auth_exports.dart supabase/migrations
```

Expected: `0 changed`; no line from `comm`; `All tests passed!` with Task 1's count plus 95 (99 with Task 7); `SCALE 2.0: 0 site(s) to fix, 25 listed apart`, `SCALE 1.6: 0 site(s) to fix, 17 listed apart`, `SCALE 1.3: 0 site(s) to fix, 6 listed apart` (listed apart: Games sites, Pulse's and the test-only lifecycle card; each run about 10 minutes on an idle machine); `latch-unchanged`; `auth-exports-unchanged`; nothing from the scoped status.

**W10a gate (spec: "the W10 group gate (under W10c)").** Nothing to switch: `text_scale_v2` is false in production and its production gate row needs the device matrix (Task 14, owner checklist 1). In development the dev script already has it on; with `v2Cap` 1.0 that changes nothing until owner question 1.

---

# W10b · Motion, RTL, first frame, size (Tasks 9-12)

### Task 9: Reduce motion, and the 900 ms deck advance (§2.2; §8 W10b; P-13, P-14)

**Files:**
- Modify: `lib/features/onboarding/presentation/widgets/onboarding_deck_card.dart` (by `$D/t9_deck.py`)
- Create: `test/accessibility/w10/deck_advance_motion_test.dart`, `test/architecture/spec1_rtl_motion_test.dart` (its motion half is checked here, its RTL half in Task 10)

**Interfaces:**
- Consumes: `kMakeRoomDuration` (`lib/core/ui/motion/motion_tokens.dart`), `reduceMotionOf`.
- Produces: `spec1Presentation` (the 71 Spec 1 presentation files, `test/architecture/spec1_rtl_motion_test.dart`).

- [ ] **Step 1: Write the failing test**

Create `test/accessibility/w10/deck_advance_motion_test.dart` with exactly:

```dart
// Spec 1 §2.2, W10b: the quiz deck advances in kMakeRoomDuration (320 ms),
// not 900 ms, and not at all under reduce motion.
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _flying = ValueKey<String>('deck-flying-card');

Widget _deck(int step, {bool reduceMotion = false}) => ScreenUtilConfig.builder(
  builder:
      (_) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            disableAnimations: reduceMotion,
          ),
          child: Scaffold(
            body: SizedBox(
              height: 700,
              child: OnboardingDeckCard(
                title: 'How you connect',
                subtitle: 'Question ${step + 1} of 10',
                stepIndex: step,
                enableDeck: true,
                totalSegments: 10,
                progressValue: (step + 1) / 10,
                child: Text('Question ${step + 1}'),
              ),
            ),
          ),
        ),
      ),
);

void main() {
  testWidgets('the deck advance takes kMakeRoomDuration (320 ms)', (t) async {
    expect(kMakeRoomDuration, const Duration(milliseconds: 320));
    await t.pumpWidget(_deck(0));
    await t.pumpAndSettle();
    await t.pumpWidget(_deck(1));
    await t.pump();
    expect(find.byKey(_flying), findsOneWidget);
    await t.pump(kMakeRoomDuration - const Duration(milliseconds: 20));
    expect(find.byKey(_flying), findsOneWidget, reason: 'still moving');
    await t.pump(const Duration(milliseconds: 40));
    expect(find.byKey(_flying), findsNothing, reason: 'settled by 320 ms');
    expect(find.text('Question 2'), findsOneWidget);
  });

  testWidgets('under reduce motion the next card is simply there', (t) async {
    await t.pumpWidget(_deck(0, reduceMotion: true));
    await t.pumpAndSettle();
    await t.pumpWidget(_deck(1, reduceMotion: true));
    await t.pump();
    expect(find.byKey(_flying), findsNothing);
    expect(find.text('Question 2'), findsOneWidget);
  });
}
```

Run: `flutter test --no-pub test/accessibility/w10/deck_advance_motion_test.dart`
Expected: `the deck advance takes kMakeRoomDuration (320 ms)` FAILS (`Expected: no matching candidates` with the reason `settled by 320 ms`: the 900 ms card is still flying); the reduce-motion test passes (today's behaviour).

- [ ] **Step 2: Cut the advance to 320 ms**

```bash
cat > $D/t9_deck.py <<'PY'
# Spec 1 §2.2 (W10b): the quiz deck advances in kMakeRoomDuration.
import sys
sys.path.insert(0, sys.argv[1])
from edit_lib import replace
p = 'lib/features/onboarding/presentation/widgets/onboarding_deck_card.dart'
replace(p, "  static const Duration _advanceDuration = Duration(milliseconds: 900);",
        "  // Spec 1 §2.2 (W10b): the 150-320 ms band, not 900 ms.\n"
        "  static const Duration _advanceDuration = kMakeRoomDuration;")
replace(p, "import 'package:attune/core/ui/motion/reduce_motion.dart';",
        "import 'package:attune/core/ui/motion/motion_tokens.dart';\n"
        "import 'package:attune/core/ui/motion/reduce_motion.dart';")
print('deck at 320 ms')
PY
python3 $D/t9_deck.py $D
flutter test --no-pub test/accessibility/w10/deck_advance_motion_test.dart test/features/onboarding 2>&1 | tail -1
```

Expected: `deck at 320 ms`; `All tests passed!` (the attachment quiz's deck tests included).

- [ ] **Step 3: The Spec 1 motion and RTL guard**

Create `test/architecture/spec1_rtl_motion_test.dart` with exactly:

```dart
// Spec 1 W10b (§2.2, §2.3): every Spec 1 screen and widget lays out by
// direction (start/end), never by physical side, so right-to-left text
// mirrors it; and every one that animates reads the phone's reduce-motion
// setting. The list is the presentation files Spec 1 created (W1-W9e); a
// file added to it later is checked the same way.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const spec1Presentation = <String>[
  'lib/core/notifications/presentation/widgets/push_ask_row.dart',
  'lib/core/ui/motion/shared_axis_step.dart',
  'lib/core/ui/text/allow_large_text.dart',
  'lib/features/auth/sign_up/presentation/screens/guest_age_gate_screen.dart',
  'lib/features/auth/sign_up/presentation/screens/invite_landing_screen.dart',
  'lib/features/auth/sign_up/presentation/screens/sign_up_flow.dart',
  'lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart',
  'lib/features/auth/sign_up/presentation/screens/welcome_screen.dart',
  'lib/features/auth/sign_up/presentation/sign_up_flags.dart',
  'lib/features/auth/sign_up/presentation/steps/account_check_step.dart',
  'lib/features/auth/sign_up/presentation/steps/birth_date_step.dart',
  'lib/features/auth/sign_up/presentation/steps/code_step.dart',
  'lib/features/auth/sign_up/presentation/steps/consent_step.dart',
  'lib/features/auth/sign_up/presentation/steps/dormant_step.dart',
  'lib/features/auth/sign_up/presentation/steps/fresh_start_step.dart',
  'lib/features/auth/sign_up/presentation/steps/name_step.dart',
  'lib/features/auth/sign_up/presentation/steps/no_account_step.dart',
  'lib/features/auth/sign_up/presentation/steps/phone_step.dart',
  'lib/features/auth/sign_up/presentation/widgets/flow_buttons.dart',
  'lib/features/auth/sign_up/presentation/widgets/flow_colors.dart',
  'lib/features/auth/sign_up/presentation/widgets/flow_frame.dart',
  'lib/features/auth/sign_up/presentation/widgets/flow_text_field.dart',
  'lib/features/auth/sign_up/presentation/widgets/join_attune_panel.dart',
  'lib/features/auth/sign_up/presentation/widgets/one_time_code_field.dart',
  'lib/features/auth/sign_up/presentation/widgets/path_preview_sheet.dart',
  'lib/features/auth/sign_up/presentation/widgets/submit_once.dart',
  'lib/features/couple_profile/presentation/about_us_copy.dart',
  'lib/features/couple_profile/presentation/about_us_entry.dart',
  'lib/features/couple_profile/presentation/couple_profile_providers.dart',
  'lib/features/couple_profile/presentation/screens/about_us_question_flow.dart',
  'lib/features/couple_profile/presentation/screens/about_us_screen.dart',
  'lib/features/couple_profile/presentation/widgets/about_us_card.dart',
  'lib/features/couple_profile/presentation/widgets/about_us_choice.dart',
  'lib/features/couple_profile/presentation/widgets/changed_by_line.dart',
  'lib/features/healing/presentation/providers/healing_support_providers.dart',
  'lib/features/healing/presentation/widgets/healing_support.dart',
  'lib/features/me/presentation/me_providers.dart',
  'lib/features/me/presentation/path_switch.dart',
  'lib/features/me/presentation/screens/me_home_screen.dart',
  'lib/features/me/presentation/widgets/dating_lock_setting.dart',
  'lib/features/me/presentation/widgets/dating_slot.dart',
  'lib/features/me/presentation/widgets/first_action_card.dart',
  'lib/features/me/presentation/widgets/healing_choice_sheet.dart',
  'lib/features/me/presentation/widgets/journal_reminder_row.dart',
  'lib/features/me/presentation/widgets/more_ways_sheet.dart',
  'lib/features/me/presentation/widgets/your_space_section.dart',
  'lib/features/onboarding/presentation/path_chooser.dart',
  'lib/features/onboarding/presentation/providers/flow_flags.dart',
  'lib/features/onboarding/presentation/providers/home_state_providers.dart',
  'lib/features/onboarding/presentation/screens/invite_partner_screen.dart',
  'lib/features/onboarding/presentation/screens/onboarding_gate_v2.dart',
  'lib/features/onboarding/presentation/widgets/catch_up_steps.dart',
  'lib/features/onboarding/presentation/widgets/invite_partner_step.dart',
  'lib/features/onboarding/presentation/widgets/path_step.dart',
  'lib/features/opinions/presentation/providers/opinions_safety_provider.dart',
  'lib/features/opinions/presentation/widgets/content_filter_notice.dart',
  'lib/features/opinions/presentation/widgets/need_support_link.dart',
  'lib/features/reflection_journal/presentation/providers/journal_support_providers.dart',
  'lib/features/reflection_journal/presentation/widgets/journal_support_card.dart',
  'lib/features/relationships/presentation/invite_error_copy.dart',
  'lib/features/relationships/presentation/invite_share_actions.dart',
  'lib/features/relationships/presentation/screens/join_invite_screen.dart',
  'lib/features/relationships/presentation/screens/relationship_space_screen.dart',
  'lib/features/relationships/presentation/widgets/linked_moment.dart',
  'lib/features/relationships/presentation/widgets/linked_moment_gate.dart',
  'lib/features/safety/presentation/providers/support_resources_providers.dart',
  'lib/features/safety/presentation/screens/report_child_concern_screen.dart',
  'lib/features/safety/presentation/screens/support_resources_v2_screen.dart',
  'lib/features/settings/presentation/screens/birth_date_settings_screen.dart',
  'lib/features/settings/presentation/screens/how_you_use_attune_screen.dart',
  'lib/home/widgets/home_tab_two.dart',
];

/// Physical-side layout that does not mirror under RTL.
final _physical = <String, RegExp>{
  'EdgeInsets.only(left:/right:)': RegExp(
    r'EdgeInsets\.only\([^)]*\b(left|right)\s*:',
  ),
  'Alignment left/right': RegExp(
    r'\bAlignment\.(centerLeft|centerRight|topLeft|topRight|bottomLeft|bottomRight)\b',
  ),
  'TextAlign.left/right': RegExp(r'\bTextAlign\.(left|right)\b'),
  'Positioned(left:/right:)': RegExp(r'Positioned\([^)]*\b(left|right)\s*:'),
};

/// EdgeInsets.fromLTRB with different left and right values.
final _ltrb = RegExp(
  r'EdgeInsets\.fromLTRB\(\s*([^,]+?)\s*,\s*[^,]+?\s*,\s*([^,]+?)\s*,',
);

final _animates = RegExp(
  r'\b(AnimationController|AnimatedContainer|AnimatedOpacity|'
  r'TweenAnimationBuilder|AnimatedSwitcher|AnimatedSize|AnimatedCrossFade|'
  r'AnimatedAlign|AnimatedPositioned|AnimatedScale|AnimatedSlide)\b',
);
final _readsReduceMotion = RegExp(
  r'reduceMotionOf\(|disableAnimations|\breduceMotion\b',
);

void main() {
  test('every listed file exists', () {
    for (final path in spec1Presentation) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('Spec 1 screens lay out by direction, not by side (RTL)', () {
    final found = <String>[];
    for (final path in spec1Presentation) {
      final src = File(path).readAsStringSync();
      for (final MapEntry(key: rule, value: re) in _physical.entries) {
        for (final m in re.allMatches(src)) {
          final line = src.substring(0, m.start).split('\n').length;
          found.add('$path:$line $rule');
        }
      }
      for (final m in _ltrb.allMatches(src)) {
        if (m.group(1) != m.group(2)) {
          final line = src.substring(0, m.start).split('\n').length;
          found.add('$path:$line EdgeInsets.fromLTRB, left != right');
        }
      }
    }
    expect(found, isEmpty);
  });

  test('Spec 1 widgets that animate read reduce motion', () {
    final found = <String>[];
    for (final path in spec1Presentation) {
      final src = File(path).readAsStringSync();
      if (_animates.hasMatch(src) && !_readsReduceMotion.hasMatch(src)) {
        found.add(path);
      }
    }
    expect(found, isEmpty);
  });
}
```

Run: `flutter test --no-pub test/architecture/spec1_rtl_motion_test.dart`
Expected: `All tests passed!` (`+3`): every Spec 1 widget that animates already reads reduce motion (P-14), and every Spec 1 file already lays out by direction (P-15).

- [ ] **Step 4: Mutants**

Run: `python3 $D/mutants.py deck_900 motion_ignores_reduce`
Expected: `deck_900: RED (caught)`, `motion_ignores_reduce: RED (caught)`.

- [ ] **Step 5: Format and analyze**

```bash
dart format --output=none --set-exit-if-changed test/accessibility/w10/deck_advance_motion_test.dart test/architecture/spec1_rtl_motion_test.dart
flutter analyze --no-pub lib/features/onboarding/presentation/widgets/onboarding_deck_card.dart test/accessibility/w10/deck_advance_motion_test.dart test/architecture/spec1_rtl_motion_test.dart
```

Expected: `0 changed`; `No issues found!`

### Task 10: Right to left on every Spec 1 screen (§2.3; §8 W10b; P-15)

**Files:**
- Create: `test/accessibility/w10/spec1_rtl_goldens_test.dart` and its 8 goldens (`j4_more_ways.*`, `switch_dating_to_just_me.*`)

**Interfaces:**
- Consumes: `pumpFlowScreen`, `flowGoldenVariants`, `MeHomeScreen`, `switchPath`, `homeJson`, `FakeHomeStateGateway`, `snapshotOf`, `FakeHomeAuth`, `testUser`, `relationshipLifecycleProvider`, `firstActionInputsProvider`, `homeAuthProvider`, `homeStateServiceProvider`.
- Produces: nothing new.

- [ ] **Step 1: The two sheets that had no goldens**

Create `test/accessibility/w10/spec1_rtl_goldens_test.dart` with exactly:

```dart
// Spec 1 W10b (§2.3): the Spec 1 sheets that had no goldens yet, at 1.0,
// 1.3, 2.0 and right to left: "More ways to use Attune" (J4) and the
// path-switch sheet (Dating -> Just for me). "Cancel your invite?" already
// has its goldens (how_you_use_attune).
//   flutter test --update-goldens test/accessibility/w10/spec1_rtl_goldens_test.dart
import 'package:attune/features/me/presentation/me_providers.dart';
import 'package:attune/features/me/presentation/path_switch.dart';
import 'package:attune/features/me/presentation/screens/me_home_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

Future<void> _variants(
  WidgetTester t,
  String name,
  Future<void> Function(double scale, TextDirection direction) pumpAndOpen,
) async {
  for (final (variant, scale, direction) in flowGoldenVariants) {
    await pumpAndOpen(scale, direction);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.$variant.png'),
    );
    expect(t.takeException(), isNull, reason: '$name at $variant');
  }
}

void main() {
  testWidgets('J4 "More ways to use Attune" on the Dating path', (t) async {
    await _variants(t, 'j4_more_ways', (scale, direction) async {
      await t.pumpWidget(const SizedBox());
      final home = homeJson(path: 'dating');
      await pumpFlowScreen(
        t,
        () => MeHomeScreen(home: snapshotOf(home)),
        textScale: scale,
        direction: direction,
        size: const Size(390, 1600),
        overrides: [
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-rtl'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(FakeHomeStateGateway(state: home)),
          ),
          relationshipLifecycleProvider.overrideWith((ref) async => null),
          firstActionInputsProvider.overrideWithValue((
            hasNote: true,
            hasQuiz: true,
          )),
        ],
      );
      await t.tap(find.text('More ways to use Attune'));
      await t.pumpAndSettle();
    });
  });

  for (final (name, from, to) in [
    ('switch_dating_to_just_me', homeJson(path: 'dating'), AppPath.justMe),
  ]) {
    testWidgets('path switch sheet: $name', (t) async {
      await _variants(t, name, (scale, direction) async {
        await t.pumpWidget(const SizedBox());
        final home = snapshotOf(from);
        await pumpFlowScreen(
          t,
          () => Consumer(
            builder:
                (context, ref, _) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed:
                          () => switchPath(context, ref, to: to, home: home),
                      child: const Text('SWITCH'),
                    ),
                  ),
                ),
          ),
          textScale: scale,
          direction: direction,
          overrides: [
            homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-rtl'))),
            homeStateServiceProvider.overrideWithValue(
              HomeStateService(FakeHomeStateGateway(state: from)),
            ),
          ],
        );
        await t.tap(find.text('SWITCH'));
        await t.pumpAndSettle();
      });
    });
  }
}
```

```bash
flutter test --no-pub --update-goldens test/accessibility/w10/spec1_rtl_goldens_test.dart
flutter test --no-pub test/accessibility/w10/spec1_rtl_goldens_test.dart 2>&1 | tail -1
```

Expected: `All tests passed!` (`+2`), eight new goldens. Open `j4_more_ways.rtl.png`: the sheet's rows mirror (icons on the right, text right-aligned, chevrons pointing left).

- [ ] **Step 2: Look at every Spec 1 RTL golden**

```bash
find test -name '*.rtl.png' | sort | tee $D/rtl-goldens.txt | wc -l
```

Expected: `68` (66 from W2-W9e plus Step 1's two). Open each with the Read tool and check, for each: text starts at the right edge; back arrows and chevrons point the other way; a row's leading icon is on the right; nothing is clipped at the left edge; numbers and the phone field stay left-to-right inside their boxes. Record each file with `ok` or what is wrong in `$D/rtl-review.txt`. If one is wrong, fix it in its Spec 1 file with `EdgeInsetsDirectional`/`AlignmentDirectional`/`TextAlign.start`, regenerate only that golden, and list it in the task report. (While this plan was written, 14 of the 66 were looked at, across sign-up, Welcome, A6, About us, Me, R3/RI-3, support, Settings and Opinions; none was wrong.)

- [ ] **Step 3: Mutant**

Run: `python3 $D/mutants.py rtl_physical_side`
Expected: `rtl_physical_side: RED (caught)`.

- [ ] **Step 4: Format**

Run: `dart format --output=none --set-exit-if-changed test/accessibility/w10/spec1_rtl_goldens_test.dart && flutter analyze --no-pub test/accessibility/w10/spec1_rtl_goldens_test.dart`
Expected: `0 changed`; `No issues found!`

### Task 11: The first frame (§3.14; §8 W10b; P-16)

**Files:**
- Create: `lib/app/boot_timeline.dart`, `test/app/boot_timeline_test.dart`
- Modify: `lib/main.dart` (by `$D/t11_main.py`: one `start`, five `mark`s, one `reportFirstFrame`; nothing else)

**Interfaces:**
- Produces: `BootTimeline({Stopwatch? clock})` with `start()`, `mark(String step)`, `summary() -> String` (`[startup] supabase 40 ms, chat cache 12 ms, first frame 352 ms`), `reportFirstFrame({Future<void>? firstFrame, void Function(String)? log}) -> Future<void>`; the app's `bootTimeline`.

- [ ] **Step 1: Write the failing test**

Create `test/app/boot_timeline_test.dart` with exactly:

```dart
// Spec 1 W10b (§3.14): the startup line names each step's own time and the
// total to the first frame, and main() marks every awaited step before
// runApp.
import 'dart:async';
import 'dart:io';

import 'package:attune/app/boot_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stopwatch the test moves by hand.
class _HandStopwatch implements Stopwatch {
  int ms = 0;

  @override
  int get elapsedMilliseconds => ms;

  @override
  void start() {}

  @override
  void reset() => ms = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('each step is its own duration; the first frame is the total', () {
    final clock = _HandStopwatch();
    final timeline = BootTimeline(clock: clock)..start();
    clock.ms = 40;
    timeline.mark('supabase');
    clock.ms = 52;
    timeline.mark('chat cache');
    clock.ms = 352;
    timeline.mark('first frame');
    expect(
      timeline.summary(),
      '[startup] supabase 40 ms, chat cache 12 ms, first frame 352 ms',
    );
  });

  test('the line is printed once the first frame is drawn', () async {
    final lines = <String>[];
    final frame = Completer<void>();
    final timeline = BootTimeline(clock: _HandStopwatch())..start();
    final done = timeline.reportFirstFrame(
      firstFrame: frame.future,
      log: lines.add,
    );
    await Future<void>.delayed(Duration.zero);
    expect(lines, isEmpty, reason: 'not before the frame');
    frame.complete();
    await done;
    expect(lines, ['[startup] first frame 0 ms']);
  });

  test('main() marks every awaited step before runApp', () {
    final main = File('lib/main.dart').readAsStringSync();
    final body = main.substring(
      main.indexOf('Future<void> main() async {'),
      main.indexOf('  runApp('),
    );
    expect(body, contains('bootTimeline.start();'));
    for (final step in [
      "bootTimeline.mark('supabase');",
      "bootTimeline.mark('chat cache');",
      "bootTimeline.mark('prefs');",
      "bootTimeline.mark('age block');",
      "bootTimeline.mark('lock seed');",
    ]) {
      expect(body, contains(step));
    }
    expect(main, contains('unawaited(bootTimeline.reportFirstFrame());'));
  });
}
```

Run: `flutter test --no-pub test/app/boot_timeline_test.dart`
Expected: fails to compile (`Error when reading 'lib/app/boot_timeline.dart'`).

- [ ] **Step 2: Create `lib/app/boot_timeline.dart`** with exactly:

```dart
import 'package:flutter/widgets.dart';

/// How long each step before the first frame took (Spec 1 §3.14, W10b).
///
/// main() marks each awaited step; once the first frame is drawn one line
/// is printed, `[startup] supabase 41 ms, chat cache 12 ms, ... first frame
/// 380 ms`, so a slow cold start (airplane mode, an expired session) shows
/// which step held the splash. Device-side, the owner reads it next to
/// `flutter run --profile --trace-startup`. Nothing is stored or sent.
class BootTimeline {
  BootTimeline({Stopwatch? clock}) : _clock = clock ?? Stopwatch();

  final Stopwatch _clock;
  final _marks = <(String, int)>[];

  /// Starts the clock (first thing in main()).
  void start() =>
      _clock
        ..reset()
        ..start();

  /// Records that [step] has finished.
  void mark(String step) => _marks.add((step, _clock.elapsedMilliseconds));

  /// Each step's own duration, then the total to the first frame.
  String summary() {
    final parts = <String>[];
    var previous = 0;
    for (final (step, at) in _marks) {
      parts.add(
        step == 'first frame' ? '$step $at ms' : '$step ${at - previous} ms',
      );
      previous = at;
    }
    return '[startup] ${parts.join(', ')}';
  }

  /// Prints [summary] once the first frame has been drawn ([firstFrame]:
  /// the binding's, unless a test passes its own).
  Future<void> reportFirstFrame({
    Future<void>? firstFrame,
    void Function(String line)? log,
  }) async {
    await (firstFrame ?? WidgetsBinding.instance.waitUntilFirstFrameRasterized);
    mark('first frame');
    (log ?? debugPrint)(summary());
  }
}

/// The app's one timeline.
final bootTimeline = BootTimeline();
```

Run: `flutter test --no-pub test/app/boot_timeline_test.dart`
Expected: two pass; `main() marks every awaited step before runApp` FAILS (`Expected: contains 'bootTimeline.start();'`).

- [ ] **Step 3: Mark main()'s steps**

Create `$D/t11_main.py` with exactly:

```python
import sys
sys.path.insert(0, sys.argv[1])
from edit_lib import replace, add_import
p = 'lib/main.dart'
replace(p, "  WidgetsFlutterBinding.ensureInitialized();\n",
        "  WidgetsFlutterBinding.ensureInitialized();\n"
        "  // Spec 1 W10b (§3.14): how long each step before the first frame takes.\n"
        "  bootTimeline.start();\n")
replace(p, "  await _initializeSupabase();\n",
        "  await _initializeSupabase();\n  bootTimeline.mark('supabase');\n")
replace(p, "    debugPrint('[startup] chat cache unavailable: ${error.runtimeType}');\n  }\n",
        "    debugPrint('[startup] chat cache unavailable: ${error.runtimeType}');\n  }\n"
        "  bootTimeline.mark('chat cache');\n")
replace(p, "  final prefs = await SharedPreferences.getInstance();\n  // Spec 1 W2a (§3.6)",
        "  final prefs = await SharedPreferences.getInstance();\n  bootTimeline.mark('prefs');\n  // Spec 1 W2a (§3.6)")
replace(p, "    debugPrint('[startup] age block restore skipped: ${error.runtimeType}');\n  }\n",
        "    debugPrint('[startup] age block restore skipped: ${error.runtimeType}');\n  }\n"
        "  bootTimeline.mark('age block');\n")
replace(p, "  final safetyLockSeed = await _safetyLockSeed();\n",
        "  final safetyLockSeed = await _safetyLockSeed();\n  bootTimeline.mark('lock seed');\n")
replace(p, "      child: const App(),\n    ),\n  );\n}\n",
        "      child: const App(),\n    ),\n  );\n  unawaited(bootTimeline.reportFirstFrame());\n}\n")
add_import(p, "import 'package:attune/app/boot_timeline.dart';")
print('main.dart edited')
```

Run: `python3 $D/t11_main.py $D && flutter test --no-pub test/app/boot_timeline_test.dart 2>&1 | tail -1 && flutter analyze --no-pub lib/main.dart lib/app/boot_timeline.dart`
Expected: `main.dart edited`; `All tests passed!` (`+3`); `No issues found!`

- [ ] **Step 4: Mutant**

Run: `python3 $D/mutants.py boot_no_prefs_mark`
Expected: `boot_no_prefs_mark: RED (caught)`.

- [ ] **Step 5: The measurement is the owner's** (owner checklist 3): a profile build on a phone in airplane mode with an expired session, read with `flutter run --profile --trace-startup` and the `[startup]` line. The bounded boot is not built (P-16); the contingency is in the owner checklist.

- [ ] **Step 6: Format**

Run: `dart format --output=none --set-exit-if-changed lib/app/boot_timeline.dart test/app/boot_timeline_test.dart`
Expected: `0 changed`.

### Task 12: App size against the budget (§3.14; §8 W10b; P-17)

**Files:**
- Create: `scripts/app_size_report.sh`
- Output: `$D/size/size-report.txt` (git-ignored)

**Interfaces:**
- Produces: `scripts/app_size_report.sh [BASE] [OUT]` (defaults `360db8d1~1`, `$D/size`).

- [ ] **Step 1: Create `scripts/app_size_report.sh`** with exactly:

```bash
#!/usr/bin/env bash
# Spec 1 §3.14 (W10b): what Spec 1 adds to the download, against its 1.5 MB
# budget. Builds the Android arm64 release APK (what Play delivers to most
# phones, per ABI) and the iOS release app (unsigned) twice: from the tree
# before Spec 1 (git archive of BASE, default 360db8d1~1, the commit before
# W1) and from the working tree. Writes the sizes and the differences to
# OUT/size-report.txt. Nothing is uploaded or signed.
#
#   scripts/app_size_report.sh [BASE] [OUT]
set -euo pipefail
BASE=${1:-360db8d1~1}
OUT=${2:-.superpowers/sdd/2026-11-04-spec1-w10/size}
ROOT=$(pwd)
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

build() { # $1 = source tree, $2 = label
  (
    cd "$1"
    flutter build apk --release --target-platform android-arm64 \
      --split-per-abi > "$OUT/$2-apk.log" 2>&1
    stat -f%z build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
      > "$OUT/$2-apk.bytes"
    if [[ "$(uname)" == Darwin ]]; then
      flutter build ios --release --no-codesign > "$OUT/$2-ios.log" 2>&1
      (cd build/ios/iphoneos && rm -f "$OUT/$2-ios.zip" &&
        zip -qr -X "$OUT/$2-ios.zip" Runner.app)
      stat -f%z "$OUT/$2-ios.zip" > "$OUT/$2-ios.bytes"
    fi
  )
}

rm -rf "$OUT/base-tree" && mkdir -p "$OUT/base-tree"
git archive "$BASE" | tar -x -C "$OUT/base-tree"
(cd "$OUT/base-tree" && flutter pub get --offline > "$OUT/base-pub.log" 2>&1)
build "$OUT/base-tree" base
build "$ROOT" now

mb() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1048576 }'; }
{
  echo "Spec 1 download-size budget: 1.5 MB (spec section 3.14)"
  echo "base: $BASE ($(git rev-parse --short "$BASE")); now: working tree at $(git rev-parse --short HEAD)"
  for kind in apk ios; do
    [[ -f "$OUT/base-$kind.bytes" ]] || continue
    b=$(cat "$OUT/base-$kind.bytes"); n=$(cat "$OUT/now-$kind.bytes")
    d=$((n - b))
    verdict=$([[ $d -le 1572864 ]] && echo within || echo OVER)
    echo "$kind: base $(mb "$b") MB, now $(mb "$n") MB, +$(mb "$d") MB ($verdict budget)"
  done
} | tee "$OUT/size-report.txt"
```

Run: `chmod +x scripts/app_size_report.sh && bash -n scripts/app_size_report.sh && echo syntax-ok`
Expected: `syntax-ok`.

- [ ] **Step 2: Measure** (about 30-60 minutes: four release builds; nothing is signed or uploaded; it writes only under `$D/size` and the working tree's ignored `build/`)

Run: `scripts/app_size_report.sh 360db8d1~1 $D/size`
Expected: `apk: base 68.46 MB, now 69.73 MB, +1.27 MB (within budget)` (the `now` figure a few kilobytes higher with W10's Dart) and an `ios` line in the same form. While this plan was written, the Android half was run on HEAD `8753f112` (the nine Spec 1 commits after `29070139`): `apk: base 68.46 MB, now 69.73 MB, +1.27 MB (within budget)`, 0.23 MB under the line; W10 adds a few kilobytes of Dart. The iOS half was not run here: `flutter build ios` runs `pod install` in the extracted baseline, which the owner's Mac does routinely. If either says `OVER`, read `$D/size/*-apk.log`'s `--analyze-size`-free summary and the new packages' native libraries (`smart_auth`, `play_install_referrer`, the age-signal and SIM channels, the three WebP previews), and record it as owner checklist item 4's input; the plan changes no dependency.

- [ ] **Step 3: The W10b gate**

```bash
flutter test --no-pub 2>&1 | tail -1
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*(error|warning) ' | sed 's/:[0-9]*:[0-9]* / /' | sort | comm -13 $D/analyze-baseline.txt -
git status --short lib/features/games lib/features/auth/utility/auth_exports.dart lib/app/routing/app_router.dart
```

Expected: `All tests passed!` with every test added so far; no line from `comm`; nothing from the scoped status. Spec: "Gate: the W10 group gate" (Task 14).

---

# W10c · Dead code and doc amendments (Tasks 13-14)

### Task 13: The dead auth code, as its own changeset (§8 W10c; review N-1; P-18)

**Files:**
- Delete: `lib/features/auth/log_in/presentation/screens/username_creation_screen.dart`, `forgot_password_screen.dart`, `update_password_screen.dart`, `password_reset_email_sent_screen.dart`, `login_screen_options.dart` (same folder), `lib/features/auth/verify_email/verify_email_screen.dart`, `lib/features/auth/models/email_signup_attempt.dart`, `email_signup_attempt.freezed.dart`, `email_signup_attempt.g.dart`, `lib/app/splash_screen.dart`, `lib/features/shell/presentation/attune_shell.dart`
- Modify: `lib/core/utils/exports/export_screens.dart` (the export at `:43`), `lib/features/profile/repositories/supabase_profile_repository.dart` (the doc comment at `:30`)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing; `auth_exports.dart`'s bytes are unchanged and its surface loses `LoginScreenOptions` (no Games file uses it).

**Never touch:** `lib/features/auth/utility/auth_exports.dart`, `lib/features/auth/services/auth_service.dart`, `lib/features/auth/services/auth_ui_service.dart`, anything under `lib/features/games/`, `app_router.dart` (its `RouteNames` constants for these screens stay, P-18).

- [ ] **Step 1: Prove no Games file uses anything being removed**

```bash
SYMS='UsernameCreationScreen|VerifyEmailScreen|ForgotPasswordScreen|UpdatePasswordScreen|PasswordResetEmailSentScreen|LoginScreenOptions|EmailSignupAttempt|EmailVerificationStatus|EmailVerificationAction|EmailVerificationSession|SplashScreen|AttuneShell'
FILES='username_creation_screen|verify_email_screen|forgot_password_screen|update_password_screen|password_reset_email_sent_screen|login_screen_options|email_signup_attempt|splash_screen|attune_shell'
grep -rnwE "$SYMS" lib/features/games test/features/games; echo "games symbols: $?"
grep -rnE "$FILES" lib/features/games test/features/games; echo "games imports: $?"
grep -rnwE "$SYMS" lib test | grep -vE "lib/features/auth/log_in/presentation/screens/|lib/features/auth/verify_email/|lib/features/auth/models/email_signup_attempt|lib/app/splash_screen.dart|lib/features/shell/presentation/attune_shell.dart"
grep -rnE "$FILES" lib test --include='*.dart' | grep -vE "^lib/features/auth/models/email_signup_attempt"
```

Expected: `games symbols: 1` and `games imports: 1` (grep found nothing); then exactly two lines: `lib/features/profile/repositories/supabase_profile_repository.dart:30:` (the doc comment) and `lib/core/utils/exports/export_screens.dart:43:export ...login_screen_options.dart';`. Anything else: stop and report it.

- [ ] **Step 2: Delete the 11 files and fix the two references**

```bash
rm lib/features/auth/log_in/presentation/screens/username_creation_screen.dart \
   lib/features/auth/log_in/presentation/screens/forgot_password_screen.dart \
   lib/features/auth/log_in/presentation/screens/update_password_screen.dart \
   lib/features/auth/log_in/presentation/screens/password_reset_email_sent_screen.dart \
   lib/features/auth/log_in/presentation/screens/login_screen_options.dart \
   lib/features/auth/verify_email/verify_email_screen.dart \
   lib/features/auth/models/email_signup_attempt.dart \
   lib/features/auth/models/email_signup_attempt.freezed.dart \
   lib/features/auth/models/email_signup_attempt.g.dart \
   lib/app/splash_screen.dart \
   lib/features/shell/presentation/attune_shell.dart
python3 - <<'PY'
import sys; sys.path.insert(0, '.superpowers/sdd/2026-11-04-spec1-w10')
from edit_lib import replace
replace('lib/core/utils/exports/export_screens.dart',
        "export 'package:attune/features/auth/log_in/presentation/screens/login_screen_options.dart';\n", "")
replace('lib/features/profile/repositories/supabase_profile_repository.dart',
        "  /// callers (e.g. `_handleNewUser` racing with `UsernameCreationScreen`)\n",
        "  /// callers (e.g. two `_handleNewUser` calls racing each other)\n")
print('dead code removed')
PY
```

Expected: `dead code removed`. (Plain `rm`, not `git rm`: nothing is staged.)

- [ ] **Step 3: Analyzer, Games tests, the barrel**

```bash
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*(error|warning) ' | sed 's/:[0-9]*:[0-9]* / /' | sort > $D/analyze-t13.txt
diff $D/analyze-baseline.txt $D/analyze-t13.txt
flutter test --no-pub test/features/games test/architecture/games_untouched_test.dart test/features/chat/game_card_no_duplicate_title_test.dart test/features/chat/game_card_viewer_test.dart test/features/chat/game_staged_wiring_test.dart test/features/chat/game_move_motion_test.dart test/features/chat/game_trail_golden_test.dart test/accessibility/large_text_test.dart test/accessibility/w10/in_chat_games_large_text_test.dart 2>&1 | tail -1
shasum -a 256 lib/features/auth/utility/auth_exports.dart | diff - $D/auth_exports.sha && echo auth-exports-unchanged
```

Expected: `diff` prints exactly one removed line, `< warning • The receiver can't be null, so the null-aware operator '?.' is unnecessary • lib/features/auth/log_in/presentation/screens/login_screen_options.dart • invalid_null_aware_operator` (that warning goes with the file) plus whatever Tasks 1-12 already changed in the baseline (none expected); `All tests passed!` (every Games test, the in-chat Games measurement and Spec 5's large-text test); `auth-exports-unchanged`.

- [ ] **Step 4: The full suite, and the changeset for the owner**

```bash
flutter test --no-pub 2>&1 | tail -1
git status --short -- lib/features/auth/log_in/presentation/screens lib/features/auth/verify_email lib/features/auth/models lib/app/splash_screen.dart lib/features/shell lib/core/utils/exports/export_screens.dart lib/features/profile/repositories/supabase_profile_repository.dart | tee $D/t13-changeset.txt
```

Expected: `All tests passed!`; exactly 13 lines: 11 ` D` and 2 ` M`. Put this in the task report for the owner, who commits it on its own (spec: "dead auth code removed in a separate commit"):

```bash
git add -A lib/features/auth/log_in/presentation/screens lib/features/auth/verify_email lib/features/auth/models lib/app/splash_screen.dart lib/features/shell lib/core/utils/exports/export_screens.dart lib/features/profile/repositories/supabase_profile_repository.dart
git commit -m "chore(auth): Spec 1 W10c remove the dead auth and shell screens"
```

(Not run here. `lib/features/auth/log_in/presentation/screens` also holds `login_profile.dart` and `login_screen.dart`, which this task doesn't change, so `-A` on that folder stages only the deletions.)

### Task 14: The approved doc amendments, the SOUL proposal, and the W10 gate (§8 W10c; Q20; review C-9; P-19)

**Files:**
- Modify (by `$D/t14_docs.py`): `lib/architecture/attune/ATTUNE_MASTER_SPEC.md`, `lib/architecture/AUTH_ONBOARDING_ENGINE.md`, `docs/superpowers/research/2026-10-16-couples-research/06-synthesis-roadmap.md`
- Create: `docs/superpowers/proposals/2026-11-04-attune-soul-line-73.md`

**Interfaces:** none (documents).

**Never touch:** `lib/architecture/attune/ATTUNE_SOUL.md`, `lib/architecture/attune/ATTUNE_THESIS.md`, `DATING_MODE_SPEC.md`, `DATING_CHAT_SAFETY_SPEC.md`, `FORUM.md`.

- [ ] **Step 1: Save and run the amendments**

Create `$D/t14_docs.py` with exactly:

```python
# Spec 1 W10c: the approved doc amendments (Q20, review C-9), and only those.
# Run from the repo root: python3 $D/docs_amend.py $D
import sys
sys.path.insert(0, sys.argv[1])
from edit_lib import replace

MS = 'lib/architecture/attune/ATTUNE_MASTER_SPEC.md'
REV = ' *(revised by decision 34)*'

# Version line.
replace(MS, "**Version:** 2.22 (Two-ask couples onboarding; SMS delivery requirements)\n**Last updated:** July 2026",
        "**Version:** 2.28 (App flow and identity: three paths, sign-up order, a two-tab home per path; forums retired)\n**Last updated:** November 2026")

# Section 2: modes -> paths.
replace(MS, """| Mode | Who it's for | Core value | Status |
|---|---|---|---|
| Couples mode | Active couples using Attune as their primary chat | Shared chat + AI intelligence + games + insights | Build first |
| Personal mode | Individuals — between relationships, solo users, waiting partners | Self-reflection, pattern awareness, growth | Build alongside couples |
| Healing mode | Post-breakup users | Structured recovery journey before dating unlocks | Month 4 |
| Dating mode | Single users ready to date again | Psychology-first matching using real behavioural data | Month 6+ |

Couple shape is a profile on the relationship (stage, distance, intent, household) plus per-partner preferences — not a mode and not a type. Modes remain personal / couplesPending / couples. *(Added 2026-10-16, §8.11.)*

### Mode transitions
```
New user (taken) → Couples mode (only after partner accepts invite and completes their onboarding)
New user (taken) → Personal mode / waiting state (if partner doesn't join within 7 days)
New user (single) → Personal mode immediately
Couples mode → Personal mode (if relationship ends or partner unlinks)
Personal mode → Healing mode (if user flags a recent breakup)
Healing mode → Dating mode eligibility (latest valid readiness score > 70,
minimum 8 weeks, all trusted gates pass); separate opt-in and profile activation
Dating mode → Couples mode (after match forms and both users link)
```

### Onboarding fork (screen one — locked in)
The very first screen after signup asks one question: **"Are you single or in a relationship?"**
- **Single** → Personal mode onboarding (attachment quiz + personal anchors, no invite flow — self-initiated self-knowledge is the value, so the quiz stays up front here)
- **In a relationship** → Couples onboarding, two-ask design (8.8, decision 29): Ask 1 is profile + partner invite only — chat unlocks on mutual verified linking; the intelligence layer, quiz, and anchors are introduced as Ask 2 after chat value exists
""", """*(Amended 2026-11, decision 34: an account carries a **path**, not a mode.)*

Every account chooses one of three paths after sign-up, stored on the account (`users.path`) and switched only by the person:

| Path | Who it's for | Tab 2 of the home | Status |
|---|---|---|---|
| In a relationship (`relationship`) | Couples, including a partner who hasn't joined yet | **Chat**: the shared space once linked; "Your space" and the invite while waiting | Live |
| Single and open to dating (`dating`) | Single adults in a country where Dating is open | **Me**, with the Dating section on top | Dating opens in Ghana and the UK (Spec 2) |
| Just for me (`just_me`) | Anyone: single, partnered or in between | **Me**: journal, quizzes, Healing | Live |

Relationship and Dating are never active together. Healing is a space inside Me ("After a breakup or a loss"), offered and never required: it is not a mode, and no readiness score gates Dating. Couple shape is a profile on the relationship ("About us": the owner's four fields), never a mode or a type.

### Path transitions
```
Any path → another: Settings → How you use Attune; nobody is told
Just for me → Relationship: the invite flow (the path is set when the invite is sent)
Dating → Relationship: inviting a partner pauses Dating (confirmed first)
Dating → Just for me: Dating is paused and hidden (confirmed first)
Relationship (invite pending) → another path: the invite is withdrawn (confirmed first)
Relationship (linked or paused) → another path: pause or end the shared space first
Relationship ended inside Attune → Dating: a gentle wait for the 30-day ending
  window, with Healing offered (Spec 2)
Dating → Relationship after a match: the couple link (Spec 2)
```

### Path choice (after sign-up — replaces the screen-one fork)
Sign-up comes first: name → date of birth → phone → code → consent (8.8). Then one question, **"What brings you to Attune?"**, with three equal cards and nothing preselected:
- **In a relationship** → the partner invite (or "My partner already invited me"); the two-ask design (8.8, decision 29) is unchanged: Ask 1 is the invite only, and the quiz, anchors and intelligence layer come as Ask 2 after chat value exists
- **Single and open to dating** → Me with the Dating section ("Not open in {country} yet" where Dating isn't open)
- **Just for me** → Me straight away; the quiz is optional (8.8 Track A)
""")

# Section 8.8: the fork note and Track A.
replace(MS, """#### Screen one fork (non-negotiable — routes entire onboarding)
""", """#### Screen one fork (non-negotiable — routes entire onboarding)

*(Revised by decision 34: sign-up comes first, then "What brings you to Attune?" with three paths; see section 2. The fork below is kept as the history of decision 18.)*
""")
replace(MS, """#### Track A: Single onboarding
```
1. Sign up + profile setup
2. "Are you single or in a relationship?" → Single
3. Relationship reflection quiz (final attachment instrument pending clinical decision)
4. Three personal anchors:
   - "What do you most want to understand about yourself in relationships?"
   - "What pattern from past relationships are you trying to do differently?"
   - "What does a steady relationship feel like to you?"
5. → Personal mode home (no waiting, no invite)
```""", """#### Track A: Just for me *(amended 2026-11, decision 34)*
```
1. Sign up: name → date of birth → phone → code → consent
2. "What brings you to Attune?" → Just for me
3. → The Me home straight away (no quiz up front, no waiting, no invite):
   one first-action card, "Write your first note" or
   "Take a 3-minute look at how you connect"
4. The relationship reflection quiz is optional, self-facing, with its
   caveat (final attachment instrument pending clinical decision)
5. The three personal anchors are optional, offered after the quiz:
   - "What do you most want to understand about yourself in relationships?"
   - "What pattern from past relationships are you trying to do differently?"
   - "What does a steady relationship feel like to you?"
```""")

# Section 9: the shell, the default tab, the tabs' contents, the guest tab.
replace(MS, """```
Tab 1: Opinions  ← anonymous community surface
Tab 2: Chat      ← relationship workspace / personal workspace
```
""", """```
Tab 1: Opinions  ← anonymous community surface
Tab 2: Chat      ← the relationship workspace (In a relationship)
       Me        ← your own space, with Dating inside it (Dating, Just for me)
       Sign in   ← guests: "Join Attune"
```

*(Amended 2026-11, decision 34: Tab 2 follows the path. "Dating" never appears on the tab bar.)*
""")
replace(MS, """```
Anonymous user:       Opinions
Personal/single user: Opinions
Couples user:         Chat
```
""", """```
Anonymous user:          Opinions
Signed in, any path:     Tab 2 (Chat on In a relationship; Me on Dating and Just for me)
```

*(Amended 2026-11, decision 34: after sign-in every path lands on its own space, with Opinions one tap away.)*
""")
replace(MS, """final initialTab = switch (sessionState) {
  anonymous => opinions,
  personal => opinions,
  couples => chat,
}""", """final initialTab = switch (sessionState) {
  anonymous => opinions,
  signedIn => tabTwo, // Chat or Me, by path
}""")
replace(MS, "- Nested Forums area for categories and threaded posts\n",
        "- Forums retired 2026-10, Spec 3\n")
replace(MS, """**Chat tab:**
- Couples mode: exactly one active partner chat
- Personal mode: personal reflection workspace or onboarding CTA, depending MVP scope
- Anonymous mode: `LoginProfile` guest gate with phone-auth CTA
""", """**Tab 2 — Chat (In a relationship):**
- Linked: exactly one active partner chat
- Not linked yet, paused or ended: "Your space" with the invite or the lifecycle card; never Dating

**Tab 2 — Me (Dating, Just for me):** the Dating section (Dating path only), then "Your space": journal, quizzes, Healing, reminders.

**Tab 2 — Sign in (guests):** `LoginProfile` as "Join Attune" (below).

**Chat tab, as before:**
""")
replace(MS, """#### Anonymous Chat gate
""", """#### Anonymous Chat gate

*(Revised by decision 34: the guest's Tab 2 is labelled "Sign in"; with the new sign-in on, `LoginProfile` reads "Join Attune" with "Get started", "I already have an account" and "I have an invite", still phone only. A neutral birth-year question comes before a guest reads Opinions.)*
""")

# Decision log: mark the revised rows, then decision 34.
for end in [
    "Chat default for couples; dot not badge |",
    "profile review/activation, and an optional separate historical-data choice |",
    "— no direct user_id FK on forum posts |",
    "are Opinions/forum display labels only — not account states |",
    "Phone OTP only at launch; no Apple/Google, email/password, or email magic link |",
    "with phone OTP only and no Google/Apple/email/password |",
]:
    replace(MS, end, end[:-2] + REV + ' |')
replace(MS, """| 18 | Onboarding fork | Screen one asks "single or in a relationship?" — routes entire onboarding experience |""",
        """| 18 | Onboarding fork | Screen one asks "single or in a relationship?" — routes entire onboarding experience""" + REV + " |")
ROW33 = "| 33 | Scope decisions (2026-10-16, owner Q1, Q5, Q6, Q8–Q18) |"
import pathlib
src = pathlib.Path(MS).read_text()
assert src.count(ROW33) == 1
start = src.index(ROW33)
end = src.index('\n', start)
row34 = ("\n| 34 | App flow and identity (revises 11, 18, 20, 21, 22, 23 and 25; documented reason: "
         "the 2026-10-24 flow and dating research, owner rulings Q1-Q20 (Q4, Q6, Q7, Q8, Q11, Q18, Q20), "
         "built as Spec 1 W1-W10) | "
         "**Paths, not modes:** In a relationship, Single and open to dating, or Just for me, chosen after sign-up "
         "(\"What brings you to Attune?\") and switched silently in Settings; Relationship and Dating never together. "
         "**Navigation (11):** two tabs: Opinions, and Tab 2 = Chat (Relationship) or Me (Dating, Just for me); "
         "guests land on Opinions with Tab 2 \"Sign in\"; signed-in people land on Tab 2; \"Dating\" never on the tab bar. "
         "**Sign-up (18):** name, date of birth, phone, code, consent, then the path. "
         "**Dating entry (20):** a path, open only where the server lists the country (Ghana and the UK at launch); "
         "after an ending inside Attune a gentle wait for the 30-day window with Healing offered, no readiness score "
         "or 8-week timer (Spec 2); enrollment still needs the Dating opt-in, terms, the age checks and profile review. "
         "**Opinions anonymity (21):** a stable keyed pseudonym per author (HMAC with a server secret; the user_id never "
         "reaches a client); forums retired 2026-10 (Spec 3); per-post handles stay deferred (Q9). "
         "**Labels (22):** 'taken', 'single' and 'figuring_it_out' are self-declared Opinions labels, written once at the "
         "first path choice and never re-synced; not account states. "
         "**Sign-in (23):** phone only (SMS; WhatsApp for a number with no account yet; voice built but off until it can "
         "never speak a code to voicemail); the date of birth comes before the phone and the server refuses under 18; "
         "a seam to link other sign-in methods later, no work now (Q18). "
         "**Guest Tab 2 (25):** \"Sign in\", showing \"Join Attune\" (Get started / I already have an account / I have an "
         "invite); a neutral birth-year question before a guest reads Opinions | "
         "One app with three ways in needs the way in on the account, not on the phone; a minor must be stopped before "
         "they hand over a number; the specs and the code must say the same thing again (06 section 2.1.7) |")
pathlib.Path(MS).write_text(src[:end] + row34 + src[end:])

# The update log.
replace(MS, "### Update log\n\n```\n[July 2026 — v2.27]", """### Update log

```
[November 2026 — v2.28] — app flow and identity (decision 34)
- Section 2: an account carries a path (In a relationship, Single and open
  to dating, Just for me), not a mode; Healing is a space inside Me
- 8.8: sign-up is name, date of birth, phone, code, consent, then the path;
  Track A is now Just for me, with the quiz and anchors optional
- Section 9: Tab 2 is Chat or Me by path, "Sign in" for guests; every
  signed-in path lands on Tab 2; forums retired 2026-10, Spec 3
- Decisions 11, 18, 20, 21, 22, 23 and 25 revised by decision 34

[July 2026 — v2.27]""")

# AUTH_ONBOARDING_ENGINE.md: order, voice OTP, no Ask 2 preview.
AE = 'lib/architecture/AUTH_ONBOARDING_ENGINE.md'
replace(AE, """```
Phone number -> SMS OTP -> Supabase session
```
""", """```
Name -> date of birth -> phone number -> code -> consent -> Supabase session
```

*(Amended 2026-11, Spec 1, Q4/Q20.)* The name and date of birth are asked
first and held on the device; nothing is written until the code is checked,
and then everything is written in one call (`complete_sign_up`). Under 18,
nothing is written at all and the server refuses the account. The code goes
by SMS, or by WhatsApp for a number that has no account yet.
""")
replace(AE, """- **Voice OTP is the required automatic fallback** when SMS delivery fails
  or times out — not a nice-to-have.
""", """- **Voice OTP** *(amended 2026-11, Spec 1 W2)*: built into the Send SMS
  Hook and switched off until the provider's answering-machine detection is
  in place, because a code must never be spoken to voicemail. Until then a
  failed WhatsApp or voice route falls back to SMS, and the app offers
  "Try WhatsApp" (new numbers only) after the second resend.
""")
replace(AE, """After phone verification, collect only:

- display name
""", """Before the phone number *(amended 2026-11, Spec 1)*, collect only:

- display name
- date of birth (shown back as an age, never stored on the device past sign-up)
""")
replace(AE, """```
LoginProfile CTA
  -> Legal acceptance bottom sheet
  -> LoginScreen (phone OTP)
  -> OnboardingFlow
```""", """```
Welcome (/welcome), or LoginProfile "Get started"
  -> /signup: name, date of birth, phone, code, consent (the legal step
     comes after the code)
  -> /onboarding: "What brings you to Attune?"
```

*(Amended 2026-11, Spec 1.)*""")
replace(AE, """  Intelligence introduction
    -> Attachment quiz
    -> Relationship anchors
    -> Compatibility preview (completion reward)
```""", """  Intelligence introduction
    -> Attachment quiz
    -> Relationship anchors
    -> The two anchors reflected back, and "something for tonight"
       (decision 30: no compatibility preview, no pairing or type)
```""")

# CR-06 section 5.3 rule 6.
CR = 'docs/superpowers/research/2026-10-16-couples-research/06-synthesis-roadmap.md'
replace(CR, "6. Shared fields change silently (no activity feed, Together D7); the only exception is the per-user plan-change notice the autistic partner can opt into for plans they are *in* (C7).",
        "6. Shared fields change silently (no activity feed, Together D7); the only exception is the per-user plan-change notice the autistic partner can opt into for plans they are *in* (C7). *Amended 2026-11 (Spec 1, Q8 and Q20):* the four shared \"About us\" fields each show one quiet attribution line (\"Changed by Yaw - Tue, 12 Nov\"); still no push, no feed and no history.")
print('docs amended')
```

Run: `python3 $D/t14_docs.py $D`
Expected: `docs amended`.

- [ ] **Step 2: Check them**

```bash
git diff --stat -- lib/architecture docs/superpowers/research
grep -c 'revised by decision 34' lib/architecture/attune/ATTUNE_MASTER_SPEC.md
grep -n '^| 34 ' lib/architecture/attune/ATTUNE_MASTER_SPEC.md | cut -c1-60
grep -n 'Forums retired 2026-10, Spec 3' lib/architecture/attune/ATTUNE_MASTER_SPEC.md
grep -n 'Nested Forums\|Compatibility preview (completion reward)\|required automatic fallback' lib/architecture/attune/ATTUNE_MASTER_SPEC.md lib/architecture/AUTH_ONBOARDING_ENGINE.md
git status --short lib/architecture/attune/ATTUNE_SOUL.md lib/architecture/attune/ATTUNE_THESIS.md
```

Expected: three files changed (`76 insertions(+), 45 deletions(-)`, `22 insertions(+), 9 deletions(-)`, `1 insertion(+), 1 deletion(-)`); `8` (the seven revised rows and the update log line); `| 34 | App flow and identity (revises 11, 18, 20, 21`; two lines (§9's Opinions tab and the update log); nothing from the stale-text grep; nothing from the SOUL/THESIS status. Read the changed sections once in full (`git diff lib/architecture`): every sentence says what Spec 1 built, no partner is "they", no date outside `MyDateFormat` style is invented.

- [ ] **Step 3: The SOUL proposal (never an edit to SOUL)**

Create `docs/superpowers/proposals/2026-11-04-attune-soul-line-73.md` with exactly:

```markdown
# Proposal: `ATTUNE_SOUL.md` line 73 ("a forum")

**Status:** a proposal to the owner. No wave edits `ATTUNE_SOUL.md`; the owner makes this change, or doesn't.
**Source:** owner ruling Q20 (`docs/superpowers/research/2026-10-24-flow-dating-research/11-synthesis-decisions.md` §10, accepted in §12), review C-9, Spec 1 §8 W10c.

## Today (lines 72-75)

> The product has a chat system, a couple's journal (Planning, Calendar,
> Map), quizzes, games, a pulse score, a forum, and a dating mode. These are
> the surfaces through which intelligence is built and delivered. They are
> not the product. The intelligence is the product.

## Proposed

> The product has a chat system, a couple's journal (Planning, Calendar,
> Map), quizzes, games, a pulse score, Opinions, and a dating mode. These are
> the surfaces through which intelligence is built and delivered. They are
> not the product. The intelligence is the product.

## Why

- The forums were retired in October 2026 (Spec 3); "Forums retired 2026-10, Spec 3" is now in the Master Spec's §9.
- Opinions, the anonymous relationship-opinions surface, stays (owner ruling Q9: kept as it is, open for debate), so the list still names a community surface, by its current name.
- Only the one noun changes; the paragraph's point (the surfaces are not the product) is untouched.
```

Run: `git status --short lib/architecture/attune/ATTUNE_SOUL.md; sed -n '72,74p' lib/architecture/attune/ATTUNE_SOUL.md`
Expected: nothing from the status; line 73 still reads `Map), quizzes, games, a pulse score, a forum, and a dating mode. These are`.

- [ ] **Step 4: The W10 group gate (what this plan can check)**

```bash
flutter test --no-pub 2>&1 | tail -1
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*(error|warning) ' | sed 's/:[0-9]*:[0-9]* / /' | sort | comm -13 $D/analyze-baseline.txt -
for s in 2.0 1.6 1.3; do python3 scripts/large_text_audit.py --scale $s test | tail -1; done
sed -n '/if (isAuthenticated && !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - $D/latch.sha && echo latch-unchanged
shasum -a 256 lib/features/auth/utility/auth_exports.dart | diff - $D/auth_exports.sha && echo auth-exports-unchanged
git status --short lib/features/games lib/app/routing/app_router.dart lib/features/auth/utility/auth_exports.dart lib/architecture/attune/ATTUNE_SOUL.md lib/architecture/attune/ATTUNE_THESIS.md supabase
git status --short | sort > $D/status-after.txt; cat $D/status-after.txt
```

Expected: `All tests passed!` with Task 1's count plus every test this plan added (105 without Task 7, 109 with it); no line from `comm`; `SCALE 2.0: 0 site(s) to fix, 25 listed apart`, `SCALE 1.6: 0 site(s) to fix, 17 listed apart`, `SCALE 1.3: 0 site(s) to fix, 6 listed apart` (listed apart: Games sites, Pulse's and the test-only lifecycle card; each run about 10 minutes on an idle machine); `latch-unchanged`; `auth-exports-unchanged`; from the scoped status only ` M supabase/.temp/cli-latest` (the owner's); the full status lists the owner's two entries plus exactly the files in this plan's file map and their goldens.

**W10 group gate (spec: "before `text_scale_v2` in production: the device matrix (TalkBack, VoiceOver, 200% text, Android Go, three OEMs) passes on the chosen cap").** This is the owner's (owner checklist 1). Until it passes, `text_scale_v2`'s production gate row has no `review_ref` and production refuses to turn it on.

---

## Owner checklist (the plan never runs any of this)

1. **The W10 group gate: the device matrix, on the chosen cap (`v2Cap` 2.0, batch 6), before `text_scale_v2` goes on in production.** On the development project (where `text_scale_v2` is already on), with a build from this tree:
   - **Phones:** an Android Go phone (2 GB); a Samsung, a Tecno or Infinix, and a Pixel; an iPhone. On each, system text at its largest non-accessibility size and at 200% (Android 14+ "Font size" to the end; iOS Larger Text to 200%, which is the accessibility range).
   - **Walk through:** sign-up A1-A6, X1, R1, RI-3, About us (Spec 1 screens: up to 2.0 on every cap); then chat (the thread, a long draft, the games sheet, a game card, a voice note), Opinions (Discover, a thread, compose, the report list), Together (agenda and month), Planning (home, an entry with expenses), Settings (every row, quiet states), Healing (the journey and a stage), the journal (list, an entry with a reflection, J3's reminder and its time picker); over the chat, the Repair tray, Hard moment and "Help me say this"; About us and the reminder sheet. With `v2Cap` 2.0 (owner question 1 answered yes, 2026-11-05) the audited non-Spec-1 screens reach 2.0; the Games routes and every route not audited yet stay at 1.0 (P-9). Nothing overflows (no yellow-and-black stripe in a debug build), nothing that carries meaning is cut, every button can be reached.
   - **TalkBack and VoiceOver** through the same path: every control has a spoken label, the reading order follows the screen, errors are announced, the 6-box code field reads as one field.
   - **Motion (§2.2; batch 7 review M-5):** on the Android Go phone and a mid-range Android, the attachment quiz deck forward and Back at 320 ms (Task 9 cut it from 900 ms; the staggered fall, rise and settle all run in that time) reads as a deck moving, not a flicker; with the phone's reduce motion on, the next card is simply there; R4's two avatars settle toward each other.
   - **Evidence:** screenshots per phone and size; then, on the project that becomes production and only after the flip: `select record_flag_gate_evidence('text_scale_v2', '<link to the evidence>');` (service role). Until then production refuses to turn `text_scale_v2` on.
2. **Owner questions 2, 4, 5, 6 and 7** (above). Questions 1 and 3 were answered on 2026-11-05: the two-line Games change is approved (changeset (c), item 5), so Task 8 set `v2Cap` to 2.0; the light error colour is `#C62828` (Task 7). Nothing in Task 8 needs re-running.
3. **First frame (§3.14).** A profile build on a phone: sign in, close the app, wait more than an hour (the access token expires), turn on airplane mode, then `flutter run --profile --trace-startup -d <device>` (USB stays connected). Read `build/start_up_info.json` (`timeToFirstFrameMicros`, `timeToFirstFrameRasterizedMicros`) and the app's `[startup] ...` line (`flutter logs`). Pass: the first frame within 1 s of the splash. **Contingency, only if not:** the `[startup]` line names the slow step. If it is the chat cache, the age block or the lock seed (keystore), shorten that step's bound; if it is `supabase` (not expected, P-16), add a bounded boot as its own small wave: start `Supabase.initialize` without awaiting it, wait for it or 2 s, whichever comes first, show a neutral frame (the splash colour, no text) if it isn't done, and build the app only once it is, so no provider ever reads an unready client. Never shorten the existing 30 s `Supabase.initialize` timeout alone: dozens of providers would then throw on first use.
4. **App size (§3.14).** Compare Task 12's `$D/size/size-report.txt` with Play Console's download size for arm64 and App Store Connect's App Thinning size for a recent iPhone, on the next internal build. Over 1.5 MB on either: decide which of Spec 1's native additions to drop or defer.
   - **The margin is thin (batch 8, measured 2026-11-06).** Android arm64 is +1.27 MB of the 1.5 MB budget (+1,329,607 bytes; 0.23 MB, 15%, left); iOS is not measured yet. Any new native library (a Mapbox- or Sentry-class `.so` is 1-13 MB) or one more ~1 MB PNG would go over, so check the size before adding either. The figure is a debug-keyed APK with no dart-defines (not an AAB, so Play's per-device number differs); W10 itself adds about 22 KB of AOT code. Before release, run `IOS=1 scripts/app_size_report.sh` on a Mac with about 10 GB free; on the 8 GB dev Mac add `GRADLE_XMX=3G` (`android/gradle.properties` asks for `-Xmx8G`, which swaps to about 13 GB and can fill the disk).
5. **Commits: three changesets, in this order: (c), then (a), then (b)** (the file lists are in `$D/final-fix-report.md`). Push and deploy nothing until W10's own review.
   - **Why (c) comes first:** (a) sets `TextScalePolicy.v2Cap` to 2.0 and adds `test/accessibility/w10/in_chat_games_large_text_test.dart`, whose "the chosen cap ... nothing new up to 2.0" cases pass only with (c) (without it the in-chat games tiles overflow from 1.3, P-8). (a) committed before (c) would leave a commit with a red suite, and a development build of it, where `text_scale_v2` is on, would show the chat's games sheet overflowing at large text. (b) is independent of both.
   - **(c) The Games changeset, first:** the owner-approved 2-line Games change (`lib/features/games/presentation/widgets/chat_games_sheet.dart`, `lib/features/games/presentation/widgets/game_grid_tile.dart`; 2 files, 3 lines), its own commit outside Spec 1. If (c) is ever reverted, set `v2Cap` back to 1.0 in the same change (the comment on `v2Cap` says so).
   - **(a) The main W10 changeset, second:** everything else this plan changed or created (Tasks 1-12, 14 and the final fix wave), as the W10 commit.
   - **(b) The dead-code changeset, last:** Task 13's 13 paths as their own commit (the command is in Task 13 Step 4 and `$D/batch-9-report.md`).
   - Never in any of them: the owner's own `supabase/.temp/cli-latest` and `backup-before-planning-p2.sql`.
6. **Docs.** Read decision 34 and the rewritten §2, §8.8 and §9 of the Master Spec; decide owner question 6 (SOUL line 73, the wording in `docs/superpowers/proposals/2026-11-04-attune-soul-line-73.md`) and owner question 5 (`AUTH_ONBOARDING_ENGINE.md`'s Data Writes table). `lib/architecture/FOLDER_STRUCTURE.md:67` still mentions `forgot_password_screen.dart` (deleted in Task 13; the doc is an illustrative tree that was already out of date): fix it in the next doc pass.
7. **Found, not fixed (for later waves):** Pulse overflows from 1.3 (Task 1 Step 5's audit lists every site; P-9 keeps it at 1.0); the in-chat Games sheet overflows at 1.0 on 360-wide phones (Games-owned); in `chat.scale2.0.png` the chat header's name and status stay at their normal size (nothing is cut; a later pass can let them grow).
   - **`AppButton` labels never grow** with text: a follow-up wave after W10, not W10 (owner question 4).
   - **The two "they/them" partner lines** (`quiet_states_screen.dart:193`, `share_win_sheet.dart:85`; lines as of batch 10): Spec 7's next copy pass.
   - **Phone numbers in translated sentences** ("Call {number}") need LTR isolates once an RTL locale ships (batch 7).
   - **Games follow-ups (Games-owned):** the stale "above 1.3x" comment in `game_grid_tile.dart` (left by the 2-line allowance); the This-or-That tests swallow overflows.
   - **Planning's rose/pink categories** follow `LightColors.error`, so the owner's `#C62828` shifts them a shade deeper in both themes (Task 7, PF-C1; `planning.scale{1.0,1.3,2.0}.png` regenerated).
   - **Two now-redundant colour overrides with stale contrast comments:** W7's "Exit now" `#B3261E` and W9 B6's snackbar override; kept with no visual change (W10 B5), their contrast comments to be updated.
   - **Dead auth navigation left in protected files (Task 13 review T13-m1):** `lib/features/auth/services/auth_ui_service.dart` (lines 114, 147, 156, 360) still navigates to `/createUsername`, `/verifyEmail` and `/forgot-password`, the screens Task 13 deleted. The `RouteNames` constants for all 7 removed screens stay in `app_router.dart`, and so do the screens' ARB keys (`authForgotPassword*`, `authUpdatePassword*`, `loginForgotPassword*`). None of those paths was ever routed, so nobody can reach them today. `AuthUiService` and `app_router.dart` are protected in W10, so they were not edited. In the next auth pass that may touch them, delete the email/password helpers, the 7 constants and the orphaned ARB keys.
8. **Deferred minors from the W10 ledger** (each a "Final: minor (deferred)" line in `$D/progress.md`):
   - W10 B3 N-1: the composer's room isn't re-measured while a multi-line draft grows.
   - W10 B3 N-2: the `InfoRowWidget` 40% trailing cap is of the screen width, not the row (wide trailings on iPad).
   - W10 B4: 14 taps already miss at 1.0 in existing tests (backlog line added).
   - W10 B5: the stale contrast comments in the 2 kept overrides (above); a pre-existing Planning dark-mode test gap; pre-existing light fills below 3:1; an optional test pin.
   - W10 B6 N-1: dialogs opened from a `KeepsDefaultTextSize` screen render at the root scale 2.0.
   - W10 B6 N-2: no test pins a double pop. N-3: the rise can be delayed the full 500 ms. The dispose listener's removal can't be observed. M-3: the architecture-pin mutant is impossible (`app_router.dart` is protected).

## Spec coverage (self-review)

| Spec item | Where |
|---|---|
| §8 W10a: large-text audit with goldens at 1.0/1.3/2.0 in the order chat → Opinions → Together/Planning → Settings → Healing → journal | Task 1 (the audit, the goldens' 1.0 from today's code), Tasks 3-6 in that order (Settings, Healing and the journal share Task 6) |
| Fixing truncation and overflow | Tasks 3-6 (35 overflow sites, P-3; truncation P-4) |
| Checking ScreenUtil (`minTextAdapt`, the identity `fontSizeResolver`) and the iPad 1.25x cap | Task 2 (`screen_util_large_text_test.dart`, P-10) |
| The root clamp raised behind `text_scale_v2` to the highest of 2.0/1.6/1.3 at which every audited surface, the in-chat game sheets included, passes | Task 8 (`TextScalePolicy`, `RootTextScaleClamp`, the measurement, the cap rule; result 1.0 with Games frozen, P-8, owner question 1) |
| Game routes keep 1.0 through `TextScalePolicy` route prefixes, checked by an architecture test against `app_router.dart`; no Games file edited | Task 8 (`gameRoutePrefixes`, `test/architecture/text_scale_routes_test.dart`); every task's Games status check |
| Tests: golden suites; `large_text_test.dart` extended; architecture test for game route prefixes | Tasks 1, 3-6, 8 |
| §5.1 `lib/app/text_scale_policy.dart` (root cap from `text_scale_v2`; route prefixes that keep 1.0) | Task 8 |
| §5.2 `app.dart`, `app_shell.dart`: `appShell(maxTextScale:)` from `textScaleCapProvider` | Task 8 Step 3 |
| §5.6 R11 (every screen reflows: last step, behind the flag, after the audit) | Task 8 is W10a's last; P-9 keeps unaudited routes at 1.0 |
| §2.3 accessibility (AllowLargeText keeps working; goldens incl. RTL; contrast) | Task 8 test (`AllowLargeText still reaches 2.0`); Task 10; Task 7 (contrast, owner question 3) |
| §8 W10b reduce-motion pass and the 900 → 320 ms deck advance (§2.2) | Task 9 |
| RTL pass on every Spec 1 screen | Tasks 9-10 (the guard over 71 files, two new RTL goldens, a review of all 68) |
| First-frame measurement and, if needed, the bounded boot (§3.14) | Task 11 (instrument), owner checklist 3 (measurement, contingency); P-16 |
| App-size measurement and budget (§3.14) | Task 12, owner checklist 4 |
| Tests: RTL tests; reduce-motion tests; size report | Tasks 9-12 |
| §8 W10c dead auth code in a separate commit; never `auth_exports.dart`, `AuthService`, `AuthUiService`; `export_screens.dart:43`; `supabase_profile_repository.dart`; Games grep before, Games tests after (review N-1) | Task 13 |
| Approved doc amendments (Q20, C-9): Master Spec decisions 11, 18, 20, 21, 22, 23, 25, §2, §8.8 Track A, §9, Spec 3's "Forums retired 2026-10, Spec 3"; `AUTH_ONBOARDING_ENGINE.md` (order, voice OTP, no Ask 2 preview); CR-06 §5.3 rule 6; SOUL:73 as a proposal | Task 14 |
| Tests: Games tests; analyzer on touched files | Tasks 13-14 |
| W10 group gate: the device matrix (TalkBack, VoiceOver, 200% text, Android Go, three OEMs) on the chosen cap | Owner checklist 1 |
| §2.5 `text_scale_v2` (client, anon; off = root clamp 1.0; gate = the W10 group gate) | P-1; Task 8 (`textScaleV2Provider`) |
| §4.7 "W10 has no migration" | P-1 |
| §6 item 6 ("W10 may add the flag to `get_public_app_config()`") | P-1 (not done) |
| §9 "Games touched" (Games tests after the W10c dead-code commit) | Task 13 Step 3 |
| The HomeScreen latch byte-identical | Task 1 (hash), Tasks 8 and 14 (compare) |

Placeholder scan: every step names its files, code, commands and expected output. Type consistency: `isTextScaledUp`, `ScrollWhenTall`, `ScaleDownToFit`, `ScrollWhenScaledUp`, `ScrollsInPlaceUnlessScaledUp` (Task 2) are the names Tasks 3-6 use; `TextScalePolicy.v2Cap`, `textScaleCapProvider`, `RootTextScaleClamp`, `appShell(maxTextScale:)` (Task 8) are the names the shell edit, the tests and the in-chat Games test use; `rootTextScaleCap` (Task 1) is the name the surface tests use; `bootTimeline` (Task 11) is the name `main.dart` uses.
