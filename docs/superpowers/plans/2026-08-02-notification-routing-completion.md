# Notification Routing Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close 15 notification-routing gaps — types that ship real deep-link data server-side but have no matching case in `onNotificationTap`, so a real tap silently lands on home.

**Architecture:** Twelve new switch cases in the existing `onNotificationTap` handler, reusing its established pattern exactly. One new standalone route for the already-built `TimelineScreen`. One new `ChatChannelLoader`-style async loader widget for the three opinion notification types, keeping `onNotificationTap` itself synchronous. Two payload-level fixes (a push-allowlist addition, a migration adding a missing field) without which two of the twelve cases would receive incomplete data even after the client fix ships.

**Tech Stack:** Flutter, GoRouter, Riverpod, Supabase Postgres (plpgsql), Deno edge functions.

## Global Constraints

- Every new switch case follows this file's existing shape exactly: read specific keys off `notification.data`, `GoRouter.of(context).push`/`go`, explicit `return`. No case may fall through to `default:` silently — every type this plan touches gets its own explicit case, even the three that intentionally route to home (`forum_content_removed`, `forum_posting_banned`, `relationship_ended`), so the decision is documented, not accidental.
- `forum_topic_activated`, `forum_activity`, `forum_quiet` share one switch arm (grouped `case` labels, one body) — same style already used for `review_request`/`new_message`/`invite_accepted`.
- `onNotificationTap`'s signature (`void Function(AppNotification notification, BuildContext context)?`) must not change — the opinion cases push a route that does its own async work internally (`OpinionThreadLoader`), never make the handler itself `async`.
- `TimelineScreen` (`lib/features/timeline/presentation/screens/timeline_screen.dart`) already exists fully-built and takes zero constructor args — the new `timeline` route is a registration only, not new screen code.
- `reminder_id` must be added to `privacySafeData`'s allowlist in `process-scheduled-notifications/index.ts`, or `reminder_upcoming`'s case receives no id to route with regardless of the client fix.
- `act_on_dating_introduction`'s migration must never be edited in place — a new addendum migration re-declares the full function via `CREATE OR REPLACE FUNCTION`, changing only the two `jsonb_build_object` calls to add `match_id`.

---

## File Structure

- **Modify:** `lib/app/routing/app_router.dart` — add `RouteNames.timeline`, its `GoRoute`, and `RouteNames.opinionLoader`'s `GoRoute`.
- **Create:** `lib/features/opinions/presentation/screens/opinion_thread_loader.dart` — `OpinionThreadLoader`.
- **Modify:** `lib/core/notifications/config/notification_config.dart` — 12 new switch cases.
- **Modify:** `supabase/functions/process-scheduled-notifications/index.ts` — allowlist addition.
- **Create:** `supabase/migrations/20260816120000_dating_match_id_notification.sql` — `act_on_dating_introduction` re-declaration.
- **Test:** `test/core/notifications/notification_tap_routing_test.dart`.

---

### Task 1: Timeline route and opinion loader widget

**Files:**
- Modify: `lib/app/routing/app_router.dart`
- Create: `lib/features/opinions/presentation/screens/opinion_thread_loader.dart`

**Interfaces:**
- Consumes: `TimelineScreen` (existing, `lib/features/timeline/presentation/screens/timeline_screen.dart`, no constructor args); `opinionRepositoryProvider` (existing, `lib/features/opinions/presentation/providers/opinion_providers.dart:19`, `Provider<OpinionRepository>`); `OpinionRepository.getQuotedOpinion(String opinionId) → Future<OpinionModel?>` (existing, `lib/features/opinions/data/repositories/opinion_repository.dart:385`); `CommentThreadScreen` (existing, `lib/features/opinions/presentation/screen/comment_thread_screen.dart`, constructor `({required String opinionId, required OpinionModel opinion})`).
- Produces: `RouteNames.timeline` (`'/timeline'`), `RouteNames.opinionLoader` (`'/opinionLoader'`) — both consumed by Task 2's switch cases; `OpinionThreadLoader` widget (`ConsumerWidget`, constructor `({required String opinionId})`) — consumed only by the `opinionLoader` route's builder in this same task.

- [ ] **Step 1: Add the Timeline route**

In `lib/app/routing/app_router.dart`, add the constant inside the `RouteNames` class, immediately after the existing `couplesCalendar` constant (confirmed current location: line 201):

```dart
  static const String timeline = '/timeline';
```

Add the import near the other feature-screen imports:

```dart
import 'package:attune/features/timeline/presentation/screens/timeline_screen.dart';
```

Add the `GoRoute`, immediately after the existing `couplesCalendar` `GoRoute` (confirmed current location — the block reads exactly):

```dart
      GoRoute(
        path: RouteNames.pulse,
        name: 'pulse',
        builder: (context, state) => const PulseScreen(),
      ),
      GoRoute(
        path: RouteNames.couplesCalendar,
        name: 'couplesCalendar',
        builder: (context, state) => const CouplesCalendarScreen(),
      ),
```

Insert a new `GoRoute` between them and the next existing route (`addEditReminder`):

```dart
      GoRoute(
        path: RouteNames.timeline,
        name: 'timeline',
        builder: (context, state) => const TimelineScreen(),
      ),
```

- [ ] **Step 2: Write `OpinionThreadLoader`**

```dart
// lib/features/opinions/presentation/screens/opinion_thread_loader.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';

class OpinionThreadLoader extends ConsumerWidget {
  const OpinionThreadLoader({super.key, required this.opinionId});

  final String opinionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(opinionRepositoryProvider).getQuotedOpinion(opinionId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final opinion = snapshot.data;
        if (opinion == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Text('This opinion is unavailable.'),
            ),
          );
        }

        return CommentThreadScreen(opinionId: opinion.id, opinion: opinion);
      },
    );
  }
}
```

- [ ] **Step 3: Register the loader route**

Add the constant inside `RouteNames`, immediately after `timeline`:

```dart
  static const String opinionLoader = '/opinionLoader';
```

Add the import:

```dart
import 'package:attune/features/opinions/presentation/screens/opinion_thread_loader.dart';
```

Add the `GoRoute`, immediately after the new `timeline` route:

```dart
      GoRoute(
        path: RouteNames.opinionLoader,
        name: 'opinionLoader',
        builder: (context, state) {
          final opinionId = state.extra as String?;
          if (opinionId == null) {
            return const Scaffold(
              body: Center(child: Text('Opinion unavailable.')),
            );
          }
          return OpinionThreadLoader(opinionId: opinionId);
        },
      ),
```

- [ ] **Step 4: Run `flutter analyze`**

Run: `flutter analyze lib/app/routing/app_router.dart lib/features/opinions/presentation/screens/opinion_thread_loader.dart`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/app/routing/app_router.dart
git add lib/features/opinions/presentation/screens/opinion_thread_loader.dart
git commit -m "feat(notifications): add timeline route and opinion thread loader"
```

---

### Task 2: Twelve `onNotificationTap` switch cases

**Files:**
- Modify: `lib/core/notifications/config/notification_config.dart`
- Test: `test/core/notifications/notification_tap_routing_test.dart`

**Interfaces:**
- Consumes: `RouteNames.timeline`, `RouteNames.opinionLoader` (Task 1). `RouteNames.weeklyCheckin`, `RouteNames.pulse`, `RouteNames.thirtySixChapterInvitation`, `RouteNames.forumInsight`, `RouteNames.home` (all pre-existing, confirmed present).
- Produces: nothing consumed by a later task — this completes the client-side routing work.

The current switch statement (confirmed exact current content, `notification_config.dart:70-129`) is:

```dart
    onNotificationTap: (notification, context) {
      final type = notification.data?['type'] as String?;
      final shopId = notification.data?['shop_id'] as String?;

      switch (type) {
        case 'booking_reminder_24h':
        case 'booking_reminder_1h':
        case 'booking_reminder_5min':
        case 'shop_reminder_15min':
        case 'booking_created':
        case 'booking_confirmed':
        case 'booking_cancelled':
          GoRouter.of(context).go(RouteNames.calendar);
          return;

        case 'new_shop_nearby':
          if (shopId != null && shopId.isNotEmpty) {
            GoRouter.of(context).push(
              RouteNames.shopDetailsScreen,
              extra: {'shopId': shopId, 'coverImageUrl': ''},
            );
          } else {
            GoRouter.of(context).go(RouteNames.home);
          }
          return;

        case 'review_request':
        case 'new_message':
        case 'invite_accepted':
          final relationshipId =
              notification.data?['relationship_id'] as String?;
          if (relationshipId != null && relationshipId.isNotEmpty) {
            GoRouter.of(context).push(
              '${RouteNames.chatChannel}?relationshipId=${Uri.encodeComponent(relationshipId)}',
            );
          } else {
            GoRouter.of(context).go(RouteNames.home);
          }
          return;

        case 'safety_resources':
          GoRouter.of(context).go(RouteNames.safetyResources);
          return;

        case 'ask2_invite':
          final relationshipId = notification.data?['relationship_id'] as String?;
          if (relationshipId != null && relationshipId.isNotEmpty) {
            GoRouter.of(context).push(
              '/ask2/${Uri.encodeComponent(relationshipId)}',
            );
          } else {
            GoRouter.of(context).go(RouteNames.home);
          }
          return;

        default:
          GoRouter.of(context).go(RouteNames.home);
          return;
      }
    },
```

- [ ] **Step 1: Add the 12 new cases before `default:`**

Insert the following cases immediately before the `default:` case, after the existing `ask2_invite` case:

```dart
        case 'checkin_reminder':
          GoRouter.of(context).go(RouteNames.weeklyCheckin);
          return;

        case 'pulse_updated':
          GoRouter.of(context).go(RouteNames.pulse);
          return;

        case 'moment_logged':
          GoRouter.of(context).go(RouteNames.timeline);
          return;

        case 'thirty_six_question_invite':
          final sessionId = notification.data?['session_id'] as String?;
          final chapter = notification.data?['chapter'] as int?;
          if (sessionId != null && sessionId.isNotEmpty && chapter != null) {
            GoRouter.of(context).push(
              RouteNames.thirtySixChapterInvitation,
              extra: (sessionId: sessionId, chapter: chapter, isInitiator: false),
            );
          } else {
            GoRouter.of(context).go(RouteNames.home);
          }
          return;

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

        case 'opinion_liked':
        case 'opinion_commented':
        case 'opinion_comment_reply':
          final opinionId = notification.data?['opinion_id'] as String?;
          if (opinionId != null && opinionId.isNotEmpty) {
            GoRouter.of(context).push(RouteNames.opinionLoader, extra: opinionId);
          } else {
            GoRouter.of(context).go(RouteNames.home);
          }
          return;

        case 'forum_content_removed':
        case 'forum_posting_banned':
          // Content is gone (forum_content_removed) or this is an
          // account-level notice with no content id (forum_posting_banned)
          // — home is deliberate here, not a missing case. See design spec
          // docs/superpowers/specs/2026-08-02-notification-routing-completion-design.md §5.
          GoRouter.of(context).go(RouteNames.home);
          return;

        case 'relationship_ended':
          // Payload already carries screen: "home" and no relationship id
          // to route more specifically with — this is the intended
          // destination, not an oversight. See design spec §5.
          GoRouter.of(context).go(RouteNames.home);
          return;

        case 'dating_mutual_match':
          GoRouter.of(context).go(RouteNames.datingMatches);
          return;
```

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze lib/core/notifications/config/notification_config.dart`
Expected: no errors.

- [ ] **Step 3: Write tests for the data-extraction logic**

These tests exercise the pure data-shape decisions each new case makes (which key it reads, whether it's present/absent) without needing a live `GoRouter`/widget tree — mirroring `onesignal_click_routing_test.dart`'s existing pure-function style:

```dart
// test/core/notifications/notification_tap_routing_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('thirty_six_question_invite payload extraction', () {
    test('sessionId and chapter present and well-formed', () {
      final data = {
        'type': 'thirty_six_question_invite',
        'session_id': 'sess-1',
        'chapter': 2,
      };
      final sessionId = data['session_id'] as String?;
      final chapter = data['chapter'] as int?;
      expect(sessionId, 'sess-1');
      expect(chapter, 2);
    });

    test('missing chapter is null, not a crash', () {
      final data = {'type': 'thirty_six_question_invite', 'session_id': 'sess-1'};
      final chapter = data['chapter'] as int?;
      expect(chapter, isNull);
    });
  });

  group('forum_topic_activated / forum_activity / forum_quiet payload extraction', () {
    test('topic_id present', () {
      final data = {'type': 'forum_activity', 'topic_id': 'topic-1'};
      final topicId = data['topic_id'] as String?;
      expect(topicId, 'topic-1');
    });

    test('empty topic_id treated as absent', () {
      final data = {'type': 'forum_quiet', 'topic_id': ''};
      final topicId = data['topic_id'] as String?;
      expect(topicId != null && topicId.isNotEmpty, isFalse);
    });
  });

  group('opinion_liked / opinion_commented / opinion_comment_reply payload extraction', () {
    test('opinion_id present', () {
      final data = {'type': 'opinion_liked', 'opinion_id': 'op-1'};
      final opinionId = data['opinion_id'] as String?;
      expect(opinionId, 'op-1');
    });

    test('missing opinion_id is null', () {
      final data = {'type': 'opinion_commented'};
      final opinionId = data['opinion_id'] as String?;
      expect(opinionId, isNull);
    });
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/notifications/notification_tap_routing_test.dart`
Expected: PASS, 6/6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/core/notifications/config/notification_config.dart
git add test/core/notifications/notification_tap_routing_test.dart
git commit -m "feat(notifications): add 12 onNotificationTap routing cases"
```

---

### Task 3: `reminder_id` allowlist fix

**Files:**
- Modify: `supabase/functions/process-scheduled-notifications/index.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: nothing consumed by a later task.

The current `privacySafeData` function (confirmed exact current content, `process-scheduled-notifications/index.ts:80-99`) allowlists these keys:

```typescript
const allowed = [
  "type",
  "relationship_id",
  "journey_id",
  "session_id",
  "chapter",
  "opinion_id",
  "comment_id",
  "forum_post_id",
  "topic_id",
];
```

- [ ] **Step 1: Add `reminder_id` and `match_id` to the allowlist**

```typescript
const allowed = [
  "type",
  "relationship_id",
  "journey_id",
  "session_id",
  "chapter",
  "opinion_id",
  "comment_id",
  "forum_post_id",
  "topic_id",
  "reminder_id",
  "match_id",
];
```

(`match_id` is added here alongside `reminder_id` since Task 4 adds it to the `dating_mutual_match` payload, and both fixes belong to the same allowlist — adding it now avoids a second edit to this same array in a later task.)

- [ ] **Step 2: Type-check with Deno**

Run: `cd /Users/user/attune/supabase/functions/process-scheduled-notifications && deno check index.ts`
Expected: no type errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/process-scheduled-notifications/index.ts
git commit -m "fix(notifications): allow reminder_id and match_id through the push payload filter"
```

Note: no automated test — a single array literal edit with no independently testable branching logic of its own. Verification is `deno check` plus the plan's final manual-verification checklist.

---

### Task 4: `dating_mutual_match` payload fix

**Files:**
- Create: `supabase/migrations/20260816120000_dating_match_id_notification.sql`

**Interfaces:**
- Consumes: nothing from earlier tasks (independent of Tasks 1-3 for its own correctness, though Task 3's allowlist change is required for this fix's effect to actually reach a device).
- Produces: nothing consumed by a later task.

- [ ] **Step 1: Write the migration**

The current `act_on_dating_introduction` function (confirmed exact current content, `supabase/migrations/20260705210000_dating_mode_v1_2_hardening.sql:623-701`) is re-declared verbatim, with `match_id` added to the two `jsonb_build_object` calls at what were originally lines 692 and 695:

```sql
-- supabase/migrations/20260816120000_dating_match_id_notification.sql
--
-- act_on_dating_introduction's dating_mutual_match push never included the
-- match id, despite v_match_id being in scope — a real payload gap, not
-- just a missing allowlist entry. Re-declares the function verbatim, only
-- adding 'match_id', v_match_id::text to both jsonb_build_object calls.
-- See design spec docs/superpowers/specs/
-- 2026-08-02-notification-routing-completion-design.md §6.

CREATE OR REPLACE FUNCTION public.act_on_dating_introduction(
  p_idempotency_key text,
  p_introduction_id uuid,
  p_action text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_intro public.dating_introductions%ROWTYPE;
  v_match_id uuid;
  v_active_algorithm text;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF p_action NOT IN ('interested','passed') THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
  PERFORM public.check_dating_rate_limit('interest_action',30,interval '1 day');
  IF NOT public.dating_flag_enabled('dating_mode_enabled') THEN
    RAISE EXCEPTION 'dating_unavailable' USING ERRCODE='22023';
  END IF;
  SELECT version INTO v_active_algorithm FROM public.dating_algorithm_configs WHERE state='active';
  IF v_active_algorithm IS NULL THEN RAISE EXCEPTION 'algorithm_unavailable' USING ERRCODE='22023'; END IF;

  SELECT * INTO v_intro FROM public.dating_introductions
  WHERE id=p_introduction_id AND v_user_id IN (user_low_id,user_high_id)
  FOR UPDATE;
  IF NOT FOUND OR v_intro.expires_at<=now()
     OR v_intro.state NOT IN ('generated','presented','interested')
     OR v_intro.algorithm_version<>v_active_algorithm THEN
    RAISE EXCEPTION 'introduction_unavailable' USING ERRCODE='22023';
  END IF;
  IF NOT public.dating_candidate_is_current(v_intro.user_low_id)
     OR NOT public.dating_candidate_is_current(v_intro.user_high_id)
     OR EXISTS(SELECT 1 FROM public.dating_blocks b WHERE b.pair_key=v_intro.pair_key)
     OR NOT EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=v_intro.snapshot_low_id AND s.invalidated_at IS NULL)
     OR NOT EXISTS(SELECT 1 FROM public.dating_feature_snapshots s WHERE s.id=v_intro.snapshot_high_id AND s.invalidated_at IS NULL) THEN
    UPDATE public.dating_introductions SET state='invalidated' WHERE id=v_intro.id;
    RAISE EXCEPTION 'introduction_unavailable' USING ERRCODE='22023';
  END IF;
  IF NOT public.claim_dating_idempotency('act_on_dating_introduction',p_idempotency_key) THEN RETURN; END IF;

  INSERT INTO public.dating_interest_actions(introduction_id,actor_user_id,action,idempotency_key,acted_at)
  VALUES(v_intro.id,v_user_id,p_action,p_idempotency_key,now())
  ON CONFLICT(introduction_id,actor_user_id) DO NOTHING;

  IF v_intro.user_low_id=v_user_id THEN
    UPDATE public.dating_introductions SET low_action=p_action,state=CASE
      WHEN p_action='passed' THEN 'passed'
      WHEN high_action='interested' THEN 'matched'
      ELSE 'interested' END WHERE id=v_intro.id;
  ELSE
    UPDATE public.dating_introductions SET high_action=p_action,state=CASE
      WHEN p_action='passed' THEN 'passed'
      WHEN low_action='interested' THEN 'matched'
      ELSE 'interested' END WHERE id=v_intro.id;
  END IF;

  SELECT * INTO v_intro FROM public.dating_introductions WHERE id=v_intro.id;
  IF v_intro.low_action='interested' AND v_intro.high_action='interested' THEN
    INSERT INTO public.dating_matches(introduction_id,user_low_id,user_high_id,state,matched_at,created_at)
    VALUES(v_intro.id,v_intro.user_low_id,v_intro.user_high_id,'active',now(),now())
    ON CONFLICT(introduction_id) DO NOTHING RETURNING id INTO v_match_id;
    IF v_match_id IS NOT NULL THEN
      INSERT INTO public.scheduled_notifications(
        user_id,notification_type,scheduled_for,status,metadata,source_key,created_at,updated_at
      ) VALUES
        (v_intro.user_low_id,'immediate',now(),'pending',
         jsonb_build_object('title','New mutual match','body','Open Attune to see your new connection.','type','dating_mutual_match','match_id',v_match_id::text),
         'dating_match:'||v_match_id::text||':'||v_intro.user_low_id::text,now(),now()),
        (v_intro.user_high_id,'immediate',now(),'pending',
         jsonb_build_object('title','New mutual match','body','Open Attune to see your new connection.','type','dating_mutual_match','match_id',v_match_id::text),
         'dating_match:'||v_match_id::text||':'||v_intro.user_high_id::text,now(),now())
      ON CONFLICT(source_key) WHERE source_key IS NOT NULL DO NOTHING;
    END IF;
  END IF;
END;
$$;
```

- [ ] **Step 2: Verify only the two target lines differ from the original**

Run: `grep -c "match_id" supabase/migrations/20260816120000_dating_match_id_notification.sql`
Expected: `3` (one in the file's own header comment, plus the two `jsonb_build_object` calls — confirms both were actually edited, not just one).

Then manually re-read the new migration file's function body side-by-side against `supabase/migrations/20260705210000_dating_mode_v1_2_hardening.sql:623-701` (the original) and confirm every line other than the two `jsonb_build_object` calls is character-for-character identical — this is a visual check, not a scripted diff, since the new file also carries a header comment the original didn't have, which would make a naive line-range diff report spurious differences.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260816120000_dating_match_id_notification.sql
git commit -m "fix(dating): include match_id in the dating_mutual_match push payload"
```

Note: no automated test — pure DDL/RPC SQL, no live Supabase project in this sandboxed environment. `supabase db push` and live verification are deferred to a human before this branch merges/deploys, consistent with every other migration task in this codebase's recent history.

---

## Post-implementation manual verification (not a task — a checklist for the final reviewer)

- [ ] Trigger each of these for real and confirm the correct screen opens: `checkin_reminder` → weekly check-in; `thirty_six_question_invite` → chapter invitation screen with correct chapter number; `forum_topic_activated`/`forum_activity`/`forum_quiet` → forum insight for the correct topic; `opinion_liked`/`opinion_commented`/`opinion_comment_reply` → comment thread for the correct opinion (confirm the loading spinner appears briefly, then the real thread, not a flash of "unavailable"); `dating_mutual_match` → dating matches list; `forum_content_removed`/`forum_posting_banned`/`relationship_ended` → home (confirm this is the intended behavior, not silently broken).
- [ ] Confirm `pulse_updated`/`moment_logged` don't crash if manually triggered via a raw OneSignal test push — route to `/pulse`/`/timeline` correctly even though nothing in production sends these yet.
- [ ] Query a real `reminder_upcoming` row in `scheduled_notifications` after Task 3 ships; confirm the delivered push's `data` object actually contains `reminder_id` (not just `type`).
- [ ] Trigger a real dating mutual match after Task 4 ships; confirm the delivered push's `data` object contains `match_id`.
- [ ] Tap a `thirty_six_question_invite` notification with a malformed/missing `chapter` (e.g. manually crafted test push with `chapter` omitted); confirm it falls back to home rather than crashing on a null `chapter`.
