# Chat Wave 3 — Chat Screen (issues #30–#38) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the chat screen behave like WhatsApp/iMessage for the nine verified screen-level failures: jump-to-message always lands and flashes, "edited" is visible with reachable history, a scroll-to-bottom pill + unread divider with a list that never jumps under the reader, overlays that never cover the newest bubble, a Starred screen that is always current, over-limit pastes that never destroy a draft, delivery ticks on own bubbles (and delivered stamped on push receipt), tappable links, and three concrete performance fixes (thumbnail decode size, wallpaper repaint, timestamp-drag rebuilds).

**Architecture:** Every change is client-side Flutter inside `lib/features/chat` plus one small shared layout widget (`MeasureSize`) and one OneSignal hook. Jump-to-message gets a convergent two-stage design: the controller pages history (large pages, bounded by the target's `(sort_at, id)` fetched with Plan 1a's `getMessagesByIds` and checked against 1a's server-confirmed `_oldestFetchedCursor`) until the target row is in `state.messages`, then the screen iterates "nearest built row → extrapolate → jumpTo → next frame" until the target's GlobalKey is attached, then `ensureVisible` + flash. The list becomes key-anchored (`findChildIndexCallback`) so arrivals while scrolled up do not shift the viewport. Overlay height is measured, not guessed. The reveal-drag offset becomes a `ValueListenable` consumed inside `MessageBubble` so bubble content is built once per list build.

**Tech Stack:** Flutter 3.29, Riverpod 2.6, `cached_network_image`, `url_launcher` (already a direct dependency), Supabase (one new PostgREST select, no migration, no edge-function change). No new packages: `pubspec.yaml` has no `scrollable_positioned_list`/`flutter_linkify`; neither is needed (see Task 4 and Task 13 rulings).

**Spec:** `docs/reviews/2026-10-18-chat-robustness-review.md` (issues #30–#38), evidence in `docs/reviews/2026-10-18-chat-review/05_ui_actions_perf.md` (H-1, H-2, H-3, M-1..M-6) and `docs/reviews/2026-10-18-chat-review/V1_client_verify.md` (RC-11, RC-12, RC-13, RC-14, RC-16); product spec `lib/architecture/CHAT_SYSTEM_SPEC.md` (§3.3 derived delivery status, §Text maximum 10,000 Unicode scalar values client+server, §6.4 read receipts) and `docs/superpowers/specs/2026-08-13-message-actions-design.md` ("Edited label + history view", "Pinned banner").

## Global Constraints

- Work on main in the existing working tree (the owner has other uncommitted work; never revert or reformat it). NO COMMITS: replace every "Commit" step with "Checkpoint: run this task's tests and `flutter analyze <touched files>` filtered with `grep -E '^\s*(error|warning) '`; no commit (the owner commits)".
- Never run `dart format` on pre-existing files (repo uses an older formatter; reflowing is a regression). Only new files may be formatted.
- Test-first: every fix starts with a failing test that reproduces the verified failure scenario; watch it fail for the right reason, then fix.
- Flutter tests: `flutter test <path>`; reuse existing harnesses (test/features/chat/support/chat_test_harness.dart, FakeChatRepository, fake cache backends, FakeHaptics). Update old tests only where they encode the wrong behaviour, and say so.
- SQL: new migrations only (never edit an existing migration). Use ONLY your assigned timestamp range (20261019130000–20261019139999). Apply locally with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/<file>.sql`; contract tests in supabase/tests/<name>_contracts.sql in the existing style (BEGIN … RAISE EXCEPTION 'CONTRACT VIOLATED: …' … ROLLBACK; see supabase/tests/home_card_order_contracts.sql and chat_system_contracts.sql), run with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/<file>.sql`. Include a mutation check for each key rule (temporarily break the rule in a transaction and show the contract fails). NEVER use the attune_test database. Never touch the live project; deploying migrations/functions is an owner step — list them at the end under "Owner deploy steps". (This plan needs no migration: the 10,000-char limit already exists as `messages_content_length` in `supabase/migrations/20260705120000_chat_system_v1_2.sql`, and the jump lookup reuses Plan 1a's `getMessagesByIds`, a plain RLS-protected select.)
- Edge functions (Deno/TS): follow existing patterns in supabase/functions; if the function has Deno tests, add tests; otherwise extract pure logic into a testable module with a Deno test (`deno test` if available — check `which deno`; if not available, say so and make the logic testable via SQL or Dart instead). (`which deno` → `/opt/homebrew/bin/deno`; this plan changes no edge function.)
- Owner-only steps (Xcode capabilities, OneSignal dashboard settings, App Store / Apple developer portal) are listed explicitly as "Owner step" with exact instructions; the plan still makes every file change that can be made in the repo (e.g. entitlements/Info.plist edits).
- Display dates via MyDateFormat; user-facing copy plain and warm; respect reduceMotionOf for animations; haptics via hapticsProvider.
- Don't touch ATTUNE_SOUL.md / ATTUNE_THESIS.md. Don't read .env/credentials/keychain.
- Execution order across plans: 1a → 1b → 2 → 3 → 4, sequential on the same tree. Later plans must not assume line numbers from before earlier plans ran; say which files you share with other plans in a "Shared files" note.
- Message text limit is `Message.maxContentRunes = 10000` code points (`value.runes.length`), identical to the DB `CHECK (char_length(content) <= 10000)`. Never count with `String.length` (UTF-16) or `characters` (graphemes).
- Private-row gating stays as it is: actions only on server-backed rows (`!message.id.startsWith('_local_')`) in a `canSend` conversation.
- Every new Flutter file is created with `dart format` applied once; every edited existing file is left in its current formatting.

**Shared files (other waves edit these too — design against names, re-read before editing):**
- `lib/features/chat/presentation/screens/chat_screen.dart` — Plan 1a (Task 5 `onRetry` gating, Task 7 `didChangeAppLifecycleState`, Task 8 RouteAware/`_syncViewActive`, Task 9 `_restoreDraft`), Plan 2 (Task 3 `_attachImage`, Task 7 `initState`/`dispose` voice stop, Task 9 `MessageBubble(onCancelSend:)`). Plan 4 runs AFTER this plan and edits `_syncArrivals` (keeps Task 10's unseen-count block), `_send`, `_scrollToLatest`, `_tryEnsureMessageVisible`, the typing `AnimatedSwitcher`, the `MessageBubble(` construction and `MakeRoom`/`SettleIn` keys — so keep those names exactly as written here.
- `lib/features/chat/presentation/state/chat_state.dart` — Plan 1a REPLACES `loadMoreMessages` (pages from `_oldestFetchedCursor`, merges through `reconcileWindow`, deletes `_appendOlderMessages`) and rewrites the realtime handler/outbox; Plan 2 edits `signedMediaUrlProvider`, `_prepareAndAttemptSend`, `_attemptSend`. Task 13 below therefore adds a `limit` parameter to the 1a shape of `loadMoreMessages` instead of rewriting it, and bounds its paging loop with 1a's `_oldestFetchedCursor` / `isOlderThanCursor`.
- `lib/features/chat/data/repositories/chat_repository.dart`, `supabase_chat_repository.dart` — Plan 1a adds `getMessagesByIds(relationshipId, ids)`, `getMessagesChangedSince`, `ensureRealtimeConnected`; Plan 1b removes `isSystemNotice` from `sendTextMessage`; Plan 2 changes `uploadChatMedia`. This plan adds NO repository method: Task 13 looks a jump target up with 1a's `getMessagesByIds`.
- `lib/features/chat/presentation/widgets/message_bubble.dart` — Plan 2 (voice call site passes `mediaKey`, `_MediaBusyOverlay(progress, onCancel)`, `onCancelSend` threading). Plan 4 later adds `onActionsOpened`, `viewerUserId`, `_BubbleBody.onRetry` and edits the streak branch — Task 7's `shell(...)` restructure must keep the `onLongPress:` lambda, the `_BubbleBody(` construction and the streak branch textually intact (moved, not rewritten).
- `test/features/chat/support/chat_test_harness.dart` — Plan 1a adds `getMessagesCalls`, `getMessagesByIdsCalls`, `serverUpdatedAt`, `touch(id)`, typed `emitRealtime([event])` and `seedIncoming` stamps `serverUpdatedAt`; Plan 1b/2 add theirs. Add this plan's seams (`editHistory`, `hiddenFromPages`, `seedIncoming(editedAt/replyToMessageId/quotedText)`), never rename or re-declare an existing one.
- `lib/core/notifications/services/onesignal_service.dart` — Plan 1b REWRITES the class head: `OneSignalService(this._ref, {PushSdk? sdk, String? platform})` with `_sdk`, `_platform`, `attach()`, `beforeSignOut()`; the `addClickListener` / `addForegroundWillDisplayListener` bodies stay. Task 12 adds one more named constructor parameter and one method to that 1b shape — it does not restore the pre-1b constructor.

## Review Focus

1. A 300-character unbroken URL inside a bubble must wrap across lines (no overflow stripes) and still open on tap — pinned in Task 4.
2. A "Go to message" whose target is a deleted (tombstoned) pinned message older than the loaded page must still land on the tombstone row and flash it, not silently return — pinned in Task 13.
3. Opening a chat with more unread than the first page holds (80 unread, page 50) must place the divider above the oldest loaded partner message with the true count, not omit it or point at the wrong row — pinned in Task 10.
4. A paste that lands in the MIDDLE of a long draft and crosses 10,000 code points must keep the caret inside the kept text (no `RangeError`), and the user must be told — pinned in Task 3.
5. The scroll-to-bottom pill must rise with the typing indicator / reply strip / staged-game bar instead of being covered by them — pinned in Task 10 (it reads the same measured overlay height Task 8 produces).

---

## File Structure

**Create**
- `lib/core/ui/layout/measure_size.dart` — `MeasureSize` render-proxy widget reporting its child's laid-out size (post-frame).
- `lib/features/chat/presentation/widgets/rune_length_limiting_formatter.dart` — `RuneLengthLimitingTextInputFormatter` (code-point limit, truncation callback).
- `lib/features/chat/presentation/widgets/linkified_message_text.dart` — `detectLinks`, `LinkifiedMessageText`, `openMessageLink`.
- `lib/features/chat/presentation/widgets/message_status_rule.dart` — `showsDeliveryStatus` (pure rule for which own bubbles carry ticks) and `thumbnailDecodeSize` (pure rule for decode dimensions).
- `lib/features/chat/presentation/widgets/scroll_to_latest_pill.dart` — `ScrollToLatestPill`.
- `lib/features/chat/presentation/widgets/unread_divider.dart` — `UnreadDivider` + `unreadDividerMessageId`.
- Tests: `test/core/ui/layout/measure_size_test.dart`, `test/features/chat/rune_length_limiting_formatter_test.dart`, `test/features/chat/linkified_message_text_test.dart`, `test/features/chat/message_status_rule_test.dart`, `test/features/chat/chat_screen_overlay_clearance_test.dart`, `test/features/chat/chat_screen_list_anchor_test.dart`, `test/features/chat/chat_screen_scroll_to_latest_test.dart`, `test/features/chat/chat_screen_delivery_status_test.dart`, `test/features/chat/chat_screen_jump_convergence_test.dart`, `test/features/chat/chat_screen_draft_limit_test.dart`, `test/features/chat/starred_messages_refresh_test.dart`, `test/features/chat/message_bubble_edited_test.dart`, `test/features/chat/message_bubble_reveal_rebuild_test.dart`, `test/features/chat/message_bubble_thumbnail_decode_test.dart`, `test/core/notifications/onesignal_delivery_ack_test.dart`.

**Modify**
- `lib/features/chat/presentation/screens/chat_screen.dart` — jump pipeline, overlay measurement, list anchoring, pill, divider, status rule, draft guard, edit-history date format.
- `lib/features/chat/presentation/widgets/message_bubble.dart` — edited label, reveal listenable, reveal status icon, link text, decode size, "Copy link".
- `lib/features/chat/presentation/widgets/message_actions_sheet.dart` — optional "Copy link" item.
- `lib/features/chat/presentation/widgets/chat_media_group.dart` — decode size on tiles.
- `lib/features/chat/presentation/widgets/attune_chat_wallpaper.dart` — single lerped gradient, quantised listener.
- `lib/features/chat/presentation/widgets/chat_text_field.dart` — rune formatter + truncation notice.
- `lib/features/chat/presentation/state/chat_state.dart` — `starredMessagesProvider` (autoDispose), invalidation, `loadMoreMessages({limit})` (one-line change to the Plan 1a shape), `ensureMessageLoaded`, `JumpTargetResult`.
- `lib/features/chat/presentation/screens/starred_messages_screen.dart` — use the moved provider; `MyDateFormat`.
- `lib/features/chat/config/chat_config.dart` — `jumpPageSize`.
- `lib/core/notifications/services/onesignal_service.dart` — delivery ack on push receipt (added to the Plan 1b class shape).
- `test/features/chat/support/chat_test_harness.dart` — `seedIncoming(editedAt, replyToMessageId, quotedText)`, `editHistory`, `hiddenFromPages` (`getMessagesCalls` and `getMessagesByIds` already exist after Plan 1a).
- `test/features/chat/chat_screen_message_actions_test.dart` — flip the `findsNothing` on `'edited'` (encoded regression).
- `test/features/chat/message_list_padding_test.dart` — replace the constant-reserve source assertions (encoded the guessed reserve) with the measured-overlay rule.
- `test/features/chat/presentation/widgets/attune_chat_wallpaper_test.dart` — dark mode now paints ONE gradient.

---

### Task 1: "edited" label restored + reachable history sheet (#31)

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (`MessageBubble.build` → `hasVisibleFooter`, the `_MessageMeta(...)` footer call, `_MessageMeta.build` item order)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_showEditHistorySheet` date formatting)
- Modify: `test/features/chat/support/chat_test_harness.dart` (`seedIncoming` gains `editedAt`; `editHistory` map; `getMessageEditHistory` reads it)
- Modify: `test/features/chat/chat_screen_message_actions_test.dart` (the `expect(find.text('edited'), findsNothing)` in "Edit saves the new content through the controller" — this encoded the regression; flip it)
- Test: `test/features/chat/message_bubble_edited_test.dart`

**Interfaces:**
- Consumes: `Message.editedAt`, `Message.isDeleted`, `MessageBubble.onShowEditHistory`, `MyDateFormat.toDate/toTime/join` (`lib/core/utils/date_formatter.dart`).
- Produces: harness `FakeChatRepository.seedIncoming({DateTime? editedAt})`, `FakeChatRepository.editHistory: Map<String, List<MessageEditHistoryEntry>>` used by Task 13's tests too.

- [ ] **Step 1: Extend the harness (test support only)**

In `test/features/chat/support/chat_test_harness.dart`, `seedIncoming`: add parameters `DateTime? editedAt, String? replyToMessageId, String? quotedText` and the row keys:

```dart
      'edited_at': editedAt?.toUtc().toIso8601String(),
      'reply_to_message_id': replyToMessageId,
      'quoted_text': quotedText,
```

(Plan 1a already made `seedIncoming` stamp `serverUpdatedAt[id] = createdAt` before `return message;` — leave that line in place; these parameters are purely additive.)

Add next to `deleteMessageCalls`:

```dart
  /// Prior versions per message id, oldest first — what the edit-history
  /// sheet renders. Empty by default, matching a never-edited message.
  final Map<String, List<MessageEditHistoryEntry>> editHistory = {};
```

and change `getMessageEditHistory` to `async => editHistory[messageId] ?? const [];`.

- [ ] **Step 2: Write the failing widget test**

`test/features/chat/message_bubble_edited_test.dart`:

```dart
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// Spec "Edited label + history view": an edited message carries a small
/// "edited" label after its time, and tapping it opens the history sheet.
/// Regression from f29007b6, where the footer moved outside the bubble and
/// the label was hard-wired off.
void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  testWidgets('an edited partner message shows "edited" in the list', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final now = DateTime.now();
    repo.seedIncoming(
      id: 'm-edited',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'home at 9',
      createdAt: now.subtract(const Duration(minutes: 3)),
      editedAt: now.subtract(const Duration(minutes: 1)),
    );
    // A newer, un-edited message so the edited one is NOT the newest row
    // (the newest row already has a footer for other reasons).
    repo.seedIncoming(
      id: 'm-newest',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'ok',
      createdAt: now,
    );
    final container = await pumpChat(tester, repo);

    expect(find.text('edited'), findsOneWidget);
    await tearDownChat(tester, container);
  });

  testWidgets('tapping "edited" opens the history sheet with prior text', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final now = DateTime.now();
    repo.seedIncoming(
      id: 'm-edited',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'home at 9',
      createdAt: now.subtract(const Duration(minutes: 3)),
      editedAt: now.subtract(const Duration(minutes: 1)),
    );
    repo.editHistory['m-edited'] = [
      MessageEditHistoryEntry(
        previousContent: 'home at 7',
        editedAt: now.subtract(const Duration(minutes: 1)),
      ),
    ];
    final container = await pumpChat(tester, repo);

    await tester.tap(find.text('edited'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Edit history'), findsOneWidget);
    expect(find.text('home at 7'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);

    await tester.tapAt(const Offset(400, 40));
    await tester.pump(const Duration(milliseconds: 400));
    await tearDownChat(tester, container);
  });

  testWidgets('a deleted message never shows "edited"', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final now = DateTime.now();
    repo.seedIncoming(
      id: 'm-gone',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: '',
      createdAt: now.subtract(const Duration(minutes: 3)),
      editedAt: now.subtract(const Duration(minutes: 2)),
      deletedAt: now.subtract(const Duration(minutes: 1)),
    );
    final container = await pumpChat(tester, repo);
    expect(find.text('edited'), findsNothing);
    await tearDownChat(tester, container);
  });
}
```

- [ ] **Step 3: Run it; expect the first two to fail**

Run: `flutter test test/features/chat/message_bubble_edited_test.dart`
Expected: FAIL — `Expected: exactly one matching candidate, Actual: _TextWidgetFinder:<Found 0 widgets with text "edited">` for the first test; the second fails at `tester.tap(find.text('edited'))` ("zero widgets"); the third passes.

- [ ] **Step 4: Render the label**

In `MessageBubble.build` (message_bubble.dart), directly above `final hasVisibleFooter =`:

```dart
    // Spec "Edited label + history view": an edited message always carries
    // its label, whatever else the footer would have shown. Deleted rows
    // are tombstones and never say "edited".
    final isEdited = message.editedAt != null && !message.isDeleted;
```

and make the footer condition:

```dart
    final hasVisibleFooter =
        showLatestTimestamp ||
        (showStatus && isMine) ||
        isEdited ||
        (message.isFailed && (onRetry != null || onRemove != null));
```

In the `footer:` argument, change `showTime: showLatestTimestamp,` to `showTime: showLatestTimestamp || isEdited,` and `showEdited: false,` to `showEdited: isEdited,`.

In `_MessageMeta.build`, move the `if (showEdited && …)` block to AFTER the `if (showTime)` block (spec: the label follows the timestamp) and replace it with:

```dart
      if (showEdited && message.editedAt != null && !message.isDeleted)
        Semantics(
          button: onShowEditHistory != null,
          label: 'Edited. Shows edit history',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                onShowEditHistory == null
                    ? null
                    : () => onShowEditHistory!(message),
            child: Padding(
              // Widens the tap target without moving the glyphs.
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Text(
                'edited',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: onBubbleColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
```

- [ ] **Step 5: Date format in the history sheet**

In `chat_screen.dart` `_showEditHistorySheet`, replace the `subtitle: Text(DateFormat.yMMMd(...).add_jm().format(entry.editedAt))` with:

```dart
                    subtitle: Text(
                      MyDateFormat.join([
                        MyDateFormat.toDate(entry.editedAt),
                        MyDateFormat.toTime(entry.editedAt),
                      ]),
                    ),
```

Add `import 'package:attune/core/utils/date_formatter.dart';` if the file does not already import it (grep `MyDateFormat` in chat_screen.dart first). If `flutter analyze` then reports the `intl` import unused, remove that import line only.

- [ ] **Step 6: Flip the encoded regression**

In `test/features/chat/chat_screen_message_actions_test.dart`, test "Edit saves the new content through the controller": change `expect(find.text('edited'), findsNothing);` to

```dart
    // f29007b6 asserted the label was absent; that WAS the regression.
    expect(find.text('edited'), findsOneWidget);
```

- [ ] **Step 7: Run both tests**

Run: `flutter test test/features/chat/message_bubble_edited_test.dart test/features/chat/chat_screen_message_actions_test.dart`
Expected: all PASS.

- [ ] **Step 8: Checkpoint**

Run this task's tests and `flutter analyze lib/features/chat/presentation/widgets/message_bubble.dart lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/support/chat_test_harness.dart | grep -E '^\s*(error|warning) '`; expect no lines. No commit (the owner commits).

---

### Task 2: Starred screen always current (#34)

**Files:**
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (add `starredMessagesProvider` next to the other top-level providers; `starMessage`/`unstarMessage`)
- Modify: `lib/features/chat/presentation/screens/starred_messages_screen.dart` (remove its local provider; `MyDateFormat`)
- Test: `test/features/chat/starred_messages_refresh_test.dart`

**Interfaces:**
- Produces: `final starredMessagesProvider = FutureProvider.autoDispose<List<Message>>(...)` exported from `chat_state.dart`.

- [ ] **Step 1: Write the failing controller test**

```dart
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// RC-12: starredMessagesProvider was a plain FutureProvider nobody ever
/// invalidated, so Starred showed its first fetch for the whole session.
void main() {
  test('starring and unstarring refresh the Starred list', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm2',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'keep this',
      createdAt: DateTime.now(),
    );
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // A live listener, as the Starred screen's ref.watch would be.
    final sub = container.listen(starredMessagesProvider, (_, __) {});
    addTearDown(sub.close);
    expect(await container.read(starredMessagesProvider.future), isEmpty);

    await controller.starMessage('m2');
    expect(
      (await container.read(starredMessagesProvider.future)).map((m) => m.id),
      ['m2'],
    );

    await controller.unstarMessage('m2');
    expect(await container.read(starredMessagesProvider.future), isEmpty);
  });

  test('the provider is released when nothing watches it', () {
    expect(starredMessagesProvider, isA<AutoDisposeFutureProvider<Object?>>());
  });
}
```

- [ ] **Step 2: Run it; expect failure**

Run: `flutter test test/features/chat/starred_messages_refresh_test.dart`
Expected: FAIL to compile — `Undefined name 'starredMessagesProvider'` (it lives in the screen file today).

- [ ] **Step 3: Move and invalidate**

In `chat_state.dart`, after `conversationsRefreshProvider`:

```dart
/// This user's starred messages, newest-starred first. autoDispose so a
/// reopened Starred screen fetches fresh, and invalidated by
/// ChatController.starMessage/unstarMessage so a screen left open updates.
final starredMessagesProvider = FutureProvider.autoDispose<List<Message>>((
  ref,
) async {
  final repository = ref.watch(chatRepositoryProvider);
  return repository.getStarredMessages();
});
```

In `starMessage` and `unstarMessage`, after the `state = state.copyWith(...)` statement add `ref.invalidate(starredMessagesProvider);`.

In `starred_messages_screen.dart`: delete the local `starredMessagesProvider` definition (the file already imports `chat_state.dart`); replace `DateFormat.yMMMd().add_jm().format(message.createdAt)` with `MyDateFormat.join([MyDateFormat.toDate(message.createdAt), MyDateFormat.toTime(message.createdAt)])`, import `package:attune/core/utils/date_formatter.dart`, drop the now-unused `intl` import.

- [ ] **Step 4: Run; expect pass**

Run: `flutter test test/features/chat/starred_messages_refresh_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Checkpoint**

`flutter analyze lib/features/chat/presentation/state/chat_state.dart lib/features/chat/presentation/screens/starred_messages_screen.dart | grep -E '^\s*(error|warning) '` → nothing. No commit.

---

### Task 3: Over-limit paste never destroys the draft (#35)

**Files:**
- Create: `lib/features/chat/presentation/widgets/rune_length_limiting_formatter.dart`
- Modify: `lib/features/chat/presentation/widgets/chat_text_field.dart` (the composer `TextField(...)` with `key: widget.composerTextKey`)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_send`, `_sendDraftText`; new `_refuseOverLimitDraft`)
- Test: `test/features/chat/rune_length_limiting_formatter_test.dart`, `test/features/chat/chat_screen_draft_limit_test.dart`

**Interfaces:**
- Produces: `class RuneLengthLimitingTextInputFormatter extends TextInputFormatter { RuneLengthLimitingTextInputFormatter(int maxRunes, {VoidCallback? onTruncated}); }`; `_ChatScreenState._refuseOverLimitDraft(String text) → bool` (true = refused and the person was told).
- Consumes: `Message.maxContentRunes`, `Message.isValidContent`, `context.showWarningSnackbar/showErrorSnackbar`.
- Ordering contract with Plan 4 (Task 11 there): the refusal in `_send()` sits ABOVE the send haptic/chirp, so a refused draft never gets "accepted" feedback. Plan 4 verifies this and only adds the missing staged-game chirp.

- [ ] **Step 1: Formatter unit test (failing: file missing)**

```dart
import 'package:attune/features/chat/presentation/widgets/rune_length_limiting_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TextEditingValue apply(
    RuneLengthLimitingTextInputFormatter f,
    String text, {
    int? caret,
  }) => f.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret ?? text.length),
    ),
  );

  test('text within the limit passes through untouched', () {
    final f = RuneLengthLimitingTextInputFormatter(5);
    final v = apply(f, 'abcde');
    expect(v.text, 'abcde');
    expect(v.selection.extentOffset, 5);
  });

  test('counts code points, not UTF-16 units', () {
    var truncated = 0;
    final f = RuneLengthLimitingTextInputFormatter(
      3,
      onTruncated: () => truncated++,
    );
    final v = apply(f, '😀😀😀😀');
    expect(v.text, '😀😀😀');
    expect(v.text.runes.length, 3);
    expect(truncated, 1);
  });

  test('a mid-text paste keeps the caret inside the kept text', () {
    final f = RuneLengthLimitingTextInputFormatter(4);
    // Caret reported past the cut.
    final v = apply(f, 'abcdefgh', caret: 7);
    expect(v.text, 'abcd');
    expect(v.selection.extentOffset, 4);
    expect(v.composing, TextRange.empty);
  });
}
```

Run: `flutter test test/features/chat/rune_length_limiting_formatter_test.dart` → Expected: FAIL, `Target of URI doesn't exist`.

- [ ] **Step 2: Implement the formatter (new file, formatted)**

```dart
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Caps a field at [maxRunes] Unicode code points — the unit the server's
/// `char_length(content) <= 10000` CHECK counts. Flutter's
/// LengthLimitingTextInputFormatter counts grapheme clusters, which can
/// exceed the code-point budget (a flag emoji is 1 grapheme, 2 code points),
/// so a draft it accepted could still be refused server-side.
///
/// On truncation the FIRST [maxRunes] code points are kept and
/// [onTruncated] fires once, so the composer can tell the person.
class RuneLengthLimitingTextInputFormatter extends TextInputFormatter {
  RuneLengthLimitingTextInputFormatter(this.maxRunes, {this.onTruncated})
    : assert(maxRunes > 0);

  final int maxRunes;
  final VoidCallback? onTruncated;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final runes = newValue.text.runes;
    if (runes.length <= maxRunes) return newValue;

    // fromCharCodes over whole code points never splits a surrogate pair.
    final kept = String.fromCharCodes(runes.take(maxRunes));
    onTruncated?.call();
    final caret = math.min(newValue.selection.extentOffset, kept.length);
    return TextEditingValue(
      text: kept,
      selection: TextSelection.collapsed(offset: math.max(caret, 0)),
      composing: TextRange.empty,
    );
  }
}
```

Run the unit test → Expected: PASS (3 tests).

- [ ] **Step 3: Screen test (failing: the draft is destroyed today)**

`test/features/chat/chat_screen_draft_limit_test.dart`:

```dart
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// RC-16: _sendDraftText cleared the composer BEFORE sendMessage silently
/// refused an over-limit draft, so 10,001 characters vanished with no word.
void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  testWidgets('typing/pasting past the limit trims and says so', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hi',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    final field = find.byType(TextField).first;
    await tester.enterText(field, 'x' * (Message.maxContentRunes + 1));
    await tester.pump(const Duration(milliseconds: 300));

    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text.runes.length, Message.maxContentRunes);
    expect(
      find.textContaining('10,000 characters'),
      findsOneWidget,
      reason: 'the person must be told their text was trimmed',
    );
    await tester.pump(const Duration(seconds: 5));
    await tearDownChat(tester, container);
  });

  testWidgets('an over-limit draft set programmatically is kept, not sent', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hi',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    // _appendToComposer / the translator set controller.value directly,
    // bypassing input formatters — the send path must still refuse safely.
    final field = find.byType(TextField).first;
    final controller = tester.widget<TextField>(field).controller!;
    final tooLong = 'y' * (Message.maxContentRunes + 1);
    controller.value = TextEditingValue(
      text: tooLong,
      selection: TextSelection.collapsed(offset: tooLong.length),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.sendCallCount, 0);
    expect(controller.text, tooLong, reason: 'the draft must survive');
    expect(find.textContaining('10,000 characters'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tearDownChat(tester, container);
  });
}
```

Run: `flutter test test/features/chat/chat_screen_draft_limit_test.dart`
Expected: FAIL — test 1: `controller.text.runes.length` is 10001; test 2: `controller.text` is `''` (cleared) and `sendCallCount` 0 with no snackbar.

- [ ] **Step 4: Wire the formatter into the composer**

In `chat_text_field.dart`, import `rune_length_limiting_formatter.dart` and `package:attune/features/chat/domain/entities/message.dart` (check first whether `Message` is already imported). In `_ChatTextFieldState` add:

```dart
  /// Last time the "trimmed" notice showed; one notice per paste, not one
  /// per formatter pass.
  DateTime? _truncationNoticeAt;

  void _onDraftTruncated() {
    final now = DateTime.now();
    final last = _truncationNoticeAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _truncationNoticeAt = now;
    if (!mounted) return;
    context.showWarningSnackbar(
      'Messages can be up to 10,000 characters — we kept the first 10,000.',
    );
  }
```

On the composer `TextField(key: widget.composerTextKey, ...)` add:

```dart
                            inputFormatters: [
                              RuneLengthLimitingTextInputFormatter(
                                Message.maxContentRunes,
                                onTruncated: _onDraftTruncated,
                              ),
                            ],
```

(`showWarningSnackbar` comes from `lib/core/widgets/feedback/export_extensions.dart`; chat_text_field.dart already imports the export barrel that exposes it — verify with grep `showErrorSnackbar` in that file; if absent, import `package:attune/core/widgets/feedback/export_extensions.dart`.)

- [ ] **Step 5: Guard the send path**

In `chat_screen.dart` add to `_ChatScreenState` (next to `_sendDraftText`):

```dart
  /// RC-16: sendMessage silently drops an over-limit draft, and the
  /// composer used to be cleared first — so 10,001 characters vanished
  /// without a word. True when [text] was refused (and the person told).
  bool _refuseOverLimitDraft(String text) {
    if (Message.isValidContent(text)) return false;
    context.showErrorSnackbar(
      'That message is too long — the limit is 10,000 characters. '
      'Trim it a little and try again.',
    );
    return true;
  }
```

In `_send()`, right after `if (text.isEmpty) return;` and BEFORE `ref.read(hapticsProvider).light();` (the chirp and haptic mean "accepted" — Plan 4 Task 11 relies on this order):

```dart
    if (_refuseOverLimitDraft(text)) return;
```

In `_sendDraftText`, right after `if (trimmed.isEmpty) return;` (the translator rewrite, the staged-game caption and the Pulse/assist paths call `_sendDraftText` directly, bypassing `_send`):

```dart
    if (_refuseOverLimitDraft(trimmed)) return;
```

- [ ] **Step 6: Run; expect pass**

Run: `flutter test test/features/chat/chat_screen_draft_limit_test.dart test/features/chat/chat_text_field_test.dart test/features/chat/composer_layout_test.dart`
Expected: all PASS (the two existing composer suites must stay green).

- [ ] **Step 7: Checkpoint**

`flutter analyze lib/features/chat/presentation/widgets/rune_length_limiting_formatter.dart lib/features/chat/presentation/widgets/chat_text_field.dart lib/features/chat/presentation/screens/chat_screen.dart | grep -E '^\s*(error|warning) '` → nothing. No commit.

---

### Task 4: Tappable links with safe launching and long-press copy (#37)

**Ruling on dependencies:** `url_launcher ^6.3.1` is already a direct dependency (`pubspec.yaml`); `flutter_linkify` is not and is not added — a 40-line regex linkifier covers http/https/www links, which is all the review asked for. Bare domains (`example.com`) are deliberately NOT linked (false positives on "e.g." and file names); phone/email detection is out of scope for this wave.

**Ruling on long-press:** `TextSpan` accepts one recognizer. Putting a `LongPressGestureRecognizer` on the span would win the arena against the bubble's own long-press and break the message menu on any link. So: tap on the link opens it; long-press anywhere on the bubble opens the usual focused menu, which gains a **"Copy link"** item when the message contains links (copies the first link; "Copy" still copies the whole text). This is the reviewer's "keep long-press routing to the focused menu".

**Files:**
- Create: `lib/features/chat/presentation/widgets/linkified_message_text.dart`
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (`_BubbleBody` text block; `MessageBubble` gains `onCopyLink`; the `buildMessageActionItems(...)` call passes it)
- Modify: `lib/features/chat/presentation/widgets/message_actions_sheet.dart` (`buildMessageActionItems` gains `VoidCallback? onCopyLink`)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (list passes `onCopyLink`)
- Test: `test/features/chat/linkified_message_text_test.dart`

**Interfaces:**
- Produces:
  - `class DetectedLink { final int start; final int end; final String text; final Uri uri; }`
  - `List<DetectedLink> detectLinks(String text)`
  - `typedef LinkLauncher = Future<bool> Function(Uri uri, {LaunchMode mode});`
  - `Future<void> openMessageLink(BuildContext context, Uri uri, {LinkLauncher? launcher})` — only `http`/`https`; snackbar on failure.
  - `class LinkifiedMessageText extends StatefulWidget { const LinkifiedMessageText({required String text, required TextStyle? style, required Color linkColor, void Function(Uri)? onOpenLink}); }`
  - `MessageBubble.onCopyLink: VoidCallback?`; `buildMessageActionItems(onCopyLink: VoidCallback?)`.

- [ ] **Step 1: Failing tests**

```dart
import 'package:attune/features/chat/presentation/widgets/linkified_message_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  group('detectLinks', () {
    test('finds http, https and www links and strips trailing punctuation', () {
      final links = detectLinks(
        'see https://maps.app.goo.gl/abc, or http://x.io/p?q=1). '
        'also www.example.com/path!',
      );
      expect(links.map((l) => l.text), [
        'https://maps.app.goo.gl/abc',
        'http://x.io/p?q=1',
        'www.example.com/path',
      ]);
      expect(links[2].uri.toString(), 'https://www.example.com/path');
      expect(links[0].start, 4);
    });

    test('ignores bare domains and non-web schemes', () {
      expect(detectLinks('e.g. example.com or file.txt'), isEmpty);
      expect(detectLinks('javascript:alert(1) ftp://host/x'), isEmpty);
    });
  });

  group('openMessageLink', () {
    testWidgets('launches http(s) externally and refuses other schemes', (
      tester,
    ) async {
      final launched = <Uri>[];
      Future<bool> fakeLauncher(Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
        expect(mode, LaunchMode.externalApplication);
        launched.add(uri);
        return true;
      }

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await openMessageLink(
        ctx,
        Uri.parse('https://example.com/a'),
        launcher: fakeLauncher,
      );
      await openMessageLink(
        ctx,
        Uri.parse('javascript:alert(1)'),
        launcher: fakeLauncher,
      );
      await openMessageLink(
        ctx,
        Uri.parse('tel:+233240000000'),
        launcher: fakeLauncher,
      );
      expect(launched.map((u) => u.toString()), ['https://example.com/a']);
    });

    testWidgets('a launcher that returns false shows a warm error', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await openMessageLink(
        ctx,
        Uri.parse('https://example.com/a'),
        launcher: (uri, {LaunchMode mode = LaunchMode.platformDefault}) async => false,
      );
      await tester.pump();
      expect(find.text("Couldn't open that link."), findsOneWidget);
    });
  });

  group('LinkifiedMessageText', () {
    testWidgets('renders links as tappable spans and wraps a long URL', (
      tester,
    ) async {
      final opened = <Uri>[];
      final longUrl = 'https://example.com/${'a' * 300}';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: LinkifiedMessageText(
                text: 'look $longUrl now',
                style: const TextStyle(fontSize: 16),
                linkColor: Colors.blue,
                onOpenLink: opened.add,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'no overflow');

      final rich = tester.widget<Text>(find.byType(Text));
      final root = rich.textSpan! as TextSpan;
      final linkSpans = <TextSpan>[];
      root.visitChildren((span) {
        if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
          linkSpans.add(span);
        }
        return true;
      });
      expect(linkSpans, hasLength(1));
      expect(linkSpans.single.style?.decoration, TextDecoration.underline);
      (linkSpans.single.recognizer! as TapGestureRecognizer).onTap!();
      expect(opened.single.toString(), longUrl);

      final size = tester.getSize(find.byType(Text));
      expect(size.height, greaterThan(40), reason: 'the URL wrapped');
    });

    testWidgets('plain text has no recognizers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkifiedMessageText(
              text: 'no links here',
              style: TextStyle(fontSize: 16),
              linkColor: Colors.blue,
            ),
          ),
        ),
      );
      final rich = tester.widget<Text>(find.byType(Text));
      final root = rich.textSpan! as TextSpan;
      var recognizers = 0;
      root.visitChildren((span) {
        if (span is TextSpan && span.recognizer != null) recognizers++;
        return true;
      });
      expect(recognizers, 0);
    });
  });
}
```

Run: `flutter test test/features/chat/linkified_message_text_test.dart` → Expected: FAIL, `Target of URI doesn't exist`.

- [ ] **Step 2: Implement (new file, formatted)**

```dart
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// One web link found inside a message body.
class DetectedLink {
  const DetectedLink({
    required this.start,
    required this.end,
    required this.text,
    required this.uri,
  });

  /// Code-unit range in the source string, [start, end).
  final int start;
  final int end;

  /// Exactly what the person typed (shown as the link text).
  final String text;

  /// What gets launched: http/https only; `www.` is given `https://`.
  final Uri uri;
}

/// http://, https:// and www. links. Bare domains are NOT linked (too many
/// false positives: "e.g.", "file.txt"), nor are other schemes — the only
/// thing a tap can ever launch here is a web URL.
final RegExp _linkPattern = RegExp(
  r'(?:https?:\/\/|www\.)[^\s<>()\[\]{}"' "'" r']+',
  caseSensitive: false,
);

const String _trailingPunctuation = '.,;:!?';

List<DetectedLink> detectLinks(String text) {
  final links = <DetectedLink>[];
  for (final match in _linkPattern.allMatches(text)) {
    var end = match.end;
    while (end > match.start &&
        _trailingPunctuation.contains(text[end - 1])) {
      end--;
    }
    final raw = text.substring(match.start, end);
    final withScheme =
        raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw;
    final uri = Uri.tryParse(withScheme);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      continue;
    }
    if (uri.host.isEmpty) continue;
    links.add(
      DetectedLink(start: match.start, end: end, text: raw, uri: uri),
    );
  }
  return links;
}

typedef LinkLauncher = Future<bool> Function(Uri uri, {LaunchMode mode});

Future<bool> _defaultLauncher(
  Uri uri, {
  LaunchMode mode = LaunchMode.platformDefault,
}) => launchUrl(uri, mode: mode);

/// Opens a web link in the external browser. Refuses anything that is not
/// http/https (nothing a message can contain should ever reach `tel:`,
/// `javascript:` or an app scheme through this path). canLaunchUrl is
/// skipped on purpose: it is unreliable on Android 11+ without <queries>,
/// and launchUrl's own false/throw is the honest signal.
Future<void> openMessageLink(
  BuildContext context,
  Uri uri, {
  LinkLauncher? launcher,
}) async {
  if (!(uri.scheme == 'http' || uri.scheme == 'https')) return;
  final launch = launcher ?? _defaultLauncher;
  var ok = false;
  try {
    ok = await launch(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    context.showErrorSnackbar("Couldn't open that link.");
  }
}

/// Message text with web links underlined and tappable. Recognizers are
/// owned here and disposed with the State, so a recycled list row never
/// leaks them.
class LinkifiedMessageText extends StatefulWidget {
  const LinkifiedMessageText({
    super.key,
    required this.text,
    required this.style,
    required this.linkColor,
    this.onOpenLink,
  });

  final String text;
  final TextStyle? style;
  final Color linkColor;

  /// Defaults to [openMessageLink] when null.
  final void Function(Uri uri)? onOpenLink;

  @override
  State<LinkifiedMessageText> createState() => _LinkifiedMessageTextState();
}

class _LinkifiedMessageTextState extends State<LinkifiedMessageText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final links = detectLinks(widget.text);
    if (links.isEmpty) {
      return Text.rich(TextSpan(text: widget.text), style: widget.style);
    }

    final linkStyle = (widget.style ?? const TextStyle()).copyWith(
      color: widget.linkColor,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
    );
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final link in links) {
      if (link.start > cursor) {
        children.add(TextSpan(text: widget.text.substring(cursor, link.start)));
      }
      final recognizer =
          TapGestureRecognizer()
            ..onTap = () {
              final open = widget.onOpenLink;
              if (open != null) {
                open(link.uri);
              } else {
                openMessageLink(context, link.uri);
              }
            };
      _recognizers.add(recognizer);
      children.add(
        TextSpan(
          text: link.text,
          style: linkStyle,
          recognizer: recognizer,
          semanticsLabel: 'Link: ${link.text}',
        ),
      );
      cursor = link.end;
    }
    if (cursor < widget.text.length) {
      children.add(TextSpan(text: widget.text.substring(cursor)));
    }
    return Text.rich(TextSpan(children: children), style: widget.style);
  }
}
```

Run the unit test → Expected: PASS (6 tests).

- [ ] **Step 3: Use it in the bubble + "Copy link"**

In `message_bubble.dart` `_BubbleBody.build`, replace the `children.add(Text(message.content, style: ...))` block with:

```dart
      children.add(
        LinkifiedMessageText(
          text: message.content,
          // Was an unstyled Text (no fontSize at all), which fell back to
          // Flutter's raw default rather than this app's own type scale —
          // bodyLarge (17px) matches how WhatsApp/iMessage actually size
          // message text; bodyMedium (14px, AppTextTheme's paragraph
          // default) reads small for a chat bubble specifically.
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
          linkColor: color,
        ),
      );
```

(The link keeps the bubble's text colour and is underlined — legible on both the sender gradient and the receiver surface, which a fixed blue is not.) Import `linkified_message_text.dart`.

Add to `MessageBubble`: `this.onCopyLink,` in the constructor and `final VoidCallback? onCopyLink;` with doc "Copies the first web link in the message; null when the text has none." Pass `onCopyLink: onCopyLink,` in the `buildMessageActionItems(` call.

In `message_actions_sheet.dart` `buildMessageActionItems`: add parameter `VoidCallback? onCopyLink,` and, right after the `Copy` item:

```dart
    if (onCopyLink != null)
      item(
        leading: const Icon(Icons.link_rounded),
        title: 'Copy link',
        onSelected: onCopyLink,
      ),
```

In `chat_screen.dart` list `MessageBubble(...)` add:

```dart
                          onCopyLink: () {
                            final links = detectLinks(message.content);
                            if (links.isEmpty) return;
                            Clipboard.setData(
                              ClipboardData(text: links.first.uri.toString()),
                            );
                            context.showSuccessSnackbar('Link copied');
                          },
```

but only when there is a link — build it as a local before the widget: `final firstLink = detectLinks(message.content).isEmpty ? null : ...` and pass `onCopyLink: firstLink == null ? null : () {...}` (import `linkified_message_text.dart`).

- [ ] **Step 4: Actions-sheet test**

Append to `test/features/chat/presentation/widgets/message_actions_sheet_test.dart` (read its existing helper first and reuse it) a case: with `onCopyLink: () {}` the item list contains text `'Copy link'`; with `onCopyLink: null` it does not.

Run: `flutter test test/features/chat/linkified_message_text_test.dart test/features/chat/presentation/widgets/message_actions_sheet_test.dart test/features/chat/message_bubble_test.dart test/features/chat/chat_screen_message_actions_test.dart` → Expected: PASS.

- [ ] **Step 5: Checkpoint**

`flutter analyze lib/features/chat/presentation/widgets/linkified_message_text.dart lib/features/chat/presentation/widgets/message_bubble.dart lib/features/chat/presentation/widgets/message_actions_sheet.dart lib/features/chat/presentation/screens/chat_screen.dart | grep -E '^\s*(error|warning) '` → nothing. No commit.

---

### Task 5: Thumbnails decode at display size (#38a)

**Files:**
- Create: `lib/features/chat/presentation/widgets/message_status_rule.dart` (holds `thumbnailDecodeSize`; Task 11 adds `showsDeliveryStatus` to the same file)
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (`_BubbleBody` image branch: `Image(FileImage)` and `CachedNetworkImage`)
- Modify: `lib/features/chat/presentation/widgets/chat_media_group.dart` (`_MediaPoster.build`)
- Test: `test/features/chat/message_status_rule_test.dart` (decode-size cases), `test/features/chat/message_bubble_thumbnail_decode_test.dart`

**Interfaces:**
- Produces: `({int? width, int? height}) thumbnailDecodeSize({required int displayPx, int? mediaWidth, int? mediaHeight})` — constrains the SHORTER side (portrait/unknown → width; landscape → height) so `BoxFit.cover` never upscales a soft decode.
- Rule: never set `maxWidthDiskCache`/`maxHeightDiskCache` — the full-screen viewer shares `cacheKey: mediaKey` and must keep the original file.

- [ ] **Step 1: Failing tests**

`test/features/chat/message_status_rule_test.dart` (group 'thumbnailDecodeSize'):

```dart
import 'package:attune/features/chat/presentation/widgets/message_status_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('thumbnailDecodeSize', () {
    test('portrait constrains width (the shorter side)', () {
      final s = thumbnailDecodeSize(displayPx: 660, mediaWidth: 1200, mediaHeight: 1600);
      expect(s.width, 660);
      expect(s.height, isNull);
    });
    test('landscape constrains height', () {
      final s = thumbnailDecodeSize(displayPx: 660, mediaWidth: 1600, mediaHeight: 1200);
      expect(s.width, isNull);
      expect(s.height, 660);
    });
    test('unknown dimensions constrain width', () {
      final s = thumbnailDecodeSize(displayPx: 660);
      expect(s.width, 660);
      expect(s.height, isNull);
    });
  });
}
```

`test/features/chat/message_bubble_thumbnail_decode_test.dart`:

```dart
import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// 05 M-4: a 220px tile decoded the full 1600px bitmap (~7 MB each).
void main() {
  testWidgets('a local image thumbnail decodes at display size', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('attune_thumb');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/p.jpg')..writeAsBytesSync(const [0, 1, 2]);

    final message = Message(
      id: 'm1',
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      content: '',
      createdAt: DateTime(2026, 7, 1),
      status: MessageStatus.sending,
      isMine: true,
      mediaType: 'image',
      localMediaPath: file.path,
      mediaWidth: 1200,
      mediaHeight: 1600,
    );
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(home: Scaffold(body: MessageBubble(message: message))),
      ),
    );
    await tester.pump();
    // The 3-byte "jpeg" fails to decode — expected; only the provider matters.
    tester.takeException();

    final image = tester.widget<Image>(find.byType(Image).first);
    final provider = image.image;
    expect(provider, isA<ResizeImage>());
    final dpr = tester.view.devicePixelRatio;
    expect((provider as ResizeImage).width, (220 * dpr).round());
    expect(provider.height, isNull);
  });
}
```

Run: `flutter test test/features/chat/message_status_rule_test.dart test/features/chat/message_bubble_thumbnail_decode_test.dart`
Expected: first FAILs with `Target of URI doesn't exist`; second FAILs with `Expected: <Instance of 'ResizeImage'> Actual: FileImage(...)`.

- [ ] **Step 2: Implement**

`lib/features/chat/presentation/widgets/message_status_rule.dart` (new, formatted):

```dart
import 'package:attune/features/chat/domain/entities/message.dart';

/// Decode dimensions for a thumbnail painted with BoxFit.cover inside a
/// square of [displayPx] physical pixels. Only the shorter side is
/// constrained so the decode never comes out smaller than the box: a
/// portrait photo is width-bound, a landscape one height-bound, and an
/// unknown shape is treated as portrait (phone photos mostly are).
({int? width, int? height}) thumbnailDecodeSize({
  required int displayPx,
  int? mediaWidth,
  int? mediaHeight,
}) {
  final landscape =
      mediaWidth != null && mediaHeight != null && mediaWidth > mediaHeight;
  return landscape
      ? (width: null, height: displayPx)
      : (width: displayPx, height: null);
}

/// Which own bubbles carry a delivery tick (Task 11 fills this in).
bool showsDeliveryStatus({
  required bool isMine,
  required bool isNewestOwn,
  required bool isGroupEnd,
  required MessageStatus status,
}) {
  if (!isMine) return false;
  return isNewestOwn ||
      isGroupEnd ||
      status == MessageStatus.queued ||
      status == MessageStatus.sending ||
      status == MessageStatus.failed;
}
```

In `message_bubble.dart` `_BubbleBody.build`, before `final thumbnail = ClipRRect(`:

```dart
      final decode = thumbnailDecodeSize(
        displayPx: (220 * MediaQuery.devicePixelRatioOf(context)).round(),
        mediaWidth: message.mediaWidth,
        mediaHeight: message.mediaHeight,
      );
```

Local branch: `image: ResizeImage(FileImage(File(localImagePath)), width: decode.width, height: decode.height),`. Network branch: add `memCacheWidth: decode.width, memCacheHeight: decode.height,` to the `CachedNetworkImage(` (NOT `maxWidthDiskCache`: the viewer shares the disk entry). Import `message_status_rule.dart`.

In `chat_media_group.dart` `_MediaPoster.build`, wrap the returned widget in a `LayoutBuilder` and compute `final displayPx = (constraints.biggest.shortestSide.clamp(1.0, 600.0) * MediaQuery.devicePixelRatioOf(context)).round();` then `final decode = thumbnailDecodeSize(displayPx: displayPx, mediaWidth: message.mediaWidth, mediaHeight: message.mediaHeight);`; the local branch becomes `Image(image: ResizeImage(FileImage(File(localPath)), width: decode.width, height: decode.height), fit: BoxFit.cover, errorBuilder: ...)` and the `CachedNetworkImage` gets `memCacheWidth: decode.width, memCacheHeight: decode.height`. (If `constraints.biggest.shortestSide` is infinite, `clamp` gives 600 — a safe ceiling.)

- [ ] **Step 3: Run; expect pass**

Run: `flutter test test/features/chat/message_status_rule_test.dart test/features/chat/message_bubble_thumbnail_decode_test.dart test/features/chat/chat_media_group_test.dart test/features/chat/message_bubble_test.dart`
Expected: PASS.

- [ ] **Step 4: Checkpoint**

`flutter analyze lib/features/chat/presentation/widgets/message_status_rule.dart lib/features/chat/presentation/widgets/message_bubble.dart lib/features/chat/presentation/widgets/chat_media_group.dart | grep -E '^\s*(error|warning) '` → nothing. No commit.

---

### Task 6: Wallpaper gradient without a per-frame saveLayer (#38b)

**Files:**
- Modify: `lib/features/chat/presentation/widgets/attune_chat_wallpaper.dart`
- Modify: `test/features/chat/presentation/widgets/attune_chat_wallpaper_test.dart` (the dark-mode test asserted TWO gradients — that was the layered-`Opacity` design; it now asserts one composite gradient)

**Interfaces:**
- Produces: `AttuneChatWallpaper` is a `StatefulWidget`; the dark layer is one `DecoratedBox` whose stop colours are `[lerp(bg, accent, p), lerp(bg, accent, 0.2), lerp(accent, bg, p)]`. This is EXACT, not an approximation: both old gradients were piecewise-linear on stops [0, 0.5, 1] and an alpha blend of two such gradients is piecewise-linear on the same stops; at t=0 the base is `bg`, the overlay `accent` → `lerp(bg, accent, p)`; at t=0.5 both are `lerp(bg, accent, 0.2)`; at t=1 base `accent`, overlay `bg` → `lerp(accent, bg, p)`.
- Progress is quantised to 1/64 and only triggers `setState` when it changes; once it hits 1 (620 px) scrolling costs one compare per tick.

- [ ] **Step 1: Update + add tests (failing)**

In the dark-mode test replace `expect(canvas, hasLength(2));` and the two colour asserts with:

```dart
    expect(canvas, hasLength(1), reason: 'one composite gradient, no Opacity');
    expect(canvas.single.colors.first, ChatColorScheme.dark.background);
    expect(
      canvas.single.colors.last,
      Color.lerp(
        ChatColorScheme.dark.background,
        ChatColorScheme.dark.backgroundAccent,
        0.28,
      ),
    );
    expect(
      find.descendant(of: wallpaperWidget, matching: find.byType(Opacity)),
      findsNothing,
      reason: 'a full-screen Opacity forces a saveLayer every frame',
    );
```

Append a new test:

```dart
  testWidgets('dark gradient follows scroll, saturates at 620px and stops rebuilding', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [ChatColorScheme.dark],
        ),
        home: Scaffold(
          body: AttuneChatWallpaper(
            scrollController: controller,
            child: ListView(
              controller: controller,
              children: const [SizedBox(height: 20000)],
            ),
          ),
        ),
      ),
    );
    LinearGradient gradient() =>
        tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(AttuneChatWallpaper),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((w) => w.decoration)
            .whereType<BoxDecoration>()
            .map((d) => d.gradient)
            .whereType<LinearGradient>()
            .single;

    final bg = ChatColorScheme.dark.background;
    final accent = Color.lerp(bg, ChatColorScheme.dark.backgroundAccent, 0.28)!;
    expect(gradient().colors.first, bg);

    controller.jumpTo(5000);
    await tester.pump();
    expect(gradient().colors.first, accent, reason: 'saturated: topLeft is accent');
    expect(gradient().colors.last, bg);

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    controller.jumpTo(6000);
    await tester.pump();
    expect(
      rebuilt.whereType<AttuneChatWallpaper>(),
      isEmpty,
      reason: 'past saturation a scroll tick must not rebuild the wallpaper',
    );
    // Scoped to the wallpaper: MaterialApp/Scaffold use AnimatedBuilders of
    // their own, so an unscoped finder would fail for unrelated reasons.
    expect(
      find.descendant(
        of: find.byType(AttuneChatWallpaper),
        matching: find.byType(AnimatedBuilder),
      ),
      findsNothing,
    );
  });
```

Run: `flutter test test/features/chat/presentation/widgets/attune_chat_wallpaper_test.dart` → Expected: FAIL on `hasLength(1)` (actual 2) and on the new test (the `AnimatedBuilder` rebuilds; `colors.first` stays `bg` because the first layer never changes).

- [ ] **Step 2: Rewrite the gradient path**

Replace the class header and `build` of `AttuneChatWallpaper` with a `StatefulWidget`:

```dart
class AttuneChatWallpaper extends StatefulWidget {
  const AttuneChatWallpaper({
    super.key,
    required this.child,
    this.scrollController,
  });

  static const _assetPath =
      'assets/images/attune_chat_wallpaper_tile_refined.png';
  static const _showDarkGradient = true;
  // Restore the background accent independently of the pattern tint/glow.
  static const _showPatternGlow = false;

  final Widget child;
  final ScrollController? scrollController;

  @override
  State<AttuneChatWallpaper> createState() => _AttuneChatWallpaperState();
}

class _AttuneChatWallpaperState extends State<AttuneChatWallpaper> {
  /// Quantised progress (1/64 steps). Rebuilding on every pixel of scroll
  /// repainted the whole screen for changes nobody can see.
  double _progress = 0;
  static const _steps = 64;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant AttuneChatWallpaper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) return;
    final raw = _scrollGradientProgress(controller);
    final quantised = (raw * _steps).round() / _steps;
    if (quantised == _progress) return;
    setState(() => _progress = quantised);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final usesScroll =
        widget.scrollController != null &&
        isDark &&
        AttuneChatWallpaper._showDarkGradient;
    return _buildWallpaper(context, usesScroll ? _progress : 0);
  }

  Widget _buildWallpaper(BuildContext context, double scrollProgress) {
    // ... the existing body of the old _buildWallpaper, with ONE change:
    // the `if (isDark) ...[ two _WallpaperGradientLayer ]` becomes
    //
    //   if (isDark)
    //     _WallpaperGradientLayer(
    //       background: chatColors.background,
    //       accent: backgroundAccent,
    //       progress: scrollProgress,
    //     )
    //   else ...
    //
    // and every `AttuneChatWallpaper._assetPath` / `_showPatternGlow`
    // reference uses the widget-class static.
  }

  double _scrollGradientProgress(ScrollController controller) {
    if (!controller.hasClients) return 0;
    const range = 620.0;
    final raw = (controller.offset / range).clamp(0.0, 1.0);
    return Curves.easeInOutCubic.transform(raw);
  }
}
```

Replace `_WallpaperGradientLayer` with:

```dart
/// The two former layers (a fixed topLeft→bottomRight gradient under a
/// bottomRight→topLeft one faded in by scroll) composited exactly into a
/// single gradient — no Opacity, no saveLayer. Both ran on stops
/// [0, 0.5, 1], so their alpha blend is piecewise-linear on the same stops:
/// t=0 → lerp(bg, accent, p); t=0.5 → the shared mid colour;
/// t=1 → lerp(accent, bg, p).
class _WallpaperGradientLayer extends StatelessWidget {
  const _WallpaperGradientLayer({
    required this.background,
    required this.accent,
    required this.progress,
  });

  final Color background;
  final Color accent;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final mid = Color.lerp(background, accent, 0.2)!;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(background, accent, progress)!,
                mid,
                Color.lerp(accent, background, progress)!,
              ],
              stops: const [0, 0.5, 1],
            ),
          ),
        ),
      ),
    );
  }
}
```

Keep `_WallpaperTile` unchanged. `topLeftAccentOpacity`/`bottomRightAccentOpacity` are still used by the (disabled) glow branches — leave them.

- [ ] **Step 3: Run; expect pass**

Run: `flutter test test/features/chat/presentation/widgets/attune_chat_wallpaper_test.dart test/features/chat/chat_wallpaper_extent_test.dart test/features/chat/chat_screen_header_test.dart`
Expected: PASS.

- [ ] **Step 4: Checkpoint**

`flutter analyze lib/features/chat/presentation/widgets/attune_chat_wallpaper.dart | grep -E '^\s*(error|warning) '` → nothing. No commit.

---

### Task 7: Timestamp-reveal drag no longer rebuilds bubble content (#38c)

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (`MessageBubble` gains `timestampRevealListenable`; `build` hoists content/footer and wraps only the shell in a `ValueListenableBuilder`)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_MessageListState.build`: drop the outer `ValueListenableBuilder<double>` around `MessageBubble`, pass the listenable)
- Test: `test/features/chat/message_bubble_reveal_rebuild_test.dart`

**Interfaces:**
- Produces: `MessageBubble.timestampRevealListenable: ValueListenable<double>?` — when non-null it supersedes `timestampRevealOffset`.
- Mechanism: the `content` Column, `footer`, reaction/star adornments are built ONCE per `MessageBubble.build`; the `ValueListenableBuilder` builder re-creates only `UniversalBubble` (its `dragOffsetOverride`) and the reveal column. Because the `content` instance is identical, `Element.updateChild` short-circuits and `_BubbleBody`/`CachedNetworkImage`/`VoiceMessagePlayer` never rebuild on a drag tick. The dragged row's `UniversalBubble` still translates itself through `dragOffsetOverride` exactly as today (no double translation).

- [ ] **Step 1: Failing test**

```dart
import 'package:attune/core/widgets/universal_bubble.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/linkified_message_text.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// 05 M-6: every drag delta rebuilt the whole bubble subtree of every
/// visible row. The offset now reaches the bubble as a ValueListenable and
/// only the shell (UniversalBubble + reveal column) rebuilds.
void main() {
  Message partner(String content) => Message(
    id: 'm-$content',
    clientMessageId: 'c-$content',
    relationshipId: 'r1',
    senderId: 'partner',
    content: content,
    createdAt: DateTime(2026, 7, 1, 15, 5),
    status: MessageStatus.delivered,
    isMine: false,
  );

  testWidgets('reveal ticks move the shell but do not rebuild content', (
    tester,
  ) async {
    final reveal = ValueNotifier<double>(0);
    addTearDown(reveal.dispose);
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MessageBubble(
                  message: partner('hello'),
                  timestampRevealListenable: reveal,
                ),
                MessageBubble(
                  message: partner('there'),
                  timestampRevealListenable: reveal,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    reveal.value = 30;
    await tester.pump();
    reveal.value = 45;
    await tester.pump();

    // Task 4 turned the body text into LinkifiedMessageText (a Text.rich,
    // so `Text.data` is null) — assert on the body widget itself.
    expect(
      rebuilt.whereType<LinkifiedMessageText>(),
      isEmpty,
      reason: 'message content must not rebuild per drag delta',
    );
    expect(
      rebuilt.whereType<Text>().where(
        (t) =>
            (t.data ?? t.textSpan?.toPlainText()) == 'hello' ||
            (t.data ?? t.textSpan?.toPlainText()) == 'there',
      ),
      isEmpty,
    );
    expect(rebuilt.whereType<MessageBubble>(), isEmpty);
    expect(rebuilt.whereType<UniversalBubble>(), isNotEmpty);
    for (final bubble in tester.widgetList<UniversalBubble>(
      find.byType(UniversalBubble),
    )) {
      expect(bubble.dragOffsetOverride, -45);
    }
  });
}
```

Run: `flutter test test/features/chat/message_bubble_reveal_rebuild_test.dart` → Expected: FAIL to compile, `No named parameter with the name 'timestampRevealListenable'`.

- [ ] **Step 2: Restructure `MessageBubble.build`**

Add to `MessageBubble`: constructor `this.timestampRevealListenable,`, field:

```dart
  /// Live reveal offset for the iMessage-style left swipe. When set, it
  /// replaces [timestampRevealOffset] and only the bubble SHELL rebuilds on
  /// each tick — content, footer and adornments are built once per list
  /// build (05 M-6).
  final ValueListenable<double>? timestampRevealListenable;
```

(import `package:flutter/foundation.dart` for `ValueListenable` if not already available through material).

In `build`, hoist the pieces that today are constructed inline inside the `UniversalBubble(` call:

```dart
    final content = Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ...exactly the existing children (quoted/reply preview branch,
        // EmojiMessageContent or _BubbleBody) moved here verbatim...
      ],
    );
    final footer =
        hasVisibleFooter
            ? _MessageMeta(/* existing args verbatim */)
            : const SizedBox.shrink();
```

Then extract the current `return SizedBox(width: double.infinity, child: Padding(... Stack(children: [reveal column, Align(... UniversalBubble(...), adornments ...)])))` into a local function `Widget shell(double revealOffset)` that uses `revealOffset` wherever `timestampRevealOffset` was used (the `if (showTimestamp && timestampRevealOffset > 0)` reveal column, `timestampRevealProgress`, `dragOffsetOverride: revealOffset > 0 ? -revealOffset : null`) and passes `content: content, footer: footer` (the hoisted instances). Finally:

```dart
    final listenable = timestampRevealListenable;
    if (listenable == null) return shell(timestampRevealOffset);
    return ValueListenableBuilder<double>(
      valueListenable: listenable,
      builder: (context, offset, _) => shell(offset),
    );
```

`timestampRevealProgress` and `timestampRevealBottomInset` move inside `shell` (they depend on the offset). Nothing else changes.

- [ ] **Step 3: Use it from the list**

In `_MessageListState.build`, replace

```dart
                  Widget bubble = ValueListenableBuilder<double>(
                    valueListenable: _timestampRevealOffset,
                    builder:
                        (context, timestampRevealOffset, _) => MessageBubble(
```

with `Widget bubble = MessageBubble(`, delete the `timestampRevealOffset: timestampRevealOffset,` argument, add `timestampRevealListenable: _timestampRevealOffset,`, and close the parenthesis/indentation accordingly (the trailing `),` of the builder goes away; do not reflow unrelated lines).

- [ ] **Step 4: Run; expect pass**

Run: `flutter test test/features/chat/message_bubble_reveal_rebuild_test.dart test/features/chat/message_bubble_test.dart test/features/chat/message_footer_outside_test.dart test/features/chat/chat_screen_message_actions_test.dart test/features/chat/voice_lock_drag_test.dart`
Expected: PASS.

- [ ] **Step 5: Checkpoint**

`flutter analyze lib/features/chat/presentation/widgets/message_bubble.dart lib/features/chat/presentation/screens/chat_screen.dart | grep -E '^\s*(error|warning) '` → nothing. No commit.

---

### Task 8: Bottom overlays never cover the newest message (#33)

**Files:**
- Create: `lib/core/ui/layout/measure_size.dart`
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_ChatScreenState`: `_bottomOverlayHeight`; wrap the bottom `Positioned(... SafeArea(top: false, ...))` child; `_MessageList` gains `bottomOverlayHeight`, loses `composerFocused`; `_MessageListState.build` padding)
- Modify: `test/features/chat/message_list_padding_test.dart` (encoded the guessed 120/64 reserve; replaced)
- Test: `test/core/ui/layout/measure_size_test.dart`, `test/features/chat/chat_screen_overlay_clearance_test.dart`

**Interfaces:**
- Produces: `class MeasureSize extends SingleChildRenderObjectWidget { const MeasureSize({required ValueChanged<Size> onChange, required Widget child}); }` — reports after layout, post-frame, only on change.
- `_MessageList.bottomOverlayHeight: double` (0 until first measurement → falls back to `_messageListBottomReserve = 120.0`). List bottom padding = `bottomOverlayHeight + _messageListOverlayGap (12.0)`.
- Task 10 reads the same `bottomOverlayHeight` to position the pill.

- [ ] **Step 1: MeasureSize unit test (failing)**

```dart
import 'package:attune/core/ui/layout/measure_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reports the laid-out size once per change', (tester) async {
    final sizes = <Size>[];
    var height = 40.0;
    late StateSetter setHeight;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHeight = setState;
            return Align(
              alignment: Alignment.bottomCenter,
              child: MeasureSize(
                onChange: sizes.add,
                child: SizedBox(width: 100, height: height),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(sizes, [const Size(100, 40)]);

    setHeight(() {});
    await tester.pump();
    await tester.pump();
    expect(sizes, hasLength(1), reason: 'same size: no second report');

    setHeight(() => height = 96);
    await tester.pump();
    await tester.pump();
    expect(sizes.last, const Size(100, 96));
    expect(sizes, hasLength(2));
  });
}
```

Run → Expected: FAIL, `Target of URI doesn't exist`.

- [ ] **Step 2: Implement MeasureSize (new file, formatted)**

```dart
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Reports its child's laid-out [Size] whenever it changes.
///
/// Delivered in a post-frame callback so the receiver can call setState
/// (changing layout during layout is forbidden); the dependent widget
/// therefore follows one frame behind, which is invisible for the chat's
/// composer overlays and far better than guessing their height.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({
    super.key,
    required this.onChange,
    required Widget super.child,
  });

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (_reported == size) return;
    _reported = size;
    final reported = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onChange(reported);
    });
  }
}
```

Run → Expected: PASS.

- [ ] **Step 3: Screen test (failing: typing bubble covers the newest message)**

`test/features/chat/chat_screen_overlay_clearance_test.dart`:

```dart
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// #33: the list reserved a fixed 120/64px above the composer, so anything
/// stacked on top of the composer (typing indicator, reply strip, staged
/// game bar) painted over the newest bubble.
void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  testWidgets('the typing indicator never covers the newest message', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'newest message',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    final composerTop = tester.getTopLeft(find.byType(ChatTextField)).dy;
    expect(
      tester.getBottomLeft(find.text('newest message')).dy,
      lessThan(composerTop),
    );

    repo.emitPartnerTyping('partner', true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    final indicator = find.byKey(const ValueKey('typing_indicator'));
    expect(indicator, findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('newest message')).dy,
      lessThan(tester.getTopLeft(indicator).dy),
      reason: 'the list must grow its bottom reserve by the indicator height',
    );

    repo.emitPartnerTyping('partner', false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tearDownChat(tester, container);
  });
}
```

Run: `flutter test test/features/chat/chat_screen_overlay_clearance_test.dart` → Expected: FAIL on the second `lessThan` (the bubble's bottom sits below the indicator's top).

- [ ] **Step 4: Measure the overlay and feed the list**

In `_ChatScreenState` add `double _bottomOverlayHeight = 0;` and:

```dart
  void _onBottomOverlayMeasured(Size size) {
    if (!mounted) return;
    if ((size.height - _bottomOverlayHeight).abs() < 0.5) return;
    setState(() => _bottomOverlayHeight = size.height);
  }
```

In `build`, the bottom `Positioned(left: 0, right: 0, bottom: 0, child: SafeArea(top: false, child: AppContentWidth(...)))` becomes `child: MeasureSize(onChange: _onBottomOverlayMeasured, child: SafeArea(top: false, child: AppContentWidth(...)))`. Pass `bottomOverlayHeight: _bottomOverlayHeight,` to `_MessageList` and remove `composerFocused: _composerFocusNode.hasFocus,`.

In `_MessageList`: replace the `composerFocused` field/param with:

```dart
  /// Measured height of everything stacked over the bottom of the list
  /// (typing indicator, reply strip, staged game, pause card, composer,
  /// home-indicator inset). The list pads itself by exactly this much so
  /// the newest bubble is always fully above the overlay (#33). 0 until
  /// the first frame has measured it.
  final double bottomOverlayHeight;
```

In `_MessageListState`: delete `_messageListKeyboardBottomReserve`, add `static const _messageListOverlayGap = 12.0;`, delete the `keyboardIsOpen` local and the `composerFocused` local, and make the padding:

```dart
                padding: EdgeInsets.fromLTRB(
                  0,
                  10,
                  0,
                  widget.bottomOverlayHeight > 0
                      ? widget.bottomOverlayHeight + _messageListOverlayGap
                      : _messageListBottomReserve,
                ),
```

Keep `_onComposerFocusChanged` in the screen (other code reads focus) — only its use for the reserve is gone. Import `package:attune/core/ui/layout/measure_size.dart`.

- [ ] **Step 5: Replace the old source-string test**

Rewrite `test/features/chat/message_list_padding_test.dart` to:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the list reserve is the measured overlay height, not a constant', () {
    // The reserve used to be 120 (keyboard closed) / 64 (focused) — a guess
    // that any extra strip above the composer (typing, reply, staged game)
    // immediately broke. It is now measured with MeasureSize (#33).
    final source =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();

    expect(source.contains('_messageListKeyboardBottomReserve'), isFalse);
    expect(source.contains('MeasureSize('), isTrue);
    expect(source.contains('bottomOverlayHeight + _messageListOverlayGap'), isTrue);
  });
}
```

- [ ] **Step 6: Run; expect pass**

Run: `flutter test test/core/ui/layout/measure_size_test.dart test/features/chat/chat_screen_overlay_clearance_test.dart test/features/chat/message_list_padding_test.dart test/features/chat/composer_layout_test.dart test/features/chat/chat_screen_wide_layout_test.dart test/features/chat/game_staged_wiring_test.dart`
Expected: PASS.

- [ ] **Step 7: Checkpoint**

`flutter analyze lib/core/ui/layout/measure_size.dart lib/features/chat/presentation/screens/chat_screen.dart | grep -E '^\s*(error|warning) '` → nothing. No commit.

---

### Task 9: The list stays put when a message arrives while scrolled up (#32a)

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_MessageListState.build`: `findChildIndexCallback`, top-level row keys)
- Test: `test/features/chat/chat_screen_list_anchor_test.dart`

**Interfaces:**
- Every `itemBuilder` result (row, separator+row Column, hidden media-run placeholder) is wrapped in `KeyedSubtree(key: ValueKey<String>('row-${message.id}'))`; `findChildIndexCallback` maps that key back to the index via a per-build `Map<String, int>`. The inner `GlobalKey` (`_rowKeys`) is unchanged — it stays the `ensureVisible` target.

- [ ] **Step 1: Failing test**

```dart
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// RC-13 (jump half): a reverse ListView matched rows by INDEX, so a new
/// message at index 0 handed every row the next message's content while
/// keeping that index's layout offset — the text under the reader's finger
/// hopped by one bubble per arrival.
void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  testWidgets('an arrival while scrolled up does not move visible rows', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final base = DateTime.now().subtract(const Duration(hours: 1));
    for (var i = 0; i < 50; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: i.isEven ? 'partner' : 'user-a',
        content: 'message $i',
        createdAt: base.add(Duration(minutes: i)),
      );
    }
    final container = await pumpChat(tester, repo);

    // Scroll toward older history (reverse list: drag down).
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Pick a row that is fully on screen now.
    String? anchor;
    for (var i = 49; i >= 0; i--) {
      final f = find.text('message $i');
      if (f.evaluate().isEmpty) continue;
      final rect = tester.getRect(f);
      if (rect.top > 200 && rect.bottom < 1000) {
        anchor = 'message $i';
        break;
      }
    }
    expect(anchor, isNotNull, reason: 'test needs a fully visible row');
    final before = tester.getTopLeft(find.text(anchor!));

    repo.seedIncoming(
      id: 'm-new',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'just arrived',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final after = tester.getTopLeft(find.text(anchor));
    expect(
      (after.dy - before.dy).abs(),
      lessThan(1),
      reason: 'the viewport must stay anchored on the row being read',
    );
    await tearDownChat(tester, container);
  });
}
```

Run: `flutter test test/features/chat/chat_screen_list_anchor_test.dart` → Expected: FAIL with a dy difference of roughly one bubble height (tens of px). If it unexpectedly passes, re-read `_MessageListState.build` for a `findChildIndexCallback` someone added since; otherwise widen the arrival to three messages (`m-new-1..3`) before concluding — the review verifier marked this half "plausible, unverified", so the failing run IS the verification. Record the measured delta in the test's doc comment.

- [ ] **Step 2: Key the rows and map them back**

In `_MessageListState.build`, after `final mediaRuns = ChatMediaRunLayout.fromMessages(state.messages);` add:

```dart
    // Key → index map for findChildIndexCallback, so the sliver matches a
    // row by WHICH message it is, not by its position. Without it an
    // arrival at index 0 re-targets every element one message over while
    // their layout offsets stay put — the list visibly shifts (#32).
    final indexByRowKey = <String, int>{
      for (var i = 0; i < state.messages.length; i++)
        'row-${state.messages[i].id}': i,
    };
```

On `ListView.builder(` add:

```dart
                findChildIndexCallback: (key) {
                  if (key is ValueKey<String>) return indexByRowKey[key.value];
                  return null;
                },
```

In `itemBuilder`: the hidden media-run branch becomes `return KeyedSubtree(key: ValueKey<String>('row-${state.messages[index].id}'), child: const SizedBox.shrink());`. At the end, where it currently does `if (!isFirstOfDay) return row;` and `return Column(...)`, wrap both: declare `final rowKey = ValueKey<String>('row-${message.id}');` next to `messageKey`, then `if (!isFirstOfDay) return KeyedSubtree(key: rowKey, child: row);` and `return KeyedSubtree(key: rowKey, child: Column(...));`. The loading-more indicator keeps no key (returns null from the callback → index lookup as before).

- [ ] **Step 3: Run; expect pass**

Run: `flutter test test/features/chat/chat_screen_list_anchor_test.dart test/features/chat/message_list_animation_test.dart test/features/chat/chat_media_group_test.dart test/features/chat/chat_date_pin_test.dart test/features/chat/first_of_day_shimmer_test.dart`
Expected: PASS.

- [ ] **Step 4: Checkpoint**

`flutter analyze lib/features/chat/presentation/screens/chat_screen.dart | grep -E '^\s*(error|warning) '` → nothing. No commit.

---

### Task 10: Scroll-to-bottom pill with unread count + "N unread messages" divider (#32b)

**Files:**
- Create: `lib/features/chat/presentation/widgets/scroll_to_latest_pill.dart`, `lib/features/chat/presentation/widgets/unread_divider.dart`
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_MessageList` gains `initialUnreadCount`, `onScrollToLatest`; `_MessageListState` tracks away-from-bottom + unseen count, renders pill and divider)
- Test: `test/features/chat/chat_screen_scroll_to_latest_test.dart`; `unreadDividerMessageId` cases in the same file's first group

**Interfaces:**
- `class ScrollToLatestPill extends StatelessWidget { const ScrollToLatestPill({required bool visible, required int count, required VoidCallback onTap}); }` — key `ValueKey('chat_scroll_to_latest')`; count badge text is `'$count'` (or `'99+'`); honours `reduceMotionOf`.
- `class UnreadDivider extends StatelessWidget { const UnreadDivider({required int count}); }` — key `ValueKey('chat_unread_divider')`, label `'1 unread message'` / `'$count unread messages'`, same rule+pill look as `ChatDateSeparator`.
- `String? unreadDividerMessageId(List<Message> newestFirst, int unreadCount)` — the id of the row the divider sits ABOVE: the `unreadCount`-th newest partner message (not mine, not system notice, not deleted); if fewer such rows are loaded, the oldest loaded one (Review Focus 3); null when `unreadCount <= 0` or none.
- `_MessageList.initialUnreadCount: int` (= `widget.conversation.unreadCount` of the ChatScreen), `_MessageList.onScrollToLatest: VoidCallback` (= `_scrollToLatest`).
- Away threshold: `pixels > 240` (a few bubbles — WhatsApp shows the arrow early). Unseen count = partner arrivals from `MessageArrivalTracker.sync` while away; resets when back within 240 px.

- [ ] **Step 1: Failing tests**

```dart
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/unread_divider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  Message row(String id, {required bool mine, bool deleted = false}) => Message(
    id: id,
    clientMessageId: 'c-$id',
    relationshipId: 'r',
    senderId: mine ? 'me' : 'partner',
    content: 'x',
    createdAt: DateTime(2026, 7, 1),
    status: MessageStatus.sent,
    isMine: mine,
    deletedAt: deleted ? DateTime(2026, 7, 1) : null,
  );

  group('unreadDividerMessageId', () {
    test('points at the Nth newest partner message', () {
      final list = [row('a', mine: false), row('b', mine: true), row('c', mine: false), row('d', mine: false)];
      expect(unreadDividerMessageId(list, 2), 'c');
    });
    test('skips deleted rows and falls back to the oldest loaded partner row', () {
      final list = [row('a', mine: false), row('b', mine: false, deleted: true), row('c', mine: false)];
      expect(unreadDividerMessageId(list, 2), 'c');
      expect(unreadDividerMessageId(list, 80), 'c', reason: 'more unread than loaded');
    });
    test('null for zero unread or no partner rows', () {
      expect(unreadDividerMessageId([row('a', mine: false)], 0), isNull);
      expect(unreadDividerMessageId([row('a', mine: true)], 3), isNull);
    });
  });

  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo, {
    Conversation? conversation,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    final convo = conversation ?? activeConversation('rel-1');
    repo.conversationOverride = convo;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  void seedMany(FakeChatRepository repo, int n) {
    final base = DateTime.now().subtract(const Duration(hours: 2));
    for (var i = 0; i < n; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: i % 3 == 0 ? 'user-a' : 'partner',
        content: 'message $i',
        createdAt: base.add(Duration(minutes: i)),
      );
    }
  }

  testWidgets('pill appears with the arrival count and returns to the latest', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final container = await pumpChat(tester, repo);
    final pill = find.byKey(const ValueKey('chat_scroll_to_latest'));
    expect(find.descendant(of: pill, matching: find.byIcon(Icons.keyboard_arrow_down_rounded)).hitTestable(), findsNothing,
        reason: 'hidden at the bottom');

    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.descendant(of: pill, matching: find.byIcon(Icons.keyboard_arrow_down_rounded)).hitTestable(), findsOneWidget);

    repo.seedIncoming(id: 'n1', relationshipId: 'rel-1', senderId: 'partner', content: 'new one', createdAt: DateTime.now());
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    repo.seedIncoming(id: 'n2', relationshipId: 'rel-1', senderId: 'partner', content: 'new two', createdAt: DateTime.now());
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.descendant(of: pill, matching: find.text('2')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('new two').hitTestable(), findsOneWidget);
    expect(find.descendant(of: pill, matching: find.text('2')), findsNothing);
    await tearDownChat(tester, container);
  });

  testWidgets('the pill sits above the typing indicator (Review Focus 5)', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final container = await pumpChat(tester, repo);
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    repo.emitPartnerTyping('partner', true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    final indicatorTop = tester.getTopLeft(find.byKey(const ValueKey('typing_indicator'))).dy;
    final pillBottom = tester.getBottomLeft(find.byIcon(Icons.keyboard_arrow_down_rounded)).dy;
    expect(pillBottom, lessThan(indicatorTop));
    repo.emitPartnerTyping('partner', false);
    await tester.pump(const Duration(milliseconds: 600));
    await tearDownChat(tester, container);
  });

  testWidgets('opening with unread shows the divider above the oldest unread', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final base = DateTime.now().subtract(const Duration(minutes: 30));
    for (var i = 0; i < 10; i++) {
      repo.seedIncoming(id: 'm$i', relationshipId: 'rel-1', senderId: 'partner', content: 'message $i', createdAt: base.add(Duration(minutes: i)));
    }
    final container = await pumpChat(
      tester,
      repo,
      conversation: activeConversation('rel-1').copyWith(unreadCount: 3),
    );
    final divider = find.byType(UnreadDivider);
    expect(find.text('3 unread messages'), findsOneWidget);
    final dividerTop = tester.getTopLeft(divider).dy;
    expect(dividerTop, greaterThan(tester.getTopLeft(find.text('message 6')).dy));
    expect(dividerTop, lessThan(tester.getTopLeft(find.text('message 7')).dy));
    await tearDownChat(tester, container);
  });

  testWidgets('no divider without unread', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 5);
    final container = await pumpChat(tester, repo);
    expect(find.byType(UnreadDivider), findsNothing);
    await tearDownChat(tester, container);
  });
}
```

Run: `flutter test test/features/chat/chat_screen_scroll_to_latest_test.dart` → Expected: FAIL to compile (`unread_divider.dart` missing).

- [ ] **Step 2: Widgets (new files, formatted)**

`scroll_to_latest_pill.dart`:

```dart
import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart'
    show kComposerShadows;
import 'package:flutter/material.dart';

/// WhatsApp's "↓" button: shown once the reader has scrolled away from the
/// newest message, with a badge counting partner messages that arrived
/// since. Sits on the same surface and shadow as the composer.
class ScrollToLatestPill extends StatelessWidget {
  const ScrollToLatestPill({
    super.key,
    required this.visible,
    required this.count,
    required this.onTap,
  });

  final bool visible;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instant = reduceMotionOf(context);
    final duration = instant ? Duration.zero : const Duration(milliseconds: 180);
    final badge = count > 99 ? '99+' : '$count';
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.4),
          duration: duration,
          curve: Curves.easeOutCubic,
          child: Semantics(
            button: true,
            label:
                count > 0
                    ? 'Jump to newest, $count new'
                    : 'Jump to newest message',
            child: Material(
              color: theme.chatControlSurface,
              shape: const CircleBorder(),
              shadowColor: Colors.transparent,
              child: Ink(
                decoration: const ShapeDecoration(
                  shape: CircleBorder(),
                  shadows: kComposerShadows,
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: theme.colorScheme.onSurface,
                        ),
                        if (count > 0)
                          Positioned(
                            top: -6,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badge,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

`unread_divider.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/chat_date_chip.dart';
import 'package:flutter/material.dart';

/// The row the "N unread messages" divider sits ABOVE: the [unreadCount]-th
/// newest partner message that can be unread (not mine, not a system
/// notice, not deleted — matching count_unread_messages). When fewer such
/// rows are loaded than the count, the oldest loaded one is used so the
/// divider still marks "everything from here down is new".
String? unreadDividerMessageId(List<Message> newestFirst, int unreadCount) {
  if (unreadCount <= 0) return null;
  String? candidate;
  var seen = 0;
  for (final message in newestFirst) {
    if (message.isMine || message.isSystemNotice || message.isDeleted) continue;
    candidate = message.id;
    seen++;
    if (seen == unreadCount) break;
  }
  return candidate;
}

/// Same rule-and-pill grammar as ChatDateSeparator, so it reads as part of
/// the list rather than a banner.
class UnreadDivider extends StatelessWidget {
  const UnreadDivider({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = count == 1 ? '1 unread message' : '$count unread messages';
    final rule = Expanded(
      child: Container(
        height: 0.6,
        color: colorScheme.primary.withValues(alpha: 0.35),
      ),
    );
    return Padding(
      key: const ValueKey('chat_unread_divider'),
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          rule,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
            child: ChatDateChip(label: label),
          ),
          rule,
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Wire into the list**

`_MessageList`: add `required this.initialUnreadCount, required this.onScrollToLatest,` with fields:

```dart
  /// conversation.unreadCount as it was when the screen opened — the
  /// one-shot "N unread messages" divider is placed from it, never from the
  /// live count (which drops to 0 as soon as the view is active).
  final int initialUnreadCount;

  /// Animates the list back to the newest message (the pill's tap).
  final VoidCallback onScrollToLatest;
```

The screen passes `initialUnreadCount: widget.conversation.unreadCount, onScrollToLatest: _scrollToLatest,`.

`_MessageListState`: fields

```dart
  /// Reader has left the newest messages (more than ~a few bubbles up).
  bool _awayFromBottom = false;
  static const _awayThreshold = 240.0;

  /// Partner messages that arrived while [_awayFromBottom]; the pill badge.
  int _unseenWhileAway = 0;

  /// Resolved once, from the first settled page.
  String? _unreadDividerId;
  bool _unreadDividerResolved = false;
```

In `_syncArrivals`, capture the returned set:

```dart
  void _syncArrivals(ChatState state) {
    final arrivals = _arrivalTracker.sync(
      state.messages.map((message) => message.clientMessageId),
      initialLoading: state.isLoading,
      loadingMore: state.isLoadingMore,
    );
    _pendingArrivalIds.addAll(arrivals);
    if (_awayFromBottom && arrivals.isNotEmpty) {
      final byClientId = {
        for (final m in state.messages) m.clientMessageId: m,
      };
      _unseenWhileAway +=
          arrivals.where((id) => byClientId[id]?.isMine == false).length;
    }
  }
```

In the `NotificationListener.onNotification`, add before `return false;`:

```dart
              final away = notification.metrics.pixels > _awayThreshold;
              if (away != _awayFromBottom) {
                setState(() {
                  _awayFromBottom = away;
                  if (!away) _unseenWhileAway = 0;
                });
              }
```

In `build`, after the empty/archived early returns and before the `Stack`:

```dart
    if (!_unreadDividerResolved && !state.isLoading) {
      _unreadDividerResolved = true;
      _unreadDividerId = unreadDividerMessageId(
        state.messages,
        widget.initialUnreadCount,
      );
    }
```

In `itemBuilder`, where the separator Column is built: compute `final showsUnreadDivider = _unreadDividerId == message.id;` and emit the divider BELOW the date separator (it must sit immediately above the row): change the end to

```dart
                  final rowWithDividers = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isFirstOfDay)
                        Padding(
                          padding: const EdgeInsets.only(top: 32, bottom: 20),
                          child: ChatDateSeparator(
                            label: chatDateLabel(message.createdAt),
                          ),
                        ),
                      if (showsUnreadDivider)
                        UnreadDivider(count: widget.initialUnreadCount),
                      row,
                    ],
                  );
                  if (!isFirstOfDay && !showsUnreadDivider) {
                    return KeyedSubtree(key: rowKey, child: row);
                  }
                  return KeyedSubtree(key: rowKey, child: rowWithDividers);
```

(keep the long explanatory comment about separator placement above this block). Add the pill to the outer `Stack` children, after the pinned date chip:

```dart
        Positioned(
          right: 16,
          bottom:
              (widget.bottomOverlayHeight > 0
                  ? widget.bottomOverlayHeight
                  : _messageListBottomReserve) +
              12,
          child: ScrollToLatestPill(
            key: const ValueKey('chat_scroll_to_latest'),
            visible: _awayFromBottom,
            count: _unseenWhileAway,
            onTap: () {
              ref.read(hapticsProvider).selection();
              widget.onScrollToLatest();
            },
          ),
        ),
```

Imports: `scroll_to_latest_pill.dart`, `unread_divider.dart`, `package:attune/core/ui/feedback/haptics.dart` (check whether `hapticsProvider` is already imported in chat_screen.dart — it is referenced in the composer args).

- [ ] **Step 4: Run; expect pass**

Run: `flutter test test/features/chat/chat_screen_scroll_to_latest_test.dart test/features/chat/chat_screen_list_anchor_test.dart test/features/chat/message_list_animation_test.dart test/features/chat/chat_date_pin_test.dart`
Expected: PASS.

- [ ] **Step 5: Checkpoint**

`flutter analyze lib/features/chat/presentation/widgets/scroll_to_latest_pill.dart lib/features/chat/presentation/widgets/unread_divider.dart lib/features/chat/presentation/screens/chat_screen.dart | grep -E '^\s*(error|warning) '` → nothing. No commit.

---

### Task 11: Delivery status on own bubbles (#36, client half)

**Ruling:** ticks go on the newest own message, on the LAST bubble of every own group (the row whose newer neighbour is a different sender or day), and on every queued/sending/failed own row. Not on every own bubble: this app's footer sits OUTSIDE the bubble on the wallpaper (24 px per footer), so a tick under each of five grouped one-liners would double the group's height — the iMessage treatment ("Delivered" under the last of a run) keeps grouping dense while still answering "did my last three get through?". The swipe-to-reveal column additionally shows the tick next to the time for EVERY own row, so the per-message answer is one swipe away.

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_status_rule.dart` (`showsDeliveryStatus` already added in Task 5 — this task tests it)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_MessageListState.build`: `firstOwnIndex`, `showStatus:`)
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (`_RevealTimestamp` shows `_StatusChip` for own rows)
- Test: `test/features/chat/message_status_rule_test.dart` (add group), `test/features/chat/chat_screen_delivery_status_test.dart`

- [ ] **Step 1: Failing tests**

Append to `message_status_rule_test.dart`:

```dart
  group('showsDeliveryStatus', () {
    test('partner rows never', () {
      expect(showsDeliveryStatus(isMine: false, isNewestOwn: true, isGroupEnd: true, status: MessageStatus.read), isFalse);
    });
    test('newest own and group ends do', () {
      expect(showsDeliveryStatus(isMine: true, isNewestOwn: true, isGroupEnd: false, status: MessageStatus.sent), isTrue);
      expect(showsDeliveryStatus(isMine: true, isNewestOwn: false, isGroupEnd: true, status: MessageStatus.delivered), isTrue);
    });
    test('a settled mid-group row does not; a pending/failed one always does', () {
      expect(showsDeliveryStatus(isMine: true, isNewestOwn: false, isGroupEnd: false, status: MessageStatus.read), isFalse);
      for (final s in [MessageStatus.queued, MessageStatus.sending, MessageStatus.failed]) {
        expect(showsDeliveryStatus(isMine: true, isNewestOwn: false, isGroupEnd: false, status: s), isTrue, reason: '$s');
      }
    });
  });
```

`chat_screen_delivery_status_test.dart` (same `pumpChat`/`tearDownChat` helpers as Task 9's file, copied verbatim):

```dart
  testWidgets('ticks show on the newest own message and each own group end', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final base = DateTime.now().subtract(const Duration(minutes: 10));
    // own, own (group end), partner, own (newest own)
    repo.seedIncoming(id: 'o1', relationshipId: 'rel-1', senderId: 'user-a', content: 'one', createdAt: base, deliveredAt: base);
    repo.seedIncoming(id: 'o2', relationshipId: 'rel-1', senderId: 'user-a', content: 'two', createdAt: base.add(const Duration(minutes: 1)), deliveredAt: base);
    repo.seedIncoming(id: 'p1', relationshipId: 'rel-1', senderId: 'partner', content: 'reply', createdAt: base.add(const Duration(minutes: 2)));
    repo.seedIncoming(id: 'o3', relationshipId: 'rel-1', senderId: 'user-a', content: 'three', createdAt: base.add(const Duration(minutes: 3)));
    repo.seedIncoming(id: 'p2', relationshipId: 'rel-1', senderId: 'partner', content: 'last', createdAt: base.add(const Duration(minutes: 4)));
    final container = await pumpChat(tester, repo);

    bool hasTick(String text) =>
        find
            .descendant(
              of: find.ancestor(of: find.text(text), matching: find.byType(MessageBubble)),
              matching: find.bySemanticsLabel(RegExp('^Message status:')),
            )
            .evaluate()
            .isNotEmpty;

    expect(hasTick('three'), isTrue, reason: 'newest own');
    expect(hasTick('two'), isTrue, reason: 'end of the first own group');
    expect(hasTick('one'), isFalse, reason: 'settled mid-group row');
    expect(hasTick('reply'), isFalse);
    await tearDownChat(tester, container);
  });
```

(import `message_bubble.dart`). Add to `test/features/chat/message_bubble_test.dart` (reuse its `_mine`/`_pump` helpers):

```dart
  testWidgets('the swipe-reveal column shows the tick beside the time for own rows', (
    tester,
  ) async {
    await _pump(
      tester,
      MessageBubble(
        message: _mine(status: MessageStatus.read),
        showStatus: false,
        timestampRevealOffset: 40,
      ),
    );
    expect(find.bySemanticsLabel('Message status: Read'), findsOneWidget);
  });
```

Run: `flutter test test/features/chat/message_status_rule_test.dart test/features/chat/chat_screen_delivery_status_test.dart test/features/chat/message_bubble_test.dart`
Expected: rule group PASSES (implemented in Task 5); the screen test FAILS on `hasTick('two')`; the reveal test FAILS (`findsNothing`).

- [ ] **Step 2: Apply the rule in the list**

In `_MessageListState.build` before the `Stack`: `final firstOwnIndex = state.messages.indexWhere((m) => m.isMine);`. In the `MessageBubble(` arguments replace `showStatus: index == 0 && message.isMine,` with:

```dart
                          showStatus: showsDeliveryStatus(
                            isMine: message.isMine,
                            isNewestOwn: index == firstOwnIndex,
                            isGroupEnd: !isGroupedWithPrevious,
                            status: message.status,
                          ),
```

Import `message_status_rule.dart`.

- [ ] **Step 3: Tick in the reveal column**

In `_RevealTimestamp.build`, wrap the existing `Text` in a `Row(mainAxisSize: MainAxisSize.min, children: [ <existing Semantics+Text>, if (message.isMine) ...[const SizedBox(width: 4), _StatusChip(message: message, iconColor: Theme.of(context).colorScheme.primary, readColor: Theme.of(context).colorScheme.primary)] ])` inside the `FittedBox`.

- [ ] **Step 4: Run; expect pass**

Run: `flutter test test/features/chat/message_status_rule_test.dart test/features/chat/chat_screen_delivery_status_test.dart test/features/chat/message_bubble_test.dart test/features/chat/message_footer_outside_test.dart test/features/chat/send_feedback_test.dart`
Expected: PASS. If `message_footer_outside_test.dart` asserts "no footer on a non-newest own row", read it: a row that is a group end now legitimately has one — adjust that test's fixture to a mid-group row (two own rows, assert on the OLDER one... which is now the group end; use three own rows and assert on the middle one) and note the change.

- [ ] **Step 5: Checkpoint**

`flutter analyze lib/features/chat/presentation/widgets/message_bubble.dart lib/features/chat/presentation/screens/chat_screen.dart | grep -E '^\s*(error|warning) '` → nothing. No commit.

---

### Task 12: "Delivered" stamped on push receipt, not only when the chat is open (#36, server-coordination half)

**What V1 RC-14 established:** the push worker (`supabase/functions/process-chat-notification-outbox/index.ts`) stamps `delivered_at` ONLY in the suppressed-because-actively-viewing branch; the normal push path deliberately does not ("queuing a push is not delivery"). Today the client stamps from the open chat (`_markPartnerMessagesDelivered`) and from the conversations list fetch (`markRelationshipDelivered`, which also runs on every inbox realtime event while the list is on screen). The remaining gap: the app is backgrounded/killed, the push arrives, nobody acks.

**Ruling on background acks:** `onesignal_flutter 5.5.1` exposes no background data-message handler on either platform; Android displays the push in OneSignal's own service without waking Dart, and iOS would need a Notification Service Extension (`ios/` has `Share Extension` and `TogetherWidget` only, no NSE). So the repo-side fix is: ack from the two hooks the SDK does give — `addForegroundWillDisplayListener` (app open on another screen) and `addClickListener` (tap from the tray/lock screen, including cold start) — both calling `markRelationshipDelivered(relationship_id)`. A true background ack is listed as an Owner step below; until then the sender sees one tick for a backgrounded recipient and two the moment they open the app (list fetch) or tap the push.

**Files:**
- Modify: `lib/core/notifications/services/onesignal_service.dart`
- Test: `test/core/notifications/onesignal_delivery_ack_test.dart`

**Interfaces:**
- `String? chatRelationshipIdForDeliveryAck(Map<String, dynamic>? additionalData)` — `relationship_id` when `type == 'new_message'`, else null (a reaction push is not a message delivery).
- `OneSignalService(Ref ref, {PushSdk? sdk, String? platform, Future<void> Function(String relationshipId)? ackChatDelivery})` — the first two named parameters are Plan 1b's (keep them); `ackChatDelivery` is new and defaults (at call time, never in the initializer list — `this` is not available there) to `ref.read(chatRepositoryProvider).markRelationshipDelivered`.
- `Future<void> handleChatPushReceived(Map<String, dynamic>? additionalData)` — public, best-effort (never throws).
- Test construction: `OneSignalService(ref, ackChatDelivery: …)` leaves `sdk` at Plan 1b's default `OneSignalPushSdk()`, which has no constructor body and touches no channel until `initialize()`/`attach()` — neither is called by these tests.

- [ ] **Step 1: Failing test**

```dart
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/chat/support/chat_test_harness.dart';

/// RC-14: delivered_at was only ever stamped by a foregrounded chat or the
/// conversation list. A push the SDK hands to Dart (foreground display or
/// a tap) is proof the device has the message, so it acks too.
void main() {
  test('picks the relationship out of a new_message payload only', () {
    expect(
      chatRelationshipIdForDeliveryAck({'type': 'new_message', 'relationship_id': 'rel-1'}),
      'rel-1',
    );
    expect(chatRelationshipIdForDeliveryAck({'type': 'message_reaction', 'relationship_id': 'rel-1'}), isNull);
    expect(chatRelationshipIdForDeliveryAck({'type': 'new_message'}), isNull);
    expect(chatRelationshipIdForDeliveryAck(null), isNull);
  });

  test('handleChatPushReceived marks the relationship delivered', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final container = ProviderContainer(
      overrides: [chatRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final service = container.read(oneSignalServiceProvider);

    await service.handleChatPushReceived({'type': 'new_message', 'relationship_id': 'rel-1'});
    await service.handleChatPushReceived({'type': 'message_reaction', 'relationship_id': 'rel-1'});
    await service.handleChatPushReceived({'type': 'new_message'});

    expect(repo.relationshipDeliveredCalls, ['rel-1']);
  });

  test('a failing ack never throws out of the push handler', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = OneSignalService(
      container.read(_refProvider),
      ackChatDelivery: (_) async => throw StateError('offline'),
    );
    await expectLater(
      service.handleChatPushReceived({'type': 'new_message', 'relationship_id': 'rel-1'}),
      completes,
    );
  });
}

final _refProvider = Provider<Ref>((ref) => ref);
```

Run: `flutter test test/core/notifications/onesignal_delivery_ack_test.dart` → Expected: FAIL to compile (`chatRelationshipIdForDeliveryAck`, `ackChatDelivery`, `handleChatPushReceived` undefined).

- [ ] **Step 2: Implement**

In `onesignal_service.dart` (the Plan 1b shape — re-read it first): import `package:attune/features/chat/presentation/state/chat_state.dart` (`flutter/foundation.dart` is already imported by 1b for `@visibleForTesting`; it also provides `debugPrint`). Change the constructor and add one field, keeping 1b's `sdk`/`platform` parameters and initializers exactly as they are:

```dart
  OneSignalService(
    this._ref, {
    PushSdk? sdk,
    String? platform,
    Future<void> Function(String relationshipId)? ackChatDelivery,
  }) : _sdk = sdk ?? OneSignalPushSdk(),
       _platform = platform ?? (Platform.isIOS ? 'ios' : 'android'),
       _ackChatDelivery = ackChatDelivery;

  /// Stamps delivered_at for every undelivered partner message in a
  /// relationship. Injected for tests; null means "the chat repository",
  /// resolved at call time because `_ref` cannot be touched from an
  /// initializer list.
  final Future<void> Function(String relationshipId)? _ackChatDelivery;
```

Add the method and the pure function:

```dart
  /// RC-14: a chat push the SDK hands to Dart (shown in the foreground, or
  /// tapped) proves the row reached this device, so it is acked as
  /// delivered right here rather than waiting for the chat to open.
  /// Best-effort: delivery receipts never block anything (Spec 9.2).
  Future<void> handleChatPushReceived(
    Map<String, dynamic>? additionalData,
  ) async {
    final relationshipId = chatRelationshipIdForDeliveryAck(additionalData);
    if (relationshipId == null) return;
    final ack =
        _ackChatDelivery ??
        (id) => _ref.read(chatRepositoryProvider).markRelationshipDelivered(id);
    try {
      await ack(relationshipId);
    } catch (error) {
      debugPrint('chat delivery ack failed: $error');
    }
  }
```

```dart
/// The relationship to ack for a push payload, or null when the push is not
/// a new chat message (a reaction push, for example, delivers no message).
/// Pure, so it is testable without the OneSignal SDK.
String? chatRelationshipIdForDeliveryAck(Map<String, dynamic>? additionalData) {
  if (additionalData == null) return null;
  if (additionalData['type'] != 'new_message') return null;
  final id = additionalData['relationship_id'];
  return id is String && id.isNotEmpty ? id : null;
}
```

In `initialize()`: at the top of the click listener body (before `if (additionalData == null) return;` — keep that line after) add `unawaited(handleChatPushReceived(event.notification.additionalData));`, and in the foreground listener add the same line as its first statement (before the suppress check — a suppressed banner over the lock screen still means the device has the row). `dart:async` is already imported by Plan 1b (`unawaited`); add it only if `flutter analyze` says it is missing.

- [ ] **Step 3: Run; expect pass**

Run: `flutter test test/core/notifications/onesignal_delivery_ack_test.dart test/core/notifications/onesignal_click_routing_test.dart test/core/notifications/notification_tap_routing_test.dart test/core/notifications/onesignal_service_test.dart`
Expected: PASS (`onesignal_service_test.dart` is Plan 1b's; it constructs the service with `sdk:`/`platform:` and must be untouched by the new parameter).

- [ ] **Step 4: Checkpoint**

`flutter analyze lib/core/notifications/services/onesignal_service.dart | grep -E '^\s*(error|warning) '` → nothing. No commit.

**Owner step (not in this plan's code; needed for a two-tick while the recipient's phone is in a pocket):** add an iOS Notification Service Extension target in Xcode (File → New → Target → Notification Service Extension, bundle id `<app bundle id>.NotificationServiceExtension`, same App Group), enable "Push Notifications" + "Background Modes → Remote notifications" on it, and have its `didReceive` call a new edge function `ack-chat-delivery` with the push's `relationship_id` and the OneSignal subscription id — the function would verify the subscription belongs to the recipient and call `mark_relationship_delivered`. Android has no equivalent with the OneSignal Flutter SDK; the next app open acks. Until then, "delivered" for a backgrounded recipient lands when they open the app or tap the push, which is what the second test above proves.

---

### Task 13: Jump-to-message that always converges (#30)

**Ruling on "messages around id":** a disjoint "window around the target" would break the one invariant every other part of the controller relies on (`state.messages` is a contiguous newest-first run: after Plan 1a `loadMoreMessages` cursors from `_oldestFetchedCursor` and reconciles each page's span, `_catchUpFromCursor` from the newest, cache writes the whole list). Instead the target's `sort_at` is fetched with one cheap by-id read (Plan 1a's `getMessagesByIds(relationshipId, [id])` — RLS-protected, hydrated like a page row), then history is paged CONTIGUOUSLY in large pages (`ChatConfig.jumpPageSize = 200`) until the target is in `state.messages`. The loop is bounded by the server-confirmed span: once `_oldestFetchedCursor` is at or below the target's `(sort_at, id)` and the target still is not loaded, it cannot be (hard-deleted or filtered out of pages) → "Couldn't find that message." The bound is the FETCHED cursor, not `state.messages.last`: the cache may hold rows older than anything the server re-sent this session, and 1a re-fetches that span on the way down. No RPC, no migration, no new repository method. `scrollable_positioned_list` is not added: the rows have GlobalKeys already, and an anchored extrapolation loop over measured built rows converges in a handful of frames.

**Files:**
- Modify: `lib/features/chat/config/chat_config.dart` (`jumpPageSize`)
- Modify: `test/features/chat/support/chat_test_harness.dart` (`hiddenFromPages`; `getMessagesCalls` and `getMessagesByIds` already exist after Plan 1a)
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (`loadMoreMessages({int? limit})` — one line in the Plan 1a body, `ensureMessageLoaded`, `JumpTargetResult`)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_jumpToMessage`, `_scrollUntilBuilt`, `_nearestBuiltRow`, remove `_jumpToMessageAcrossPages`, `_jumpLoading` chip)
- Test: `test/features/chat/chat_controller_test.dart` (new group), `test/features/chat/chat_screen_jump_convergence_test.dart`; `test/features/chat/chat_screen_initial_jump_test.dart` must keep passing unchanged.

**Interfaces:**
- `ChatConfig.jumpPageSize` (int, default 200).
- Consumes (Plan 1a): `ChatRepository.getMessagesByIds(String relationshipId, List<String> ids)`, `ChatController._oldestFetchedCursor`, `static bool ChatController.isOlderThanCursor(Message m, ChatMessageCursor c)`.
- `enum JumpTargetResult { loaded, notFound, exhausted }`
- `ChatController.loadMoreMessages({int? limit})` — `limit` defaults to `messagePageSize`; `hasMore = older.length >= limit`; everything else is Plan 1a's body.
- `ChatController.ensureMessageLoaded(String messageId, {int maxPages = 40}) → Future<JumpTargetResult>`.
- Screen: `_jumpToMessage(String messageId, List<Message> currentMessages)` is the single entry for quote taps, pinned banner, viewer "Go to message" and `initialJumpToMessageId`.

- [ ] **Step 1: Controller tests (failing)**

Add to `test/features/chat/chat_controller_test.dart` (uses its existing `boot` helper; add the `chatConfigProvider` override by giving `boot` an optional `ChatConfig? config` that is appended to `buildChatContainer(extraOverrides: [...])` — read `boot` first):

```dart
  group('ensureMessageLoaded (jump-to-message)', () {
    void seed(FakeChatRepository repo, int n) {
      final base = DateTime(2026, 7, 1);
      for (var i = 0; i < n; i++) {
        repo.seedIncoming(
          id: 'm$i',
          relationshipId: relId,
          senderId: 'partner',
          content: 'message $i',
          createdAt: base.add(Duration(minutes: i)),
        );
      }
    }

    test('pages contiguously until the target is in state.messages', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 40);
      final b = await boot(
        repo,
        config: const ChatConfig(messagePageSize: 5, jumpPageSize: 10),
      );
      expect(b.state.messages.length, 5);
      final callsBefore = repo.getMessagesCalls;

      final result = await b.controller.ensureMessageLoaded('m3');

      expect(result, JumpTargetResult.loaded);
      expect(b.state.messages.any((m) => m.id == 'm3'), isTrue);
      // 35 older rows in pages of 10 → 4 pages, never one per 5.
      expect(repo.getMessagesCalls - callsBefore, 4);
      // Still contiguous: every id between the newest and the target.
      final ids = b.state.messages.map((m) => m.id).toList();
      expect(ids.first, 'm39');
      expect(ids.contains('m3'), isTrue);
      expect(ids.length, 40);
    });

    test('a missing target is reported without paging the whole history', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 40);
      final b = await boot(
        repo,
        config: const ChatConfig(messagePageSize: 5, jumpPageSize: 10),
      );
      final callsBefore = repo.getMessagesCalls;
      expect(await b.controller.ensureMessageLoaded('ghost'), JumpTargetResult.notFound);
      expect(repo.getMessagesCalls - callsBefore, 0);
    });

    test('a target hidden from the pages stops once paged past its sort_at', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 40);
      // Visible by id but absent from list pages (e.g. a row the list
      // query filters). Simulate: getMessagesByIds knows it, getMessages
      // never returns it.
      repo.hiddenFromPages.add('m20');
      final b = await boot(
        repo,
        config: const ChatConfig(messagePageSize: 5, jumpPageSize: 10),
      );
      final callsBefore = repo.getMessagesCalls;
      expect(await b.controller.ensureMessageLoaded('m20'), JumpTargetResult.notFound);
      // Stopped as soon as the fetched span reached past m20 (page 1:
      // m34..m25; page 2: m24..m14 with m20 missing), not after paging the
      // whole history.
      expect(repo.getMessagesCalls - callsBefore, 2);
      expect(b.state.messages.last.sortAt.isBefore(repo.serverMessages['m20']!.sortAt), isTrue);
    });

    test('a page fetch that fails ends the jump instead of spinning', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 40);
      final b = await boot(
        repo,
        config: const ChatConfig(messagePageSize: 5, jumpPageSize: 10),
      );
      repo.getMessagesError = Exception('offline');
      final callsBefore = repo.getMessagesCalls;
      expect(await b.controller.ensureMessageLoaded('m3'), JumpTargetResult.exhausted);
      expect(repo.getMessagesCalls - callsBefore, 1, reason: 'no retry storm');
    });
  });
```

Harness additions (all additive; `getMessagesCalls` and `getMessagesByIds` are Plan 1a's — do not re-declare them): `final Set<String> hiddenFromPages = {};` filtered out of `getMessages` results (`.where((m) => !hiddenFromPages.contains(m.id))`, applied to the page AFTER the relationship filter and BEFORE the cursor/limit so paging still advances past the hidden row), and `Object? getMessagesError;` thrown by `getMessages` after `getMessagesCalls++` when set (`final error = getMessagesError; if (error != null) throw error;`). If Plan 1a already added a `getMessagesError` seam under another name, reuse that name here and in the test.

Run: `flutter test test/features/chat/chat_controller_test.dart --name ensureMessageLoaded` → Expected: FAIL to compile (`jumpPageSize` not a `ChatConfig` parameter; `ensureMessageLoaded` and `JumpTargetResult` undefined; `hiddenFromPages`/`getMessagesError` undefined on the fake).

- [ ] **Step 2: Config**

`chat_config.dart`: add `final int jumpPageSize;` and `this.jumpPageSize = 200,` with doc "Page size while paging back to a jump target (reply quote, pin, Starred). Larger than messagePageSize because the person is waiting on it."

No repository change: the by-id read is Plan 1a's `getMessagesByIds(relationshipId, [messageId])` (RLS-protected `messages` select, hydrated like a page row; the fake filters by relationship, so a target from another chat comes back empty → `notFound`).

- [ ] **Step 3: Controller**

In `chat_state.dart` add near `ChatState`:

```dart
/// Outcome of paging toward a jump target.
enum JumpTargetResult {
  /// The target row is in state.messages.
  loaded,

  /// The server has no such visible row, or history was paged past its
  /// position without meeting it.
  notFound,

  /// History ran out (hasMore false) or the page cap was hit first.
  exhausted,
}
```

`loadMoreMessages` — the Plan 1a body stays (cursor from `_oldestFetchedCursor`, `reconcileWindow`, `exhaustive: older.length < pageSize`, `hasMore: older.length >= pageSize`). Make exactly two edits to it: the signature `Future<void> loadMoreMessages() async {` → `Future<void> loadMoreMessages({int? limit}) async {`, and the line `final pageSize = ref.read(chatConfigProvider).messagePageSize;` → `final pageSize = limit ?? ref.read(chatConfigProvider).messagePageSize;`. (If the 1a body is somehow not there — `grep -n '_oldestFetchedCursor' chat_state.dart` returns nothing — stop: Plan 1a Task 4 has not run, and this plan's order assumption is broken.)

New method after it:

```dart
  /// Pages history back (contiguously, in jumpPageSize pages) until
  /// [messageId] is in state.messages. The target's own (sort_at, id)
  /// bounds the loop against the SERVER-CONFIRMED span: once
  /// _oldestFetchedCursor is at or below the target and the target still is
  /// not loaded, it cannot be — stop instead of paging to the beginning of
  /// time (#30 / RC-11). The fetched cursor, not state.messages.last, is
  /// the bound because the cache may hold older rows the server has not
  /// re-sent yet (Plan 1a re-fetches that span page by page).
  Future<JumpTargetResult> ensureMessageLoaded(
    String messageId, {
    int maxPages = 40,
  }) async {
    bool loaded() => state.messages.any((m) => m.id == messageId);
    if (loaded()) return JumpTargetResult.loaded;

    Message? target;
    var lookupFailed = false;
    try {
      final rows = await _repository.getMessagesByIds(relationshipId, [
        messageId,
      ]);
      target = rows.isEmpty ? null : rows.first;
    } catch (_) {
      lookupFailed = true; // offline: page without a bound, cap applies
    }
    if (!lookupFailed && target == null) return JumpTargetResult.notFound;

    bool pagedPastTarget() {
      final floor = _oldestFetchedCursor;
      // Target not older than the oldest fetched row → it lies inside the
      // span the server has already answered for.
      return target != null &&
          floor != null &&
          !isOlderThanCursor(target, floor);
    }

    final limit = ref.read(chatConfigProvider).jumpPageSize;
    var pages = 0;
    var waits = 0;
    while (pages < maxPages && mounted) {
      if (loaded()) return JumpTargetResult.loaded;
      if (pagedPastTarget()) return JumpTargetResult.notFound;
      if (!state.hasMore) {
        return target == null
            ? JumpTargetResult.exhausted
            : JumpTargetResult.notFound;
      }
      if (state.isLoadingMore) {
        // A scroll-triggered page is in flight; let it land.
        if (++waits > 200) return JumpTargetResult.exhausted;
        await Future<void>.delayed(const Duration(milliseconds: 25));
        continue;
      }
      pages++;
      final cursorBefore = _oldestFetchedCursor;
      await loadMoreMessages(limit: limit);
      if (!mounted) return JumpTargetResult.exhausted;
      if (identical(_oldestFetchedCursor, cursorBefore) && state.hasMore) {
        // The fetch failed (loadMoreMessages swallows the error and leaves
        // hasMore true). Don't spin on a dead network.
        return JumpTargetResult.exhausted;
      }
    }
    return loaded() ? JumpTargetResult.loaded : JumpTargetResult.exhausted;
  }
```

(`_oldestFetchedCursor` is a new `ChatMessageCursor` instance on every successful page, so `identical` is a precise "made progress" check.)

Run the controller group → Expected: PASS (4 tests).

- [ ] **Step 4: Screen test (failing: lands nowhere / wrong place)**

`test/features/chat/chat_screen_jump_convergence_test.dart` (same `pumpChat`/`tearDownChat` helpers as Task 9, but `pumpChat` builds the GoRouter `MaterialApp.router` exactly as `chat_screen_message_actions_test.dart` does so quote taps that push nothing still have a router, and accepts `String? initialJumpToMessageId`, `Set<String> pinned = const {}`):

```dart
  /// 300 rows alternating one-line and eight-line texts, so any
  /// "average row height" guess is wrong by design.
  void seedVaried(FakeChatRepository repo, {String? newestRepliesTo}) {
    final base = DateTime.now().subtract(const Duration(days: 2));
    for (var i = 0; i < 300; i++) {
      final tall = i.isOdd ? '\nline\nline\nline\nline\nline\nline\ntall' : '';
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: i % 4 == 0 ? 'user-a' : 'partner',
        content: 'message $i$tall',
        createdAt: base.add(Duration(minutes: i * 3)),
        replyToMessageId: i == 299 ? newestRepliesTo : null,
        quotedText: i == 299 && newestRepliesTo != null ? 'quoted parent' : null,
      );
    }
  }

  Future<void> pumpUntilLanded(WidgetTester tester, String text) async {
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final f = find.textContaining(text);
      if (f.evaluate().isNotEmpty) {
        final rect = tester.getRect(f.first);
        if (rect.top >= 0 && rect.bottom <= 1400) return;
      }
    }
  }

  bool highlighted(WidgetTester tester, String text) =>
      tester
          .widget<MessageBubble>(
            find.ancestor(
              of: find.textContaining(text).first,
              matching: find.byType(MessageBubble),
            ),
          )
          .isHighlighted;

  testWidgets('tapping a reply quote lands on and flashes a parent 250 rows back', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedVaried(repo, newestRepliesTo: 'm50');
    final container = await pumpChat(tester, repo);
    expect(find.textContaining('message 50'), findsNothing, reason: 'not loaded yet');

    await tester.tap(find.text('quoted parent'));
    await pumpUntilLanded(tester, 'message 50');

    final rect = tester.getRect(find.textContaining('message 50').first);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(1400));
    expect(highlighted(tester, 'message 50'), isTrue);
    await tester.pump(const Duration(seconds: 2));
    await tearDownChat(tester, container);
  });

  testWidgets('the pinned banner reaches an unloaded, deleted pin (Review Focus 2)', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedVaried(repo);
    repo.serverMessages['m10'] = repo.serverMessages['m10']!.copyWith(
      deletedAt: DateTime.now(),
      content: '',
    );
    repo.pinnedMessageIds.add('m10');
    final container = await pumpChat(tester, repo);

    // Banner label for a deleted partner message.
    await tester.tap(find.text('This message was deleted').first);
    await pumpUntilLanded(tester, 'This message was deleted');
    // Two now: the banner and the tombstone row.
    expect(find.text('This message was deleted'), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 2));
    await tearDownChat(tester, container);
  });

  testWidgets('a quote whose parent no longer exists says so', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedVaried(repo, newestRepliesTo: 'ghost');
    final container = await pumpChat(tester, repo);
    await tester.tap(find.text('quoted parent'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Couldn't find that message."), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tearDownChat(tester, container);
  });

  testWidgets('initialJumpToMessageId lands precisely on a far target', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedVaried(repo);
    final container = await pumpChat(tester, repo, initialJumpToMessageId: 'm7');
    await pumpUntilLanded(tester, 'message 7\n');
    final rect = tester.getRect(find.textContaining('message 7\n').first);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(1400));
    await tester.pump(const Duration(seconds: 2));
    await tearDownChat(tester, container);
  });
```

(Check how `MessageBubble` renders the quote: `find.text('quoted parent')` must match the quoted-preview text widget; if the preview truncates with an ellipsis via a different widget, use `find.textContaining('quoted parent')`. `tester.tap` on it hits `UniversalBubble`'s quote tap → `onJumpToParent`.)

Run: `flutter test test/features/chat/chat_screen_jump_convergence_test.dart` → Expected: FAIL — test 1: `message 50` never appears (quote tap returns at `index == -1`); test 2: the tombstone never loads; test 3: no snackbar; test 4: `message 7` is loaded (paging worked) but `rect.top` is negative or the row is unbuilt (`Bad state: No element`).

- [ ] **Step 5: Screen pipeline**

In `_ChatScreenState`, add `bool _jumpLoading = false;` and replace `_jumpToMessage` + `_jumpToMessageAcrossPages` with:

```dart
  /// The one jump entry point: reply quotes, pinned banner, viewer "Go to
  /// message" and initialJumpToMessageId. Loads the target if needed, then
  /// scrolls until its row is built, then ensureVisible + flash (#30).
  Future<void> _jumpToMessage(
    String messageId,
    List<Message> currentMessages,
  ) async {
    if (_tryEnsureMessageVisible(messageId)) return;

    var messages = currentMessages;
    if (!messages.any((m) => m.id == messageId)) {
      setState(() => _jumpLoading = true);
      JumpTargetResult result;
      try {
        result = await ref
            .read(chatControllerProvider(widget.conversation).notifier)
            .ensureMessageLoaded(messageId);
      } finally {
        if (mounted) setState(() => _jumpLoading = false);
      }
      if (!mounted) return;
      if (result != JumpTargetResult.loaded) {
        context.showInfoSnackbar("Couldn't find that message.");
        return;
      }
      messages = ref.read(chatControllerProvider(widget.conversation)).messages;
    }
    await _scrollUntilBuilt(messageId, messages);
  }

  /// Anchored extrapolation: from the built row nearest the target, step
  /// by (index distance × mean built-row extent), jump, let a frame build,
  /// repeat. Each pass measures real rows, so the error shrinks until the
  /// target's GlobalKey is attached; the old single viewport/keys guess
  /// could never converge (RC-11).
  Future<void> _scrollUntilBuilt(
    String messageId,
    List<Message> messages,
  ) async {
    final targetIndex = messages.indexWhere((m) => m.id == messageId);
    if (targetIndex == -1 || !_scrollController.hasClients) return;
    final indexById = <String, int>{
      for (var i = 0; i < messages.length; i++) messages[i].id: i,
    };

    for (var attempt = 0; attempt < 16; attempt++) {
      if (_tryEnsureMessageVisible(messageId)) return;
      final anchor = _nearestBuiltRow(targetIndex, indexById);
      if (anchor == null) break;
      final position = _scrollController.position;
      final estimate =
          anchor.scrollOffset +
          (targetIndex - anchor.index) * anchor.meanExtent;
      _scrollController.jumpTo(
        estimate.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    _tryEnsureMessageVisible(messageId);
  }

  /// The built row with the index closest to [targetIndex], its scroll
  /// offset (centred) and the mean extent of all built rows.
  ({int index, double scrollOffset, double meanExtent})? _nearestBuiltRow(
    int targetIndex,
    Map<String, int> indexById,
  ) {
    int? bestIndex;
    RenderBox? bestBox;
    var extentSum = 0.0;
    var extentCount = 0;
    for (final entry in _messageKeys.entries) {
      final index = indexById[entry.key];
      final context = entry.value.currentContext;
      if (index == null || context == null) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      extentSum += box.size.height;
      extentCount++;
      if (bestIndex == null ||
          (index - targetIndex).abs() < (bestIndex - targetIndex).abs()) {
        bestIndex = index;
        bestBox = box;
      }
    }
    if (bestIndex == null || bestBox == null || extentCount == 0) return null;
    final viewport = RenderAbstractViewport.maybeOf(bestBox);
    if (viewport == null) return null;
    // Rows carry a 3/12px top padding inside their box; the date separator
    // sits outside it, so the mean slightly under-estimates — the loop's
    // next measurement corrects for it.
    return (
      index: bestIndex,
      scrollOffset: viewport.getOffsetToReveal(bestBox, 0.5).offset,
      meanExtent: extentSum / extentCount,
    );
  }
```

Imports: `package:flutter/scheduler.dart` (for `SchedulerBinding`), `package:flutter/rendering.dart` (for `RenderAbstractViewport`; check it is not already available through material — `RenderAbstractViewport` is exported by `package:flutter/rendering.dart`, and `material.dart` re-exports `widgets.dart` which exports `rendering.dart`'s public API, so the explicit import is only needed if the analyzer complains).

In `build`, the initial-jump post-frame callback becomes `(_) => unawaited(_jumpToMessage(initialJumpId, state.messages))`. Delete `_jumpToMessageAcrossPages` entirely.

Loading affordance — add to the body `Stack` right after the header `Positioned`:

```dart
                if (_jumpLoading)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + headerHeight + 8,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Material(
                          color: Theme.of(context).chatControlSurface,
                          borderRadius: BorderRadius.circular(999),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Finding that message…',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
```

- [ ] **Step 6: Run everything that touches jumps**

Run: `flutter test test/features/chat/chat_screen_jump_convergence_test.dart test/features/chat/chat_screen_initial_jump_test.dart test/features/chat/chat_controller_test.dart test/features/chat/chat_screen_message_actions_test.dart test/features/chat/message_reply_fields_test.dart`
Expected: PASS. (`chat_screen_initial_jump_test.dart`'s "pages backward" case now pages with `jumpPageSize` 200 against a 5-row page size and still finds `message 0`; it needs no edit.)

- [ ] **Step 7: Checkpoint**

`flutter analyze lib/features/chat/config/chat_config.dart lib/features/chat/presentation/state/chat_state.dart lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/support/chat_test_harness.dart | grep -E '^\s*(error|warning) '` → nothing. No commit.

---

### Task 14: Whole-wave verification

**Files:** none new.

- [ ] **Step 1: Run the chat suites**

Run: `flutter test test/features/chat test/core/ui/layout test/core/notifications`
Expected: all PASS. Any failure in a pre-existing test must be explained in terms of a behaviour this plan deliberately changed (edited label, footer on group ends, single wallpaper gradient, measured reserve) — otherwise it is a regression to fix.

- [ ] **Step 2: Analyze every touched file**

Run: `flutter analyze lib/features/chat lib/core/ui/layout lib/core/notifications/services/onesignal_service.dart lib/core/widgets/universal_bubble.dart | grep -E '^\s*(error|warning) '`
Expected: no output.

- [ ] **Step 3: Diff hygiene**

Run: `git diff --stat -- lib test` and confirm no file outside the File Structure list changed; run `git diff -- lib/features/chat/presentation/screens/chat_screen.dart | grep -c '^[-+]'` and eyeball the diff for reflowed-but-unchanged lines (none allowed). No commit (the owner commits).

---

## Owner deploy steps

- None for this wave: no migration, no edge-function change, no new repository method (the jump lookup reuses Plan 1a's `getMessagesByIds`).
- Optional later (Task 12 note): iOS Notification Service Extension + an `ack-chat-delivery` edge function for true background delivery acks.

## Self-review

1. **Spec coverage** — #30 → Task 13; #31 → Task 1; #32 → Tasks 9 + 10; #33 → Task 8; #34 → Task 2; #35 → Task 3; #36 → Tasks 11 + 12; #37 → Task 4; #38 → Tasks 5, 6, 7. Every issue maps to a task; two rulings are recorded inline (no "messages around id" window — Task 13; ticks on group ends rather than every bubble — Task 11; links: no span long-press — Task 4).
2. **Placeholder scan** — Task 6 Step 2 says "the existing body of the old `_buildWallpaper`, with ONE change" and spells out that change; Task 7 Step 2 says "moved here verbatim" for the content Column's children (a move, not new code). No TBD/TODO.
3. **Type consistency** — `showsDeliveryStatus`/`thumbnailDecodeSize` live in `message_status_rule.dart` (Tasks 5, 11); `bottomOverlayHeight` is the field name in Tasks 8 and 10; `JumpTargetResult`/`ensureMessageLoaded`/`jumpPageSize` match between Task 13's controller test and implementation; harness seams (`editHistory`, `hiddenFromPages`, `getMessagesError`, `seedIncoming(editedAt/replyToMessageId/quotedText)`) are each introduced before use (Tasks 1, 13); `getMessagesCalls`/`getMessagesByIds`/`_oldestFetchedCursor`/`isOlderThanCursor` are consumed from Plan 1a, never re-declared.
5. **Cross-plan order** — Task 3 puts the over-limit refusal above the send haptic in `_send` (Plan 4 Task 11 depends on it); Task 10's `_syncArrivals` is the shape Plan 4 Tasks 7/8 edit; Task 12 extends Plan 1b's constructor rather than replacing it; Task 13 edits Plan 1a's `loadMoreMessages` by two lines.
4. **Review Focus** — each of the five lines names its owning task and that task carries the test (Task 4 long-URL wrap; Task 13 deleted pin; Task 10 more-unread-than-loaded + pill above the indicator; Task 3 mid-text caret).
