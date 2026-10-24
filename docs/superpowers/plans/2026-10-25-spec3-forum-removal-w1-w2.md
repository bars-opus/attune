# Spec 3 Forum Removal, Waves W1 (client removal) and W2 (stop producers) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Forums disappear from the Attune app (no tab, screen, route, compose option, manual topic, copy or tappable push), and every server path that could create, read or announce forum content is shut and shown to be shut, while Opinions, polls, tags, reports, bans, mutes and in-chat Games behave exactly as before.

**Architecture:** W1 is one client release: forum pushes are re-routed to home first (so nothing points at a route when the routes go), then the router, the Opinions shell, the tag page and the "+" entry lose their forum halves, the `lib/features/forums/**` tree is deleted, and the manual, copy and translations stop naming Forums. An architecture test grows task by task and pins that nothing names the removed code. W2 is server-only: four migrations unschedule the forum crons, close every forum RPC, table and view to clients, cancel queued forum pushes and add `public.forum_retirement_health()`; the two forum edge-function folders and three operator scripts are deleted; `supabase/tests/forum_retirement_contracts.sql` proves all of it plus unchanged Opinions behaviour. Every test and SQL block in this plan was run while writing it: the Dart tests against a scratch copy of the tree at `a7b07e79`, the SQL inside rolled-back transactions on `attune_spec3a`.

**Tech Stack:** Flutter 3.29.1 (Dart 3.7), Riverpod 2.6, GoRouter 10.2, Supabase Postgres 17 with pg_cron, Supabase CLI 2.75, psql.

**Spec:** `docs/superpowers/specs/2026-10-24-forum-removal-design.md` (read all of it, including §11 changelog and "Owner approval"), plus the "Controller rulings for the fix pass" at the end of `docs/superpowers/specs/2026-10-24-cross-spec-review.md`.

## Global Constraints

- Work in the main working tree on `main` (`/Users/user/attune`). The owner may have uncommitted edits: never revert, stash, stage, checkout or reformat them; if a file this plan edits is already modified, edit on top of the owner's version.
- **NO commits.** No `git add`, `git rm`, `git commit`, `git stash`, `git checkout`, `git reset`. Delete files with plain `rm`. Every task ends with "Run tests", not "Commit".
- Never `dart format` a pre-existing file (the repo uses an older formatter). Format only the five Dart test files this plan creates: `test/core/notifications/retired_forum_push_routing_test.dart`, `test/features/opinions/opinions_tab_shell_test.dart`, `test/features/opinions/tag_browse_screen_test.dart`, `test/core/widgets/create_content_chooser_test.dart`, `test/architecture/no_forum_references_test.dart`. `lib/core/widgets/create_content_chooser.dart` is rewritten but pre-existing: never format it.
- **Opinions stays exactly as it is.** Keep everything spec §4 names: `forum_reports`, the `forum_content_removed` / `forum_posting_banned` types and their tap cases (`notification_config.dart` lines 185-192 today), `private.enqueue_forum_notification`, `private.assert_can_post`, `public.admin_confirm_content_removal`, `post_polls` / `poll_options` / `poll_votes` and their RPCs including **the anon grant on `public.get_post_poll(uuid,uuid)`**, tags and tag RPCs, moderation and bans, `opinion_mutes` / `MutedAuthorsScreen`, `PollTarget`, `PollRepository` (its `getPollIdsForTopics` waits for W3), `FeedCacheStore`, `ForumSchimmer`, `UniversalBubble` and `ChatTextField` including their forum-only optional parameters.
- **Don't touch in-chat Games:** `lib/features/games/**`, `lib/features/community/**`, the game routes in `app_router.dart`, `ChatScreen`'s game entry points, `UniversalBubble` parameters, `auth_exports.dart`, `report_custom_question`.
- Not edited (spec §3.2 / §3.11 / §8): `home_screen.dart`, `home_widget.dart`, `tabs_with_content.dart`, `main.dart`, `discover_feed_screen.dart` (it compiles unchanged, V1), `intro_screen.dart`, `login_profile.dart`, `opinions_docs.dart`, `settings_data.dart`, `manual_content_guard_test.dart`, `universal_bubble_test.dart`, `poll_repository.dart`, `poll_providers.dart`, `process-scheduled-notifications` (its `forum_post_id` / `topic_id` allowlist stays), `ATTUNE_MASTER_SPEC.md`, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, comment-only forum mentions in files this plan does not otherwise edit.
- SQL runs only on the local scratch database `attune_spec3a`, only through `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a`. Contracts are `BEGIN … ROLLBACK`. Confirm the target first (`psql -X -d attune_spec3a -c 'select current_database()'`). NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` (it runs `dropdb`/`createdb`) or `scripts/local_pg_grants.sql` (its blanket grants undo the W2 revokes). This is stricter than spec §7.1 step 5: the from-zero check is CI's `sql-contracts` job, never a local rebuild.
- **Migrations:** new files only; never edit an applied migration. Names and order are spec §6.2's; timestamps are assigned here, later than every applied migration (newest today: `20261024100800_my_closed_story_items.sql`): `20261025090000_forum_retire_scheduled_jobs.sql`, `20261025090100_forum_revoke_client_access.sql`, `20261025090200_forum_cancel_queued_pushes.sql`, `20261025090300_forum_retirement_health.sql`. If `ls supabase/migrations | tail -1` shows a file at or after `20261025090000` when Task 5 starts, shift all four to the next free `…0000` hour, keeping the 100-second steps and the order.
- Supabase CLI 2.75 does not wrap a migration in a transaction: a multi-statement migration carries its own `BEGIN; … COMMIT;`; a single-statement one (one `DO` block or one `UPDATE`) is atomic on its own. Every migration is idempotent; every new `SECURITY DEFINER` function has `SET search_path = ''` and schema-qualifies every name; grants and revokes are explicit; no `CREATE INDEX CONCURRENTLY`.
- **No deploys.** `supabase db push`, `supabase functions delete activate-topics` / `forum-quiet-check` and the cron unscheduling (via migration) are the owner's, from the "Owner deploy checklist" at the end. The plan never deploys anything and never runs a command against the linked project.
- No new packages. Riverpod, Supabase and GoRouter as they are. No `attune_environment` setting is read or set. Don't read `.env*` or credentials.
- Spec 3 W1-W2 run BEFORE Spec 1. Edits to the files Spec 1 touches later (spec §9; listed under "Shared with Spec 1" below) are line-scoped exactly as given here; nothing else in those files moves.
- **Regression gate (end of Task 4 and Task 7):** the full `flutter test` passes ("All tests passed!"), and `flutter analyze --no-pub` shows no new errors: today's only errors are 8, all under `packages/video_compress/example/` (vendored), and `flutter analyze --no-pub lib test` has zero errors.

## Review Focus

1. A retired forum push whose `topic_id` is not a string (a hand-built or legacy row carrying `42`): today's handler casts it `as String?` and throws before navigating; a person tapping it expects home. Test: Task 1, Step 1 (`a retired push with a non-string topic_id lands on home`).
2. A named navigation left behind (`context.pushNamed('forumInsight')` or a `name: 'debateRoom'` route): it compiles after the `GoRoute`s go and throws only when tapped. Test: Task 1, Step 6 (`name:` pattern) and Task 3, Step 3 (any `'debateRoom' | 'sideSelection' | 'forumInsight'` string).
3. Dismissing the "+" sheet without posting: the old chooser stashed the picked row in a static field that could replay; a person who swipes the composer away expects nothing else to open and no feed refresh. Test: Task 3, Step 1 (`dismissing the composer opens nothing else`).
4. A guest tapping Follow on a tag page after its tabs go: they expect the same "Sign in to perform this action" prompt, not a silent tap or an error. Test: Task 2, Step 10 (`a guest tapping Follow is asked to sign in`).
5. A forum cron registered by hand under a different name (production already had the untracked `mark-quiet-forums`): it must be unscheduled by what it runs, and the health check must turn red if one comes back. Test: Task 5, Step 9 (decoy job swept by migration 1) and Task 7, Step 1 (health check flags `nightly-cleanup-copy`).

## Spec deviations found while verifying the code (read before Task 1)

- **D-1 (W2 migration 2, service_role on tables).** Spec §6.2 revokes ALL on the 8 forum **tables** from `service_role` too. That breaks the kept, passing contract `supabase/tests/service_role_grants_test.sql`, which requires SELECT and UPDATE for `service_role` on every `public` table (verified: one revoke on `forum_topics` makes it fail "1 table(s) unreadable by service_role … forum_topics"). This plan revokes the 8 tables from `PUBLIC, anon, authenticated` only; the 29 functions and the 2 views are revoked from `service_role` as well. Stale edge functions stay inert: `activate-topics` pushes only after `activate_pending_topics()` succeeds, and `forum-quiet-check` pushes only through `notify_quiet_topic()`; both RPCs lose `service_role` EXECUTE. W3 drops the tables.
- **D-2 (contract E, strike 3).** The live `admin_confirm_content_removal` (last defined in `20260802120000`, identical on `attune_spec3a`) raises `42702 column reference "banned_until" is ambiguous` at the third confirmed removal: `RETURNS TABLE (violation_count int, banned_until timestamptz)` makes `banned_until` an OUT variable that collides with `profiles.banned_until` in `SELECT GREATEST(COALESCE(banned_until, now()), now()) …`. The whole call rolls back, so the 7-day ban never applies. This is a pre-existing Opinions defect (call it **F-2**, next to the spec's F-1); Opinions stays as it is, so it is not fixed here. Contract E asserts strikes 1 and 2 and checks the ban gate with a ban written directly; the owner should route the fix to Spec 1 W9, which re-creates this function anyway.
- **D-3 (architecture test, copy rule scope).** Spec §7.4 forbids any string literal matching `\b[Ff]orums?\b` in `lib/**` and `test/**`. In `test/**` that fails on the kept `test/core/widgets/universal_bubble_test.dart` (`'forums-shaped bubble'`, lines 510-608) and on the new tests' own `find.text('Forums')` absence checks. The copy rule runs over `lib/**` only; `test/**` keeps the import, class, provider, route and RPC/relation rules.
- **D-4 (analyzer timing).** Spec §6.1 step 10 says `flutter analyze` is clean only after the deletions because the forum folder names the removed route constants. It doesn't: the forum screens navigate by name strings (`pushNamed('debateRoom')`, `'forumInsight'`, `'sideSelection'`), so the router task analyzes clean. The one transient break is `forums_section.dart` passing `onTopicSubmitted`, and Task 3 deletes that file in the same task that removes the parameter. Because a leftover name string would compile and throw, the architecture test forbids those strings (Review Focus 2).
- **D-5 (test overrides).** Beyond spec §7.2's override list, the shell test also overrides `allTagsProvider` (Discover's tag chips), and the FAB tests override `navVisibilityProvider` to `false`: `CreateContentFab` is scroll-aware and ignores taps while the nav bar shows.
- **D-6 (local "service role").** On `attune_spec3a` the `service_role` role has no EXECUTE on `admin_confirm_content_removal` (only the owner does). The contract calls it as the connecting owner with a `service_role` JWT claim, which is what the function's `auth.role()` check reads; that is also how it behaves under CI's `postgres` login.
- **Baselines today (record your own at execution time):** 14 contract files already fail on `attune_spec3a` before any Spec 3 change (`ai_assist_draft_share`, `ai_assistant_quota`, `ai_assistant_quota_evasion_regression`, `ai_assistant_schema`, `ai_processing_consent`, `ai_session_admit`, `ai_session_approve_activate`, `ai_session_dispatch_claim`, `ai_session_prepare`, `ai_session_purge`, `couple_map_presence`, `game_message`, `reminder_delivery`, `together_events`); the W2 gate is "no new FAIL line". `flutter analyze --no-pub` reports 8 errors, all in `packages/video_compress/example/`.

## Shared with Spec 1 (spec §9): the only lines this plan touches

| File | This plan changes exactly |
|---|---|
| `lib/features/onboarding/presentation/widgets/profile_setup_step.dart` | the subtitle string (line 22) |
| `lib/app/documentations/user_manual/data/manual_documentation_registry.dart` | the `forum_docs.dart` import (line 22) and the `ForumDocs(),` entry (line 133) |
| `lib/app/documentations/user_manual/data/chat_docs.dart` | the `chat_not_public` content string (line 56) |
| `test/widget_test.dart` | lines 10-11, 24-47 and 61 removed; one `findsNothing` added |
| `lib/core/notifications/config/notification_config.dart` | the three retired cases (lines 163-172) |
| `lib/app/routing/app_router.dart` | lines 35-38, 245-247 and 549-599 removed |
| `lib/i10n/app_*.arb`, `lib/i10n/generated/*` | `mutedItemSubtitle` only |
| `lib/architecture/FORUM.md` | five banner lines (Spec 3 owns this file) |
| `lib/home/widgets/forum_home.dart` | deleted (S1 W10's dead-code pass should not expect it) |

Line numbers are at `a7b07e79`; every edit below is an exact-string replacement, so an owner edit elsewhere in the file doesn't shift it.

## File map

**W1 (Tasks 1-4)**
- Create: `test/core/notifications/retired_forum_push_routing_test.dart` (Task 1): the real tap handler against a real `GoRouter`.
- Create: `test/architecture/no_forum_references_test.dart` (Task 1; extended in Tasks 3, 4, 5): no dangling forum names.
- Create: `test/features/opinions/opinions_tab_shell_test.dart` (Task 2; extended in Task 3): the one-section Opinions shell.
- Create: `test/features/opinions/tag_browse_screen_test.dart` (Task 2): the one-list tag page.
- Create: `test/core/widgets/create_content_chooser_test.dart` (Task 3): "+" opens the composer directly.
- Modify: `lib/core/notifications/config/notification_config.dart:163-172` (Task 1).
- Modify: `test/core/notifications/notification_tap_routing_test.dart:24-37` (Task 1).
- Modify: `lib/app/routing/app_router.dart:35-38, 245-247, 549-599` (Task 1).
- Modify: `lib/features/opinions/presentation/screen/opinions_tab.dart:9-11, 28-83, 87-93, 129-130, 202, 332-345` (Task 2).
- Modify: `lib/features/opinions/presentation/screen/tag_browse_screen.dart:5-7, 13-33, 43-57, 94-100, 108, 146-197, 201-255, 308-345` (Task 2).
- Modify: `lib/features/opinions/presentation/screen/tag_search_screen.dart:57` (Task 2).
- Rewrite: `lib/core/widgets/create_content_chooser.dart` (Task 3; not formatted).
- Modify: `lib/core/widgets/create_content_fab.dart:6-19, 26, 31-37, 40-43, 62` (Task 3).
- Modify: `test/widget_test.dart:10-11, 24-47, 61, 78` (Task 3).
- Delete: `lib/features/forums/` (18 files), `lib/home/widgets/forum_home.dart`, `test/features/forums/` (1 file) (Task 3).
- Delete: `lib/app/documentations/user_manual/data/forum_docs.dart` (Task 4).
- Modify: `manual_documentation_registry.dart:22, 133`, `chat_docs.dart:56`, `profile_setup_step.dart:22`, `lib/i10n/app_{en:321,de:326,es:325,fr:326,it:326,pt:326}.arb`, `lib/i10n/generated/app_localizations.dart:1111`, `lib/i10n/generated/app_localizations_{en,de,es,fr,it,pt}.dart:541`, `lib/architecture/FORUM.md:1, 442, 727, 1104, 1437` (Task 4).

**W2 (Tasks 5-7)**
- Create: `supabase/migrations/20261025090000_forum_retire_scheduled_jobs.sql` (Task 5).
- Create: `supabase/tests/forum_retirement_contracts.sql` (Task 5; extended in Tasks 6 and 7).
- Delete: `supabase/functions/activate-topics/`, `supabase/functions/forum-quiet-check/`, `supabase/sql/schedule_activate_topics.sql`, `supabase/sql/schedule_forum_quiet_check.sql`, `supabase/sql/patch_mark_quiet_forums_null_last_post.sql` (Task 5).
- Create: `supabase/migrations/20261025090100_forum_revoke_client_access.sql` (Task 6).
- Create: `supabase/migrations/20261025090200_forum_cancel_queued_pushes.sql`, `supabase/migrations/20261025090300_forum_retirement_health.sql` (Task 7).

---

## W1: client removal (one app release, no server change)

### Task 1: Retired forum pushes land on home, then the three forum routes go

**Files:**
- Create: `test/core/notifications/retired_forum_push_routing_test.dart`
- Create: `test/architecture/no_forum_references_test.dart`
- Modify: `lib/core/notifications/config/notification_config.dart:163-172`
- Modify: `test/core/notifications/notification_tap_routing_test.dart:24-37`
- Modify: `lib/app/routing/app_router.dart:35-38, 245-247, 549-599`

**Interfaces:**
- Consumes: `buildNanoEmbryoNotificationConfig()` returns a `NotificationConfig` whose `onNotificationTap` is `void Function(AppNotification notification, BuildContext context)?`; `AppNotification({required String id, required String title, required String body, Map<String, dynamic>? data, required DateTime createdAt})`; `RouteNames.home == '/home'`, `RouteNames.opinionLoader == '/opinionLoader'`; `StateProbe(String label)` from `test/helpers/state_probe.dart` renders the text `'<label> 0'`.
- Produces: the three retired types call `GoRouter.of(context).go(RouteNames.home)` and read no payload (Steps 1-5, done first so no tap points at a route when Steps 6-11 remove it); `RouteNames` without `debateRoom`, `sideSelection`, `forumInsight`; `app_router.dart` imports nothing from `features/forums`. In the architecture test: `const _self = 'test/architecture/no_forum_references_test.dart'`, `List<File> _dartFiles(List<String> roots)`, `List<String> _hits(Iterable<File> files, List<RegExp> patterns, {bool Function(String path, String line)? allow})` (returns `path:line: pattern` per non-comment match). Tasks 3, 4 and 5 add tests to this file.

- [ ] **Step 0: Record the baselines (once, before any edit)**

Run: `cd /Users/user/attune && git status --short && git log --oneline -1`
Expected: `a7b07e79 …` (or later) and the owner's own changes, if any. Note any file this plan edits that is already modified; edit on top of it.

Run: `flutter analyze --no-pub 2>&1 | grep -E '^\s*error ' | grep -vc 'packages/video_compress/example/'`
Expected: `0` (the 8 existing errors are all in the vendored example).

- [ ] **Step 1: Write the failing test**

Create `test/core/notifications/retired_forum_push_routing_test.dart`:

```dart
// Spec 3 (forum removal) §5: a forum push sent before the producers stopped
// can still be tapped from the tray. Whatever its payload, it lands on home,
// never on a removed route. Drives the real tap handler against a real
// GoRouter, as app_shell_keep_mounted_test.dart does.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/notifications/config/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/state_probe.dart';

/// A context below the router, captured by the start screen.
late BuildContext _tapContext;

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder:
          (_, __) => Builder(
            builder: (context) {
              _tapContext = context;
              return const StateProbe('START');
            },
          ),
    ),
    GoRoute(
      path: RouteNames.home,
      builder: (_, __) => const StateProbe('HOME'),
    ),
    GoRoute(
      path: RouteNames.opinionLoader,
      builder: (_, state) => StateProbe('OPINION ${state.extra}'),
    ),
  ],
);

/// Pumps the router, taps a push carrying [data], and returns the location
/// of the top screen (a `push` stacks a match; a `go` replaces the stack).
Future<String> _tap(WidgetTester tester, Map<String, dynamic> data) async {
  final router = _router();
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  final config = buildNanoEmbryoNotificationConfig();
  config.onNotificationTap!(
    AppNotification(
      id: 'n1',
      title: 'Forum check',
      body: 'Tap me',
      data: data,
      createdAt: DateTime(2026, 10, 25),
    ),
    _tapContext,
  );
  await tester.pumpAndSettle();
  return router.routerDelegate.currentConfiguration.last.matchedLocation;
}

void main() {
  const retired = ['forum_topic_activated', 'forum_activity', 'forum_quiet'];
  final payloads = <String, Map<String, dynamic> Function(String type)>{
    'with a topic_id': (t) => {'type': t, 'topic_id': 'topic-1'},
    'with an empty topic_id': (t) => {'type': t, 'topic_id': ''},
    'with no topic_id': (t) => {'type': t},
  };

  for (final type in retired) {
    for (final entry in payloads.entries) {
      testWidgets('$type ${entry.key} lands on home', (tester) async {
        expect(await _tap(tester, entry.value(type)), RouteNames.home);
        expect(find.text('HOME 0'), findsOneWidget);
      });
    }
  }

  testWidgets('a retired push with a non-string topic_id lands on home', (
    tester,
  ) async {
    // A hand-built or legacy row can carry a number here; the old handler
    // cast it with `as String?` and threw before navigating anywhere.
    expect(
      await _tap(tester, {'type': 'forum_activity', 'topic_id': 42}),
      RouteNames.home,
    );
    expect(tester.takeException(), isNull);
  });

  for (final type in ['forum_content_removed', 'forum_posting_banned']) {
    testWidgets('$type (kept Opinions moderation notice) lands on home', (
      tester,
    ) async {
      expect(
        await _tap(tester, {'type': type, 'opinion_id': 'op-1'}),
        RouteNames.home,
      );
    });
  }

  testWidgets('opinion_liked still opens the opinion loader', (tester) async {
    expect(
      await _tap(tester, {'type': 'opinion_liked', 'opinion_id': 'op-1'}),
      RouteNames.opinionLoader,
    );
    expect(find.text('OPINION op-1 0'), findsOneWidget);
  });
}
```

Run: `dart format test/core/notifications/retired_forum_push_routing_test.dart`
Expected: `Formatted 1 file (0 changed)`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/notifications/retired_forum_push_routing_test.dart`
Expected: FAIL, `Some tests failed.` Four failures: the three `… with a topic_id lands on home` tests (`Expected: '/home'  Actual: '/forumInsight'`) and `a retired push with a non-string topic_id lands on home` (`_TypeError`). The other ten pass.

- [ ] **Step 3: Route the three retired types home**

In `lib/core/notifications/config/notification_config.dart`, replace:

```dart
        case 'forum_topic_activated':
        case 'forum_activity':
        case 'forum_quiet':
          final topicId = notification.data?['topic_id'] as String?;
          if (topicId != null && topicId.isNotEmpty) {
            GoRouter.of(context).push(RouteNames.forumInsight, extra: topicId);
          } else {
            GoRouter.of(context).go(RouteNames.home);
          }
          return;
```

with:

```dart
        case 'forum_topic_activated':
        case 'forum_activity':
        case 'forum_quiet':
          // Forums were retired (Spec 3, 2026-10-24). A push sent before the
          // producers stopped can still be tapped from the tray: home, never a
          // removed route.
          GoRouter.of(context).go(RouteNames.home);
          return;
```

The `forum_content_removed` / `forum_posting_banned` cases below it and every other case stay as they are.

- [ ] **Step 4: Delete the old forum payload group**

In `test/core/notifications/notification_tap_routing_test.dart`, delete this group and the blank line after it (it asserts the route Step 3 removed); the 36-questions and opinion groups stay:

```dart
  group('forum_topic_activated / forum_activity / forum_quiet payload extraction', () {
    test('topic_id present', () {
      final data = <String, dynamic>{'type': 'forum_activity', 'topic_id': 'topic-1'};
      final topicId = data['topic_id'] as String?;
      expect(topicId, 'topic-1');
    });

    test('empty topic_id treated as absent', () {
      final data = <String, dynamic>{'type': 'forum_quiet', 'topic_id': ''};
      final topicId = data['topic_id'] as String?;
      expect(topicId != null && topicId.isNotEmpty, isFalse);
    });
  });

```

- [ ] **Step 5: Run tests**

Run: `flutter test test/core/notifications/`
Expected: PASS, `All tests passed!`

Run: `grep -rn "RouteNames.forumInsight" lib test | grep -v "^lib/app/routing/app_router.dart"`
Expected: no output.

Run: `flutter analyze --no-pub lib/core/notifications/config/notification_config.dart test/core/notifications 2>&1 | grep -E '^\s*(error|warning) '`
Expected: no output.

- [ ] **Step 6: Write the failing test**

Create `test/architecture/no_forum_references_test.dart`:

```dart
// Spec 3 (forum removal) §7.4: nothing in the app or its tests still names a
// removed forum route, screen, provider, RPC, table or push. House pattern of
// no_pairing_strings_test.dart; full-line comments (`//`, `///`) are skipped,
// as in design_tokens_test.dart, so historic notes in kept files stay. Every
// failure reads `path:line: pattern`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _self = 'test/architecture/no_forum_references_test.dart';

/// Every `.dart` file under [roots], except this one.
List<File> _dartFiles(List<String> roots) => [
  for (final root in roots)
    for (final entity in Directory(root).listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          entity.path != _self)
        entity,
];

/// `path:line: pattern` for each non-comment line of [files] that matches one
/// of [patterns], unless [allow] accepts that path and line.
List<String> _hits(
  Iterable<File> files,
  List<RegExp> patterns, {
  bool Function(String path, String line)? allow,
}) {
  final hits = <String>[];
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      for (final pattern in patterns) {
        if (!pattern.hasMatch(line)) continue;
        if (allow != null && allow(file.path, line)) continue;
        hits.add('${file.path}:${i + 1}: ${pattern.pattern}');
      }
    }
  }
  return hits;
}

void main() {
  test('no removed forum route is named', () {
    final hits = _hits(_dartFiles(['lib', 'test']), [
      RegExp(r'RouteNames\.(debateRoom|sideSelection|forumInsight)\b'),
      RegExp(r'''['"]/(debateRoom|sideSelection|forumInsight)['"]'''),
      RegExp(r'''name:\s*['"](debateRoom|sideSelection|forumInsight)['"]'''),
    ]);
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
```

Run: `dart format test/architecture/no_forum_references_test.dart`
Expected: `Formatted 1 file (0 changed)`.

- [ ] **Step 7: Run the test to verify it fails**

Run: `flutter test test/architecture/no_forum_references_test.dart`
Expected: FAIL. The reason lists nine hits, all in `lib/app/routing/app_router.dart`: lines 245, 246, 247 (`'/…'` strings), 550, 575, 588 (`RouteNames.…`) and 551, 576, 589 (`name: '…'`).

- [ ] **Step 8: Remove the three `GoRoute`s (bottom-up, so earlier line numbers stay valid)**

In `lib/app/routing/app_router.dart`, delete this block exactly (lines 549-599); the `tagBrowse` route above and the `healingJourney` route below stay:

```dart
      GoRoute(
        path: RouteNames.debateRoom,
        name: 'debateRoom',
        builder: (context, state) {
          final args =
              state.extra
                  as ({
                    String topicId,
                    String topicTitle,
                    String userSide,
                    TopicModel? initialTopic,
                  })?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('Topic unavailable.')),
            );
          }
          return DebateRoomScreen(
            topicId: args.topicId,
            topicTitle: args.topicTitle,
            userSide: args.userSide,
            initialTopic: args.initialTopic,
          );
        },
      ),
      GoRoute(
        path: RouteNames.sideSelection,
        name: 'sideSelection',
        builder: (context, state) {
          final topic = routeExtra<TopicModel>(state);
          if (topic == null) {
            return const Scaffold(
              body: Center(child: Text('Topic unavailable.')),
            );
          }
          return SideSelectionScreen(topic: topic);
        },
      ),
      GoRoute(
        path: RouteNames.forumInsight,
        name: 'forumInsight',
        builder: (context, state) {
          final topicId = routeExtra<String>(state);
          if (topicId == null) {
            return const Scaffold(
              body: Center(child: Text('Topic unavailable.')),
            );
          }
          return ForumInsightScreen(topicId: topicId);
        },
      ),
```

- [ ] **Step 9: Remove the three route constants**

Replace:

```dart
  static const String tagBrowse = '/tagBrowse';
  static const String debateRoom = '/debateRoom';
  static const String sideSelection = '/sideSelection';
  static const String forumInsight = '/forumInsight';
  static const String healingJourney = '/healingJourney';
```

with:

```dart
  static const String tagBrowse = '/tagBrowse';
  static const String healingJourney = '/healingJourney';
```

- [ ] **Step 10: Remove the four forum imports**

Replace:

```dart
import 'package:attune/features/opinions/presentation/screens/opinion_thread_loader.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/presentation/screens/debate_room_screen.dart';
import 'package:attune/features/forums/presentation/screens/forum_insight_screen.dart';
import 'package:attune/features/forums/presentation/screens/side_selection_screen.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
```

with:

```dart
import 'package:attune/features/opinions/presentation/screens/opinion_thread_loader.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
```

Nothing else in `app_router.dart` changes; every Games route stays.

- [ ] **Step 11: Run tests**

Run: `flutter test test/architecture/no_forum_references_test.dart test/core/notifications/`
Expected: PASS, `All tests passed!`

Run: `grep -n "forums/\|debateRoom\|sideSelection\|forumInsight\|TopicModel" lib/app/routing/app_router.dart`
Expected: no output.

Run: `flutter analyze --no-pub lib 2>&1 | grep -E '^\s*error '`
Expected: no output (the forum screens navigate by name strings, so nothing else breaks; D-4).

---

### Task 2: The Opinions tab and the tag page lose their Forums tab

**Files:**
- Create: `test/features/opinions/opinions_tab_shell_test.dart`
- Create: `test/features/opinions/tag_browse_screen_test.dart`
- Modify: `lib/features/opinions/presentation/screen/opinions_tab.dart:9-11, 28-83, 87-93, 129-130, 202, 332-345`
- Modify: `lib/features/opinions/presentation/screen/tag_browse_screen.dart:5-7, 13-33, 43-57, 94-100, 108, 146-197, 201-255, 308-345`
- Modify: `lib/features/opinions/presentation/screen/tag_search_screen.dart:57`

**Interfaces:**
- Consumes: `currentUserIdProvider` (`Provider<String?>`), `userRelationshipStatusProvider` and `myAuthorHandleProvider` (`FutureProvider<String?>`), `followingFeedProvider` / `discoverFeedProvider` (`AsyncNotifierProvider<FollowingFeedNotifier|DiscoverFeedNotifier, List<OpinionModel>>`), `allTagsProvider` (`FutureProvider<List<String>>`), `sharedPreferencesProvider`, `navVisibilityProvider` (`StateProvider<bool>`), `SimpleTabs`, `CreateContentFab`; `opinionsByTagProvider` (`AsyncNotifierProvider.family<OpinionsByTagNotifier, List<OpinionModel>, String>`; `OpinionsByTagNotifier.build(String arg)`, `bool get hasMore`), `isTagFollowedProvider` (`Provider.family<bool, String>`), `OpinionModel({required String id, required String authorHandle, required bool isMine, required String content, required String relationshipStatus, required int likeCount, required int dislikeCount, required int commentCount, required DateTime createdAt})`, `OpinionCard`.
- Produces: `OpinionsTab` builds `Scaffold(backgroundColor: colorScheme.onBackground, body: _OpinionsSection(isAuthenticated: …))`; `_OpinionsSection({required bool isAuthenticated})`; `OpinionsTab` no longer imports `features/forums` or passes `onTopicSubmitted` (Task 3 removes the parameter). `TagBrowseScreen` with no `TabController`, no `features/forums` import, `body:` = one opinions `Builder`, `bottom:` = the Follow row only with `preferredSize: Size.fromHeight(36 + Spacing.sm * 2)`. Shell-test helpers reused by Task 3: `final _uid = StateProvider<String?>`, `Future<ProviderContainer> _pumpTab(WidgetTester tester, {String? userId, double textScale = 1})`, `int _feedIndex(WidgetTester tester)`.

- [ ] **Step 1: Write the failing test**

Create `test/features/opinions/opinions_tab_shell_test.dart`:

```dart
// Spec 3 (forum removal) §7.2, risks R2-R4: with the Forums tab gone the
// Opinions tab is one section. Following/Discover sit directly under the app
// bar, a guest lands on Discover, a sign-in mid-session jumps to Following,
// switching sub-tabs brings a hidden nav back, and the header lays out at
// default and largest text.
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/core/widgets/app_tabs.dart';
import 'package:attune/core/widgets/create_content_fab.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/providers/profile_providers.dart';
import 'package:attune/features/opinions/presentation/screen/opinions_tab.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyFollowing extends FollowingFeedNotifier {
  @override
  Future<List<OpinionModel>> build() async => const [];
}

class _EmptyDiscover extends DiscoverFeedNotifier {
  @override
  Future<List<OpinionModel>> build() async => const [];
}

/// The signed-in user id the test flips; null is a guest.
final _uid = StateProvider<String?>((ref) => null);

Future<ProviderContainer> _pumpTab(
  WidgetTester tester, {
  String? userId,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(1170, 2532); // 390 x 844 phone
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWith((ref) => ref.watch(_uid)),
      userRelationshipStatusProvider.overrideWith((ref) async => 'single'),
      myAuthorHandleProvider.overrideWith((ref) async => 'quiet-otter'),
      followingFeedProvider.overrideWith(_EmptyFollowing.new),
      discoverFeedProvider.overrideWith(_EmptyDiscover.new),
      allTagsProvider.overrideWith((ref) async => const <String>[]),
    ],
  );
  addTearDown(container.dispose);
  container.read(_uid.notifier).state = userId;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(textScale)),
                    child: child!,
                  ),
              home: const OpinionsTab(),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The Following (0) / Discover (1) page currently selected.
int _feedIndex(WidgetTester tester) =>
    tester.widget<TabBarView>(find.byType(TabBarView)).controller!.index;

void main() {
  testWidgets('a guest sees one Following/Discover bar and lands on Discover', (
    tester,
  ) async {
    await _pumpTab(tester);

    expect(find.text('Forums'), findsNothing);
    expect(find.byType(SimpleTabs), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(_feedIndex(tester), 1);
    expect(find.byType(CreateContentFab), findsOneWidget);
  });

  testWidgets('a signed-in user lands on Following', (tester) async {
    await _pumpTab(tester, userId: 'u1');

    expect(find.text('Forums'), findsNothing);
    expect(_feedIndex(tester), 0);
  });

  testWidgets('signing in mid-session jumps from Discover to Following', (
    tester,
  ) async {
    final container = await _pumpTab(tester);
    expect(_feedIndex(tester), 1);

    container.read(_uid.notifier).state = 'u1';
    await tester.pumpAndSettle();

    expect(_feedIndex(tester), 0);
  });

  testWidgets('switching Following/Discover brings a hidden nav back', (
    tester,
  ) async {
    final container = await _pumpTab(tester, userId: 'u1');
    container.read(navVisibilityProvider.notifier).state = false;
    await tester.pump();

    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();

    expect(_feedIndex(tester), 1);
    expect(container.read(navVisibilityProvider), isTrue);
  });

  for (final scale in [1.0, 2.0]) {
    for (final userId in [null, 'u1']) {
      testWidgets('the header lays out at text scale $scale '
          '(${userId == null ? 'guest' : 'signed in'})', (tester) async {
        await _pumpTab(tester, userId: userId, textScale: scale);

        expect(tester.takeException(), isNull);
        expect(find.text('Following'), findsOneWidget);
      });
    }
  }
}
```

Run: `dart format test/features/opinions/opinions_tab_shell_test.dart`
Expected: `Formatted 1 file (0 changed)`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/opinions/opinions_tab_shell_test.dart`
Expected: FAIL, `Some tests failed.` The guest and signed-in tests report `Found 1 widget with text "Forums"`, and the Forums section's own `Supabase.instance` assertion (`supabase.dart … line 44`) appears in every test, because `ForumsSection` is still mounted in the `IndexedStack`.

- [ ] **Step 3: Remove the forum imports**

In `lib/features/opinions/presentation/screen/opinions_tab.dart`, delete:

```dart
import 'package:attune/features/forums/presentation/providers/forum_providers.dart'
    show votingTopicsProvider;
import 'package:attune/features/forums/presentation/screens/forums_section.dart';
```

- [ ] **Step 4: Replace the outer tab shell with the one section**

Replace:

```dart
class _OpinionsTabState extends ConsumerState<OpinionsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _outerTabController;

  @override
  void initState() {
    super.initState();
    _outerTabController = TabController(length: 2, vsync: this);
    // Opinions/Forums sections are both kept alive in the IndexedStack, so a
    // scroll-hidden nav from one side would otherwise persist after
    // switching — see the matching reset in home_widget.dart's onTap.
    _outerTabController.addListener(_resetNavVisibilityOnSwitch);
  }

  void _resetNavVisibilityOnSwitch() {
    if (_outerTabController.indexIsChanging) {
      ref.read(navVisibilityProvider.notifier).state = true;
    }
  }

  @override
  void dispose() {
    _outerTabController.removeListener(_resetNavVisibilityOnSwitch);
    _outerTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(currentUserIdProvider) != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.onBackground,
      body: AnimatedBuilder(
        animation: _outerTabController,
        builder:
            (context, _) => IndexedStack(
              index: _outerTabController.index,
              children: [
                _OpinionsSection(
                  outerTabController: _outerTabController,
                  isAuthenticated: isAuthenticated,
                ),
                // ForumsSection renders for guests too as of
                // 20260821120000_public_forum_reads — Contributing/Explore/
                // debate rooms are all real-data anon-readable now, the same
                // way Discover already was. Guests can read; ForumsSection's
                // own children gate posting, voting, liking, reporting and
                // Forum Insight behind sign-in.
                ForumsSection(outerTabController: _outerTabController),
              ],
            ),
      ),
    );
  }
}
```

with:

```dart
class _OpinionsTabState extends ConsumerState<OpinionsTab> {
  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(currentUserIdProvider) != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.onBackground,
      body: _OpinionsSection(isAuthenticated: isAuthenticated),
    );
  }
}
```

- [ ] **Step 5: Drop `outerTabController` from `_OpinionsSection`**

Replace:

```dart
  const _OpinionsSection({
    required this.outerTabController,
    required this.isAuthenticated,
  });

  final TabController outerTabController;
  final bool isAuthenticated;
```

with:

```dart
  const _OpinionsSection({required this.isAuthenticated});

  final bool isAuthenticated;
```

- [ ] **Step 6: Correct the `didUpdateWidget` comment**

Replace:

```dart
    // _OpinionsSection is kept alive inside OpinionsTab's IndexedStack, so
    // it is never re-constructed on sign-in — initState's isAuthenticated
```

with:

```dart
    // _OpinionsSection is kept alive by the home shell's keep-alive tab page,
    // so it is never re-constructed on sign-in — initState's isAuthenticated
```

(`lib/home/widgets/tabs_with_content.dart:160` wraps each tab in `_KeepAlivePage`.) The rest of that comment and the logic stay.

- [ ] **Step 7: Drop the FAB's topic callback**

Replace:

```dart
          await _scrollToTop();
        },
        onTopicSubmitted: () => ref.invalidate(votingTopicsProvider),
      ),
```

with:

```dart
          await _scrollToTop();
        },
      ),
```

- [ ] **Step 8: Drop the Opinions/Forums row under the app bar**

Replace:

```dart
                    ),
                  ],
                  bottom: PreferredSize(
                    preferredSize: Size.fromHeight(48.h),
                    child: SimpleTabs(
                      tabs: const [
                        AppTabItem(
                          label: 'Opinions',
                          icon: Icons.rate_review_outlined,
                        ),
                        AppTabItem(label: 'Forums', icon: Icons.forum_outlined),
                      ],
                      controller: widget.outerTabController,
                      scrollable: false,
                    ),
                  ),
                ),
```

with:

```dart
                    ),
                  ],
                ),
```

The Following/Discover `SimpleTabs` sliver, the leading row, the Tags and search buttons, guest-on-Discover, the sign-in flip, the inner nav reset and scroll-to-top are unchanged.

- [ ] **Step 9: Run tests**

Run: `flutter test test/features/opinions/opinions_tab_shell_test.dart test/widget_test.dart`
Expected: PASS, `All tests passed!` (8 shell tests, 1 widget test).

Run: `flutter analyze --no-pub lib/features/opinions/presentation/screen/opinions_tab.dart 2>&1 | grep -E '^\s*(error|warning) '`
Expected: exactly one line, the pre-existing `Unused import: 'package:attune/features/auth/presentation/widgets/logout_action.dart'` (left as it is: not a forum change).

- [ ] **Step 10: Write the failing test**

Create `test/features/opinions/tag_browse_screen_test.dart`:

```dart
// Spec 3 (forum removal) §7.2, risk R6: a tag page is one list of opinions.
// No Opinions/Forums tabs; the title, Follow button, cards and empty state
// are unchanged, and the header lays out at default and largest text.
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/tag_browse_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

OpinionModel _opinion(String id) => OpinionModel(
  id: id,
  authorHandle: 'quiet-otter',
  isMine: false,
  content: 'Opinion $id about trust',
  relationshipStatus: 'single',
  likeCount: 0,
  dislikeCount: 0,
  commentCount: 0,
  createdAt: DateTime(2026, 10, 20),
);

/// One page, nothing more to load (no trailing spinner).
class _TagFeed extends OpinionsByTagNotifier {
  _TagFeed(this._items);
  final List<OpinionModel> _items;

  @override
  Future<List<OpinionModel>> build(String arg) async => _items;

  @override
  bool get hasMore => false;
}

Future<void> _pumpTagPage(
  WidgetTester tester, {
  List<OpinionModel> opinions = const [],
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(1170, 2532); // 390 x 844 phone
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(null),
        opinionsByTagProvider.overrideWith(() => _TagFeed(opinions)),
        isTagFollowedProvider.overrideWith((ref, slug) => false),
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(textScale)),
                    child: child!,
                  ),
              home: const TagBrowseScreen(tagSlug: 'trust'),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one list of opinions under the title and Follow button', (
    tester,
  ) async {
    await _pumpTagPage(tester, opinions: [_opinion('a'), _opinion('b')]);

    expect(find.text('#trust'), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);
    expect(find.byType(OpinionCard), findsNWidgets(2));
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);
    expect(find.text('Forums'), findsNothing);
    expect(find.text('Opinions'), findsNothing);
  });

  testWidgets('no opinions shows the opinions empty state', (tester) async {
    await _pumpTagPage(tester);

    expect(find.text('No opinions tagged #trust'), findsOneWidget);
    expect(find.textContaining('forums'), findsNothing);
  });

  testWidgets('a guest tapping Follow is asked to sign in', (tester) async {
    await _pumpTagPage(tester);

    await tester.tap(find.text('Follow'));
    await tester.pump();

    expect(find.text('Sign in to perform this action'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the header lays out at text scale $scale', (tester) async {
      await _pumpTagPage(tester, opinions: [_opinion('a')], textScale: scale);

      expect(tester.takeException(), isNull);
      expect(find.text('Follow'), findsOneWidget);
    });
  }
}
```

Run: `dart format test/features/opinions/tag_browse_screen_test.dart`
Expected: `Formatted 1 file (0 changed)`.

- [ ] **Step 11: Run the test to verify it fails**

Run: `flutter test test/features/opinions/tag_browse_screen_test.dart`
Expected: FAIL, `Some tests failed.` One failure: `one list of opinions …` (`Found 1 widget with type "TabBar"`). The empty-state, guest-Follow and text-scale tests already pass: they pin behaviour that must not change.

- [ ] **Step 12: Remove the forum imports**

In `lib/features/opinions/presentation/screen/tag_browse_screen.dart`, delete:

```dart
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/widgets/forum_card.dart';
```

- [ ] **Step 13: Update the class docs**

Replace:

```dart
/// Everything carrying one tag, newest first (ATTUNE_MASTER_SPEC.md §8.11
/// "Tag browsing", FORUM.md §7).
///
/// ONE screen with two tabs rather than two separate screens: a tag applies to
/// opinions and forum topics alike, so splitting them into different routes
/// would make the user guess which surface a tag has results on and navigate
/// twice to find out. Tabs put both counts one tap apart.
///
```

with:

```dart
/// Every opinion carrying one tag, newest first (ATTUNE_MASTER_SPEC.md §8.11
/// "Tag browsing", FORUM.md §7). One list: Forums were retired (Spec 3,
/// 2026-10), so there is no second tab.
///
```

Then replace:

```dart
/// A standalone pushed route with its own Scaffold, built on NestedScrollView
/// + SliverAppBar (the same SliverOverlapAbsorber/Injector pattern OpinionsTab
/// and ForumsSection use) so the title, follow button, and tab bar all scroll
/// away together as the list beneath scrolls — see _buildOpinionList /
/// _buildTopicList for the matching SliverOverlapInjector on the other side.
```

with:

```dart
/// A standalone pushed route with its own Scaffold, built on NestedScrollView
/// + SliverAppBar (the same SliverOverlapAbsorber/Injector pattern OpinionsTab
/// uses) so the title and follow button scroll away together as the list
/// beneath scrolls — see _buildOpinionList for the matching
/// SliverOverlapInjector on the other side.
```

- [ ] **Step 14: Drop the tab controller**

Replace:

```dart
class _TagBrowseScreenState extends ConsumerState<TagBrowseScreen>
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

```

with:

```dart
class _TagBrowseScreenState extends ConsumerState<TagBrowseScreen> {
```

- [ ] **Step 15: Drop the topic scroll handler and the topics watch**

Delete:

```dart
  bool _handleTopicScroll(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 200) {
      ref.read(forumTopicsByTagProvider(widget.tagSlug).notifier).loadMore();
    }
    return false;
  }

```

and delete the line:

```dart
    final topicsAsync = ref.watch(forumTopicsByTagProvider(widget.tagSlug));
```

- [ ] **Step 16: The app bar's `bottom:` holds only the Follow row**

Replace:

```dart
                  bottom: PreferredSize(
                    preferredSize: Size.fromHeight(48.h),
                    child: Column(
                      children: [
                        Padding(
```

with:

```dart
                  // The Follow row only: a small AppButton (36) inside
                  // Spacing.sm padding on every side.
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(36 + Spacing.sm * 2),
                    child: Column(
                      children: [
                        Padding(
```

Then replace:

```dart
                          ),
                        ),
                        SimpleTabs(
                          tabs: const [
                            AppTabItem(
                              label: 'Opinions',
                              icon: Icons.rate_review_outlined,
                            ),
                            AppTabItem(
                              label: 'Forums',
                              icon: Icons.forum_outlined,
                            ),
                          ],
                          controller: _tabController,
                          scrollable: false,
                        ),
                      ],
```

with:

```dart
                          ),
                        ),
                      ],
```

(`ButtonSize.small` is 36 logical pixels in `lib/core/widgets/buttons/app_button.dart:272`; the old 48.h box was sized for the removed tab row.)

- [ ] **Step 17: The body is the opinions list**

Replace:

```dart
        body: TabBarView(
          controller: _tabController,
          children: [
            // Builder gives this subtree a context BELOW the NestedScrollView,
            // which sliverOverlapAbsorberHandleFor requires to find the
            // handle — the outer build(context) here is above the
            // NestedScrollView, same reason DiscoverFeedScreen/ForumsSection
            // get theirs from their own build(context) as a separate widget.
            Builder(
              builder:
                  (context) => NotificationListener<ScrollNotification>(
                    onNotification: _handleOpinionScroll,
                    child: RefreshIndicator(
                      onRefresh:
                          () =>
                              ref
                                  .read(
                                    opinionsByTagProvider(
                                      widget.tagSlug,
                                    ).notifier,
                                  )
                                  .refresh(),
                      child: opinionsAsync.when(
                        loading: () => const ListviewLoadingShimmer(),
                        error: (error, stack) => ErrorStateWidget.from(error),
                        data:
                            (opinions) => _buildOpinionList(context, opinions),
                      ),
                    ),
                  ),
            ),
            Builder(
              builder:
                  (context) => NotificationListener<ScrollNotification>(
                    onNotification: _handleTopicScroll,
                    child: RefreshIndicator(
                      onRefresh:
                          () =>
                              ref
                                  .read(
                                    forumTopicsByTagProvider(
                                      widget.tagSlug,
                                    ).notifier,
                                  )
                                  .refresh(),
                      child: topicsAsync.when(
                        loading: () => const ListviewLoadingShimmer(),
                        error: (error, stack) => ErrorStateWidget.from(error),
                        data: (topics) => _buildTopicList(context, topics),
                      ),
                    ),
                  ),
            ),
          ],
        ),
```

with:

```dart
        // Builder gives this subtree a context BELOW the NestedScrollView,
        // which sliverOverlapAbsorberHandleFor requires to find the
        // handle — the outer build(context) here is above the
        // NestedScrollView, same reason DiscoverFeedScreen gets its own
        // from its own build(context) as a separate widget.
        body: Builder(
          builder:
              (context) => NotificationListener<ScrollNotification>(
                onNotification: _handleOpinionScroll,
                child: RefreshIndicator(
                  onRefresh:
                      () =>
                          ref
                              .read(
                                opinionsByTagProvider(widget.tagSlug).notifier,
                              )
                              .refresh(),
                  child: opinionsAsync.when(
                    loading: () => const ListviewLoadingShimmer(),
                    error: (error, stack) => ErrorStateWidget.from(error),
                    data: (opinions) => _buildOpinionList(context, opinions),
                  ),
                ),
              ),
        ),
```

- [ ] **Step 18: Delete `_buildTopicList`**

Delete this method and the blank line after it (`_buildOpinionList` above and `_emptyState` below stay):

```dart
  Widget _buildTopicList(BuildContext context, List<TopicModel> topics) {
    if (topics.isEmpty) {
      return _emptyState(
        context: context,
        icon: Icons.forum_outlined,
        title: 'No forums tagged #${widget.tagSlug}',
        subtitle: 'Submit a topic with this tag to start the conversation.',
      );
    }

    final hasMore =
        ref.read(forumTopicsByTagProvider(widget.tagSlug).notifier).hasMore;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverPadding(
          padding: EdgeInsets.all(Spacing.md.w),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index == topics.length) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              // No userSide passed: the browse RPC returns no per-viewer vote
              // state, so the card renders without a side indicator rather
              // than guessing one.
              return ForumCard(forum: topics[index]);
            }, childCount: topics.length + (hasMore ? 1 : 0)),
          ),
        ),
      ],
    );
  }

```

- [ ] **Step 19: Tag search hint**

In `lib/features/opinions/presentation/screen/tag_search_screen.dart`, replace:

```dart
              hintText: 'Find opinions and forums using a tag',
```

with:

```dart
              hintText: 'Find opinions using a tag',
```

- [ ] **Step 20: Run tests**

Run: `flutter test test/features/opinions/`
Expected: PASS, `All tests passed!`

Run: `grep -n "forum\|Forum\|TabController\|_buildTopicList" lib/features/opinions/presentation/screen/tag_browse_screen.dart lib/features/opinions/presentation/screen/tag_search_screen.dart`
Expected: no output.

Run: `flutter analyze --no-pub lib/features/opinions/presentation/screen/tag_browse_screen.dart lib/features/opinions/presentation/screen/tag_search_screen.dart 2>&1 | grep -E '^\s*(error|warning) '`
Expected: no output.

---

### Task 3: "+" opens the composer directly, and the forum feature is deleted

**Files:**
- Create: `test/core/widgets/create_content_chooser_test.dart`
- Modify: `test/features/opinions/opinions_tab_shell_test.dart` (created in Task 2)
- Modify: `test/architecture/no_forum_references_test.dart` (created in Task 1)
- Rewrite: `lib/core/widgets/create_content_chooser.dart`
- Modify: `lib/core/widgets/create_content_fab.dart:6-19, 26, 31-37, 40-43, 62`
- Modify: `test/widget_test.dart:10-11, 24-47, 61, 78`
- Delete: `lib/features/forums/` (18 files), `lib/home/widgets/forum_home.dart`, `test/features/forums/` (`forum_feed_cache_test.dart`)

**Interfaces:**
- Consumes: `_pumpTab` / `_uid` / `_feedIndex` (Task 2), `_dartFiles` / `_hits` / `_self` (Task 1); `OpinionComposeScreen({Key? key, VoidCallback? onPosted})`; `BottomSheetUtils.showDocumentationBottomSheet<T>({required BuildContext context, Widget? widget, Color? backgroundColor, …}) → Future<T?>`.
- Produces: `CreateContentChooser.show({required BuildContext context, required Color backgroundColor, VoidCallback? onOpinionPosted}) → Future<void>` (opens `OpinionComposeScreen(onPosted: onOpinionPosted)` in the same bottom sheet); `CreateContentFab({Key? key, required bool isAuthenticated, required Object heroTag, VoidCallback? onOpinionPosted})`. In the architecture test: `const List<String> _forumRpcs` (29 names) and `const List<String> _forumRelations` (10 names), reused by Task 5. `discover_feed_screen.dart:164` compiles unchanged (V1).

- [ ] **Step 1: Write the failing chooser test**

Create `test/core/widgets/create_content_chooser_test.dart`:

```dart
// Spec 3 (forum removal) D1, risk R5: with Forums gone, "+" has one thing to
// make, so it opens the opinion composer directly (no one-row chooser). The
// caller's onOpinionPosted reaches the composer unchanged, and a guest's FAB
// still asks them to sign in.
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/core/widgets/create_content_chooser.dart';
import 'package:attune/core/widgets/create_content_fab.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpHost(
  WidgetTester tester,
  Widget Function(BuildContext context) body, {
  String? userId = 'u1',
}) async {
  tester.view.physicalSize = const Size(1170, 2532); // 390 x 844 phone
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(userId),
        userRelationshipStatusProvider.overrideWith((ref) async => 'single'),
        allTagsProvider.overrideWith((ref) async => const <String>[]),
        // The FAB is scroll-aware: it takes taps only while the nav bar is
        // scrolled away.
        navVisibilityProvider.overrideWith((ref) => false),
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: Builder(builder: body)),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('show() opens the opinion composer with the caller callback', (
    tester,
  ) async {
    void onPosted() {}
    await _pumpHost(
      tester,
      (context) => TextButton(
        onPressed:
            () => CreateContentChooser.show(
              context: context,
              backgroundColor: Colors.white,
              onOpinionPosted: onPosted,
            ),
        child: const Text('open'),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(OpinionComposeScreen), findsOneWidget);
    expect(
      tester
          .widget<OpinionComposeScreen>(find.byType(OpinionComposeScreen))
          .onPosted,
      same(onPosted),
    );
    expect(find.text('Share an opinion'), findsNothing);
    expect(find.text('Start a forum topic'), findsNothing);
  });

  testWidgets('a signed-in FAB tap opens the composer directly', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      (_) => const Center(
        child: CreateContentFab(heroTag: 'fab', isAuthenticated: true),
      ),
    );

    await tester.tap(find.byType(CreateContentFab));
    await tester.pumpAndSettle();

    expect(find.byType(OpinionComposeScreen), findsOneWidget);
    expect(find.text('Start a forum topic'), findsNothing);
  });

  testWidgets('a guest FAB tap asks to sign in and opens nothing', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      (_) => const Center(
        child: CreateContentFab(heroTag: 'fab', isAuthenticated: false),
      ),
      userId: null,
    );

    await tester.tap(find.byType(CreateContentFab));
    await tester.pump();

    expect(find.text('Sign in to perform this action'), findsOneWidget);
    expect(find.byType(OpinionComposeScreen), findsNothing);
  });

  testWidgets('dismissing the composer opens nothing else', (tester) async {
    // The old chooser stashed the tapped row in a static field; a dismissed
    // sheet must neither replay a stale pick nor report a post.
    var posted = false;
    await _pumpHost(
      tester,
      (context) => TextButton(
        onPressed:
            () => CreateContentChooser.show(
              context: context,
              backgroundColor: Colors.white,
              onOpinionPosted: () => posted = true,
            ),
        child: const Text('open'),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 20)); // the barrier above the sheet
    await tester.pumpAndSettle();

    expect(find.byType(OpinionComposeScreen), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(posted, isFalse);
  });
}
```

- [ ] **Step 2: Add the app-bar "+" test to the shell test**

In `test/features/opinions/opinions_tab_shell_test.dart`, replace:

```dart
import 'package:attune/features/opinions/presentation/screen/opinions_tab.dart';
```

with:

```dart
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/features/opinions/presentation/screen/opinions_tab.dart';
```

and insert this test before the final closing `}` of `main()`:

```dart

  testWidgets('the app-bar + opens the opinion composer directly', (
    tester,
  ) async {
    await _pumpTab(tester, userId: 'u1');

    await tester.tap(find.byTooltip('add opinions'));
    await tester.pumpAndSettle();

    expect(find.byType(OpinionComposeScreen), findsOneWidget);
    expect(find.text('Share an opinion'), findsNothing);
    expect(find.text('Start a forum topic'), findsNothing);
  });
```

- [ ] **Step 3: Add the forum-code rule to the architecture test**

In `test/architecture/no_forum_references_test.dart`, replace:

```dart
const _self = 'test/architecture/no_forum_references_test.dart';
```

with:

```dart
const _self = 'test/architecture/no_forum_references_test.dart';

/// Spec 3 §3.9: the 29 forum-only functions and the 10 forum relations.
const _forumRpcs = [
  'activate_pending_topics',
  'expire_old_topics',
  'mark_quiet_topics',
  'notify_quiet_topic',
  'queue_forum_activity_notifications',
  'record_forum_topic_visit',
  'create_forum_post',
  'create_forum_topic',
  'create_forum_topic_with_poll',
  'edit_forum_post',
  'attach_forum_topic_tags',
  'get_forum_topic_tags',
  'get_forum_topics_by_tag',
  'get_tags_for_forum_topics',
  'get_polls_for_topics',
  'get_active_forums_filtered',
  'get_quiet_forums_filtered',
  'get_voting_topics_filtered',
  'increment_topic_upvote_count',
  'decrement_topic_upvote_count',
  'increment_topic_downvote_count',
  'decrement_topic_downvote_count',
  'increment_topic_post_count',
  'decrement_topic_post_count',
  'increment_topic_seen_count',
  'increment_forum_post_like_count',
  'decrement_forum_post_like_count',
  'report_forum_post',
  'report_forum_topic',
];
const _forumRelations = [
  'forum_topics',
  'topic_votes',
  'topic_impressions',
  'forum_posts',
  'forum_post_likes',
  'user_forum_sides',
  'forum_topic_tags',
  'forum_topic_visits',
  'public_forum_topics',
  'public_forum_posts',
];
```

and insert this test before the final closing `}` of `main()`:

```dart

  test('no deleted forum code is named', () {
    const classes = [
      'ForumsSection',
      'ForumsExploreScreen',
      'ContributingForumsScreen',
      'DebateRoomScreen',
      'SideSelectionScreen',
      'ForumInsightScreen',
      'SubmitTopicScreen',
      'ForumCard',
      'ForumCardSubDetails',
      'ForumPostBubble',
      'TopicVotingCard',
      'TopicImpressionTracker',
      'MiniContainerIndicator',
      'TopicModel',
      'ForumPostModel',
      'ForumRepository',
      'ForumFeedCache',
      'ForumHome',
      'TopicLiveCounts',
      'WidgetsBindingListener',
    ];
    // §3.4, minus the generic supabaseClientProvider and
    // currentUserStatusProvider (other features own same-named providers).
    const providers = [
      'forumRepositoryProvider',
      'submitTopicProvider',
      'forumsExploreTagFilterProvider',
      'votingTopicsProvider',
      'activeForumsProvider',
      'quietForumsProvider',
      'castTopicVoteProvider',
      'recordTopicImpressionProvider',
      'recordTopicVisitProvider',
      'joinForumProvider',
      'forumPostsProvider',
      'submitForumPostProvider',
      'likeForumPostProvider',
      'unlikeForumPostProvider',
      'contributingForumsProvider',
      'topicDetailsProvider',
      'reportForumProvider',
      'reportForumPostProvider',
      'forumTopicsByTagProvider',
      'topicLiveCountsProvider',
      'postLikeLiveCountProvider',
      'forumFeedCacheProvider',
      'onTopicSubmitted',
    ];
    final names = [..._forumRpcs, ..._forumRelations].join('|');
    final hits = _hits(
      _dartFiles(['lib', 'test']),
      [
        RegExp(r'package:attune/features/forums/'),
        RegExp('\\b(${[...classes, ...providers].join('|')})\\b'),
        // A named push to a removed route compiles and then throws.
        RegExp(r'''['"](debateRoom|sideSelection|forumInsight)['"]'''),
        RegExp('[\'"][^\'"]*\\b($names)\\b[^\'"]*[\'"]'),
      ],
      // The dead topic-poll lookup goes with its RPC in W3 (§6.3).
      allow:
          (path, line) =>
              path.endsWith(
                'core/polls/data/repositories/poll_repository.dart',
              ) &&
              line.contains("'get_polls_for_topics'"),
    );
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
```

(`ForumDocs` is added by Task 4, which deletes it.)

Run: `dart format test/core/widgets/create_content_chooser_test.dart test/features/opinions/opinions_tab_shell_test.dart test/architecture/no_forum_references_test.dart`
Expected: `Formatted 3 files (0 changed)` (any reflow is fine: all three are this plan's new files).

- [ ] **Step 4: Run the tests to verify they fail**

Run: `flutter test test/core/widgets/create_content_chooser_test.dart test/features/opinions/opinions_tab_shell_test.dart test/architecture/no_forum_references_test.dart`
Expected: FAIL, `Some tests failed.` Failing: `show() opens the opinion composer …` and `a signed-in FAB tap …` (`Found 0 widgets with type "OpinionComposeScreen"`: the chooser sheet opens instead), `the app-bar + opens …` (same), and `no deleted forum code is named` (hits in `lib/features/forums/**`, `lib/home/widgets/forum_home.dart`, `lib/core/widgets/create_content_chooser.dart`, `lib/core/widgets/create_content_fab.dart`, `test/features/forums/forum_feed_cache_test.dart`, `test/widget_test.dart:11`). The guest-FAB and dismiss tests already pass: they pin behaviour that must not change.

- [ ] **Step 5: Rewrite the chooser as the single compose entry**

Replace the whole content of `lib/core/widgets/create_content_chooser.dart` with (do not `dart format` it):

```dart
// lib/core/widgets/create_content_chooser.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';

/// The one compose entry behind every Opinions "+" (the FAB, the app-bar
/// button and the Discover empty state). Forums were retired (Spec 3,
/// 2026-10), so there is nothing left to choose between: "+" opens the
/// opinion composer straight away, in the same bottom sheet as before. The
/// class keeps its name so callers, and any later compose option, build on
/// this one entry point.
class CreateContentChooser {
  /// Opens the opinion composer. [onOpinionPosted] is passed to
  /// OpinionComposeScreen.onPosted unchanged, so the caller's
  /// feed-invalidation and scroll-to-top logic runs after a post.
  static Future<void> show({
    required BuildContext context,
    required Color backgroundColor,
    VoidCallback? onOpinionPosted,
  }) {
    return BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      backgroundColor: backgroundColor,
      widget: OpinionComposeScreen(onPosted: onOpinionPosted),
    );
  }
}
```

- [ ] **Step 6: Remove `onTopicSubmitted` and the forum wording from the FAB**

In `lib/core/widgets/create_content_fab.dart`, replace:

```dart
/// The single "+" FAB shared by all four Opinions/Forums sub-tabs (Following,
/// Discover, Contributing, Explore) — one shared button/behavior instead of
/// each section owning its own differently-gated, differently-scoped FAB.
///
/// Always visible, on every tab, regardless of auth state — tapping it as a
/// guest shows the sign-in snackbar instead of the tap silently doing
/// nothing (the previous Opinions FAB) or the button being altogether absent
/// on some tabs (the previous Forums FAB, hidden outside Explore).
///
/// Opens [CreateContentChooser] with BOTH feed-invalidation callbacks wired,
/// not just the one relevant to whichever screen the FAB happened to be
/// declared on — a guest (well, signed-in user) picking "Start a forum
/// topic" from a FAB physically sitting on the Opinions tab still needs
/// votingTopicsProvider invalidated, not just the opinion feeds.
```

with:

```dart
/// The "+" FAB shared by the Opinions sub-tabs (Following, Discover): one
/// shared button and behaviour instead of each feed owning its own.
///
/// Always visible, on every tab, regardless of auth state — tapping it as a
/// guest shows the sign-in snackbar instead of the tap silently doing
/// nothing.
///
/// Opens [CreateContentChooser], which goes straight to the opinion
/// composer, with the caller's feed-invalidation callback wired through.
```

Replace:

```dart
    this.onOpinionPosted,
    this.onTopicSubmitted,
  });
```

with:

```dart
    this.onOpinionPosted,
  });
```

Replace:

```dart
  /// Required, not defaulted: _OpinionsSection and ForumsSection each mount
  /// their own CreateContentFab, and both are kept alive simultaneously by
  /// OpinionsTab's IndexedStack (Opinions/Forums are sibling pages, not
  /// swapped out) — a single shared literal tag threw "multiple heroes share
  /// the same tag" the moment both were on screen at once, since Hero
  /// uniqueness is checked across the whole mounted subtree, not just the
  /// visible page. Each caller passes its own distinct tag.
```

with:

```dart
  /// Required, not defaulted: Hero tags must be unique across the whole
  /// mounted subtree, not just the visible page, and the home shell keeps
  /// several tabs alive at once. Each caller passes its own distinct tag.
```

Replace:

```dart
  /// Mirrors CreateContentChooser.show's own callbacks exactly — plug in
  /// each caller's existing feed-invalidation/scroll-to-top logic unchanged.
  final VoidCallback? onOpinionPosted;
  final VoidCallback? onTopicSubmitted;
```

with:

```dart
  /// Mirrors CreateContentChooser.show's own callback exactly — plug in the
  /// caller's existing feed-invalidation/scroll-to-top logic unchanged.
  final VoidCallback? onOpinionPosted;
```

Replace:

```dart
          onOpinionPosted: onOpinionPosted,
          onTopicSubmitted: onTopicSubmitted,
        );
```

with:

```dart
          onOpinionPosted: onOpinionPosted,
        );
```

`heroTag` stays required and the guest snackbar is unchanged.

- [ ] **Step 7: Delete the forum feature, the dead `ForumHome` and the forum cache test**

Run:

```bash
cd /Users/user/attune
rm -r lib/features/forums
rm lib/home/widgets/forum_home.dart
rm -r test/features/forums
```

Run: `ls lib/features/forums test/features/forums lib/home/widgets/forum_home.dart 2>&1 | grep -c "No such file"`
Expected: `3`.

- [ ] **Step 8: `test/widget_test.dart` loses the forum override and asserts no Forums**

Replace:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
```

with:

```dart
import 'package:shared_preferences/shared_preferences.dart';
```

Delete (lines 24-47, plus the blank line after them):

```dart
/// A signed-out Supabase client.
///
/// ForumsSection.initState reads `supabaseClientProvider.auth.currentUser`
/// to pick its default tab, which asserts on the uninitialised singleton
/// in tests. Only `.auth.currentUser` is exercised; anything else throws
/// so an unnoticed new call site fails loudly rather than silently
/// returning null.
class _AnonymousAuth implements GoTrueClient {
  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no Supabase auth call should be issued');
}

class _AnonymousSupabase implements SupabaseClient {
  @override
  final GoTrueClient auth = _AnonymousAuth();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no Supabase call should be issued');
}

```

Replace:

```dart
          sharedPreferencesProvider.overrideWithValue(prefs),
          supabaseClientProvider.overrideWithValue(_AnonymousSupabase()),
        ],
```

with:

```dart
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
```

Replace:

```dart
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Hello!'), findsNothing);
```

with:

```dart
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Forums'), findsNothing);
    expect(find.text('Hello!'), findsNothing);
```

Every other expectation stays.

- [ ] **Step 9: Run tests**

Run: `flutter test test/core/widgets/ test/features/opinions/ test/architecture/no_forum_references_test.dart test/widget_test.dart`
Expected: PASS, `All tests passed!` (includes the kept `universal_bubble_test.dart`, `opinion_feed_cache_test.dart` and `opinion_feed_removal_test.dart`).

Run: `flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error '`
Expected: no output.

Run: `flutter analyze --no-pub lib/core/widgets/create_content_chooser.dart lib/core/widgets/create_content_fab.dart test/widget_test.dart test/core/widgets/create_content_chooser_test.dart 2>&1 | grep -E '^\s*(error|warning) '`
Expected: no output.

---

### Task 4: Manual, copy, translations and FORUM.md stop naming Forums (W1 gate)

**Files:**
- Modify: `test/architecture/no_forum_references_test.dart`
- Modify: `lib/app/documentations/user_manual/data/manual_documentation_registry.dart:22, 133`
- Delete: `lib/app/documentations/user_manual/data/forum_docs.dart`
- Modify: `lib/app/documentations/user_manual/data/chat_docs.dart:56`
- Modify: `lib/features/onboarding/presentation/widgets/profile_setup_step.dart:22`
- Modify: `lib/i10n/app_en.arb:321`, `app_de.arb:326`, `app_es.arb:325`, `app_fr.arb:326`, `app_it.arb:326`, `app_pt.arb:326`
- Modify: `lib/i10n/generated/app_localizations.dart:1111`, `lib/i10n/generated/app_localizations_{en,de,es,fr,it,pt}.dart:541`
- Modify: `lib/architecture/FORUM.md:1, 442, 727, 1104, 1437`

**Interfaces:**
- Consumes: `_dartFiles`, `_hits` (Task 1); `DocumentationRegistry.getById(String) → DocumentationModule?`, `getAllModules() → List<DocumentationModule>`, `visibleModules(Set<String>) → List<DocumentationModule>`.
- Produces: no manual topic id `forums` (34 modules on today's tree; the guard's floor is 33); the intro and login carousels lose the Forums card through `visibleModules` without being edited; `mutedItemSubtitle` in six languages without the word forum.

- [ ] **Step 1: Write the failing tests**

In `test/architecture/no_forum_references_test.dart`, replace:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
```

with:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:flutter_test/flutter_test.dart';
```

and insert these tests before the final closing `}` of `main()`:

```dart

  test('no app copy mentions Forums', () {
    // lib only: test files assert the word is absent (find.text('Forums'))
    // and universal_bubble_test.dart's kept "forums-shaped bubble" guards
    // name the old caller on purpose.
    final hits = _hits(_dartFiles(['lib']), [
      RegExp(r'''['"][^'"]*\b[Ff]orums?\b[^'"]*['"]'''),
      RegExp(r'\bForumDocs\b'),
    ]);
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('no translation mentions Forums', () {
    final word = RegExp(
      r'\bforums?\b|\bforo\b|\bforen|\bfórum\b',
      caseSensitive: false,
    );
    final hits = <String>[];
    for (final entity in Directory('lib/i10n').listSync()) {
      if (entity is! File || !entity.path.endsWith('.arb')) continue;
      final arb = jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>;
      arb.forEach((key, value) {
        if (!key.startsWith('@') && value is String && word.hasMatch(value)) {
          hits.add('${entity.path}: $key');
        }
      });
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('the manual has no Forums topic', () {
    expect(DocumentationRegistry.getById('forums'), isNull);
    expect(
      DocumentationRegistry.getAllModules().map((m) => m.id),
      isNot(contains('forums')),
    );
    expect(
      DocumentationRegistry.visibleModules(const {}).map((m) => m.id),
      isNot(contains('forums')),
    );
    // The guard's floor (manual_content_guard_test.dart). No exact count:
    // Specs 1 and 2 register more topics later.
    expect(
      DocumentationRegistry.getAllModules().length,
      greaterThanOrEqualTo(33),
    );
  });
```

Run: `dart format test/architecture/no_forum_references_test.dart`
Expected: `Formatted 1 file (0 changed)`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/architecture/no_forum_references_test.dart`
Expected: FAIL, three failures. `no app copy mentions Forums` lists `chat_docs.dart:56`, `forum_docs.dart` (many lines), `manual_documentation_registry.dart:133`, `profile_setup_step.dart:22` and `lib/i10n/generated/app_localizations_{en,fr,it}.dart:541`; `no translation mentions Forums` lists all six ARB files' `mutedItemSubtitle`; `the manual has no Forums topic` fails on `getById('forums')`.

- [ ] **Step 3: Unregister and delete `ForumDocs`**

In `lib/app/documentations/user_manual/data/manual_documentation_registry.dart`, delete the line:

```dart
import 'package:attune/app/documentations/user_manual/data/forum_docs.dart';
```

and replace:

```dart
      OpinionsDocs(),
      ForumDocs(),
```

with:

```dart
      OpinionsDocs(),
```

Nothing else in the registry changes. Then:

Run: `rm lib/app/documentations/user_manual/data/forum_docs.dart`

- [ ] **Step 4: Chat manual sentence and onboarding subtitle**

In `lib/app/documentations/user_manual/data/chat_docs.dart`, replace:

```dart
that lives in other parts of the app, like Opinions and Forums.',
```

with:

```dart
that lives in other parts of the app, like Opinions.',
```

In `lib/features/onboarding/presentation/widgets/profile_setup_step.dart`, replace:

```dart
          'Use the name you want to see in chat. Opinions and forums stay anonymous.',
```

with:

```dart
          'Use the name you want to see in chat. Opinions stay anonymous.',
```

- [ ] **Step 5: `mutedItemSubtitle` in the six ARB files**

There is no `l10n.yaml`; the generated files are checked in and edited by hand in Step 6. One replacement per file:

| File | Replace | With |
|---|---|---|
| `lib/i10n/app_en.arb` | `"mutedItemSubtitle": "Anonymous forum accounts you've muted",` | `"mutedItemSubtitle": "Anonymous Opinions accounts you've muted",` |
| `lib/i10n/app_de.arb` | `"mutedItemSubtitle": "Anonyme Forenkonten, die Sie stummgeschaltet haben",` | `"mutedItemSubtitle": "Anonyme Opinions-Konten, die Sie stummgeschaltet haben",` |
| `lib/i10n/app_es.arb` | `"mutedItemSubtitle": "Cuentas anónimas del foro que has silenciado",` | `"mutedItemSubtitle": "Cuentas anónimas de Opinions que has silenciado",` |
| `lib/i10n/app_fr.arb` | `"mutedItemSubtitle": "Comptes anonymes du forum que vous avez mis en sourdine",` | `"mutedItemSubtitle": "Comptes anonymes d'Opinions que vous avez mis en sourdine",` |
| `lib/i10n/app_it.arb` | `"mutedItemSubtitle": "Account anonimi del forum che hai silenziato",` | `"mutedItemSubtitle": "Account anonimi di Opinions che hai silenziato",` |
| `lib/i10n/app_pt.arb` | `"mutedItemSubtitle": "Contas anônimas do fórum que você silenciou",` | `"mutedItemSubtitle": "Contas anônimas do Opinions que você silenciou",` |

- [ ] **Step 6: The same strings in the seven generated files**

| File | Replace | With |
|---|---|---|
| `lib/i10n/generated/app_localizations.dart` | `  /// **'Anonymous forum accounts you\'ve muted'**` | `  /// **'Anonymous Opinions accounts you\'ve muted'**` |
| `lib/i10n/generated/app_localizations_en.dart` | `String get mutedItemSubtitle => 'Anonymous forum accounts you\'ve muted';` | `String get mutedItemSubtitle => 'Anonymous Opinions accounts you\'ve muted';` |
| `lib/i10n/generated/app_localizations_de.dart` | `String get mutedItemSubtitle => 'Anonyme Forenkonten, die Sie stummgeschaltet haben';` | `String get mutedItemSubtitle => 'Anonyme Opinions-Konten, die Sie stummgeschaltet haben';` |
| `lib/i10n/generated/app_localizations_es.dart` | `String get mutedItemSubtitle => 'Cuentas anónimas del foro que has silenciado';` | `String get mutedItemSubtitle => 'Cuentas anónimas de Opinions que has silenciado';` |
| `lib/i10n/generated/app_localizations_fr.dart` | `String get mutedItemSubtitle => 'Comptes anonymes du forum que vous avez mis en sourdine';` | `String get mutedItemSubtitle => 'Comptes anonymes d\'Opinions que vous avez mis en sourdine';` |
| `lib/i10n/generated/app_localizations_it.dart` | `String get mutedItemSubtitle => 'Account anonimi del forum che hai silenziato';` | `String get mutedItemSubtitle => 'Account anonimi di Opinions che hai silenziato';` |
| `lib/i10n/generated/app_localizations_pt.dart` | `String get mutedItemSubtitle => 'Contas anônimas do fórum que você silenciou';` | `String get mutedItemSubtitle => 'Contas anônimas do Opinions que você silenciou';` |

Run: `grep -h "mutedItemSubtitle" lib/i10n/*.arb lib/i10n/generated/app_localizations_*.dart | grep -ciE "forum|foro|foren|fórum"`
Expected: `0`.

- [ ] **Step 7: FORUM.md retirement banners**

In `lib/architecture/FORUM.md` (Spec 3 owns this file), make five insertions:

Replace:

```markdown
# ATTUNE — FORUM FEATURE SPECIFICATION V2
### Updated implementation spec incorporating owner decisions
```

with:

```markdown
# ATTUNE — FORUM FEATURE SPECIFICATION V2

> **Forums retired 2026-10 (Spec 3):** screens and pushes removed in W1, producers stopped in W2, tables dropped in W3. §4, §7 and §8 still describe Opinions.

### Updated implementation spec incorporating owner decisions
```

Replace `## 5. FEATURE 2 — FORUMS` with:

```markdown
## 5. FEATURE 2 — FORUMS

> **Retired (Spec 3, 2026-10).** Kept for history; nothing in this section ships.
```

Replace `## 6. FORUM INSIGHT SCREEN` with:

```markdown
## 6. FORUM INSIGHT SCREEN

> **Retired (Spec 3, 2026-10).** Kept for history; nothing in this section ships.
```

Replace `## 9. DATABASE SCHEMA` with:

```markdown
## 9. DATABASE SCHEMA

> **Retired (Spec 3, 2026-10):** the forum tables, views and functions below are closed to clients in W2 and dropped in W3; `forum_reports`, `post_polls`, the tag tables and every Opinions row stay.
```

Replace `## 10. NOTIFICATION SYSTEM` with:

```markdown
## 10. NOTIFICATION SYSTEM

> **Retired (Spec 3, 2026-10):** the forum pushes below (`forum_topic_activated`, `forum_activity`, `forum_quiet`) are no longer sent and their taps open home; the Opinions pushes and the two moderation notices stay.
```

Run: `grep -c "Spec 3" lib/architecture/FORUM.md`
Expected: `5`.

- [ ] **Step 8: Run tests (W1 regression gate)**

Run: `flutter test test/architecture/no_forum_references_test.dart test/app/documentations/`
Expected: PASS, `All tests passed!`

Run: `flutter analyze --no-pub lib test 2>&1 | grep -cE '^\s*error '`
Expected: `0`.

Run: `flutter analyze --no-pub 2>&1 | grep -E '^\s*error ' | grep -vc 'packages/video_compress/example/'`
Expected: `0` (only the 8 pre-existing vendored-example errors remain).

Run: `flutter test`
Expected: PASS, `All tests passed!` (includes Games, chat, `universal_bubble_test.dart`, onboarding, `login_profile_test.dart`, the manual tests and Stories).

Run: `git status --short | grep -E "forum|opinions_tab|tag_browse|tag_search|create_content|notification_config|app_router|widget_test|i10n|chat_docs|profile_setup|manual_documentation|FORUM.md"`
Expected: exactly the W1 files of the File map (modified `M`, deleted `D`, new `??`), plus any of the owner's own edits noted in Task 1 Step 0.

---

## W2: stop the producers (server only; owner deploys after the W1 build is on every test device)

### Task 5: Unschedule the forum crons and delete the forum edge functions

**Files:**
- Create: `supabase/migrations/20261025090000_forum_retire_scheduled_jobs.sql`
- Create: `supabase/tests/forum_retirement_contracts.sql`
- Modify: `test/architecture/no_forum_references_test.dart`
- Delete: `supabase/functions/activate-topics/`, `supabase/functions/forum-quiet-check/`, `supabase/sql/schedule_activate_topics.sql`, `supabase/sql/schedule_forum_quiet_check.sql`, `supabase/sql/patch_mark_quiet_forums_null_last_post.sql`

**Interfaces:**
- Consumes: `_forumRpcs`, `_forumRelations` (Task 3); `cron.job (jobid bigint, jobname text, command text, …)`, `cron.unschedule(bigint) → boolean` (pg_cron, also on `attune_spec3a`).
- Produces: no `cron.job` row named `activate-topics-sweep`, `forum-quiet-check` or `mark-quiet-forums`, or whose command matches `(activate-topics|forum-quiet-check|forum_topics|mark_quiet_topics|activate_pending_topics|expire_old_topics|notify_quiet_topic)` (case-insensitive). The contract file with section A and the footer `DO $$ BEGIN RAISE NOTICE 'forum_retirement_contracts: all held'; END $$;` + `ROLLBACK;`; Tasks 6 and 7 insert sections above the footer.

- [ ] **Step 1: Confirm the database and the timestamp slot**

Run: `cd /Users/user/attune && psql -X -d attune_spec3a -Atc 'select current_database()'`
Expected: `attune_spec3a`.

Run: `ls supabase/migrations | tail -1`
Expected: `20261024100800_my_closed_story_items.sql` (or anything earlier than `20261025090000`; otherwise shift the four W2 timestamps as Global Constraints says).

- [ ] **Step 2: Record the contract baseline**

Run:

```bash
cd /Users/user/attune
for t in supabase/tests/*.sql; do psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f "$t" >/dev/null 2>&1 || echo "FAIL $t"; done > "${TMPDIR:-/tmp}/spec3-w2-contracts-before.txt"
wc -l < "${TMPDIR:-/tmp}/spec3-w2-contracts-before.txt"
```

Expected: a count (14 when this plan was written; see "Baselines today"). Keep the file for Task 7.

- [ ] **Step 3: Write the failing architecture test**

In `test/architecture/no_forum_references_test.dart`, insert this test before the final closing `}` of `main()`:

```dart

  test('the forum producers are gone from the server folders', () {
    for (final dir in [
      'supabase/functions/activate-topics',
      'supabase/functions/forum-quiet-check',
    ]) {
      expect(Directory(dir).existsSync(), isFalse, reason: dir);
    }
    for (final script in [
      'supabase/sql/schedule_activate_topics.sql',
      'supabase/sql/schedule_forum_quiet_check.sql',
      'supabase/sql/patch_mark_quiet_forums_null_last_post.sql',
    ]) {
      expect(File(script).existsSync(), isFalse, reason: script);
    }

    // No edge function or operator script names a forum RPC, relation or
    // retired push type. The dispatcher's allowlist keys forum_post_id and
    // topic_id match none of these.
    final names = [
      ..._forumRpcs,
      ..._forumRelations,
      'forum_topic_activated',
      'forum_activity',
      'forum_quiet',
    ].join('|');
    final pattern = RegExp('\\b($names)\\b');
    final hits = <String>[];
    final files = [
      for (final entity in Directory(
        'supabase/functions',
      ).listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.ts')) entity,
      for (final entity in Directory('supabase/sql').listSync())
        if (entity is File && entity.path.endsWith('.sql')) entity,
    ];
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) hits.add('${file.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
```

Run: `dart format test/architecture/no_forum_references_test.dart`
Expected: `Formatted 1 file (0 changed)`.

- [ ] **Step 4: Write the failing contract (section A)**

Create `supabase/tests/forum_retirement_contracts.sql`:

```sql
-- supabase/tests/forum_retirement_contracts.sql
-- Spec 3 (forum removal) §7.3: the forum producers are shut and shown to be
-- shut, and Opinions (polls, tags, reports, bans, notifications) behaves
-- exactly as before. W2 sections A-E; W3 adds F. Fixture ids use the
-- 9f3a0000- prefix and phones +1555094xxxx (both free on attune_spec3a).
-- Every failure names the offending job, push, grant or behaviour.
BEGIN;

-- ---------------------------------------------------------------------
-- A. Crons: no forum job by name or by what it runs.
-- ---------------------------------------------------------------------
DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(coalesce(jobname, '<unnamed>') || ' (jobid ' || jobid || ')', ', ')
    INTO v_bad
    FROM cron.job
   WHERE jobname IN ('activate-topics-sweep', 'forum-quiet-check', 'mark-quiet-forums')
      OR command ~* '(activate-topics|forum-quiet-check|forum_topics|mark_quiet_topics|activate_pending_topics|expire_old_topics|notify_quiet_topic)';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum cron still scheduled: %', v_bad;
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'forum_retirement_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 5: Run both to verify they fail**

Run: `flutter test test/architecture/no_forum_references_test.dart`
Expected: FAIL, one failure: `the forum producers are gone from the server folders` (`Expected: false  Actual: <true>`, reason `supabase/functions/activate-topics`).

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/forum_retirement_contracts.sql`
Expected: FAIL, `ERROR:  CONTRACT VIOLATED: forum cron still scheduled: activate-topics-sweep (jobid 11), forum-quiet-check (jobid 13)` (job ids may differ).

- [ ] **Step 6: Write migration 1**

Create `supabase/migrations/20261025090000_forum_retire_scheduled_jobs.sql`:

```sql
-- Spec 3 (forum removal) W2, migration 1 of 4: stop every forum cron.
--
-- By name: 'activate-topics-sweep' and 'forum-quiet-check' (registered by
-- 20260907120000_register_scheduled_jobs.sql) and 'mark-quiet-forums'
-- (production only, registered by hand as jobid 3 and patched by the
-- operator script supabase/sql/patch_mark_quiet_forums_null_last_post.sql).
-- Then by command, so a hand-registered copy under another name goes too.
--
-- Idempotent: a second run finds nothing and does nothing. One DO block, so
-- it is atomic without its own BEGIN/COMMIT. No exception is swallowed: if
-- pg_cron refuses an unschedule, the push fails loudly.
DO $$
DECLARE
  v_name text;
  v_job record;
BEGIN
  FOREACH v_name IN ARRAY ARRAY[
    'activate-topics-sweep',
    'forum-quiet-check',
    'mark-quiet-forums'
  ] LOOP
    FOR v_job IN SELECT j.jobid, j.jobname FROM cron.job j WHERE j.jobname = v_name LOOP
      PERFORM cron.unschedule(v_job.jobid);
      RAISE NOTICE 'forum_retire_scheduled_jobs: unscheduled % (jobid %)',
        v_job.jobname, v_job.jobid;
    END LOOP;
  END LOOP;

  FOR v_job IN
    SELECT j.jobid, j.jobname FROM cron.job j
    WHERE j.command ~* '(activate-topics|forum-quiet-check|forum_topics|mark_quiet_topics|activate_pending_topics|expire_old_topics|notify_quiet_topic)'
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
    RAISE NOTICE 'forum_retire_scheduled_jobs: unscheduled % (jobid %) by its command',
      coalesce(v_job.jobname, '<unnamed>'), v_job.jobid;
  END LOOP;
END
$$;
```

- [ ] **Step 7: Delete the two edge functions and the three operator scripts**

Run:

```bash
cd /Users/user/attune
rm -r supabase/functions/activate-topics supabase/functions/forum-quiet-check
rm supabase/sql/schedule_activate_topics.sql supabase/sql/schedule_forum_quiet_check.sql supabase/sql/patch_mark_quiet_forums_null_last_post.sql
```

`supabase/functions/process-scheduled-notifications/` (its `forum_post_id` / `topic_id` allowlist) and `public.invoke_edge_function` stay.

- [ ] **Step 8: Apply migration 1 to the scratch database, twice**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025090000_forum_retire_scheduled_jobs.sql`
Expected: `NOTICE:  forum_retire_scheduled_jobs: unscheduled activate-topics-sweep (jobid …)`, the same for `forum-quiet-check`, then `DO`.

Run the same command again.
Expected: `DO` and no NOTICE (idempotent).

- [ ] **Step 9: Prove the command sweep catches a renamed copy (Review Focus 5)**

Run:

```bash
cd /Users/user/attune
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a <<'SQL'
BEGIN;
SELECT cron.schedule('legacy-quiet-copy', '0 1 * * *',
  $$UPDATE public.forum_topics SET status = 'quiet' WHERE false$$);
\i supabase/migrations/20261025090000_forum_retire_scheduled_jobs.sql
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'legacy-quiet-copy') THEN
    RAISE EXCEPTION 'the renamed forum job survived migration 1';
  END IF;
  RAISE NOTICE 'renamed forum job swept';
END $$;
ROLLBACK;
SQL
```

Expected: `NOTICE:  forum_retire_scheduled_jobs: unscheduled legacy-quiet-copy (jobid …) by its command`, then `NOTICE:  renamed forum job swept`, then `ROLLBACK`.

- [ ] **Step 10: Run tests**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/forum_retirement_contracts.sql`
Expected: PASS, `NOTICE:  forum_retirement_contracts: all held`, then `ROLLBACK`.

Run: `flutter test test/architecture/no_forum_references_test.dart`
Expected: PASS, `All tests passed!`

Run: `grep -rn "activate-topics\|forum-quiet-check" supabase/functions supabase/sql`
Expected: no output.

---

### Task 6: Close every forum RPC, table and view to clients (Opinions stays open)

**Files:**
- Create: `supabase/migrations/20261025090100_forum_revoke_client_access.sql`
- Modify: `supabase/tests/forum_retirement_contracts.sql`

**Interfaces:**
- Consumes: the contract file and its footer (Task 5).
- Produces: anon, authenticated and service_role cannot EXECUTE any of the 29 forum signatures; anon and authenticated hold no SELECT/INSERT/UPDATE/DELETE on the 10 forum relations; service_role holds nothing on the 2 views and keeps its 8 table grants (D-1). Contract helpers `pg_temp.as_user(uuid)`, `pg_temp.as_anon()`, `pg_temp.as_service()` and sections B, D, E (inserted above the footer, in that order).

- [ ] **Step 1: Write the failing contract sections B, D, E**

In `supabase/tests/forum_retirement_contracts.sql`, insert the following immediately above the footer line `DO $$ BEGIN RAISE NOTICE 'forum_retirement_contracts: all held'; END $$;` (keep one blank line between sections):

```sql
-- ---------------------------------------------------------------------
-- B. Grants: no client can run a forum RPC or touch a forum relation.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_sig text;
  v_rel text;
  v_role text;
  v_priv text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.activate_pending_topics()',
    'public.expire_old_topics()',
    'public.mark_quiet_topics()',
    'public.notify_quiet_topic(uuid)',
    'private.queue_forum_activity_notifications(uuid,uuid)',
    'public.record_forum_topic_visit(uuid)',
    'public.create_forum_post(uuid,text,text,uuid,text)',
    'public.create_forum_topic(text)',
    'public.create_forum_topic_with_poll(text,text[])',
    'public.edit_forum_post(uuid,text)',
    'public.attach_forum_topic_tags(uuid,text[])',
    'public.get_forum_topic_tags(uuid)',
    'public.get_forum_topics_by_tag(text,integer,integer)',
    'public.get_tags_for_forum_topics(uuid[])',
    'public.get_polls_for_topics(uuid[])',
    'public.get_active_forums_filtered(text[])',
    'public.get_quiet_forums_filtered(text[])',
    'public.get_voting_topics_filtered(text[])',
    'public.increment_topic_upvote_count(uuid)',
    'public.decrement_topic_upvote_count(uuid)',
    'public.increment_topic_downvote_count(uuid)',
    'public.decrement_topic_downvote_count(uuid)',
    'public.increment_topic_post_count(uuid,text)',
    'public.decrement_topic_post_count(uuid,text)',
    'public.increment_topic_seen_count(uuid)',
    'public.increment_forum_post_like_count(uuid)',
    'public.decrement_forum_post_like_count(uuid)',
    'public.report_forum_post(uuid,text)',
    'public.report_forum_topic(uuid,text)'
  ] LOOP
    IF to_regprocedure(v_sig) IS NULL THEN CONTINUE; END IF;
    -- service_role too: a stale edge-function deploy fails at its first RPC.
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
      IF has_function_privilege(v_role, v_sig, 'EXECUTE') THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % can still execute %', v_role, v_sig;
      END IF;
    END LOOP;
  END LOOP;

  FOREACH v_rel IN ARRAY ARRAY[
    'public.forum_topics', 'public.topic_votes', 'public.topic_impressions',
    'public.forum_posts', 'public.forum_post_likes', 'public.user_forum_sides',
    'public.forum_topic_tags', 'public.forum_topic_visits',
    'public.public_forum_topics', 'public.public_forum_posts'
  ] LOOP
    IF to_regclass(v_rel) IS NULL THEN CONTINUE; END IF;
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
      FOREACH v_priv IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'] LOOP
        IF has_table_privilege(v_role, v_rel, v_priv) THEN
          RAISE EXCEPTION 'CONTRACT VIOLATED: % still has % on %', v_role, v_priv, v_rel;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  -- The two views carry no service_role grant either.
  FOREACH v_rel IN ARRAY ARRAY['public.public_forum_topics', 'public.public_forum_posts'] LOOP
    IF to_regclass(v_rel) IS NOT NULL
       AND has_table_privilege('service_role', v_rel, 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: service_role can still read %', v_rel;
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- D. Keep-list sentinels: what Opinions uses is still open.
-- ---------------------------------------------------------------------
DO $$
DECLARE v_sig text;
BEGIN
  -- Guest Opinions polls: the only anon grant on get_post_poll lives in a
  -- forum migration (20260821120000:40). Spec 3 V3.
  IF NOT has_function_privilege('anon', 'public.get_post_poll(uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_post_poll(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_post_poll lost its anon or authenticated grant';
  END IF;
  FOREACH v_sig IN ARRAY ARRAY[
    'public.get_discover_opinions(integer,integer,text[])',
    'public.get_opinion_comments(uuid)',
    'public.get_all_tags()',
    'public.get_tags_for_opinions(uuid[])',
    'public.get_opinions_by_tag(text,integer,integer)',
    'public.get_opinion_tags(uuid)'
  ] LOOP
    IF NOT has_function_privilege('anon', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: guests can no longer run %', v_sig;
    END IF;
  END LOOP;
  FOREACH v_sig IN ARRAY ARRAY[
    'public.create_opinion(text)',
    'public.create_opinion_comment(uuid,text,uuid,text)',
    'public.create_opinion_with_poll(text,text[])',
    'public.cast_poll_vote(uuid)',
    'public.retract_poll_vote(uuid)',
    'public.get_polls_for_opinions(uuid[])',
    'public.report_opinion(uuid,text)',
    'public.report_opinion_comment(uuid,text)'
  ] LOOP
    IF NOT has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: signed-in users can no longer run %', v_sig;
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- E. Opinions behaviour: limits, comments, reports, polls (guest and
-- voter), strikes, the ban gate and Opinions notifications are unchanged.
-- A writes; B reports and votes; C posts the poll.
-- ---------------------------------------------------------------------
INSERT INTO auth.users (id) VALUES
  ('9f3a0000-0000-0000-0000-00000000000a'),
  ('9f3a0000-0000-0000-0000-00000000000b'),
  ('9f3a0000-0000-0000-0000-00000000000c')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9f3a0000-0000-0000-0000-00000000000a', '+15550940001', 'Spec3 A'),
  ('9f3a0000-0000-0000-0000-00000000000b', '+15550940002', 'Spec3 B'),
  ('9f3a0000-0000-0000-0000-00000000000c', '+15550940003', 'Spec3 C')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id) VALUES
  ('9f3a0000-0000-0000-0000-00000000000a'),
  ('9f3a0000-0000-0000-0000-00000000000b'),
  ('9f3a0000-0000-0000-0000-00000000000c')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.as_anon() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
END $$;

-- The connecting (owner) role with a service-role JWT: how the SQL editor
-- and edge functions reach admin_confirm_content_removal.
CREATE FUNCTION pg_temp.as_service() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
END $$;

DO $$
DECLARE
  v_a constant uuid := '9f3a0000-0000-0000-0000-00000000000a';
  v_b constant uuid := '9f3a0000-0000-0000-0000-00000000000b';
  v_c constant uuid := '9f3a0000-0000-0000-0000-00000000000c';
  v_o1 uuid;
  v_o2 uuid;
  v_poll_opinion uuid;
  v_comment uuid;
  v_yes uuid;
  v_n int;
  v_visible int;
  v_msg text;
  r record;
BEGIN
  -- A posts; an immediate second post hits the 60 s cooldown (assert_can_post).
  PERFORM pg_temp.as_user(v_a);
  v_o1 := public.create_opinion('Spec 3 contract: trust is built in small moments.');
  BEGIN
    PERFORM public.create_opinion('Spec 3 contract: a second post, too soon.');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second opinion inside 60 s was accepted';
  EXCEPTION WHEN SQLSTATE '53400' THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'cooldown' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: expected cooldown, got %', v_msg;
    END IF;
  END;
  v_comment := public.create_opinion_comment(v_o1, 'Spec 3 contract: A replies to themselves.');
  RESET ROLE;
  IF v_o1 IS NULL OR v_comment IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: create_opinion or create_opinion_comment returned null';
  END IF;

  -- B reports the opinion twice (deduplicated) and the comment once.
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.report_opinion(v_o1, 'Spam');
  PERFORM public.report_opinion(v_o1, 'Spam');
  PERFORM public.report_opinion_comment(v_comment, 'Spam');
  RESET ROLE;
  SELECT count(*) INTO v_n FROM public.forum_reports WHERE reported_by = v_b AND opinion_id = v_o1;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % opinion reports from one reporter, expected 1', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.forum_reports WHERE reported_by = v_b AND comment_id = v_comment;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % comment reports, expected 1', v_n;
  END IF;

  -- C posts an opinion with a poll.
  PERFORM pg_temp.as_user(v_c);
  v_poll_opinion := public.create_opinion_with_poll('Spec 3 contract: do you text first?', ARRAY['Yes', 'No']);
  RESET ROLE;
  SELECT count(*) INTO v_n FROM public.post_polls WHERE opinion_id = v_poll_opinion;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: create_opinion_with_poll made % polls, expected 1', v_n;
  END IF;

  -- A guest sees the poll with its counts hidden.
  PERFORM pg_temp.as_anon();
  SELECT count(*), count(vote_count) INTO v_n, v_visible
    FROM public.get_post_poll(p_opinion_id => v_poll_opinion);
  RESET ROLE;
  IF v_n <> 2 OR v_visible <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: guest poll read gave % rows, % visible counts', v_n, v_visible;
  END IF;

  -- B votes Yes and then sees the counts.
  SELECT o.id INTO v_yes FROM public.poll_options o
    JOIN public.post_polls p ON p.id = o.poll_id
   WHERE p.opinion_id = v_poll_opinion AND o.label = 'Yes';
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.cast_poll_vote(v_yes);
  SELECT * INTO r FROM public.get_post_poll(p_opinion_id => v_poll_opinion) WHERE option_id = v_yes;
  RESET ROLE;
  IF r.vote_count IS DISTINCT FROM 1 OR r.has_voted IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after voting B saw vote_count %, has_voted %', r.vote_count, r.has_voted;
  END IF;

  -- Confirmed removals count strikes. Strikes 1 and 2 only: the live
  -- function raises 42702 ("banned_until" is ambiguous) at strike 3, a
  -- pre-existing Opinions defect this spec does not change (plan finding
  -- F-2). The ban gate itself is checked below with a ban set directly.
  INSERT INTO public.opinions (user_id, content) VALUES (v_a, 'Spec 3 contract: strike two.') RETURNING id INTO v_o2;
  PERFORM pg_temp.as_service();
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o1);
  IF r.violation_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: first removal gave violation_count %', r.violation_count;
  END IF;
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o2);
  IF r.violation_count IS DISTINCT FROM 2 OR r.banned_until IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: second removal gave violation_count %, banned_until %',
      r.violation_count, r.banned_until;
  END IF;
  IF (SELECT removed_at FROM public.opinions WHERE id = v_o1) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a confirmed removal left the opinion visible';
  END IF;
  RESET ROLE;
  UPDATE public.profiles SET banned_until = now() + interval '7 days' WHERE id = v_a;

  -- A banned author cannot post (the assert_can_post ban gate).
  PERFORM pg_temp.as_user(v_a);
  BEGIN
    PERFORM public.create_opinion('Spec 3 contract: posting while banned.');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a banned author posted';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'posting_banned' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: expected posting_banned, got %', v_msg;
    END IF;
  END;
  RESET ROLE;

  -- Opinions notifications still go through the kept "forum" helper.
  PERFORM private.enqueue_forum_notification(
    p_user_id => v_a, p_title => 't', p_body => 'b',
    p_type => 'opinion_liked', p_opinion_id => v_poll_opinion);
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE user_id = v_a AND status = 'pending' AND metadata->>'type' = 'opinion_liked';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % opinion_liked pushes queued for A, expected 1', v_n;
  END IF;
END $$;
RESET ROLE;
```

- [ ] **Step 2: Run the contract to verify it fails (and that D and E already hold)**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/forum_retirement_contracts.sql`
Expected: FAIL, `ERROR:  CONTRACT VIOLATED: authenticated can still execute public.activate_pending_topics()` (spec V4). Sections D and E pin behaviour that must not change; they already pass today (they ran clean against `attune_spec3a` while this plan was written) and must still pass after Step 3.

- [ ] **Step 3: Write migration 2**

Create `supabase/migrations/20261025090100_forum_revoke_client_access.sql`:

```sql
-- Spec 3 (forum removal) W2, migration 2 of 4: close every forum RPC, table
-- and view, so an old app build or a stale edge-function deploy fails closed
-- (permission denied) instead of reading, writing or announcing forum content.
--
-- Functions and views: revoked from PUBLIC, anon, authenticated and
-- service_role (defence in depth: a stale activate-topics or
-- forum-quiet-check deploy fails at its first forum RPC, before any push).
--
-- Tables: revoked from PUBLIC, anon and authenticated only. service_role
-- keeps its table grants because supabase/tests/service_role_grants_test.sql
-- requires SELECT and UPDATE on every public table; both forum edge
-- functions push only through the revoked RPCs, so they stay inert. W3
-- drops the tables.
--
-- Deliberately NOT revoked (Spec 3 §4 keep list): public.get_post_poll
-- (uuid, uuid) and its anon grant (guest Opinions polls), forum_reports,
-- post_polls / poll_options / poll_votes, private.enqueue_forum_notification,
-- private.assert_can_post, public.admin_confirm_content_removal, tags and
-- every Opinions RPC.
--
-- Idempotent: REVOKE of a privilege that is not held is a no-op, and a
-- signature or relation that no longer exists is skipped with a NOTICE.
BEGIN;

DO $$
DECLARE
  v_sig text;
  v_rel text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.activate_pending_topics()',
    'public.expire_old_topics()',
    'public.mark_quiet_topics()',
    'public.notify_quiet_topic(uuid)',
    'private.queue_forum_activity_notifications(uuid,uuid)',
    'public.record_forum_topic_visit(uuid)',
    'public.create_forum_post(uuid,text,text,uuid,text)',
    'public.create_forum_topic(text)',
    'public.create_forum_topic_with_poll(text,text[])',
    'public.edit_forum_post(uuid,text)',
    'public.attach_forum_topic_tags(uuid,text[])',
    'public.get_forum_topic_tags(uuid)',
    'public.get_forum_topics_by_tag(text,integer,integer)',
    'public.get_tags_for_forum_topics(uuid[])',
    'public.get_polls_for_topics(uuid[])',
    'public.get_active_forums_filtered(text[])',
    'public.get_quiet_forums_filtered(text[])',
    'public.get_voting_topics_filtered(text[])',
    'public.increment_topic_upvote_count(uuid)',
    'public.decrement_topic_upvote_count(uuid)',
    'public.increment_topic_downvote_count(uuid)',
    'public.decrement_topic_downvote_count(uuid)',
    'public.increment_topic_post_count(uuid,text)',
    'public.decrement_topic_post_count(uuid,text)',
    'public.increment_topic_seen_count(uuid)',
    'public.increment_forum_post_like_count(uuid)',
    'public.decrement_forum_post_like_count(uuid)',
    'public.report_forum_post(uuid,text)',
    'public.report_forum_topic(uuid,text)'
  ] LOOP
    IF pg_catalog.to_regprocedure(v_sig) IS NULL THEN
      RAISE NOTICE 'forum_revoke_client_access: % does not exist, skipped', v_sig;
      CONTINUE;
    END IF;
    EXECUTE format(
      'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
      v_sig
    );
  END LOOP;

  FOREACH v_rel IN ARRAY ARRAY[
    'public.forum_topics',
    'public.topic_votes',
    'public.topic_impressions',
    'public.forum_posts',
    'public.forum_post_likes',
    'public.user_forum_sides',
    'public.forum_topic_tags',
    'public.forum_topic_visits'
  ] LOOP
    IF pg_catalog.to_regclass(v_rel) IS NULL THEN
      RAISE NOTICE 'forum_revoke_client_access: % does not exist, skipped', v_rel;
      CONTINUE;
    END IF;
    EXECUTE format('REVOKE ALL ON TABLE %s FROM PUBLIC, anon, authenticated', v_rel);
  END LOOP;

  FOREACH v_rel IN ARRAY ARRAY[
    'public.public_forum_topics',
    'public.public_forum_posts'
  ] LOOP
    IF pg_catalog.to_regclass(v_rel) IS NULL THEN
      RAISE NOTICE 'forum_revoke_client_access: % does not exist, skipped', v_rel;
      CONTINUE;
    END IF;
    EXECUTE format(
      'REVOKE ALL ON TABLE %s FROM PUBLIC, anon, authenticated, service_role',
      v_rel
    );
  END LOOP;
END
$$;

COMMIT;
```

- [ ] **Step 4: Apply migration 2 to the scratch database, twice**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025090100_forum_revoke_client_access.sql`
Expected: `BEGIN`, `DO`, `COMMIT`; no ERROR and no "skipped" NOTICE.

Run the same command again.
Expected: the same output (idempotent).

- [ ] **Step 5: Run tests**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/forum_retirement_contracts.sql`
Expected: PASS, `NOTICE:  forum_retirement_contracts: all held`, then `ROLLBACK`.

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/service_role_grants_test.sql`
Expected: PASS, ends in `ROLLBACK` with no ERROR (D-1: service_role still reads and updates every public table).

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/security_lockdown_contracts.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/account_deletion_contracts.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/data_export_contracts.sql`
Expected: all three end in `ROLLBACK` with no ERROR.

---

### Task 7: Cancel queued forum pushes, add the retirement health check (W2 gate)

**Files:**
- Create: `supabase/migrations/20261025090200_forum_cancel_queued_pushes.sql`
- Create: `supabase/migrations/20261025090300_forum_retirement_health.sql`
- Modify: `supabase/tests/forum_retirement_contracts.sql`

**Interfaces:**
- Consumes: the contract file (Tasks 5-6); the baseline file `${TMPDIR:-/tmp}/spec3-w2-contracts-before.txt` (Task 5).
- Produces: no `scheduled_notifications` row with status `pending` and a retired type (`processing` rows are left to finish); `public.forum_retirement_health() RETURNS TABLE (check_name text, ok boolean, detail text)`, `STABLE SECURITY DEFINER SET search_path = ''`, EXECUTE for `service_role` only, five rows in W2: `forum_cron_unscheduled`, `forum_pushes_not_queued`, `forum_rpcs_closed_to_clients`, `forum_tables_closed_to_clients`, `opinions_shared_objects_present`. W3 redefines it with two more checks.

- [ ] **Step 1: Write the failing contract section C and the health checks**

In `supabase/tests/forum_retirement_contracts.sql`, replace:

```sql
-- ---------------------------------------------------------------------
-- D. Keep-list sentinels: what Opinions uses is still open.
```

with:

```sql
-- ---------------------------------------------------------------------
-- C. Pushes: no retired forum push is waiting, and the health check
-- notices one that is.
-- ---------------------------------------------------------------------
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE status IN ('pending', 'processing')
     AND metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % forum pushes still queued', v_n;
  END IF;
END $$;

INSERT INTO auth.users (id) VALUES ('9f3a0000-0000-0000-0000-0000000000c1')
ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  v_user constant uuid := '9f3a0000-0000-0000-0000-0000000000c1';
  v_id uuid;
BEGIN
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
  VALUES (v_user, 'immediate', now(), 'pending',
          jsonb_build_object('type', 'forum_quiet', 'title', 'Forum check', 'body', 'Tap me',
                             'topic_id', gen_random_uuid()::text))
  RETURNING id INTO v_id;
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'forum_pushes_not_queued') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed a pending forum push';
  END IF;
  UPDATE public.scheduled_notifications SET status = 'cancelled' WHERE id = v_id;
  IF NOT (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'forum_pushes_not_queued') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check still sees a cancelled forum push';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- Health: every W2 check is ok, the cron and Opinions checks really look,
-- and only the service role can run it.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_bad text;
  v_job bigint;
BEGIN
  SELECT string_agg(check_name || ': ' || detail, '; ') INTO v_bad
    FROM public.forum_retirement_health() WHERE NOT ok;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum_retirement_health not ok: %', v_bad;
  END IF;
  -- By name, not by count: W3 adds two more checks.
  IF (SELECT count(*) FROM public.forum_retirement_health()
       WHERE check_name IN ('forum_cron_unscheduled', 'forum_pushes_not_queued',
                            'forum_rpcs_closed_to_clients', 'forum_tables_closed_to_clients',
                            'opinions_shared_objects_present')) <> 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W2 forum_retirement_health check is missing';
  END IF;

  -- The production-only nightly sweep, registered again by hand.
  v_job := cron.schedule('mark-quiet-forums', '0 1 * * *', 'select 1');
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'forum_cron_unscheduled') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed mark-quiet-forums';
  END IF;
  PERFORM cron.unschedule(v_job);
  -- A copy under another name is caught by what it runs.
  v_job := cron.schedule('nightly-cleanup-copy', '0 2 * * *',
    $cmd$UPDATE public.forum_topics SET status = 'quiet' WHERE false$cmd$);
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'forum_cron_unscheduled') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed a renamed forum job';
  END IF;
  PERFORM cron.unschedule(v_job);
  IF NOT (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'forum_cron_unscheduled') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the cron check stayed red after unscheduling';
  END IF;

  -- The Opinions sentinel really looks: guest polls losing their grant
  -- turns it red (restored at once; everything here rolls back anyway).
  REVOKE EXECUTE ON FUNCTION public.get_post_poll(uuid, uuid) FROM anon;
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'opinions_shared_objects_present') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed get_post_poll losing its anon grant';
  END IF;
  GRANT EXECUTE ON FUNCTION public.get_post_poll(uuid, uuid) TO anon;

  IF has_function_privilege('anon', 'public.forum_retirement_health()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.forum_retirement_health()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.forum_retirement_health()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum_retirement_health is not service-role only';
  END IF;
  IF NOT (SELECT coalesce(p.proconfig, '{}') @> ARRAY['search_path=""']
            FROM pg_proc p WHERE p.oid = 'public.forum_retirement_health()'::regprocedure) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum_retirement_health has a non-empty search_path';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- D. Keep-list sentinels: what Opinions uses is still open.
```

- [ ] **Step 2: Run the contract to verify it fails**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/forum_retirement_contracts.sql`
Expected: FAIL, `ERROR:  function public.forum_retirement_health() does not exist`.

- [ ] **Step 3: Write migration 3**

Create `supabase/migrations/20261025090200_forum_cancel_queued_pushes.sql`:

```sql
-- Spec 3 (forum removal) W2, migration 3 of 4: cancel every forum push still
-- waiting to go out. The existing cancel idiom
-- (20261018140400_put_away_gently.sql): status 'cancelled', the source key
-- released, last_error naming why. 'processing' rows are left to finish: the
-- dispatcher's own status update requires status = 'processing'. W3 deletes
-- these rows. One statement, so atomic without its own BEGIN/COMMIT;
-- idempotent (a second run matches nothing).
UPDATE public.scheduled_notifications
SET status = 'cancelled', source_key = NULL, last_error = 'forum_retired', updated_at = now()
WHERE status = 'pending'
  AND metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');
```

- [ ] **Step 4: Write migration 4**

Create `supabase/migrations/20261025090300_forum_retirement_health.sql`:

```sql
-- Spec 3 (forum removal) W2, migration 4 of 4: forum_retirement_health(), the
-- on-demand proof that the forum producers are shut (Spec 3 D9). Run it from
-- the SQL editor; supabase/tests/forum_retirement_contracts.sql runs it too.
-- Not a cron: cron failures here go unread (20260931120000).
--
-- Missing objects resolve through to_regprocedure / to_regclass, so the same
-- function stays valid after W3 drops the forum schema. Same posture as
-- scheduled_jobs_health(): service role only.
BEGIN;

CREATE OR REPLACE FUNCTION public.forum_retirement_health()
RETURNS TABLE (check_name text, ok boolean, detail text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_forum_rpcs constant text[] := ARRAY[
    'public.activate_pending_topics()',
    'public.expire_old_topics()',
    'public.mark_quiet_topics()',
    'public.notify_quiet_topic(uuid)',
    'private.queue_forum_activity_notifications(uuid,uuid)',
    'public.record_forum_topic_visit(uuid)',
    'public.create_forum_post(uuid,text,text,uuid,text)',
    'public.create_forum_topic(text)',
    'public.create_forum_topic_with_poll(text,text[])',
    'public.edit_forum_post(uuid,text)',
    'public.attach_forum_topic_tags(uuid,text[])',
    'public.get_forum_topic_tags(uuid)',
    'public.get_forum_topics_by_tag(text,integer,integer)',
    'public.get_tags_for_forum_topics(uuid[])',
    'public.get_polls_for_topics(uuid[])',
    'public.get_active_forums_filtered(text[])',
    'public.get_quiet_forums_filtered(text[])',
    'public.get_voting_topics_filtered(text[])',
    'public.increment_topic_upvote_count(uuid)',
    'public.decrement_topic_upvote_count(uuid)',
    'public.increment_topic_downvote_count(uuid)',
    'public.decrement_topic_downvote_count(uuid)',
    'public.increment_topic_post_count(uuid,text)',
    'public.decrement_topic_post_count(uuid,text)',
    'public.increment_topic_seen_count(uuid)',
    'public.increment_forum_post_like_count(uuid)',
    'public.decrement_forum_post_like_count(uuid)',
    'public.report_forum_post(uuid,text)',
    'public.report_forum_topic(uuid,text)'
  ];
  v_forum_relations constant text[] := ARRAY[
    'public.forum_topics',
    'public.topic_votes',
    'public.topic_impressions',
    'public.forum_posts',
    'public.forum_post_likes',
    'public.user_forum_sides',
    'public.forum_topic_tags',
    'public.forum_topic_visits',
    'public.public_forum_topics',
    'public.public_forum_posts'
  ];
  v_kept_relations constant text[] := ARRAY[
    'public.forum_reports',
    'public.post_polls',
    'public.poll_options',
    'public.poll_votes',
    'public.tags',
    'public.opinion_tags',
    'public.tag_follows'
  ];
  v_kept_functions constant text[] := ARRAY[
    'private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)',
    'private.assert_can_post(uuid,text)',
    'public.admin_confirm_content_removal(text,uuid)'
  ];
  v_name text;
  v_fn regprocedure;
  v_rel regclass;
  v_bad text[];
BEGIN
  -- 1. No forum cron, by name or by what it runs.
  SELECT pg_catalog.array_agg(
           coalesce(j.jobname, '<unnamed>') || ' (jobid ' || j.jobid || ')'
           ORDER BY j.jobid)
    INTO v_bad
    FROM cron.job j
   WHERE j.jobname IN ('activate-topics-sweep', 'forum-quiet-check', 'mark-quiet-forums')
      OR j.command ~* '(activate-topics|forum-quiet-check|forum_topics|mark_quiet_topics|activate_pending_topics|expire_old_topics|notify_quiet_topic)';
  check_name := 'forum_cron_unscheduled';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 2. No retired forum push waiting to go out or going out.
  SELECT pg_catalog.array_agg(DISTINCT (s.metadata->>'type') || ' ' || s.status)
    INTO v_bad
    FROM public.scheduled_notifications s
   WHERE s.status IN ('pending', 'processing')
     AND s.metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');
  check_name := 'forum_pushes_not_queued';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 3. No forum RPC a client can execute (a dropped one passes).
  v_bad := NULL;
  FOREACH v_name IN ARRAY v_forum_rpcs LOOP
    v_fn := pg_catalog.to_regprocedure(v_name);
    IF v_fn IS NOT NULL
       AND (pg_catalog.has_function_privilege('anon', v_fn, 'EXECUTE')
            OR pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE')) THEN
      v_bad := pg_catalog.array_append(v_bad, v_name);
    END IF;
  END LOOP;
  check_name := 'forum_rpcs_closed_to_clients';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 4. No forum table or view a client can read or write (a dropped one passes).
  v_bad := NULL;
  FOREACH v_name IN ARRAY v_forum_relations LOOP
    v_rel := pg_catalog.to_regclass(v_name);
    IF v_rel IS NOT NULL
       AND (pg_catalog.has_table_privilege('anon', v_rel, 'SELECT, INSERT, UPDATE, DELETE')
            OR pg_catalog.has_table_privilege('authenticated', v_rel, 'SELECT, INSERT, UPDATE, DELETE')) THEN
      v_bad := pg_catalog.array_append(v_bad, v_name);
    END IF;
  END LOOP;
  check_name := 'forum_tables_closed_to_clients';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 5. Everything Opinions shares with the old forum schema is still there,
  -- including guest polls.
  v_bad := NULL;
  FOREACH v_name IN ARRAY v_kept_relations LOOP
    IF pg_catalog.to_regclass(v_name) IS NULL THEN
      v_bad := pg_catalog.array_append(v_bad, v_name || ' missing');
    END IF;
  END LOOP;
  FOREACH v_name IN ARRAY v_kept_functions LOOP
    IF pg_catalog.to_regprocedure(v_name) IS NULL THEN
      v_bad := pg_catalog.array_append(v_bad, v_name || ' missing');
    END IF;
  END LOOP;
  v_fn := pg_catalog.to_regprocedure('public.get_post_poll(uuid,uuid)');
  IF v_fn IS NULL
     OR NOT pg_catalog.has_function_privilege('anon', v_fn, 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    v_bad := pg_catalog.array_append(v_bad, 'get_post_poll(uuid,uuid) not executable by anon and authenticated');
  END IF;
  v_fn := pg_catalog.to_regprocedure('public.create_opinion_with_poll(text,text[])');
  IF v_fn IS NULL
     OR NOT pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    v_bad := pg_catalog.array_append(v_bad, 'create_opinion_with_poll(text,text[]) not executable by authenticated');
  END IF;
  check_name := 'opinions_shared_objects_present';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;
END;
$$;

-- Service role only: it names the system's jobs and queue state.
REVOKE ALL ON FUNCTION public.forum_retirement_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.forum_retirement_health() TO service_role;

COMMIT;
```

- [ ] **Step 5: Prove migration 3 cancels only pending forum pushes**

Run:

```bash
cd /Users/user/attune
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a <<'SQL'
BEGIN;
INSERT INTO auth.users (id) VALUES ('9f3a0000-0000-0000-0000-0000000000d1') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key) VALUES
  ('9f3a0000-0000-0000-0000-0000000000d1', 'immediate', now(), 'pending',    '{"type":"forum_activity","topic_id":"t1"}', 'spec3-w2-check-1'),
  ('9f3a0000-0000-0000-0000-0000000000d1', 'immediate', now(), 'processing', '{"type":"forum_quiet","topic_id":"t2"}', NULL),
  ('9f3a0000-0000-0000-0000-0000000000d1', 'immediate', now(), 'pending',    '{"type":"opinion_liked","opinion_id":"o1"}', NULL);
\i supabase/migrations/20261025090200_forum_cancel_queued_pushes.sql
DO $$
BEGIN
  IF (SELECT count(*) FROM public.scheduled_notifications
       WHERE user_id = '9f3a0000-0000-0000-0000-0000000000d1' AND metadata->>'type' = 'forum_activity'
         AND status = 'cancelled' AND last_error = 'forum_retired' AND source_key IS NULL) <> 1 THEN
    RAISE EXCEPTION 'pending forum push was not cancelled';
  END IF;
  IF (SELECT status FROM public.scheduled_notifications
       WHERE user_id = '9f3a0000-0000-0000-0000-0000000000d1' AND metadata->>'type' = 'forum_quiet') <> 'processing' THEN
    RAISE EXCEPTION 'a processing forum push was touched';
  END IF;
  IF (SELECT status FROM public.scheduled_notifications
       WHERE user_id = '9f3a0000-0000-0000-0000-0000000000d1' AND metadata->>'type' = 'opinion_liked') <> 'pending' THEN
    RAISE EXCEPTION 'an Opinions push was cancelled';
  END IF;
  RAISE NOTICE 'cancel check: ok';
END $$;
ROLLBACK;
SQL
```

Expected: `UPDATE 1`, `NOTICE:  cancel check: ok`, `ROLLBACK`.

- [ ] **Step 6: Apply migrations 3 and 4 to the scratch database, twice**

Run:

```bash
cd /Users/user/attune
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025090200_forum_cancel_queued_pushes.sql
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025090300_forum_retirement_health.sql
```

Expected: `UPDATE 0` (no pending forum rows on the scratch DB today; any number is fine), then `BEGIN`, `CREATE FUNCTION`, `REVOKE`, `GRANT`, `COMMIT`.

Run the same two commands again.
Expected: `UPDATE 0`, then the same `BEGIN … COMMIT` output (idempotent).

Run: `psql -X -d attune_spec3a -c 'select * from public.forum_retirement_health()'`
Expected: 5 rows, every `ok` is `t`, every `detail` is `none`.

- [ ] **Step 7: Run tests (W2 regression gate)**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/forum_retirement_contracts.sql`
Expected: PASS, `NOTICE:  forum_retirement_contracts: all held`, then `ROLLBACK`.

Run:

```bash
cd /Users/user/attune
for t in supabase/tests/*.sql; do psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f "$t" >/dev/null 2>&1 || echo "FAIL $t"; done > "${TMPDIR:-/tmp}/spec3-w2-contracts-after.txt"
diff "${TMPDIR:-/tmp}/spec3-w2-contracts-before.txt" "${TMPDIR:-/tmp}/spec3-w2-contracts-after.txt"
```

Expected: no output (no new FAIL line; `forum_retirement_contracts.sql` passes). If a line appears, re-run that one file alone twice; a contract that passes alone both times is pre-existing timing flakiness (seen once with `story_hardening_contracts.sql`), anything else is a regression to fix before going on.

Run: `flutter test`
Expected: PASS, `All tests passed!`

Run: `flutter analyze --no-pub 2>&1 | grep -E '^\s*error ' | grep -vc 'packages/video_compress/example/'`
Expected: `0`.

Run: `git status --short supabase/`
Expected: the four new migrations and `supabase/tests/forum_retirement_contracts.sql` as `??`, the five deletions as ` D`, and the owner's pre-existing ` M supabase/.temp/cli-latest` untouched.

---

## Owner deploy checklist (the owner runs these; the plan never does)

**Read first: any `supabase db push` applies W2.**
- The 4 W2 migrations (`20261025090000` to `20261025090300`) are already in `supabase/migrations`. Any `supabase db push` from this tree applies W2, not only the push in W2 step 2. Push only after the W1 app build is installed on every test device (W2 step -1).
- The Stories migrations (`20261024100000` to `20261024100800`) were already pushed on 2026-10-24. No Stories push is pending, so a `db push` from this tree now carries exactly the 4 W2 files and nothing else.

**Commits are the owner's.** W1 (Tasks 1-4) ships as an app release before W2 is pushed. Split the files like this, so that both commits are green in CI:
- **W1 commit:** every change under `lib/` and `test/`, plus the deletion of the 5 server files: `supabase/functions/activate-topics/`, `supabase/functions/forum-quiet-check/`, `supabase/sql/patch_mark_quiet_forums_null_last_post.sql`, `supabase/sql/schedule_activate_topics.sql`, `supabase/sql/schedule_forum_quiet_check.sql`. Removing the folders from git deploys and undeploys nothing. The last block of `test/architecture/no_forum_references_test.dart` ("forum producers are gone from the server folders") needs those deletions, so a W1 commit without them is red in `flutter-tests`.
- **W2 commit:** the 4 migrations (`supabase/migrations/20261025090000…090300_*.sql`) plus `supabase/tests/forum_retirement_contracts.sql`.
- Leave `supabase/.temp/cli-latest` out of both commits (it is your own change).
- A single combined commit is also fine, because there are no real users yet. The split only matters for deciding when the migrations go live, and that is the push, not the commit.

**W1 (one app release, no server change)**
1. Build and install the W1 app build on **every** test device (iOS and Android). Record each device's build number; the W2 gate (step -1) and the W3 gate need it.
2. Stale-push check, before W2, while the producers still run. In the SQL editor, for your own test account:
   ```sql
   insert into public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
   values ('<your auth user id>', 'immediate', now(), 'pending',
           jsonb_build_object('type','forum_activity','title','Forum check','body','Tap me','topic_id', gen_random_uuid()::text));
   ```
   Wait for the dispatcher, tap the push: it must land on Home.
3. Screens, in light and dark, as guest and signed in, on a phone and on the iPad (ContentWidth column), at default and largest text size: the Opinions header has no tab row and no clipping; a guest lands on Discover and a sign-in mid-session jumps to Following; hiding the nav by scrolling then switching Following ↔ Discover brings it back; "+" (FAB and app bar) opens the composer and posting refreshes the feed and scrolls to the top; a tag page shows the Follow button and one list, pull to refresh and load more work; the manual list and intro carousel show no Forums; the onboarding name-step subtitle reads "…Opinions stay anonymous."; Settings → Muted accounts reads "Anonymous Opinions accounts you've muted".
4. Games smoke test: open one chat game and send a game message.
5. Release note for testers: "Forums removed. Polls and tags in Opinions are unchanged."

**W2 (same week, only after the W1 build is on every test device)**

-1. **Gate: W1 build installed on every test device.** Compare each device's build number with the one recorded in W1 step 1. Do not run any `supabase db push` until every device matches or is newer. If a device is behind and W2 lands anyway, it is still safe: that device shows Forums in an error state (every forum read fails closed with 42501), nothing crashes, and Opinions works fully. The fix is to install W1 on it.
0. Pre-push check (replaces the old Stories note). `supabase migration list` must show only the four `20261025090…` files as pending, and `supabase db push --dry-run` must list exactly those four. If it lists anything else, stop and find out why before pushing. If the Stories handoff edge-function deploy (`docs/reviews/2026-10-24-stories-handoff.md` §3) has not run yet, drop `activate-topics` and `forum-quiet-check` from its function list.
1. Snapshot the crons in the SQL editor and keep the output (expect `mark-quiet-forums`, jobid 3):
   ```sql
   select jobid, jobname, username, schedule, active, left(command, 120) from cron.job order by jobname;
   ```
1b. Cron ownership pre-check (read-only; the local cron is a stub, so this can only be checked here). Migration 1 unschedules by jobid. If a forum job belongs to another role, the push either stops at migration 1 with nothing applied (safe), or the job is hidden by `cron_job_policy` row security and is silently skipped, which makes `forum_retirement_health()` falsely green.
   ```sql
   -- a) who runs the push, and can it see / delete other roles' jobs?
   select current_user,
          (select rolbypassrls from pg_roles where rolname = current_user) as sees_all_jobs,
          has_table_privilege('cron.job', 'DELETE')                        as can_unschedule_others;
   -- b) exactly what migration 1 will unschedule, and who owns it
   select jobid, jobname, username, username = current_user as owned_by_me, active, schedule,
          left(command, 120) as command
     from cron.job
    where jobname in ('activate-topics-sweep', 'forum-quiet-check', 'mark-quiet-forums')
       or command ~* '(activate-topics|forum-quiet-check|forum_topics|mark_quiet_topics|activate_pending_topics|expire_old_topics|notify_quiet_topic)'
    order by jobid;
   -- c) the 29 forum signatures, and no stray overload (expect 29 rows)
   select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and p.proname ~ '(forum|topic)'
      and p.proname not in ('enqueue_forum_notification', 'forum_retirement_health')
    order by 1;
   ```
   - **Go:** (b) lists only the 3 forum jobs, each with `owned_by_me = t`, and (c) returns 29 rows.
   - If any (b) row has `owned_by_me = f` and `can_unschedule_others = f`, unschedule that job first, as its owner or from Dashboard → Integrations → Cron, then continue.
   - If `sees_all_jobs = f`, (b) shows only your own jobs. Cross-check the Dashboard Cron list for any forum job that (b) does not show, and unschedule it there.
2. From the repo root: `supabase migration list` (the four `20261025090…` files show as pending), then `supabase db push`.
3. Undeploy the two functions:
   ```
   supabase functions delete activate-topics
   supabase functions delete forum-quiet-check
   supabase functions list
   ```
   Neither name may appear in the list.
4. Verify in the SQL editor: `select * from public.forum_retirement_health();` → 5 rows, all `ok = true`; `select * from public.scheduled_jobs_health();` → no forum job; Dashboard → Integrations → Cron: none of `activate-topics-sweep`, `forum-quiet-check`, `mark-quiet-forums`.
   - If `forum_pushes_not_queued` is red (a forum push that was `processing` when migration 3 ran went back to `pending` through the 5-minute stale-lease recovery), cancel it again and re-check. The statement is idempotent:
     ```sql
     update public.scheduled_notifications
     set status = 'cancelled', source_key = null, last_error = 'forum_retired', updated_at = now()
     where status = 'pending'
       and metadata->>'type' in ('forum_topic_activated', 'forum_activity', 'forum_quiet');
     ```
5. From now on, never run `supabase functions deploy` with no function names from a checkout older than W2 (it would recreate the two functions; step 3 undoes it, and the W2 revokes keep them inert). The chat handoff's step-4 deploy command no longer names `activate-topics`.
6. Route two pre-existing Opinions bugs to Spec 1 W9 (they are not W2 and W2 does not change them). Spec 1 W9 now lists both under these ids: **OPN-BAN-42702** (the third confirmed Opinions removal fails with 42702, so the 7-day ban never applies; contract E stops at strike 2 for this reason) and **OPN-DELETE-RLS** (an author deleting their own opinion or comment fails row-level security). Do not call them "F-2" or "O-1": "F-2" already means something else in Spec 1's review.
