# Notification Routing Completion — Design

**Goal:** Close 15 gaps found in a follow-up audit: notification types that ship real data server-side but have no matching `case` in `onNotificationTap`'s switch (`lib/core/notifications/config/notification_config.dart`), so a real tap on any of them silently lands on home.

## 1. Scope

Twelve types get a straightforward switch case, reusing this file's existing pattern exactly (read `notification.data` keys, `GoRouter.of(context).push/go`). Three need a fix beyond the switch statement before their case can work at all:

- `reminder_upcoming`'s `reminder_id` is silently stripped by `process-scheduled-notifications`'s payload allowlist before the push ever leaves the server — the switch case is correct but receives nothing to route with.
- `dating_mutual_match`'s payload never included a match id in the first place — a gap in the migration that builds the push, not in anything downstream.
- `pulse_updated`/`moment_logged` get correct switch cases, but nothing in production currently sends either notification (`AttuneNotificationService`'s senders are `debugPrint` stubs) — out of scope to wire those senders live; in scope only to make sure the case is ready the moment someone does.

Explicitly out of scope: turning `pulse_updated`/`moment_logged` into real, firing notifications (a separate "wire the sender" task, unrelated to routing); the more specific `datingGuidedDate` destination for `dating_mutual_match` (routing to the existing `datingMatches` list is the smallest correct destination, matching the bar every other case in this file already uses — no new screen-specific payload plumbing for one type when the rest of the file doesn't do that either).

## 2. The twelve direct cases

| Type | Payload keys used | Destination |
|---|---|---|
| `checkin_reminder` | none (payload already says `screen: "weekly_checkin"`, unused today) | `go(RouteNames.weeklyCheckin)` |
| `pulse_updated` | none | `go(RouteNames.pulse)` — resolves the caller's own relationship internally, no id needed |
| `moment_logged` | none (`event_type` is present in the payload but is display-copy-only, per `AttuneNotificationService`'s own `_getEventTypeDisplay` — not consumed here since `TimelineScreen` takes no constructor args to filter by) | `go(RouteNames.timeline)` — new route registration only (see §3), `TimelineScreen` itself already exists fully-built |
| `thirty_six_question_invite` | `session_id`, `chapter` | `push(RouteNames.thirtySixChapterInvitation, extra: (sessionId: ..., chapter: ..., isInitiator: false))` — `isInitiator` is always `false` here since this push only ever goes to the invitee, never the sender |
| `forum_topic_activated`, `forum_activity`, `forum_quiet` | `topic_id` | `push(RouteNames.forumInsight, extra: topicId)` — all three share one payload shape and one destination; grouped into a single switch arm, same pattern the existing `review_request`/`new_message` cases already use for shared bodies |
| `opinion_liked`, `opinion_commented`, `opinion_comment_reply` | `opinion_id` | route to the existing `commentThread` route via a new loader widget (§4) |
| `forum_content_removed`, `forum_posting_banned` | none used | `go(RouteNames.home)`, explicit — see §5 |
| `relationship_ended` | none used | `go(RouteNames.home)`, explicit — see §5 |

## 3. New route: `RouteNames.timeline`

`TimelineScreen` (`lib/features/timeline/presentation/screens/timeline_screen.dart`) already exists, fully built, and takes zero constructor args (`const TimelineScreen({super.key})`) — currently only reachable as the second tab inside `PulseTab`, with no standalone `GoRoute`. This is a one-line registration (`RouteNames.timeline = '/timeline'`, `GoRoute(path: ..., builder: (context, state) => const TimelineScreen())`), not new screen work — the exact same pattern `PulseScreen`/`CouplesCalendarScreen` already use (each independently routable despite also being tabs in the same `PulseTab`).

## 4. New widget: `OpinionThreadLoader`

Mirrors `ChatChannelLoader` (`lib/features/chat/presentation/screens/chat_channel_loader.dart`) exactly — a `ConsumerWidget` taking an `opinionId`, using `FutureBuilder` over `ref.read(opinionRepositoryProvider).getQuotedOpinion(opinionId)` (existing method, `Future<OpinionModel?>`), showing a spinner while loading, an "Opinion unavailable" message if the fetch returns `null`, and `CommentThreadScreen(opinionId: opinion.id, opinion: opinion)` once loaded (existing screen, existing constructor — unchanged).

This keeps `onNotificationTap`'s signature fully synchronous — the three opinion cases push a new lightweight loader route (`RouteNames.opinionLoader = '/opinionLoader'`, taking `opinionId` via `state.extra`) that does the async fetch internally, rather than making the tap handler itself `async` (which would touch the shared, reusable `NotificationConfig` interface that the in-app inbox also depends on — unnecessary blast radius for a problem three call sites have, not the interface itself).

## 5. Deliberate home-fallback cases

`forum_content_removed`: even though `opinion_id`/`comment_id`/`forum_post_id` are technically present in the payload, the underlying content has `removed_at` set — navigating to it would show an empty/error state, not useful content. `forum_posting_banned`: an account-level notice with no content id at all, by design (confirmed in the migration's own comment). `relationship_ended`: the payload literally already hardcodes `screen: "home"` and carries no relationship/journey id to route more specifically with (unlike `new_message`/`invite_accepted`, which do carry `relationship_id`) — home is the correct, already-intended destination, not an oversight.

All three get an explicit `case` calling `go(RouteNames.home)` rather than being left to fall through `default:` — same reasoning as the earlier `invite_accepted` fix's own logic: an explicit case documents "we considered this and home is correct," distinguishable from a type nobody has thought about yet.

## 6. Payload-level fixes

**`process-scheduled-notifications`'s allowlist** (`privacySafeData()`, `supabase/functions/process-scheduled-notifications/index.ts`): add `reminder_id` to the existing allowlist (`type, relationship_id, journey_id, session_id, chapter, opinion_id, comment_id, forum_post_id, topic_id`). Without this, `reminder_upcoming`'s switch case is correct but receives `{ type: 'reminder_upcoming' }` and nothing else — this file is the reason the feature built earlier this session doesn't fully work yet, independent of anything in `notification_config.dart`.

**`act_on_dating_introduction`** (originally defined in `supabase/migrations/20260705210000_dating_mode_v1_2_hardening.sql:623-701`, a 79-line function): both `jsonb_build_object(...)` calls building the `dating_mutual_match` push (lines 692, 695) already have `v_match_id` in scope (`RETURNING id INTO v_match_id`, line 686) but never include it. A new addendum migration re-declares the entire function verbatim via `CREATE OR REPLACE FUNCTION`, changing only those two lines to add `'match_id', v_match_id`:

```sql
-- line 692 becomes:
jsonb_build_object('title','New mutual match','body','Open Attune to see your new connection.','type','dating_mutual_match','match_id',v_match_id::text),
-- line 695 becomes:
jsonb_build_object('title','New mutual match','body','Open Attune to see your new connection.','type','dating_mutual_match','match_id',v_match_id::text),
```

Every other line of the function (the auth check, rate limit, algorithm check, introduction lookup/locking, candidate-currency checks, idempotency claim, the interest-action insert, the match-state update, and the match insert itself) is copied unchanged — this is a full re-declaration because the function is short enough that copying it whole removes any ambiguity about which lines change, following this codebase's established convention of never editing an already-shipped migration file directly (confirmed pattern from this session's own prior work — e.g. `20260813140000_reminders_timeline_link_grant.sql` was a small addendum migration rather than an edit to an already-committed one). `match_id` also needs adding to `privacySafeData`'s allowlist in the same commit as the `reminder_id` addition above, or the newly-added payload key would just get stripped right back out.

## 7. Testing evidence expected at implementation time

- No live-push test possible in this sandboxed environment (same constraint as the prior push-wiring branch) — this is inherent to the whole notification system, not new here.
- Unit test for the grouped `forum_topic_activated`/`forum_activity`/`forum_quiet` case and the `opinion_*` cases' correct extraction of `topic_id`/`opinion_id` from `notification.data`, following the same pattern as the existing `onesignal_click_routing_test.dart` (pure data-shape assertions, no widget pump needed for the data-extraction logic — though routing itself, since it calls `GoRouter.of(context)`, needs at minimum a smoke-level widget test confirming each case doesn't throw when given a well-formed payload and a real `GoRouter` in the tree, mirroring the empirical navigation test the previous branch's final reviewer wrote to prove the click-listener fix worked).
- Manual verification checklist (device/build required, cannot run in this sandbox): trigger each of the 12 already-firing types for real (where their sender is genuinely wired — `thirty_six_question_invite`, `forum_topic_activated`, `forum_activity`, `forum_quiet`, `opinion_liked`, `opinion_commented`, `opinion_comment_reply`, `forum_content_removed`, `forum_posting_banned`, `checkin_reminder`, `dating_mutual_match`, `reminder_upcoming`, `relationship_ended`) and confirm each opens the correct screen; confirm `pulse_updated`/`moment_logged` cases don't crash if manually triggered via a raw OneSignal test push even though nothing in production sends them yet.
