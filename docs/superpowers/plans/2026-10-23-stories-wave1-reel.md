# Stories Wave 1 — Reel (Story Viewer) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the story reel follow the story on screen by id, survive refreshes, close exactly once, count a story as seen only when it actually appears, recover from failed media, and add the owner actions and labels the reference apps have (delete from your own reel, author and time, Seen, resume at first unseen).

**Architecture:** All reel behaviour stays in `story_reel_screen.dart` (one `ConsumerStatefulWidget`), but its state machine changes. The screen holds `_current` (the `StoryItem` on screen) and reconciles every new list by id through `ref.listenManual`. Pausing becomes a set of independent causes. Each item moves through `loading → ready | failed`, where "ready" means the first decoded image frame or an initialized video. `_close()` is a one-shot latch that pops only its own route. The keyset pager keeps its previous data during a refresh (`copyWithPrevious`), and `loadMore()` shares one future while a page is in flight. Small new widgets carry the byline and the Seen chip (`story_reel_header.dart`). The progress bars gain a `viewed` input and a fixed white palette.

**Tech Stack:** Flutter 3.29.1, flutter_riverpod 2.6.1 (StateNotifier pager, `ConsumerStatefulWidget`), Supabase (via `StoryReadGateway` / `ChatRepository` fakes in tests), flutter_test widget tests.

**Spec:** `docs/reviews/2026-10-23-stories-robustness-review.md` (Wave 1 and the owner rulings), `docs/reviews/2026-10-23-stories-review/02_watching.md`, `07a_verification_client.md` (groups A–F), `06_standards_checklist.md` (#6–#11, #15, #18), `05_security_privacy.md` #7, and `lib/architecture/STORIES.md` §4.1, §5.2, §5.3 and §5.5 (amended in Task 19).

## Global Constraints

- Work in the **main working tree** on `main`. The user has unrelated uncommitted edits (`git status` at start: `ios/Podfile.lock`, `games_docs.dart`, `app_router.dart`, `chat_screen.dart`, `planning_home_screen.dart`, and others). Never revert, stash, stage or reformat them. Touch only the files each task names.
- **No commits.** Every "Commit" step in the standard template is replaced by "Run tests". Nothing is staged.
- **Never `dart format` a pre-existing file.** The repo uses an older formatter, and formatting reflows whole files. Run `dart format` only on files this plan creates (listed under each task as "Create").
- **TDD:** write the test, run it, and **see it fail** (or fail to compile, where noted) before writing production code. Where a test is a regression guard that already passes, the step says so.
- **Design tokens:** spacing uses `Spacing.*`, icon sizes `IconSizes.*`, radii `BorderRadiusTokens.*` (`lib/app/theme/design_tokens.dart`). Displayed dates and times use `MyDateFormat` (`lib/core/utils/date_formatter.dart`), and a date or time sharing a line with other text is joined with `MyDateFormat.join` (`' - '`). The reel is a fixed black media surface in both themes, so its foreground is literal `Colors.white` / white-with-alpha (as today). `theme.appColors.white` is themed (dark = `0xFF121212`) and is exactly the dark-mode bug Task 14 fixes, so do not use it on the reel.
- **State via Riverpod.** No new state-management packages, and no new dependencies at all.
- **SQL:** none is expected. If any check needs a database, use only local `attune_spec3a`, never `attune_test`.
- **Regression gate:** every existing test in `test/features/stories/**`, `test/features/timeline/**` and `test/features/couple_map/**` stays green. Only these existing test edits are allowed:
  - Task 8 adds `imageProviderBuilder: kitInstantImage` to three harness constructions (no assertion changes).
  - Task 11 flips the one test that pins "author mode never shows delete" (owner ruling 2).
- User-facing copy stays plain English, sentence case, as the existing reel strings are (the l10n extraction is a separate gate item).
- Shared/core files touched: `story_providers.dart` (Tasks 4 and 7, a shared pager used by the calendar day sheet) and `message_bubble.dart` (Task 15, a one-argument change). Both carry a regression note in their task.

## Review Focus

Five conditions the spec implies but no requirement names. Each is most likely to bite a real person, and each is pinned by a test in the owning task:

1. **Archive key swap mid-view:** the current item's `media_key` changes under an open reel (archive swap plus signal). Retry must sign the *new* key, not the cached old one. Test in Task 9; the URL cache is keyed by storage key in Task 10.
2. **Interruption during a dialog or while typing:** the app is backgrounded and foregrounded while the Delete dialog (or the reply keyboard) is open. The reel must stay paused until the dialog or keyboard is gone. Test in Task 6.
3. **Delete while offline:** the delete RPC fails. The story stays on screen, the person is told, and Delete works again. A delete that succeeds but whose refetch fails still steps off the story. Tests in Tasks 2 and 4.
4. **Everything already seen:** a partner reel where every story is seen opens at the oldest (it does not close and does not start at the end). Test in Task 15.
5. **Very long partner name:** the byline ellipsizes, with no RenderFlex overflow, and the buttons stay reachable. Test in Task 12.

## Spec rulings made by this plan

Owner rulings 2, 3 and 6 are binding. Where they or the review leave a choice, the plan rules as follows:

- **Opening position:**
  - First-unseen applies to the **partner's active reel only**, falling back to the oldest when everything is seen.
  - Your own reel, a plain calendar day and the map still open at the oldest.
  - A story reply opens its day at the quoted story.
  - STORIES.md §5.5 is amended (Task 19).
- **Delete:** a visible trash button in every mode where the story is yours. The review suggested putting it behind a ⋯ menu. The plan keeps the button because the existing keys, a11y tests and the calendar/map affordance already use it. §5.3 is amended.
- **Seen:** shown on the poster's own story whenever `has_been_viewed` is true. The server already masks the flag when receipts are off, so there is no client logic.
- **Signed URLs:** reuse within the reel screen only, by storage key, for under 540 s (§4.1 is amended). Cross-screen caching stays Wave 4.
- **Screen-reader pause:**
  - It is an explicit toggle plus a named "Pause story" / "Play story" action, persisting across stories.
  - The plan does not stop auto-advance whenever `accessibleNavigation` is on (06 #11's alternative), to avoid two divergent playback modes.
- **Video after a long pause:**
  - A mid-play error shows Retry, which re-signs and restarts the item.
  - "Resume at the saved position" (02 #15) is left out (YAGNI).
- **Left out as not one-line:** 02 #19 (reduce-motion 1 s steps), #20 (quote-tap in-flight guard and network copy), #24 (RTL and l10n), #25 (skip re-marking; its expiry check would break calendar tests that use past dates) and #26 (ring invalidation after close). Per-author day rings opening at the right item is Wave 4, though `initialStoryItemId` now makes it a one-line follow-up.

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `lib/features/stories/presentation/screens/story_reel_screen.dart` (modify) | Reel state machine: identity, pause causes, load phases, close latch, actions | 1–3, 5–18 |
| `lib/features/stories/presentation/providers/story_providers.dart` (modify) | `_KeysetPager`: keep data on refresh; shared `loadMore` future; no loadMore during refresh | 4, 7 |
| `lib/features/stories/presentation/widgets/story_progress_bars.dart` (modify) | Fixed white palette; `viewed` (faded) segments; per-segment keys | 14 |
| `lib/features/stories/presentation/widgets/story_reel_header.dart` (create) | `storyPostedLabel()`, `StoryReelHeader` (byline, Seen chip, trailing actions) | 12, 13 |
| `lib/features/chat/presentation/widgets/message_bubble.dart` (modify) | Story-quote tap passes `initialStoryItemId` | 15 |
| `lib/architecture/STORIES.md` (modify) | §4.1, §5.2, §5.3, §5.5 amendments per owner rulings | 19 |
| `test/features/stories/support/reel_test_kit.dart` (create) | Scriptable gateway, fake player, test images, harness, readers | 1, 6, 8, 9, 12, 15 |
| `test/features/stories/story_reel_identity_test.dart` (create) | R1 identity, reconcile, delete step-off, composer | 1–3, 11 |
| `test/features/stories/story_pager_refresh_test.dart` (create) | Provider: refresh keeps data; shared loadMore | 4, 7 |
| `test/features/stories/story_reel_refresh_test.dart` (create) | Reel during refresh, error/empty states | 4 |
| `test/features/stories/story_reel_close_test.dart` (create) | One-shot close, modal pause, page boundary | 5–7 |
| `test/features/stories/story_reel_load_test.dart` (create) | First-frame seen, failure UI, backoff, video errors, URL reuse | 8–10 |
| `test/features/stories/story_reel_chrome_test.dart` (create) | Byline, Seen chip, bars, a11y pause, gestures, start position | 12–17 |
| `test/features/stories/story_progress_bars_test.dart` (create) | Bars palette and faded segments | 14 |
| `test/features/stories/story_reel_reply_retry_test.dart` (create) | Reply idempotency and timeout | 18 |
| `test/features/stories/story_reel_test.dart`, `story_calendar_test.dart` (modify, minimal) | Harness seam (Task 8); the one owner-ruling flip (Task 11) | 8, 11 |

## Before you start

- [ ] **Baseline:** run the regression suites and record the pass counts. They must all pass before Task 1.

```bash
cd /Users/user/attune
flutter test test/features/stories test/features/timeline test/features/couple_map
```
Expected: all pass (the review recorded 169/169 for stories and timeline). If anything already fails, stop and report it; do not fix it under this plan.

---

### Task 1: R1 — track the story on screen by id; reconcile every refreshed list

Fixes 02 #4, #5 (the per-frame loop's trigger) and #16; it is 07a group A.

**Files:**
- Create: `test/features/stories/support/reel_test_kit.dart`
- Create: `test/features/stories/story_reel_identity_test.dart`
- Modify: `lib/features/stories/presentation/screens/story_reel_screen.dart`:
  - state fields at `:254-337`;
  - `initState` at `:339-355`;
  - `_startItemAsync` at `:387-516`;
  - `_startTicker` at `:564-610`;
  - `_advance` / `raceAdvanceForTest` / `_advanceAtEndOfPage` / `_retreat` at `:707-868`;
  - `build` at `:1093-1182`;
  - `_ReelBody` at `:1185-1267`;
  - `_MediaView` at `:1648-1654`.

**Interfaces:**
- Produces, used by every later task:
  - `StoryItem? _current` is the story on screen.
  - `List<StoryItem> _liveItems()` returns the list currently backing the screen.
  - `int _currentIndexIn(List<StoryItem>)` finds `_current` by id.
  - `void _onItemsChanged(List<StoryItem>? raw)` reconciles a new list.
  - `void _stopMedia()` stops playback and bumps `_generation`.
  - `Future<void> _advance(int fromGeneration)` reads the live list.
  - `void _retreat()` steps back on the live list.
  - `bool _started` is the playback-started latch.
  - `ProviderListenable<AsyncValue<List<StoryItem>>> _itemsProvider()` is the pager this screen watches.
  - The `Image` on screen carries `key: ValueKey('story-reel-image')`.
- Produces (test kit), used by all later test files:
  - `ScriptedReelGateway`, `KitPlayer`, `KitPlayers`, `KitMode`, `ReelRig`;
  - `kitItems()`, `kitItem()`, `pumpReel()`, `kitReel()`, `settle()`;
  - `tapRight()`, `tapLeft()`, `shownItemId()`, `bars()`;
  - `typeReply()`, `sendReply()`, `replyFocused()`, `confirmDelete()`;
  - the constants `kitMe`, `kitPartner`, `kitRel`, `kitDay`, `kitUser`.

- [ ] **Step 1: Create the test kit**

Create `test/features/stories/support/reel_test_kit.dart`:

```dart
// Shared fixtures for the Wave 1 reel suites
// (docs/superpowers/plans/2026-10-23-stories-wave1-reel.md): a scriptable
// gateway whose lists change under an open reel, a change signal the test
// fires, a fake video player, base routes under the reel, and readers for
// "which story is on screen". House pattern: fake the gateway, never the
// Supabase client or Riverpod internals.
import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart'
    show chatRepositoryProvider;
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/features/stories/presentation/widgets/story_progress_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../chat/support/chat_test_harness.dart' show FakeChatRepository;

const kitMe = 'me-1';
const kitPartner = 'partner-1';
const kitRel = 'rel-1';
final kitDay = DateTime.utc(2026, 10, 20);

const kitUser = User(
  id: kitMe,
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

/// The item id inside a signed URL or storage key built by this kit.
String? kitIdFrom(String urlOrKey) =>
    RegExp(r'story-media/([^/.]+)\.jpg').firstMatch(urlOrKey)?.group(1);

StoryItem kitItem(
  String id, {
  String author = kitPartner,
  String mediaType = 'image',
  required DateTime createdAt,
  bool viewed = false,
  String? mediaKey,
}) {
  return StoryItem(
    id: id,
    clientStoryId: 'client-$id',
    relationshipId: kitRel,
    authorId: author,
    mediaType: mediaType,
    mediaKey: mediaKey ?? 'story-media/$id.jpg',
    thumbnailKey: 'story-media/$id-thumb.jpg',
    mediaWidth: 1080,
    mediaHeight: 1920,
    durationMs: mediaType == 'video' ? 4000 : null,
    occurredOn: kitDay,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 24)),
    hasBeenViewed: viewed,
  );
}

/// Oldest first, one minute apart, starting [start] (default: 3 h ago).
List<StoryItem> kitItems(
  List<String> ids, {
  String author = kitPartner,
  Set<String> videos = const {},
  Set<String> viewed = const {},
  DateTime? start,
}) {
  final base =
      start ?? DateTime.now().toUtc().subtract(const Duration(hours: 3));
  return [
    for (var i = 0; i < ids.length; i++)
      kitItem(
        ids[i],
        author: author,
        mediaType: videos.contains(ids[i]) ? 'video' : 'image',
        createdAt: base.add(Duration(minutes: i)),
        viewed: viewed.contains(ids[i]),
      ),
  ];
}

/// Server truth the test can change under an open reel, then announce with
/// [emitSignal] (a partner's delete, a new post, an expiry, a seen flip).
class ScriptedReelGateway implements StoryReadGateway {
  ScriptedReelGateway({
    List<StoryItem> active = const [],
    List<StoryItem> day = const [],
  }) : active = [...active],
       day = [...day];

  final List<StoryItem> active;
  final List<StoryItem> day;
  int pageSize = 50;

  int listCalls = 0;

  /// Holds the very first list call (the reel's initial load).
  Completer<void>? firstLoadGate;

  /// FIFO gates for later FIRST-page fetches (signal or manual refreshes).
  final List<Completer<void>> refreshGates = [];

  /// Holds every later-page fetch (loadMore) while set.
  Completer<void>? nextPageGate;

  /// One-shot error thrown by the next list call.
  Object? nextListError;

  final _signals = StreamController<void>.broadcast();
  void emitSignal() => _signals.add(null);

  final List<String> signCalls = [];
  final Set<String> signFailKeys = {};
  int signCallsFor(String id) =>
      signCalls.where((k) => kitIdFrom(k) == id).length;

  final List<String> marked = [];
  final List<String> deleteCalls = [];
  Completer<void>? deleteGate;
  Object? deleteError;
  final Map<String, StoryReplyTarget> replyTargets = {};

  Future<StoryItemPage> _page(
    List<StoryItem> source,
    StoryPageCursor? after,
  ) async {
    final call = listCalls++;
    if (call == 0 && firstLoadGate != null) await firstLoadGate!.future;
    if (after == null && call > 0 && refreshGates.isNotEmpty) {
      await refreshGates.removeAt(0).future;
    }
    if (after != null && nextPageGate != null) await nextPageGate!.future;
    final error = nextListError;
    if (error != null) {
      nextListError = null;
      throw error;
    }
    final start =
        after == null ? 0 : source.indexWhere((i) => i.id == after.id) + 1;
    final end = (start + pageSize).clamp(0, source.length);
    final items = source.sublist(start, end);
    return StoryItemPage(
      items: items,
      nextCursor: end < source.length ? items.last.cursor : null,
    );
  }

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) => _page(active.where((i) => i.authorId == authorId).toList(), after);

  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  }) => _page(List.of(day), after);

  @override
  Future<String?> signMediaUrl(String storageKey) async {
    signCalls.add(storageKey);
    if (signFailKeys.contains(storageKey)) return null;
    return 'https://signed.example/$storageKey';
  }

  @override
  Future<void> markViewed({required String storyItemId}) async =>
      marked.add(storyItemId);

  @override
  Future<void> deleteItem({required String storyItemId}) async {
    deleteCalls.add(storyItemId);
    if (deleteGate != null) await deleteGate!.future;
    final error = deleteError;
    if (error != null) {
      deleteError = null;
      throw error;
    }
    active.removeWhere((i) => i.id == storyItemId);
    day.removeWhere((i) => i.id == storyItemId);
  }

  @override
  Future<StoryReplyTarget?> getReplyTarget({required String storyItemId}) async =>
      replyTargets[storyItemId];

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async => const [];

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) async => const [];

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      _signals.stream;

  @override
  void disposeChannel(String relationshipId) {}

  @override
  void disposeAllChannels() {}
}

/// A [StoryItemPlayer] the test drives: init can fail or hang, and
/// [complete] fires onEnded once.
class KitPlayer implements StoryItemPlayer {
  KitPlayer(this.uri, {this.initError, this.hangInit = false});

  final Uri uri;
  final Object? initError;
  final bool hangInit;
  bool playing = false;
  bool disposed = false;
  Duration _position = Duration.zero;
  final _ended = StreamController<void>.broadcast();

  String get itemId => kitIdFrom(uri.toString())!;

  @override
  Duration duration = const Duration(seconds: 4);

  @override
  Future<void> initialize() async {
    if (hangInit) await Completer<void>().future;
    final error = initError;
    if (error != null) throw error;
  }

  @override
  Duration get position => _position;

  @override
  void play() => playing = true;

  @override
  void pause() => playing = false;

  @override
  Stream<void> get onEnded => _ended.stream;

  void complete() {
    _position = duration;
    playing = false;
    if (!_ended.isClosed) _ended.add(null);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    playing = false;
    await _ended.close();
  }
}

class KitPlayers {
  final List<KitPlayer> all = [];
  Object? Function(String itemId)? initErrorFor;
  bool Function(String itemId)? hangInitFor;

  KitPlayer get last => all.last;

  StoryItemPlayer Function(Uri uri) get factory => (uri) {
    final id = kitIdFrom(uri.toString())!;
    final player = KitPlayer(
      uri,
      initError: initErrorFor?.call(id),
      hangInit: hangInitFor?.call(id) ?? false,
    );
    all.add(player);
    return player;
  };
}

enum KitMode { partnerReel, ownReel, day, places }

class ReelRig {
  ReelRig({
    required this.navigatorKey,
    required this.chat,
    required this.players,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final FakeChatRepository chat;
  final KitPlayers players;
}

Widget kitReel({
  required KitMode mode,
  required KitPlayers players,
  List<StoryItem> placeItems = const [],
  Duration hold = const Duration(seconds: 1),
}) {
  return switch (mode) {
    KitMode.partnerReel => StoryReelScreen(
      relationshipId: kitRel,
      authorId: kitPartner,
      videoPlayerFactory: players.factory,
      imageHoldDuration: hold,
    ),
    KitMode.ownReel => StoryReelScreen(
      relationshipId: kitRel,
      authorId: kitMe,
      isOwnReel: true,
      videoPlayerFactory: players.factory,
      imageHoldDuration: hold,
    ),
    KitMode.day => StoryReelScreen.forDay(
      relationshipId: kitRel,
      occurredOn: kitDay,
      videoPlayerFactory: players.factory,
      imageHoldDuration: hold,
    ),
    KitMode.places => StoryReelScreen.forPlaces(
      relationshipId: kitRel,
      items: placeItems,
      videoPlayerFactory: players.factory,
      imageHoldDuration: hold,
    ),
  };
}

class _KitPage extends StatelessWidget {
  const _KitPage(this.name);
  final String name;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(name)));
}

/// Pumps [below] as a real route stack (first = home), then pushes the reel
/// on top, so a close that pops too far is observable.
Future<ReelRig> pumpReel(
  WidgetTester tester, {
  required ScriptedReelGateway gateway,
  KitMode mode = KitMode.partnerReel,
  List<StoryItem> placeItems = const [],
  List<String> below = const ['HOME'],
  Duration hold = const Duration(seconds: 1),
  KitPlayers? players,
  ThemeData? theme,
  List<Override> extraOverrides = const [],
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  final chat = FakeChatRepository(currentUserId: kitMe);
  final kitPlayers = players ?? KitPlayers();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(kitUser),
        storyReadGatewayProvider.overrideWithValue(gateway),
        chatRepositoryProvider.overrideWithValue(chat),
        ...extraOverrides,
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: theme ?? AppTheme.lightTheme,
        home: _KitPage(below.first),
      ),
    ),
  );
  for (final name in below.skip(1)) {
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => _KitPage(name)),
      ),
    );
    await tester.pumpAndSettle();
  }
  unawaited(
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder:
            (_) => kitReel(
              mode: mode,
              players: kitPlayers,
              placeItems: placeItems,
              hold: hold,
            ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await settle(tester);
  return ReelRig(navigatorKey: navigatorKey, chat: chat, players: kitPlayers);
}

/// Lets sign / load / mark microtasks and one short frame run.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> tapRight(WidgetTester tester) async {
  final size = tester.getSize(find.byType(StoryReelScreen));
  await tester.tapAt(Offset(size.width * 0.8, size.height * 0.5));
  await settle(tester);
}

Future<void> tapLeft(WidgetTester tester) async {
  final size = tester.getSize(find.byType(StoryReelScreen));
  await tester.tapAt(Offset(size.width * 0.2, size.height * 0.5));
  await settle(tester);
}

/// The id of the photo the reel is showing (or trying to show), or null.
String? shownItemId(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('story-reel-image'));
  if (finder.evaluate().isEmpty) return null;
  final provider = tester.widget<Image>(finder).image;
  return provider is NetworkImage ? kitIdFrom(provider.url) : null;
}

({int index, int count}) bars(WidgetTester tester) {
  final b = tester.widget<StoryProgressBars>(find.byType(StoryProgressBars));
  return (index: b.currentIndex, count: b.itemCount);
}

Future<void> typeReply(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('story-reel-reply-field')),
    text,
  );
  await settle(tester);
}

Future<void> sendReply(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('story-reel-reply-send')));
  await settle(tester);
}

bool replyFocused(WidgetTester tester) =>
    tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(const ValueKey('story-reel-reply-field')),
            matching: find.byType(EditableText),
          ),
        )
        .focusNode
        .hasFocus;

Future<void> confirmDelete(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('story-reel-delete')));
  await settle(tester);
  await tester.tap(find.text('Delete'));
  await settle(tester);
}
```

- [ ] **Step 2: Write the failing identity tests**

Create `test/features/stories/story_reel_identity_test.dart`:

```dart
// R1 (07a group A): the reel follows the story on screen by id while its
// list is refetched underneath it (review 02 #1, #4, #5, #16).
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R1: the reel follows the story on screen, not a position', () {
    testWidgets(
      'a reply after the partner deletes an earlier story quotes the story '
      'on screen',
      (tester) async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']));
        final rig = await pumpReel(
          tester,
          gateway: gateway,
          hold: const Duration(seconds: 30),
        );
        await tapRight(tester);
        expect(shownItemId(tester), 'b');

        gateway.active.removeWhere((i) => i.id == 'a');
        gateway.emitSignal();
        await settle(tester);

        expect(shownItemId(tester), 'b');
        expect(bars(tester), (index: 0, count: 2));
        await typeReply(tester, 'where is this?');
        await sendReply(tester);
        expect(rig.chat.lastSendArgs!.storyItemId, 'b');
      },
    );

    testWidgets('when the story on screen is deleted, the next one plays', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      await tapRight(tester);
      expect(shownItemId(tester), 'b');

      gateway.active.removeWhere((i) => i.id == 'b');
      gateway.emitSignal();
      await settle(tester);

      expect(shownItemId(tester), 'c');
      expect(bars(tester), (index: 1, count: 2));
    });

    testWidgets(
      'the last story deleted under me stops its sound and closes the reel',
      (tester) async {
        final gateway = ScriptedReelGateway(
          active: kitItems(['v'], videos: {'v'}),
        );
        final rig = await pumpReel(
          tester,
          gateway: gateway,
          below: ['HOME', 'CHAT'],
        );
        final player = rig.players.last;
        expect(player.playing, isTrue);

        gateway.active.clear();
        gateway.emitSignal();
        await settle(tester);

        expect(player.playing, isFalse, reason: 'no audio under an empty reel');
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(StoryReelScreen), findsNothing);
        expect(find.text('CHAT'), findsOneWidget);
      },
    );

    testWidgets('auto-advance follows the live list, never a stale copy', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 1));
      expect(shownItemId(tester), 'a');

      gateway.active.removeWhere((i) => i.id == 'b');
      gateway.emitSignal();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 1100));
      await settle(tester);

      expect(shownItemId(tester), 'c');
    });

    testWidgets(
      'a first story that fails to load is not re-requested every frame',
      (tester) async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']))
          ..signFailKeys.add('story-media/a.jpg');
        await pumpReel(tester, gateway: gateway);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(gateway.signCallsFor('a'), 1);
      },
    );
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_identity_test.dart`
Expected: 5 FAIL. Each fails on its first assertion:
1. bars `(index: 1, count: 2)`;
2. shown `b`;
3. `player.playing` is still true;
4. shown `b`;
5. `signCallsFor('a')` ≥ 20.

- [ ] **Step 4: Implement identity tracking**

In `story_reel_screen.dart`:

(a) Fields: directly under `int _index = 0;` (`:255`) add:

```dart
  /// The story on screen. Delete, Reply, the bars and auto-advance act on
  /// this item, found by id in the live list, never by position: the list
  /// is refetched underneath the reel (review 02 #1/#4, 07a group A).
  StoryItem? _current;

  /// Playback starts once, from the first non-empty list. Replaces the old
  /// render-state heuristic that restarted a failed first item every frame
  /// (review 02 #5).
  bool _started = false;
```

(b) `initState`: after the `_replyFocusNode.addListener(...)` block, add:

```dart
    if (!_placesMode) {
      ref.listenManual<AsyncValue<List<StoryItem>>>(
        _itemsProvider(),
        (_, next) => _onItemsChanged(next.valueOrNull),
      );
    }
```

(c) Add these members (place them right after `_setForeground`):

```dart
  /// The pager backing this screen (author or day mode).
  ProviderListenable<AsyncValue<List<StoryItem>>> _itemsProvider() {
    final occurredOn = widget.occurredOn;
    if (occurredOn != null) {
      return storyDayItemsProvider(
        StoryDayKey(
          relationshipId: widget.relationshipId,
          occurredOn: occurredOn,
        ),
      );
    }
    return storyReelPagesProvider(
      StoryReelKey(
        relationshipId: widget.relationshipId,
        authorId: widget.authorId,
      ),
    );
  }

  /// The list backing the screen right now.
  List<StoryItem> _liveItems() => _pagerCurrentItems() ?? const <StoryItem>[];

  int _currentIndexIn(List<StoryItem> items) {
    final id = _current?.id;
    return id == null ? -1 : items.indexWhere((i) => i.id == id);
  }

  /// Reconciles a refreshed list with the story on screen: same story,
  /// new position (and fresh row data); or, when it is gone, stop it and
  /// play the story that followed it, or close when nothing is left.
  void _onItemsChanged(List<StoryItem>? items) {
    final current = _current;
    if (items == null || current == null || !mounted) return;
    final at = items.indexWhere((i) => i.id == current.id);
    if (at >= 0) {
      setState(() {
        _index = at;
        _current = items[at];
      });
      return;
    }
    _stopMedia();
    if (items.isEmpty) {
      _close();
      return;
    }
    _startItem(items, _successorIndex(items, current));
  }

  /// The first story posted after [gone] (lists are oldest-first by
  /// `(created_at, id)`), else the newest one left.
  static int _successorIndex(List<StoryItem> items, StoryItem gone) {
    final at = items.indexWhere(
      (i) =>
          i.createdAt.isAfter(gone.createdAt) ||
          (i.createdAt == gone.createdAt && i.id.compareTo(gone.id) > 0),
    );
    return at == -1 ? items.length - 1 : at;
  }

  /// Stops whatever is playing without choosing what comes next. Bumps
  /// [_generation] so every late callback for it is ignored.
  void _stopMedia() {
    _generation++;
    _tickTimer?.cancel();
    _tickTimer = null;
    unawaited(_endedSub?.cancel());
    _endedSub = null;
    final player = _player;
    _player = null;
    if (player != null) {
      player.pause();
      unawaited(player.dispose());
    }
  }
```

(d) `_startItemAsync`: inside the existing `setState(() { _index = index; ...` add `_current = items[index];` as the first line. Change `_endedSub = player.onEnded.listen(...)`'s body to `unawaited(_advance(generation));`. Change both `_startTicker(generation, items);` calls to `_startTicker(generation);`.

(e) `_startTicker`: change the signature to `void _startTicker(int generation)`, and inside it replace `unawaited(_advance(items, generation));` with `unawaited(_advance(generation));`.

(f) Replace `_advance`, `raceAdvanceForTest`, the head of `_advanceAtEndOfPage`, and `_retreat` with:

```dart
  Future<void> _advance(int fromGeneration) async {
    if (fromGeneration != _generation) return;
    final items = _liveItems();
    final at = _currentIndexIn(items);
    if (at + 1 < items.length) {
      _startItem(items, at + 1);
      return;
    }
    return _advanceAtEndOfPage(fromGeneration);
  }

  @visibleForTesting
  Future<void> raceAdvanceForTest([List<StoryItem>? unused]) async {
    final generation = _generation;
    unawaited(_advance(generation));
    unawaited(_advance(generation));
  }
```

In `_advanceAtEndOfPage`, change the signature to `Future<void> _advanceAtEndOfPage(int fromGeneration) async`. Replace its tail (from `final refreshed = ...` to the end of the `if`/`else`) with:

```dart
    final refreshed = _liveItems();
    final at = _currentIndexIn(refreshed);
    if (at + 1 < refreshed.length) {
      _startItem(refreshed, at + 1);
    } else {
      setState(() => _loadingItem = false);
      _close();
    }
```

```dart
  void _retreat() {
    final items = _liveItems();
    final at = _currentIndexIn(items);
    if (at > 0) _startItem(items, at - 1);
  }
```

(g) `build`: replace the `pagesAsync` ternary's two `ref.watch(...)` arms with `ref.watch(_itemsProvider())`, keeping the places arm. In the `data:` builder, replace the old auto-start block (`if (_index == 0 && !_loadingItem ...) {...}`) and the `clampedIndex` / `currentItem` lines with:

```dart
          if (!_started) {
            _started = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _current != null) return;
              final live = _liveItems();
              if (live.isNotEmpty) _startItem(live, 0);
            });
          }
          final found = _currentIndexIn(items);
          final clampedIndex =
              found >= 0 ? found : _index.clamp(0, items.length - 1);
          final currentItem = _current ?? items[clampedIndex];
```

Change `onTapLeft: () => _retreat(items)` to `onTapLeft: _retreat`, and `onTapRight: () => unawaited(_advance(items, _generation))` to `onTapRight: () => unawaited(_advance(_generation))`. Pass `current: currentItem` to `_ReelBody`.

(h) `_ReelBody`: add `required this.current` (`final StoryItem current;`). In `build`, replace `final item = items[index];` with `final item = current;`.

(i) `_MediaView`: give the photo a key: `Image.network(url, key: const ValueKey('story-reel-image'), fit: ..., errorBuilder: ...)`.

(j) Update the class doc comment above `StoryReelScreen` (`:165-171`) to say "Opens at the OLDEST item (Task 15 changes this for the partner's reel)". Keep it one line; Task 15 rewrites it.

- [ ] **Step 5: Run the new tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_identity_test.dart`
Expected: 5 PASS.

- [ ] **Step 6: Run tests (regression)**

Run: `flutter test test/features/stories test/features/timeline test/features/couple_map`
Expected: all PASS, including the F2 race test (`raceAdvanceForTest(items)` still compiles against the optional parameter) and the F3 paging tests.

---

### Task 2: R1 — delete steps off the deleted story at once; Delete targets the story on screen

Fixes the Critical (02 #1, 07a V1).

**Files:**
- Modify: `lib/features/stories/presentation/screens/story_reel_screen.dart`: `_confirmAndDelete` (`:889-965`), `build` and `_ReelBody` (the delete button).
- Test: `test/features/stories/story_reel_identity_test.dart` (append a group).

**Interfaces:**
- Consumes: `_current`, `_onItemsChanged`, `_liveItems` (Task 1).
- Produces:
  - `final Set<String> _removedIds` holds stories this screen deleted and hides at once.
  - `List<StoryItem> _visible(List<StoryItem> raw)` applies that filter.
  - `bool _deleting`.
  - `Future<void> _refreshPager()` refreshes whichever pager backs the screen (used by Tasks 4 and 11).
  - `_ReelBody.deleting` (bool) disables the delete button.
  - `_confirmAndDelete(StoryItem item)` loses its `items` parameter.

- [ ] **Step 1: Write the failing tests**

Append to `story_reel_identity_test.dart` inside `main()`. Add the import `import 'dart:async';` and `import 'package:attune/features/stories/data/story_read_repository.dart';` at the top.

```dart
  group('R1: Delete acts on the story on screen and steps off it', () {
    testWidgets(
      'deleting in the day reel shows the next story, and a second Delete '
      'removes only the story then on screen',
      (tester) async {
        final gateway = ScriptedReelGateway(
          day: kitItems(['a', 'b', 'c', 'd'], author: kitMe),
        );
        await pumpReel(
          tester,
          gateway: gateway,
          mode: KitMode.day,
          hold: const Duration(seconds: 30),
        );
        await tapRight(tester);
        expect(shownItemId(tester), 'b');

        await confirmDelete(tester);
        expect(gateway.deleteCalls, ['b']);
        expect(shownItemId(tester), 'c');
        expect(bars(tester), (index: 1, count: 3));

        await confirmDelete(tester);
        expect(gateway.deleteCalls, ['b', 'c']);
        expect(shownItemId(tester), 'd');
      },
    );

    testWidgets('deleting the newest story steps back to the one before it '
        '(regression guard)', (tester) async {
      final gateway = ScriptedReelGateway(day: kitItems(['a', 'b'], author: kitMe));
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        hold: const Duration(seconds: 30),
      );
      await tapRight(tester);
      await confirmDelete(tester);
      expect(shownItemId(tester), 'a');
      expect(bars(tester), (index: 0, count: 1));
    });

    testWidgets('Delete is disabled while a delete is in flight', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(day: kitItems(['a', 'b'], author: kitMe))
        ..deleteGate = Completer<void>();
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        hold: const Duration(seconds: 30),
      );
      await confirmDelete(tester);
      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('story-reel-delete')),
      );
      expect(button.onPressed, isNull);

      gateway.deleteGate!.complete();
      await settle(tester);
      expect(gateway.deleteCalls, ['a']);
      expect(shownItemId(tester), 'b');
    });

    testWidgets(
      'a failed delete keeps the story and lets the person try again '
      '(Review Focus 3, regression guard)',
      (tester) async {
        final gateway = ScriptedReelGateway(day: kitItems(['a', 'b'], author: kitMe))
          ..deleteError = StoryApiError.network('offline');
        await pumpReel(
          tester,
          gateway: gateway,
          mode: KitMode.day,
          hold: const Duration(seconds: 30),
        );
        await confirmDelete(tester);
        expect(find.text('Could not delete this story.'), findsOneWidget);
        expect(shownItemId(tester), 'a');
        expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('story-reel-delete')))
              .onPressed,
          isNotNull,
        );
      },
    );
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_identity_test.dart --plain-name "Delete acts on"`
Expected: the first test FAILs (`shownItemId` is `b` after the first delete) and the in-flight test FAILs (`onPressed` is non-null). The two guards PASS.

- [ ] **Step 3: Implement**

(a) Fields (beside `_current`):

```dart
  /// Stories this screen deleted: hidden at once, so the reel steps off
  /// them before, or without, the refetch that confirms it (02 #1).
  final Set<String> _removedIds = {};
  bool _deleting = false;

  List<StoryItem> _visible(List<StoryItem> raw) => _removedIds.isEmpty
      ? raw
      : raw.where((i) => !_removedIds.contains(i.id)).toList();
```

(b) Route every list through the filter. Change `_liveItems()` to `_visible(_pagerCurrentItems() ?? const <StoryItem>[])`. In `initState`'s listener, call `_onItemsChanged(next.valueOrNull == null ? null : _visible(next.valueOrNull!))`. In `build`'s `data:` builder, start with `final items = _visible(raw);`, renaming the builder parameter to `raw`, and run the empty check on the filtered `items`.

(c) Add:

```dart
  /// Re-reads whichever pager backs this screen.
  Future<void> _refreshPager() {
    if (_placesMode) return Future.value();
    final occurredOn = widget.occurredOn;
    if (occurredOn != null) {
      return ref
          .read(
            storyDayItemsProvider(
              StoryDayKey(
                relationshipId: widget.relationshipId,
                occurredOn: occurredOn,
              ),
            ).notifier,
          )
          .refresh();
    }
    return ref
        .read(
          storyReelPagesProvider(
            StoryReelKey(
              relationshipId: widget.relationshipId,
              authorId: widget.authorId,
            ),
          ).notifier,
        )
        .refresh();
  }
```

(d) Replace `_confirmAndDelete` with the version below. The dialog builder is unchanged; copy it verbatim from `:893-912`.

```dart
  Future<void> _confirmAndDelete(StoryItem item) async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this story?'),
        content: const Text(
          'This removes it from the reel and the calendar permanently. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(storyReadGatewayProvider).deleteItem(storyItemId: item.id);
    } catch (_) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this story.')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _deleting = false);

    if (_placesMode) {
      ProviderScope.containerOf(context).invalidate(storyPlacesProvider);
      _stepOffPlaceItem(item.id);
      return;
    }

    // Step off NOW, by id: hide it locally and reconcile, so the screen
    // never keeps showing a story that no longer exists (02 #1). The
    // refetch then confirms server truth.
    _removedIds.add(item.id);
    _onItemsChanged(_liveItems());
    unawaited(_refreshPager());
  }
```

(e) In `build`, set `onDelete: canDeleteCurrent ? () => unawaited(_confirmAndDelete(currentItem)) : null` and pass `deleting: _deleting`. In `_ReelBody`, add `this.deleting = false` and `final bool deleting;`, and set the delete `IconButton`'s `onPressed: deleting ? null : onDelete`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_identity_test.dart`
Expected: all PASS.

- [ ] **Step 5: Run tests (regression)**

Run: `flutter test test/features/stories test/features/couple_map`
Expected: all PASS. In particular `story_calendar_test.dart` "deleting the only item closes" and `story_reel_places_test.dart` "deleting the first of two in places mode shows the survivor".

---

### Task 3: R1 — the composer has its own pause; a tap on the photo while typing only closes the keyboard

Fixes 02 #12, upgraded to High in 07a §3, plus the 02 #27 composer-padding Low.

**Files:**
- Modify: `story_reel_screen.dart`:
  - pause fields at `:270-292`;
  - `_setHeldPaused` / `_setLifecyclePaused` / `_applyPausedTransition` at `:612-647`;
  - the focus listener;
  - `_startItemAsync`'s `_heldPaused = false`;
  - `_sendReply`;
  - `build`'s tap callbacks;
  - `_ReelBody`'s composer `Positioned`.
- Test: `test/features/stories/story_reel_identity_test.dart` (append a group).

**Interfaces:**
- Produces:
  - `enum _PauseCause { hold, lifecycle, composer, modal, accessibility }`.
  - `final Set<_PauseCause> _pauseCauses`.
  - `bool get _paused`.
  - `void _setPaused(_PauseCause cause, bool on)` (used by Tasks 6 and 16).
  - `StoryItem? _replyTarget`.
  - `void _onTapNext()` / `void _onTapBack()` (used by Tasks 16 and 17).
- `_heldPaused`, `_lifecyclePaused`, `_setHeldPaused` and `_setLifecyclePaused` are removed.

- [ ] **Step 1: Write the failing tests**

Append to `story_reel_identity_test.dart`:

```dart
  group('R1: typing a reply has its own pause', () {
    testWidgets('tapping the story while typing only closes the keyboard', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      await typeReply(tester, 'hi');
      expect(replyFocused(tester), isTrue);

      await tapRight(tester);

      expect(shownItemId(tester), 'a');
      expect(replyFocused(tester), isFalse);
    });

    testWidgets('a hold released while typing does not restart the clock', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 1));
      await typeReply(tester, 'hi');

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(StoryReelScreen)),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      expect(shownItemId(tester), 'a');
      expect(replyFocused(tester), isTrue);
    });

    testWidgets("a tap in the reply strip's padding never moves the reel", (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      final send = tester.getRect(
        find.byKey(const ValueKey('story-reel-reply-send')),
      );
      final size = tester.getSize(find.byType(StoryReelScreen));

      await tester.tapAt(Offset(size.width - 4, send.center.dy));
      await settle(tester);

      expect(shownItemId(tester), 'a');
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_identity_test.dart --plain-name "own pause"`
Expected:
1. FAIL: shown `b`.
2. FAIL: shown `b`, because the hold release cleared the shared flag.
3. FAIL: shown `b`.

- [ ] **Step 3: Implement**

(a) Replace the `_heldPaused` / `_lifecyclePaused` fields and the `_paused` getter (`:270-292`) with the code below. Put the enum at file level, above `StoryReelScreen`.

```dart
/// Why the reel is paused. Each cause sets and clears only itself, so one
/// ending (a hold released, the app back in front) never resumes a story
/// another cause still holds (02 #12; the F1 lesson generalised).
enum _PauseCause { hold, lifecycle, composer, modal, accessibility }
```

```dart
  final Set<_PauseCause> _pauseCauses = {};
  bool get _paused => _pauseCauses.isNotEmpty;

  /// The reply this person is typing goes to the story they started it on.
  StoryItem? _replyTarget;
```

(b) Replace `_setHeldPaused` and `_setLifecyclePaused` with:

```dart
  void _setPaused(_PauseCause cause, bool on) {
    final wasPaused = _paused;
    final changed = on ? _pauseCauses.add(cause) : _pauseCauses.remove(cause);
    if (!changed) return;
    setState(() {});
    _applyPausedTransition(wasPaused);
  }
```

Then update the callers:
- `_setForeground` calls `_setPaused(_PauseCause.lifecycle, true / false)`.
- `onHoldStart: () => _setPaused(_PauseCause.hold, true)`.
- `onHoldEnd: () => _setPaused(_PauseCause.hold, false)`.
- In `_startItemAsync`'s `setState`, replace `_heldPaused = false;` with `_pauseCauses.remove(_PauseCause.hold);`. The new item's player starts only `if (!_paused)`, which still holds.

(c) Replace the focus listener body in `initState` with:

```dart
    _replyFocusNode.addListener(() {
      if (!mounted) return;
      final focused = _replyFocusNode.hasFocus;
      _replyTarget = focused ? _current : null;
      _setPaused(_PauseCause.composer, focused);
    });
```

(d) Add:

```dart
  /// While the reply field has focus, a tap on the story only closes the
  /// keyboard. It never pages the reel under a half-typed reply (07a §3).
  bool _consumeTapForComposer() {
    if (!_replyFocusNode.hasFocus) return false;
    _replyFocusNode.unfocus();
    return true;
  }

  void _onTapNext() {
    if (_consumeTapForComposer()) return;
    unawaited(_advance(_generation));
  }

  void _onTapBack() {
    if (_consumeTapForComposer()) return;
    _retreat();
  }
```

In `build`, set `onTapLeft: _onTapBack` and `onTapRight: _onTapNext`.

(e) Change `_sendReply(StoryItem item)` to `_sendReply()`, and open its body with:

```dart
    final item = _replyTarget ?? _current;
    if (item == null) return;
```

In `build`, set `onSendReply: () => unawaited(_sendReply())`.

(f) In `_ReelBody`, wrap the `_ReplyComposer` inside the composer's `SafeArea` so that taps on the strip never reach the navigation layer (02 #27):

```dart
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: _ReplyComposer(
                    controller: replyController!,
                    focusNode: replyFocusNode!,
                    sending: sendingReply,
                    onSend: onSendReply!,
                  ),
                ),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_identity_test.dart`
Expected: all PASS.

- [ ] **Step 5: Run tests (regression)**

Run: `flutter test test/features/stories`
Expected: all PASS. These cover the hold and background tests (`story_reel_test.dart` "holding through a backgrounding keeps the reel paused") and every `story_reply_test.dart` test.

---

### Task 4: R2 — keep the data on screen during a refresh; spinner only before the first data

Fixes 02 #3 / 07a V3, plus the 02 #22 Low (retry and close labels).

**Files:**
- Modify: `lib/features/stories/presentation/providers/story_providers.dart`, `_KeysetPager.refresh()` (`:239-266`). This is a **shared pager**, also watched by `calendar_day_sheet.dart`'s `_StoriesSection` via `valueOrNull`. That screen only gains: it no longer blinks out during a refresh.
- Modify: `story_reel_screen.dart`, `build` (`:1093-1182`), `_EmptyState` and `_ErrorState` (`:1676-1736`).
- Create: `test/features/stories/story_pager_refresh_test.dart`
- Create: `test/features/stories/story_reel_refresh_test.dart`

**Interfaces:**
- Produces: during a refresh, a pager in the data state goes to `AsyncLoading` with the previous value (`isRefreshing == true`). A failed refresh goes to `AsyncError` with the previous value. The reel renders `valueOrNull` whenever it exists. `_ErrorState({required VoidCallback onClose, required VoidCallback onRetry})`, with its retry button keyed `story-reel-error-retry`.
- Not changed: the first load still starts in plain `AsyncLoading` (no value), and the coalescing and epoch logic are untouched.

- [ ] **Step 1: Write the failing provider tests**

Create `test/features/stories/story_pager_refresh_test.dart`:

```dart
// R2 (07a group B): a refresh keeps what is on screen until the new page
// arrives, and a failed refresh keeps it too.
import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

const _key = StoryReelKey(relationshipId: kitRel, authorId: kitPartner);

ProviderContainer _container(ScriptedReelGateway gateway) {
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(kitUser),
      storyReadGatewayProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);
  final sub = container.listen(
    storyReelPagesProvider(_key),
    (_, __) {},
    fireImmediately: true,
  );
  addTearDown(sub.close);
  return container;
}

List<String>? _ids(ProviderContainer c) =>
    c.read(storyReelPagesProvider(_key)).valueOrNull?.map((i) => i.id).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R2: refresh keeps data', () {
    test('a refresh keeps the loaded stories readable while it runs', () async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      final container = _container(gateway);
      await pumpEventQueue();
      expect(_ids(container), ['a', 'b']);

      final gate = Completer<void>();
      gateway.refreshGates.add(gate);
      gateway.active.add(kitItem('c', createdAt: DateTime.now().toUtc()));
      gateway.emitSignal();
      await pumpEventQueue();

      final during = container.read(storyReelPagesProvider(_key));
      expect(during.isRefreshing, isTrue);
      expect(_ids(container), ['a', 'b']);

      gate.complete();
      await pumpEventQueue();
      expect(_ids(container), ['a', 'b', 'c']);
    });

    test('a refresh that fails keeps the stories and reports the error', () async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      final container = _container(gateway);
      await pumpEventQueue();

      gateway.nextListError = StoryApiError.network('offline');
      gateway.emitSignal();
      await pumpEventQueue();

      final after = container.read(storyReelPagesProvider(_key));
      expect(after.hasError, isTrue);
      expect(_ids(container), ['a', 'b']);
    });
  });
}
```

- [ ] **Step 2: Write the failing reel tests**

Create `test/features/stories/story_reel_refresh_test.dart`:

```dart
// R2 in the reel: a change signal never blanks the reel or drops the
// keyboard; error and empty states can be retried and closed by name.
import 'dart:async';

import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a change signal while typing keeps the reply field, the text and the '
    'keyboard',
    (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      await typeReply(tester, 'half a tho');

      final gate = Completer<void>();
      gateway.refreshGates.add(gate);
      gateway.emitSignal();
      await settle(tester);

      expect(find.byKey(const ValueKey('story-reel-reply-field')), findsOneWidget);
      expect(replyFocused(tester), isTrue);
      expect(shownItemId(tester), 'a');

      gate.complete();
      await settle(tester);
      expect(replyFocused(tester), isTrue);
      expect(find.text('half a tho'), findsOneWidget);
    },
  );

  testWidgets('the first load still shows a spinner (regression guard)', (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(active: kitItems(['a']))
      ..firstLoadGate = Completer<void>();
    await pumpReel(tester, gateway: gateway);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gateway.firstLoadGate!.complete();
    await settle(tester);
    expect(shownItemId(tester), 'a');
  });

  testWidgets('a first load that fails offers Try again, which reloads', (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(active: kitItems(['a']))
      ..nextListError = StoryApiError.network('offline');
    await pumpReel(tester, gateway: gateway);
    expect(find.text("Couldn't load this story."), findsOneWidget);
    expect(find.byTooltip('Close story'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('story-reel-error-retry')));
    await settle(tester);
    expect(shownItemId(tester), 'a');
  });

  testWidgets('the empty state close button is labelled', (tester) async {
    await pumpReel(tester, gateway: ScriptedReelGateway());
    expect(find.text('No stories to show.'), findsOneWidget);
    expect(find.byTooltip('Close story'), findsOneWidget);
  });

  testWidgets(
    'a delete whose refetch fails still steps off the story '
    '(Review Focus 3)',
    (tester) async {
      final gateway = ScriptedReelGateway(
        day: kitItems(['a', 'b', 'c'], author: kitMe),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        hold: const Duration(seconds: 30),
      );
      gateway.nextListError = StoryApiError.network('offline');
      await confirmDelete(tester);
      expect(gateway.deleteCalls, ['a']);
      expect(shownItemId(tester), 'b');
    },
  );
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_pager_refresh_test.dart test/features/stories/story_reel_refresh_test.dart`
Expected:
- Provider tests: both FAIL. `_ids` is `null` during the refresh, and after the failed refresh.
- Reel tests:
  - "change signal" FAILs (the reply field is gone during the refresh).
  - The spinner guard PASSes.
  - "Try again" FAILs (no such button).
  - "empty state" FAILs (no tooltip).
  - "delete whose refetch fails" FAILs (the error state replaces the reel, so `shownItemId` is `null`).

- [ ] **Step 4: Implement the pager change**

In `story_providers.dart`, inside `refresh()`'s `do` loop, replace `if (mounted) state = const AsyncValue.loading();` with:

```dart
        // Keep what is on screen while re-reading (07a group B): the reel
        // and the day view must never blank to a spinner, or drop a reply
        // keyboard, because a signal arrived.
        if (mounted) {
          state = state.hasValue
              ? const AsyncLoading<List<StoryItem>>().copyWithPrevious(state)
              : const AsyncLoading<List<StoryItem>>();
        }
```

In the same loop's `catch`, replace `state = AsyncValue.error(error, stackTrace);` with:

```dart
          state = AsyncValue<List<StoryItem>>.error(
            error,
            stackTrace,
          ).copyWithPrevious(state);
```

Update the class doc: append one paragraph under F3 starting "**Wave 1 R2:** a refresh keeps the previous value (`copyWithPrevious`)…".

- [ ] **Step 5: Implement the reel change**

(a) In `build`, replace `body: pagesAsync.when(...)` with the code below. Then move the existing `data:` builder body into `Widget _buildLoaded(List<StoryItem> raw)` unchanged (it already starts with `final items = _visible(raw);` from Task 2). Open the method with `final occurredOn = widget.occurredOn;`, because the moved body reads that local.

```dart
      body: switch (pagesAsync.valueOrNull) {
        final List<StoryItem> raw => _buildLoaded(raw),
        null when pagesAsync.hasError => _ErrorState(
          onClose: _close,
          onRetry: () => unawaited(_refreshPager()),
        ),
        null => const _CenteredSpinner(),
      },
```

(b) Replace `_EmptyState`'s and `_ErrorState`'s close `IconButton`s with the version below. Use `Positioned(top: Spacing.sm, right: Spacing.sm, ...)` in place of the literal `8`.

```dart
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: 'Close story',
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: onClose,
            ),
```

(c) Replace `_ErrorState` with:

```dart
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onClose, required this.onRetry});

  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Couldn't load this story.",
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: Spacing.md),
              TextButton(
                key: const ValueKey('story-reel-error-retry'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
        Positioned(
          top: Spacing.sm,
          right: Spacing.sm,
          child: SafeArea(
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: 'Close story',
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: onClose,
            ),
          ),
        ),
      ],
    );
  }
}
```

Add `import 'package:attune/app/theme/design_tokens.dart';` to the reel's imports.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_pager_refresh_test.dart test/features/stories/story_reel_refresh_test.dart`
Expected: all PASS.

- [ ] **Step 7: Run tests (regression)**

Run: `flutter test test/features/stories test/features/timeline test/features/couple_map`
Expected: all PASS. These include `story_read_repository_test.dart`'s pager concurrency group (F1/F2/F3) and every calendar day sheet test.

---

### Task 5: R3 — one-shot completion and a close latch that pops only its own route

Fixes 02 #2 / 07a V4 (popping two screens), plus #23 (audio during the pop).

**Files:**
- Modify: `story_reel_screen.dart`, `_startTicker` (completion branch) and `_close` (`:870-873`).
- Create: `test/features/stories/story_reel_close_test.dart`

**Interfaces:**
- Produces:
  - `bool _closing`.
  - `void _close()`, which is idempotent: it does nothing unless this reel's route is current, and pauses media before popping.
  - The ticker cancels itself the moment an item completes (images and videos alike), then calls `_advance` once.

- [ ] **Step 1: Write the failing tests**

Create `test/features/stories/story_reel_close_test.dart`:

```dart
// R3 (07a group C): an item completes once, and the reel closes once,
// popping only itself.
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R3: one-shot completion and close', () {
    testWidgets('the last photo ending closes only the reel', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      await pumpReel(
        tester,
        gateway: gateway,
        below: ['HOME', 'CHAT'],
        hold: const Duration(seconds: 1),
      );
      await tester.pump(const Duration(milliseconds: 1200));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expect(find.byType(StoryReelScreen), findsNothing);
      expect(find.text('CHAT'), findsOneWidget);
    });

    testWidgets('closing a video stops its sound at once', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['v'], videos: {'v'}));
      final rig = await pumpReel(tester, gateway: gateway);
      final player = rig.players.last;
      expect(player.playing, isTrue);

      await tester.tap(find.byTooltip('Close story'));
      await tester.pump();

      expect(player.playing, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_close_test.dart`
Expected:
1. FAIL: `CHAT` is not found, because CHAT was popped too.
2. FAIL: still playing during the transition.

- [ ] **Step 3: Implement**

(a) In `_startTicker`, replace the `if (elapsed >= _currentDuration) { ... }` block with:

```dart
      if (elapsed >= _currentDuration) {
        // One-shot (07a group C): stop this clock before advancing, so the
        // completion cannot fire again every tick while the next item (or
        // the close transition) is on its way. For a video this is also a
        // fallback when onEnded never arrives; whichever runs first wins on
        // the generation guard.
        _tickTimer?.cancel();
        _tickTimer = null;
        setState(() => _elapsed = _currentDuration);
        unawaited(_advance(generation));
        return;
      }
```

(b) Add the field `bool _closing = false;` and replace `_close()` with:

```dart
  /// Closes the reel once. Pops only when this reel's own route is on top:
  /// never a confirm dialog above it, never the screen beneath it while
  /// the reel is already animating out (07a V4).
  void _close() {
    if (_closing || !mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _closing = true;
    _stopMedia();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      unawaited(navigator.maybePop());
    }
  }
```

`_stopMedia()` pauses and disposes the player, cancels the ticker and bumps the generation. That stops the audio before the pop transition (02 #23).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_close_test.dart`
Expected: PASS.

- [ ] **Step 5: Run tests (regression)**

Run: `flutter test test/features/stories test/features/couple_map`
Expected: all PASS. These include `story_reel_test.dart`'s "a video's advance is driven by its own length", the F3 "reaching the end of the LAST page closes", "a confident downward drag pops the reel", and places "remove from map ... closes the last one".

---

### Task 6: R3 — a modal pause cause around the reel's dialogs

Fixes 02 #14.

**Files:**
- Modify: `story_reel_screen.dart`, `_confirmAndDelete` and `_confirmAndRemovePlace` (their `showDialog` calls).
- Modify: `test/features/stories/support/reel_test_kit.dart` (add `backgroundAndResume`).
- Test: `test/features/stories/story_reel_close_test.dart` (append).

**Interfaces:**
- Consumes: `_setPaused`, `_PauseCause.modal` (Task 3).
- Produces: `Future<T?> _showReelDialog<T>(WidgetBuilder builder)`. Kit: `Future<void> backgroundAndResume(WidgetTester tester)`.

- [ ] **Step 1: Add the kit helper**

Append to `reel_test_kit.dart`:

```dart
/// The real OS order: resumed → inactive → hidden → paused, and back.
Future<void> backgroundAndResume(WidgetTester tester) async {
  final binding = TestWidgetsFlutterBinding.instance;
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}
```

- [ ] **Step 2: Write the failing tests**

Append inside `main()` of `story_reel_close_test.dart`:

```dart
  group('R3: dialogs pause the reel', () {
    testWidgets(
      'the Delete dialog pauses the reel; the story resumes after Cancel',
      (tester) async {
        final gateway = ScriptedReelGateway(day: kitItems(['a', 'b'], author: kitMe));
        await pumpReel(
          tester,
          gateway: gateway,
          mode: KitMode.day,
          hold: const Duration(seconds: 1),
        );
        await tester.tap(find.byKey(const ValueKey('story-reel-delete')));
        await settle(tester);
        await tester.pump(const Duration(seconds: 3));

        expect(find.text('Delete this story?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(shownItemId(tester), 'a');

        await tester.pump(const Duration(milliseconds: 1100));
        await settle(tester);
        expect(shownItemId(tester), 'b');
      },
    );

    testWidgets(
      'coming back to the app with the dialog open keeps the reel paused '
      '(Review Focus 2)',
      (tester) async {
        final gateway = ScriptedReelGateway(day: kitItems(['a', 'b'], author: kitMe));
        await pumpReel(
          tester,
          gateway: gateway,
          mode: KitMode.day,
          hold: const Duration(seconds: 1),
        );
        await tester.tap(find.byKey(const ValueKey('story-reel-delete')));
        await settle(tester);
        await backgroundAndResume(tester);
        await tester.pump(const Duration(seconds: 3));

        expect(find.text('Delete this story?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(shownItemId(tester), 'a');
      },
    );
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_close_test.dart --plain-name "dialogs pause"`
Expected: both FAIL. The reel advanced to `b` under the dialog, and on `b`'s completion the R3 latch's `isCurrent` check stops a pop, so the dialog stays. The `shownItemId` after Cancel is `b`, not `a`.

- [ ] **Step 4: Implement**

Add:

```dart
  /// Shows a dialog above the reel with the story paused underneath, so it
  /// cannot advance or finish behind the question (02 #14).
  Future<T?> _showReelDialog<T>(WidgetBuilder builder) async {
    _setPaused(_PauseCause.modal, true);
    try {
      return await showDialog<T>(context: context, builder: builder);
    } finally {
      if (mounted) _setPaused(_PauseCause.modal, false);
    }
  }
```

In `_confirmAndDelete` and `_confirmAndRemovePlace`, replace `await showDialog<bool>(context: context, builder: (dialogContext) => ...)` with `await _showReelDialog<bool>((dialogContext) => ...)`, keeping each builder body verbatim.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_close_test.dart`
Expected: all PASS.

- [ ] **Step 6: Run tests (regression)**

Run: `flutter test test/features/stories test/features/couple_map`
Expected: all PASS.

---

### Task 7: The 50-item page boundary — `loadMore` shares its in-flight future; the reel latches page advances

Fixes 02 #13, plus the duplicate-append risk R2 opens. Once a refresh keeps its value, a `loadMore` during a refresh would append page 1 again.

**Files:**
- Modify: `story_providers.dart`, `_KeysetPager` (`_loadingMore`, `refresh()`, `loadMore()`). Shared pager; the calendar day sheet does not call `loadMore`.
- Modify: `story_reel_screen.dart`, `_advanceAtEndOfPage` and `_ReelBody` (page spinner).
- Test: `test/features/stories/story_pager_refresh_test.dart` (append) and `story_reel_close_test.dart` (append).

**Interfaces:**
- Produces:
  - `loadMore()` returns the in-flight page future to every concurrent caller.
  - During a refresh it returns the refresh's completion and fetches nothing.
  - `refresh()` no longer clears `_cursor` / `_hasMore` before its page arrives.
  - Reel: `bool _advancingPage` and `bool _pageLoading`; `_ReelBody.pageLoading` shows a spinner keyed `story-reel-page-loading`.
- Removed: `_KeysetPager._loadingMore`.

- [ ] **Step 1: Write the failing provider tests**

Append to `story_pager_refresh_test.dart` inside `main()`:

```dart
  group('loadMore shares one page', () {
    test('two callers share one fetch and both see the new page', () async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']))
        ..pageSize = 2;
      final container = _container(gateway);
      await pumpEventQueue();
      final notifier = container.read(storyReelPagesProvider(_key).notifier);
      final gate = Completer<void>();
      gateway.nextPageGate = gate;

      var firstDone = false;
      var secondDone = false;
      unawaited(notifier.loadMore().then((_) => firstDone = true));
      unawaited(notifier.loadMore().then((_) => secondDone = true));
      await pumpEventQueue();
      expect(secondDone, isFalse, reason: 'the second caller waits for the page');

      gate.complete();
      await pumpEventQueue();
      expect(firstDone && secondDone, isTrue);
      expect(gateway.listCalls, 2);
      expect(_ids(container), ['a', 'b', 'c']);
    });

    test('a loadMore during a refresh fetches nothing and never duplicates', () async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']))
        ..pageSize = 2;
      final container = _container(gateway);
      await pumpEventQueue();
      final notifier = container.read(storyReelPagesProvider(_key).notifier);

      final gate = Completer<void>();
      gateway.refreshGates.add(gate);
      gateway.emitSignal();
      await pumpEventQueue();
      final callsBefore = gateway.listCalls;

      final more = notifier.loadMore();
      await pumpEventQueue();
      expect(gateway.listCalls, callsBefore);
      expect(_ids(container), ['a', 'b']);

      gate.complete();
      await more;
      await pumpEventQueue();
      expect(_ids(container), ['a', 'b']);
    });
  });
```

- [ ] **Step 2: Write the failing reel test**

Append to `story_reel_close_test.dart` inside `main()`. It needs `import 'dart:async';`.

```dart
  testWidgets(
    'a tap while the next page loads waits for it instead of closing the reel',
    (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['p1', 'p2', 'p3']))
        ..pageSize = 2;
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 1));
      await tapRight(tester);
      expect(shownItemId(tester), 'p2');

      final gate = Completer<void>();
      gateway.nextPageGate = gate;
      await tester.pump(const Duration(milliseconds: 1100));
      await tapRight(tester);
      expect(find.byType(StoryReelScreen), findsOneWidget);

      gate.complete();
      await settle(tester);
      expect(shownItemId(tester), 'p3');
    },
  );
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_pager_refresh_test.dart test/features/stories/story_reel_close_test.dart`
Expected:
- "two callers" FAILs (`secondDone` is already true).
- "loadMore during a refresh" FAILs (an extra fetch, then `['a','b','a','b']`).
- The reel test FAILs (the reel closes after the tap).

- [ ] **Step 4: Implement the pager**

In `_KeysetPager`, replace `bool _loadingMore = false;` with:

```dart
  /// The page fetch in flight. Every concurrent caller awaits this one
  /// future instead of returning early (02 #13).
  Future<void>? _loadMoreInFlight;

  /// Completes when the running refresh ends. A loadMore during a refresh
  /// waits for it and fetches nothing: the refresh restarts from page one.
  Completer<void>? _refreshDone;
```

In `refresh()`:
- right after `_refreshing = true;` add `final done = _refreshDone = Completer<void>();`;
- inside the loop, after `final epoch = ++_epoch;`, add `_loadMoreInFlight = null;`;
- delete the two lines `_cursor = null;` and `_hasMore = true;` (they are set on success already);
- in `finally`, after `_refreshing = false;`, add `_refreshDone = null; done.complete();`.

Replace `loadMore()` with:

```dart
  Future<void> loadMore() {
    final refreshing = _refreshDone;
    if (refreshing != null) return refreshing.future;
    final inFlight = _loadMoreInFlight;
    if (inFlight != null) return inFlight;
    if (!_hasMore) return Future.value();
    final current = state.valueOrNull;
    if (current == null) return Future.value();
    return _loadMoreInFlight = _fetchMore(current);
  }

  Future<void> _fetchMore(List<StoryItem> current) async {
    final epoch = _epoch; // do NOT bump — must be supersedable by refresh()
    try {
      final page = await fetchPage(_cursor);
      if (!mounted || epoch != _epoch) return;
      state = AsyncValue.data([...current, ...page.items]);
      _cursor = page.nextCursor;
      _hasMore = page.nextCursor != null;
    } catch (error, stackTrace) {
      if (!mounted || epoch != _epoch) return;
      state = AsyncValue<List<StoryItem>>.error(
        error,
        stackTrace,
      ).copyWithPrevious(AsyncValue.data(current));
      _hasMore = true;
    } finally {
      if (epoch == _epoch) _loadMoreInFlight = null;
    }
  }
```

Keep the existing doc comments; append "Wave 1: shares the in-flight future" to `loadMore`'s doc.

- [ ] **Step 5: Implement the reel latch**

Add the fields `bool _advancingPage = false;` and `bool _pageLoading = false;`. Replace `_advanceAtEndOfPage` with:

```dart
  Future<void> _advanceAtEndOfPage(int fromGeneration) async {
    if (_advancingPage) return;
    _advancingPage = true;
    try {
      // Two passes: a loadMore that landed during a refresh returns once the
      // refresh ends without fetching; the second pass fetches page two.
      for (var pass = 0; pass < 2; pass++) {
        if (!_pagerHasMore()) break;
        setState(() => _pageLoading = true);
        await _pagerLoadMore();
        if (!mounted || fromGeneration != _generation) return;
        final items = _liveItems();
        final at = _currentIndexIn(items);
        if (at + 1 < items.length) {
          _startItem(items, at + 1);
          return;
        }
      }
      _close();
    } finally {
      _advancingPage = false;
      if (mounted) setState(() => _pageLoading = false);
    }
  }
```

Remove the now-unused `setState(() => _loadingItem = true/false)` lines from the old version. Pass `pageLoading: _pageLoading` to `_ReelBody`. Add `this.pageLoading = false` and `final bool pageLoading;` to it. Add this as the last `Stack` child:

```dart
          if (pageLoading)
            const Center(
              child: CircularProgressIndicator(
                key: ValueKey('story-reel-page-loading'),
                color: Colors.white,
              ),
            ),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_pager_refresh_test.dart test/features/stories/story_reel_close_test.dart`
Expected: all PASS.

- [ ] **Step 7: Run tests (regression)**

Run: `flutter test test/features/stories test/features/timeline`
Expected: all PASS. This especially includes `story_read_repository_test.dart` "F2 scenario B", "!hasMore stops loadMore" and "_loadingMore prevents a concurrent loadMore call from issuing its own fetch". That last test asserts the call count only, which the shared future satisfies.

---

### Task 8: R4 — seen and the clock start on the first decoded frame; per-item load phase

Fixes 02 #6 / 07a V6 (spec §5.2: "a failed media load … does not count").

**Files:**
- Modify: `story_reel_screen.dart`:
  - constructors and fields (`:178-248`);
  - `_rendered`, `_loadingItem` and `_currentSignedUrl` (`:294-310`);
  - `_startItemAsync` (`:387-516`);
  - `_preloadNextItem` (`:526-559`);
  - `dispose`;
  - `_ReelBody` / `_MediaView`.
- Modify: `test/features/stories/support/reel_test_kit.dart` (test images; `kitReel` passes the seam).
- Modify (seam only, no assertion changes):
  - `test/features/stories/story_reel_test.dart`: `_harness` and the ring-refresh test's direct `StoryReelScreen(...)`.
  - `test/features/stories/story_calendar_test.dart`: `_reelHarness`'s two constructors.
- Create: `test/features/stories/story_reel_load_test.dart`

**Interfaces:**
- Produces:
  - `StoryReelScreen(..., ImageProvider Function(String url)? imageProviderBuilder)` on all three constructors. The name matches `StreakViewerScreen`'s seam.
  - `enum _ItemPhase { loading, ready, failed }` and `_ItemPhase _phase`.
  - `ImageProvider? _currentImage`.
  - `void _onItemReady(StoryItem item, int generation, Duration duration)` and `void _onItemFailed(int generation)` (extended in Task 9).
  - The per-item spinner is keyed `story-reel-item-loading`.
- Kit: `KitImage` (implements `NetworkImage`, so `shownItemId` and the existing F5 `as NetworkImage` assertion both work). It has the modes `KitImage.instant`, `.gated` and `.failing`, plus `KitImages` (per-id gates and failures), `ImageProvider kitInstantImage(String url)`, and `pumpReel(..., KitImages? images)`.
- Removed: `_rendered` and `_loadingItem`.

- [ ] **Step 1: Add test images to the kit**

Append to `reel_test_kit.dart`. Add the imports `import 'dart:ui' as ui;` and `import 'package:flutter/foundation.dart';`.

```dart
ui.Image? _pixel;

/// A decoded 1×1 image, built synchronously (verified to work in this test
/// host).
ui.Image kitPixel() {
  if (_pixel != null) return _pixel!;
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint());
  return _pixel = recorder.endRecording().toImageSync(1, 1);
}

/// A photo whose bytes arrive at once, when the test says so, or never
/// decode. Implements [NetworkImage] so readers (and existing tests casting
/// `image.image as NetworkImage`) see its URL.
class KitImage extends ImageProvider<NetworkImage> implements NetworkImage {
  KitImage.instant(this.url) : _bytes = null, _fails = false;
  KitImage.gated(this.url, Completer<void> bytes) : _bytes = bytes, _fails = false;
  KitImage.failing(this.url) : _bytes = null, _fails = true;

  @override
  final String url;
  final Completer<void>? _bytes;
  final bool _fails;

  @override
  double get scale => 1.0;

  @override
  Map<String, String>? get headers => null;

  @override
  WebHtmlElementStrategy get webHtmlElementStrategy =>
      WebHtmlElementStrategy.never;

  @override
  Future<NetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<NetworkImage>(this);

  @override
  ImageStreamCompleter loadBuffer(
    NetworkImage key,
    DecoderBufferCallback decode,
  ) => _completer();

  @override
  ImageStreamCompleter loadImage(
    NetworkImage key,
    ImageDecoderCallback decode,
  ) => _completer();

  ImageStreamCompleter _completer() {
    if (_fails) {
      return OneFrameImageStreamCompleter(
        Future<ImageInfo>.error(StateError('decode failed')),
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: kitPixel().clone())),
      );
    }
    return OneFrameImageStreamCompleter(
      bytes.future.then((_) => ImageInfo(image: kitPixel().clone())),
    );
  }
}

ImageProvider kitInstantImage(String url) => KitImage.instant(url);

/// Per-item control of photo bytes, keyed by item id.
class KitImages {
  final Map<String, Completer<void>> gates = {};
  final Set<String> failing = {};

  ImageProvider build(String url) {
    final id = kitIdFrom(url);
    if (failing.contains(id)) return KitImage.failing(url);
    final gate = gates[id];
    return gate == null ? KitImage.instant(url) : KitImage.gated(url, gate);
  }
}
```

Then:
- give `kitReel` a parameter `ImageProvider Function(String url) imageProviderBuilder = kitInstantImage` and pass `imageProviderBuilder: imageProviderBuilder` to all four constructors;
- give `pumpReel` a parameter `KitImages? images` and pass `imageProviderBuilder: images?.build ?? kitInstantImage` to `kitReel`;
- add `final KitImages? images;` to `ReelRig` and set it.

- [ ] **Step 2: Write the failing tests**

Create `test/features/stories/story_reel_load_test.dart`:

```dart
// R4 (07a group D): a story is "seen", and its clock starts, only once it
// is actually on screen; a failed load never counts.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R4: seen on first frame', () {
    testWidgets('a photo counts as seen only once its bytes have arrived', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      final images = KitImages()..gates['a'] = Completer<void>();
      await pumpReel(tester, gateway: gateway, images: images);
      await tester.pump(const Duration(seconds: 2));

      expect(gateway.marked, isEmpty);
      expect(find.byKey(const ValueKey('story-reel-item-loading')), findsOneWidget);

      images.gates['a']!.complete();
      await settle(tester);
      expect(gateway.marked, ['a']);
    });

    testWidgets(
      'the clock starts when the photo appears, not when its link is signed',
      (tester) async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
        final images = KitImages()..gates['a'] = Completer<void>();
        await pumpReel(
          tester,
          gateway: gateway,
          images: images,
          hold: const Duration(seconds: 1),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(shownItemId(tester), 'a');

        images.gates['a']!.complete();
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 800));
        expect(shownItemId(tester), 'a');

        await tester.pump(const Duration(milliseconds: 300));
        await settle(tester);
        expect(shownItemId(tester), 'b');
      },
    );

    testWidgets('a photo that fails to decode is never marked seen', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      final images = KitImages()..failing.add('a');
      await pumpReel(tester, gateway: gateway, images: images);
      await tester.pump(const Duration(milliseconds: 500));
      expect(gateway.marked, isEmpty);
    });

    testWidgets('a video counts as seen once it is ready to play '
        '(regression guard)', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['v'], videos: {'v'}));
      await pumpReel(tester, gateway: gateway);
      expect(gateway.marked, ['v']);
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_load_test.dart`
Expected: COMPILE FAIL. `kitReel` passes `imageProviderBuilder`, which `StoryReelScreen` does not have yet. That is the failing state for this task.

- [ ] **Step 4: Implement the seam and phases**

(a) Add `this.imageProviderBuilder,` to all three constructors, and add the field:

```dart
  /// Test seam, as on [StreakViewerScreen]: how a signed photo URL becomes
  /// an [ImageProvider]. Production uses [NetworkImage].
  final ImageProvider Function(String url)? imageProviderBuilder;
```

(b) At file level:

```dart
/// Where the current item is: loading its media, on screen, or failed.
/// "Ready" means a decoded first frame for a photo, or an initialized
/// player for a video, and is the only state that starts the clock and
/// records a view (spec §5.2; 07a V6).
enum _ItemPhase { loading, ready, failed }
```

(c) Replace the `_loadingItem` and `_rendered` fields with the code below. Keep `_currentSignedUrl`.

```dart
  _ItemPhase _phase = _ItemPhase.loading;
  ImageProvider? _currentImage;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
```

(d) Extend `_stopMedia()` with:

```dart
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _imageStream = null;
    _imageListener = null;
```

(e) Replace `_startItemAsync` entirely:

```dart
  Future<void> _startItemAsync(List<StoryItem> items, int index) async {
    _stopMedia();
    final generation = _generation;
    final item = items[index];
    setState(() {
      _index = index;
      _current = item;
      _elapsed = Duration.zero;
      _phase = _ItemPhase.loading;
      _pauseCauses.remove(_PauseCause.hold);
      _currentDuration = widget.imageHoldDuration;
      _currentSignedUrl = null;
      _currentImage = null;
    });
    unawaited(
      SemanticsService.announce(
        'Story ${index + 1} of ${items.length}',
        TextDirection.ltr,
      ),
    );

    final signedUrl = await ref
        .read(storyReadGatewayProvider)
        .signMediaUrl(item.mediaKey);
    if (!mounted || generation != _generation) return;
    if (signedUrl == null) {
      _onItemFailed(generation);
      return;
    }
    if (item.mediaType == 'video') {
      await _loadVideo(item, signedUrl, generation);
    } else {
      _loadImage(item, signedUrl, generation);
    }
  }

  static ImageProvider _networkImage(String url) => NetworkImage(url);

  void _loadImage(StoryItem item, String url, int generation) {
    final provider = (widget.imageProviderBuilder ?? _networkImage)(url);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        if (!mounted ||
            generation != _generation ||
            _phase != _ItemPhase.loading) {
          return;
        }
        _onItemReady(item, generation, widget.imageHoldDuration);
      },
      onError: (_, __) {
        if (!mounted || generation != _generation) return;
        _onItemFailed(generation);
      },
    );
    setState(() {
      _currentSignedUrl = url;
      _currentImage = provider;
    });
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  Future<void> _loadVideo(StoryItem item, String url, int generation) async {
    final player = (widget.videoPlayerFactory ?? _defaultVideoPlayerFactory)(
      Uri.parse(url),
    );
    try {
      await player.initialize();
    } catch (_) {
      await player.dispose();
      if (mounted && generation == _generation) _onItemFailed(generation);
      return;
    }
    if (!mounted || generation != _generation) {
      await player.dispose();
      return;
    }
    _player = player;
    _endedSub = player.onEnded.listen((_) {
      if (!mounted || generation != _generation) return;
      unawaited(_advance(generation));
    });
    _onItemReady(item, generation, player.duration);
    if (!_paused) player.play();
  }

  /// The item is on screen: only now does its clock run and its view count.
  void _onItemReady(StoryItem item, int generation, Duration duration) {
    setState(() {
      _phase = _ItemPhase.ready;
      _currentDuration = duration;
    });
    _startTicker(generation);
    unawaited(_maybeMarkViewed(item));
    final live = _liveItems();
    final at = _currentIndexIn(live);
    if (at >= 0) _preloadNextItem(live, at);
  }

  void _onItemFailed(int generation) {
    setState(() => _phase = _ItemPhase.failed);
  }
```

(f) In `_preloadNextItem`, replace `NetworkImage(url)` with `(widget.imageProviderBuilder ?? _networkImage)(url)`.

(g) Replace `dispose()`'s first four lines (`_generation++` through `_player?.dispose()`) with `_stopMedia();`.

(h) Replace the `_rendered` doc comment by moving it onto `_phase`. Delete `_rendered` and `_loadingItem`, and remove the `_loadingItem` references left in `_advanceAtEndOfPage` (Task 7 already removed them).

(i) `_ReelBody`:
- replace `loading` / `signedUrl` with `required this.phase` (`_ItemPhase`) and `this.image` (`ImageProvider?`);
- set the media slot to `Center(child: _MediaView(item: item, player: player, image: image, phase: phase))`;
- in `build`, pass `phase: _phase` and `image: _currentImage`.

(j) Replace `_MediaView` with:

```dart
class _MediaView extends StatelessWidget {
  const _MediaView({
    required this.item,
    required this.player,
    required this.image,
    required this.phase,
  });

  final StoryItem item;
  final StoryItemPlayer? player;
  final ImageProvider? image;
  final _ItemPhase phase;

  @override
  Widget build(BuildContext context) {
    if (phase == _ItemPhase.failed) return const _ErrorGlyph();
    if (item.mediaType == 'video') {
      final p = player;
      if (p is VideoControllerStoryItemPlayer) {
        final controller = p.controller;
        return AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 1
              : controller.value.aspectRatio,
          child: VideoPlayer(controller),
        );
      }
      return phase == _ItemPhase.loading
          ? const _ItemSpinner()
          : const ColoredBox(color: Colors.black);
    }
    final provider = image;
    if (provider == null) return const _ItemSpinner();
    return Stack(
      alignment: Alignment.center,
      children: [
        Image(
          key: const ValueKey('story-reel-image'),
          image: provider,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
        if (phase == _ItemPhase.loading) const _ItemSpinner(),
      ],
    );
  }
}

class _ItemSpinner extends StatelessWidget {
  const _ItemSpinner();

  @override
  Widget build(BuildContext context) => const CircularProgressIndicator(
    key: ValueKey('story-reel-item-loading'),
    color: Colors.white,
  );
}
```

Update `_MediaView`'s F5 doc block to say "the provider `_loadImage` resolved (one mint per item, the same provider object that gated ready)".

- [ ] **Step 5: Add the seam to the existing harnesses (no assertion changes)**

- `story_reel_test.dart`:
  - add `import 'support/reel_test_kit.dart' show kitInstantImage;`;
  - in `_harness`'s `StoryReelScreen(...)`, add `imageProviderBuilder: kitInstantImage,`;
  - in the "a partner view refreshes my own ring locally" test's `StoryReelScreen(...)`, add the same line.
- `story_calendar_test.dart`:
  - add the same import;
  - in `_reelHarness`, add `imageProviderBuilder: kitInstantImage,` to both `StoryReelScreen.forDay(...)` and `StoryReelScreen(...)`.

Why: those tests assert `markViewed` and the image hold. In this test host `NetworkImage` never decodes, so after this task they need a decodable photo. F5's `image.image as NetworkImage` still holds, because `KitImage implements NetworkImage`.

- [ ] **Step 6: Run the new tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_load_test.dart`
Expected: 4 PASS.

- [ ] **Step 7: Run tests (regression)**

Run: `flutter test test/features/stories test/features/timeline test/features/couple_map`
Expected: all PASS. If a `story_reel_test.dart` / `story_calendar_test.dart` test fails, the cause is a missing `imageProviderBuilder` at a construction site. Add the seam there; do not change the assertion.

---

### Task 9: R4 — failure UI with Retry / Next, a bounded backoff, and video timeouts and errors

Fixes 02 #5 (bounded), #15, and 06 #9.

**Files:**
- Modify: `story_reel_screen.dart`:
  - `StoryItemPlayer` area (add `StoryItemPlayerStatus`);
  - `VideoControllerStoryItemPlayer`;
  - fields;
  - `_startItem` / `_startItemAsync` (`retry` flag);
  - `_loadVideo` (timeout, pending player, error stream);
  - `_onItemFailed`;
  - `_stopMedia`;
  - `_ReelBody` (failure overlay, buffering).
- Modify: `reel_test_kit.dart` (`KitPlayer implements StoryItemPlayerStatus`).
- Test: `test/features/stories/story_reel_load_test.dart` (append).

**Interfaces:**
- Produces:
  - `const Duration kStoryVideoInitTimeout = Duration(seconds: 15)` and `const int kStoryItemAutoRetries = 3` (1 s, 2 s, 4 s).
  - `abstract interface class StoryItemPlayerStatus { Stream<Object> get onError; bool get isBuffering; }`. It is a separate interface so the existing `_FakeStoryItemPlayer implements StoryItemPlayer` in `story_reel_test.dart` still compiles.
  - `void _startItem(List<StoryItem> items, int index, {bool retry = false})` and `void _retryCurrent({bool manual = false})`.
  - The failure overlay `_ItemFailed`, with keys `story-reel-retry` and `story-reel-next`. The buffering spinner is keyed `story-reel-buffering`.

- [ ] **Step 1: Extend the kit player**

In `reel_test_kit.dart`, change `class KitPlayer implements StoryItemPlayer` to `class KitPlayer implements StoryItemPlayer, StoryItemPlayerStatus` and add:

```dart
  final _errors = StreamController<Object>.broadcast();

  @override
  Stream<Object> get onError => _errors.stream;

  @override
  bool isBuffering = false;

  /// Playback breaks after it started (a network drop, an expired link).
  void fail() {
    if (!_errors.isClosed) _errors.add(StateError('playback dropped'));
  }
```

In `KitPlayer.dispose()`, add `await _errors.close();`.

- [ ] **Step 2: Write the failing tests**

Append inside `main()` of `story_reel_load_test.dart`:

```dart
  group('R4: failed items recover', () {
    testWidgets(
      'a story that cannot load says so, offers Retry and Next, and retries '
      'itself at most three times with growing gaps',
      (tester) async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']))
          ..signFailKeys.add('story-media/a.jpg');
        await pumpReel(tester, gateway: gateway);

        expect(find.text("Couldn't load this story."), findsOneWidget);
        expect(find.byKey(const ValueKey('story-reel-retry')), findsOneWidget);
        expect(find.byKey(const ValueKey('story-reel-next')), findsOneWidget);
        expect(gateway.signCallsFor('a'), 1);

        await tester.pump(const Duration(seconds: 1));
        await settle(tester);
        expect(gateway.signCallsFor('a'), 2);
        await tester.pump(const Duration(seconds: 2));
        await settle(tester);
        expect(gateway.signCallsFor('a'), 3);
        await tester.pump(const Duration(seconds: 4));
        await settle(tester);
        expect(gateway.signCallsFor('a'), 4);
        await tester.pump(const Duration(seconds: 30));
        await settle(tester);
        expect(gateway.signCallsFor('a'), 4);
        expect(gateway.marked, isEmpty);
      },
    );

    testWidgets('Next skips a story that will not load', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']))
        ..signFailKeys.add('story-media/a.jpg');
      await pumpReel(tester, gateway: gateway);
      await tester.tap(find.byKey(const ValueKey('story-reel-next')));
      await settle(tester);
      expect(shownItemId(tester), 'b');
    });

    testWidgets('Retry loads the story once its link works again', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']))
        ..signFailKeys.add('story-media/a.jpg');
      await pumpReel(tester, gateway: gateway);
      gateway.signFailKeys.clear();
      await tester.tap(find.byKey(const ValueKey('story-reel-retry')));
      await settle(tester);
      expect(shownItemId(tester), 'a');
      expect(gateway.marked, ['a']);
    });

    testWidgets(
      'a video that never gets ready gives up after 15 seconds and offers '
      'Retry',
      (tester) async {
        final gateway = ScriptedReelGateway(active: kitItems(['v'], videos: {'v'}));
        final players = KitPlayers()..hangInitFor = (_) => true;
        await pumpReel(tester, gateway: gateway, players: players);
        expect(find.byKey(const ValueKey('story-reel-retry')), findsNothing);

        await tester.pump(const Duration(seconds: 15));
        await settle(tester);
        expect(find.byKey(const ValueKey('story-reel-retry')), findsOneWidget);
        expect(players.all.first.disposed, isTrue);
      },
    );

    testWidgets('a video that fails mid-play stops and offers Retry', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['v'], videos: {'v'}));
      final rig = await pumpReel(tester, gateway: gateway);
      final player = rig.players.last;
      player.fail();
      await settle(tester);
      expect(find.byKey(const ValueKey('story-reel-retry')), findsOneWidget);
      expect(player.playing, isFalse);
    });

    testWidgets('a buffering video shows a small spinner', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['v'], videos: {'v'}));
      final rig = await pumpReel(tester, gateway: gateway);
      rig.players.last.isBuffering = true;
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('story-reel-buffering')), findsOneWidget);
    });

    testWidgets(
      'Retry after an archive swap signs the new storage key '
      '(Review Focus 1)',
      (tester) async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']))
          ..signFailKeys.add('story-media/a.jpg');
        await pumpReel(tester, gateway: gateway);

        gateway.active[0] = kitItem(
          'a',
          createdAt: gateway.active[0].createdAt,
          mediaKey: 'story-media/a-archived.jpg',
        );
        gateway.emitSignal();
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('story-reel-retry')));
        await settle(tester);

        expect(gateway.signCalls.last, 'story-media/a-archived.jpg');
      },
    );
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_load_test.dart --plain-name "failed items recover"`
Expected: COMPILE FAIL first (`StoryItemPlayerStatus` is undefined). Once Step 4(a) adds the interface, all 7 FAIL on their first failure-UI or retry assertion.

- [ ] **Step 4: Implement**

(a) Under `StoryItemPlayer`, add:

```dart
/// Health signals a [StoryItemPlayer] may offer. Kept apart from
/// [StoryItemPlayer] so players that only implement the core seam (the
/// existing test fakes) keep compiling.
abstract interface class StoryItemPlayerStatus {
  /// Fires when playback fails after it started (a dropped connection, a
  /// signed URL that expired during a long pause).
  Stream<Object> get onError;

  /// True while playback waits for data.
  bool get isBuffering;
}

/// A video that is not ready by now counts as failed (02 #15).
const Duration kStoryVideoInitTimeout = Duration(seconds: 15);

/// Automatic retries for an item that failed, 1 s, 2 s then 4 s apart; the
/// person can always tap Retry or Next (02 #5).
const int kStoryItemAutoRetries = 3;
```

(b) `VideoControllerStoryItemPlayer`:
- add `implements StoryItemPlayer, StoryItemPlayerStatus`;
- add `final _errorController = StreamController<Object>.broadcast(); bool _errored = false;`;
- at the top of `_onTick`, before the `_ended` check, add:

```dart
    final value = _controller.value;
    if (value.hasError && !_errored) {
      _errored = true;
      if (!_errorController.isClosed) {
        _errorController.add(value.errorDescription ?? 'playback error');
      }
      return;
    }
```

Remove the now-duplicate `final value` line below. Then add:

```dart
  @override
  Stream<Object> get onError => _errorController.stream;

  @override
  bool get isBuffering => _controller.value.isBuffering;
```

and `await _errorController.close();` in `dispose()`.

(c) Fields:

```dart
  int _autoRetries = 0;
  Timer? _retryTimer;
  Timer? _initTimer;
  StoryItemPlayer? _pendingPlayer;
  StreamSubscription<Object>? _errorSub;
```

(d) Extend `_stopMedia()`:

```dart
    _retryTimer?.cancel();
    _retryTimer = null;
    _initTimer?.cancel();
    _initTimer = null;
    unawaited(_errorSub?.cancel());
    _errorSub = null;
    final pending = _pendingPlayer;
    _pendingPlayer = null;
    if (pending != null) unawaited(pending.dispose());
```

(e) Add the retry flag: `void _startItem(List<StoryItem> items, int index, {bool retry = false}) => unawaited(_startItemAsync(items, index, retry: retry));`. In `_startItemAsync(..., {bool retry = false})`, add `if (!retry) _autoRetries = 0;` right after `_stopMedia();`.

(f) Replace `_loadVideo`'s `try { await player.initialize(); } catch ...` block with the code below. The timer is screen-owned, not `Future.timeout`, so a disposed reel leaves no pending timer.

```dart
    _pendingPlayer = player;
    final ready = Completer<bool>();
    _initTimer = Timer(kStoryVideoInitTimeout, () {
      if (!ready.isCompleted) ready.complete(false);
    });
    unawaited(
      player.initialize().then(
        (_) {
          if (!ready.isCompleted) ready.complete(true);
        },
        onError: (Object _) {
          if (!ready.isCompleted) ready.complete(false);
        },
      ),
    );
    final ok = await ready.future;
    _initTimer?.cancel();
    _initTimer = null;
    final stillMine = identical(_pendingPlayer, player);
    if (stillMine) _pendingPlayer = null;
    if (!mounted || generation != _generation || !ok) {
      if (stillMine) await player.dispose();
      if (mounted && generation == _generation && !ok) {
        _onItemFailed(generation);
      }
      return;
    }
```

After `_endedSub = ...`, add:

```dart
    if (player is StoryItemPlayerStatus) {
      _errorSub = (player as StoryItemPlayerStatus).onError.listen((_) {
        if (!mounted || generation != _generation) return;
        _tickTimer?.cancel();
        _tickTimer = null;
        _player?.pause();
        _onItemFailed(generation);
      });
    }
```

(g) Replace `_onItemFailed` and add `_retryCurrent`:

```dart
  /// The item cannot be shown. Say so, offer Retry and Next, and retry on
  /// a growing gap a bounded number of times; never in a loop (02 #5).
  void _onItemFailed(int generation) {
    setState(() => _phase = _ItemPhase.failed);
    if (_autoRetries >= kStoryItemAutoRetries) return;
    final delay = Duration(seconds: 1 << _autoRetries);
    _autoRetries++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!mounted || generation != _generation) return;
      _retryCurrent();
    });
  }

  /// Reloads the story on screen from the live list (so a swapped storage
  /// key is the one signed). A manual Retry earns a fresh set of retries.
  void _retryCurrent({bool manual = false}) {
    if (manual) _autoRetries = 0;
    final items = _liveItems();
    final at = _currentIndexIn(items);
    if (at < 0) return;
    _startItem(items, at, retry: true);
  }
```

(h) Add the failure overlay widget:

```dart
class _ItemFailed extends StatelessWidget {
  const _ItemFailed({required this.onRetry, required this.onNext});

  final VoidCallback onRetry;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final buttonStyle = TextButton.styleFrom(foregroundColor: Colors.white);
    return Padding(
      padding: Spacing.horizontalLG,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: Colors.white70,
            size: IconSizes.lg,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            "Couldn't load this story.",
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const ValueKey('story-reel-retry'),
                style: buttonStyle,
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
              const SizedBox(width: Spacing.sm),
              TextButton(
                key: const ValueKey('story-reel-next'),
                style: buttonStyle,
                onPressed: onNext,
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

(i) `_ReelBody`:
- add the required callbacks `onRetry` and `onNext`;
- make the media slot `Center(child: phase == _ItemPhase.failed ? _ItemFailed(onRetry: onRetry, onNext: onNext) : _MediaView(...))`;
- add this after the media slot:

```dart
          if (phase == _ItemPhase.ready &&
              player is StoryItemPlayerStatus &&
              (player as StoryItemPlayerStatus).isBuffering)
            const Center(
              child: SizedBox(
                width: IconSizes.lg,
                height: IconSizes.lg,
                child: CircularProgressIndicator(
                  key: ValueKey('story-reel-buffering'),
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
```

In `build`, pass `onRetry: () => _retryCurrent(manual: true)` and `onNext: _onTapNext`. Remove `_MediaView`'s own `if (phase == _ItemPhase.failed) return const _ErrorGlyph();` line; delete `_ErrorGlyph` if nothing else uses it.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_load_test.dart`
Expected: all PASS. The Task 1 "not re-requested every frame" test also still PASSes (20 × 16 ms + 350 ms < 1 s).

- [ ] **Step 6: Run tests (regression)**

Run: `flutter test test/features/stories test/features/couple_map`
Expected: all PASS. `couple_map/accessibility_test.dart` signs `null`, so it now shows the failure overlay; its tap-target and label guidelines must pass, since TextButtons are 48 dp tall and text-labelled. The "one actionable node each" test covers Close/Delete/Remove only.

---

### Task 10: Screen-local signed-URL reuse, so a preload is the photo that gets displayed

Fixes 02 #7 (Medium; 07a V7) within the allowance "screen-local `{key: (url, mintedAt)}` reuse". Cross-screen caching by storage key stays Wave 4.

**Files:**
- Modify: `story_reel_screen.dart`: `_startItemAsync` (sign call), `_preloadNextItem`, `_onItemFailed`, and the file header comment (`:9-12`).
- Test: `test/features/stories/story_reel_load_test.dart` (append).

**Interfaces:**
- Produces:
  - `final Map<String, ({String url, DateTime mintedAt})> _signedUrls`, keyed by **storage key**, so an archive swap misses.
  - `Future<String?> _signedUrlFor(StoryItem item)`.
  - `const Duration kStorySignedUrlReuse = Duration(seconds: 540)`.

- [ ] **Step 1: Write the failing tests**

Append inside `main()` of `story_reel_load_test.dart`:

```dart
  group('one signed link per story per visit', () {
    testWidgets('the preloaded next photo is not signed again when shown', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      await tapRight(tester);
      expect(shownItemId(tester), 'b');
      expect(gateway.signCallsFor('b'), 1);
    });

    testWidgets('going back to a story reuses its link', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      await tapRight(tester);
      await tapLeft(tester);
      expect(shownItemId(tester), 'a');
      expect(gateway.signCallsFor('a'), 1);
    });

    testWidgets('a photo that failed to decode is signed afresh on Retry', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      final images = KitImages()..failing.add('a');
      await pumpReel(tester, gateway: gateway, images: images);
      images.failing.clear();
      await tester.tap(find.byKey(const ValueKey('story-reel-retry')));
      await settle(tester);
      expect(gateway.signCallsFor('a'), 2);
      expect(gateway.marked, ['a']);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_load_test.dart --plain-name "one signed link"`
Expected: the first two FAIL (`signCallsFor` is 2). The third PASSes now; it is the eviction guard for Step 3.

- [ ] **Step 3: Implement**

At file level:

```dart
/// How long the reel reuses a signed URL it minted itself: comfortably
/// inside the 600 s TTL, so §4.5's deletion bound is unchanged.
const Duration kStorySignedUrlReuse = Duration(seconds: 540);
```

Fields and helper:

```dart
  /// Signed URLs minted on THIS screen, by storage key, reused while
  /// younger than [kStorySignedUrlReuse] (STORIES.md §4.1 as amended):
  /// the preloaded photo is the one displayed, and a step back does not
  /// re-sign. Never stored beyond this screen. Keyed by storage key, so an
  /// archive swap (a new key) always signs afresh.
  final Map<String, ({String url, DateTime mintedAt})> _signedUrls = {};

  Future<String?> _signedUrlFor(StoryItem item) async {
    final cached = _signedUrls[item.mediaKey];
    if (cached != null &&
        DateTime.now().difference(cached.mintedAt) < kStorySignedUrlReuse) {
      return cached.url;
    }
    final url = await ref
        .read(storyReadGatewayProvider)
        .signMediaUrl(item.mediaKey);
    if (url != null) {
      _signedUrls[item.mediaKey] = (url: url, mintedAt: DateTime.now());
    }
    return url;
  }
```

- In `_startItemAsync`, replace the `signMediaUrl` call with `final signedUrl = await _signedUrlFor(item);`.
- In `_preloadNextItem`, replace `ref.read(storyReadGatewayProvider).signMediaUrl(next.mediaKey)` with `_signedUrlFor(next)`.
- At the top of `_onItemFailed`, add:

```dart
    final key = _current?.mediaKey;
    if (key != null) _signedUrls.remove(key);
```

Update the file header line "a storage KEY is signed fresh ... on every item, never cached, spec §4.1/§5.5" to say "a storage KEY is signed when first shown on this screen and reused for up to 540 s on this screen only (§4.1 as amended, Wave 1)".

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_load_test.dart`
Expected: all PASS.

- [ ] **Step 5: Run tests (regression)**

Run: `flutter test test/features/stories`
Expected: all PASS, including F5 "an image item mints exactly ONE signed URL".

---

### Task 11: R5 — delete from your own reel (after R1)

Fixes 02 #9 / 07a V9, per owner ruling 2. It ships only now that Tasks 1–2 make Delete act on the story on screen.

**Files:**
- Modify: `story_reel_screen.dart`, the `build` author/delete gating (`:1137-1148`) and the `_ReelBody.onDelete` doc.
- Modify: `test/features/stories/story_calendar_test.dart`, the test "author-mode (the ring/reel, not day mode) never shows delete at all…" (`:579-609`). This is the one allowed flip.
- Test: `test/features/stories/story_reel_identity_test.dart` (append).

**Interfaces:**
- Consumes: `_confirmAndDelete`, `_removedIds`, `_refreshPager` (Task 2).
- Produces: `canDeleteCurrent` is true whenever the current story is the signed-in user's own, in every mode.

- [ ] **Step 1: Write the failing tests**

Append to `story_reel_identity_test.dart`:

```dart
  group('R5: delete from my own reel', () {
    testWidgets('my reel offers Delete, and deleting shows my next story', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a', 'b', 'c'], author: kitMe),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      expect(find.byKey(const ValueKey('story-reel-delete')), findsOneWidget);

      await confirmDelete(tester);
      expect(gateway.deleteCalls, ['a']);
      expect(shownItemId(tester), 'b');
      expect(bars(tester), (index: 0, count: 2));
    });

    testWidgets("my partner's reel never offers Delete", (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      expect(find.byKey(const ValueKey('story-reel-delete')), findsNothing);
    });

    testWidgets('deleting my only story closes my reel', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a'], author: kitMe));
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        below: ['HOME', 'CHATS'],
        hold: const Duration(seconds: 30),
      );
      await confirmDelete(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StoryReelScreen), findsNothing);
      expect(find.text('CHATS'), findsOneWidget);
    });
  });
```

- [ ] **Step 2: Flip the pinned calendar test**

In `story_calendar_test.dart`, rename the test "author-mode (the ring/reel, not day mode) never shows delete at all, even for the author's own reel" to `'my own reel offers delete on my story (owner ruling 2026-10-23: delete from your own reel, after R1)'`. Replace its comment block's first line with `// Owner ruling 2 (docs/reviews/2026-10-23-stories-robustness-review.md).`, and change the final assertion to:

```dart
      expect(find.byKey(const ValueKey('story-reel-delete')), findsOneWidget);
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_identity_test.dart --plain-name "own reel" test/features/stories/story_calendar_test.dart --plain-name "my own reel offers delete"`
Expected:
- "my reel offers Delete" FAILs (no button).
- "deleting my only story" FAILs (no button to tap).
- The calendar flip FAILs.
- "partner's reel never offers Delete" PASSes (guard).

- [ ] **Step 4: Implement**

In `build`, replace the gating lines with the block below, and replace the comment above them with: `// Owner ruling 2: the author can delete their own story wherever they watch it: their reel, the calendar day, the map. delete_story_item stays author-only server-side.`

```dart
          final myId = ref.read(currentUserProvider)?.id;
          final perItemAuthor = occurredOn != null || _placesMode;
          final isAuthor = myId != null && currentItem.authorId == myId;
          final canDeleteCurrent = isAuthor;
          final isCurrentMine = perItemAuthor ? isAuthor : widget.isOwnReel;
```

Update `_ReelBody.onDelete`'s doc to: "Non-null when the current story is the signed-in user's own (any mode; owner ruling 2)."

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_identity_test.dart test/features/stories/story_calendar_test.dart`
Expected: all PASS.

- [ ] **Step 6: Run tests (regression)**

Run: `flutter test test/features/stories test/features/couple_map`
Expected: all PASS.

---

### Task 12: R6 — author and time byline; actions move to a header row under the bars

Fixes 02 standards-gap item 4 / 06 #8 / summary #18, plus 02 #21's "buttons sit on the bars" Low.

**Files:**
- Create: `lib/features/stories/presentation/widgets/story_reel_header.dart`
- Modify: `story_reel_screen.dart`: `build` (labels) and the `_ReelBody` top area (`:1269-1358`).
- Modify: `reel_test_kit.dart` (`partnerName` override).
- Create: `test/features/stories/story_reel_chrome_test.dart`

**Interfaces:**
- Produces:
  - `String storyPostedLabel(DateTime createdAt, {required DateTime now, required bool clockTime})`.
  - `StoryReelHeader({required String authorLabel, required String postedLabel, List<Widget> trailing = const []})`, with the byline keyed `story-reel-byline`.
  - `_ReelBody` gains `authorLabel` and `postedLabel`.
  - The partner's name comes from `partnerNameProvider` in `lib/features/quiz/presentation/providers/quiz_providers.dart`, the same source `timeline_screen.dart` and `calendar_day_sheet.dart` use. The fallback is `'Partner'`.
- Kit: `pumpReel(..., String partnerName = 'Kofi')` overrides `partnerNameProvider`.

- [ ] **Step 1: Kit override**

In `reel_test_kit.dart`:
- add `import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart' show partnerNameProvider;`;
- add the parameter `String partnerName = 'Kofi'` to `pumpReel`;
- add to its overrides: `partnerNameProvider.overrideWith((ref) async => partnerName),`.

- [ ] **Step 2: Write the failing tests**

Create `test/features/stories/story_reel_chrome_test.dart`:

```dart
// R6 and the reel's chrome: whose story and when (06 #8), Seen for the
// poster (spec §5.2), the bars (06 #10), screen-reader pause (02 #18),
// gestures (05 #7, 02 #27) and where the reel opens (owner ruling 3).
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/stories/presentation/widgets/story_progress_bars.dart';
import 'package:attune/features/stories/presentation/widgets/story_reel_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('storyPostedLabel', () {
    final now = DateTime.utc(2026, 10, 23, 12);

    test('the 24-hour reel says how long ago', () {
      expect(
        storyPostedLabel(
          now.subtract(const Duration(seconds: 20)),
          now: now,
          clockTime: false,
        ),
        'Just now',
      );
      expect(
        storyPostedLabel(
          now.subtract(const Duration(minutes: 12)),
          now: now,
          clockTime: false,
        ),
        '12m',
      );
      expect(
        storyPostedLabel(
          now.subtract(const Duration(hours: 3, minutes: 5)),
          now: now,
          clockTime: false,
        ),
        '3h',
      );
    });

    test('calendar and map stories show the clock time', () {
      final posted = DateTime.utc(2026, 10, 20, 9, 5);
      expect(
        storyPostedLabel(posted, now: now, clockTime: true),
        MyDateFormat.toTime(posted.toLocal()),
      );
    });
  });

  group('R6: whose story, and when', () {
    final threeHoursAgo = DateTime.now().toUtc().subtract(
      const Duration(hours: 3, minutes: 5),
    );

    testWidgets("my partner's reel names them and says when", (tester) async {
      final gateway = ScriptedReelGateway(
        active: [kitItem('a', createdAt: threeHoursAgo)],
      );
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      expect(find.text('Kofi - 3h'), findsOneWidget);
    });

    testWidgets('my own reel says You', (tester) async {
      final gateway = ScriptedReelGateway(
        active: [kitItem('a', author: kitMe, createdAt: threeHoursAgo)],
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      expect(find.text('You - 3h'), findsOneWidget);
    });

    testWidgets('a day reel labels each partner with the time of day', (
      tester,
    ) async {
      final theirs = kitItem('t', createdAt: DateTime.utc(2026, 10, 20, 8));
      final mine = kitItem(
        'm',
        author: kitMe,
        createdAt: DateTime.utc(2026, 10, 20, 9),
      );
      final gateway = ScriptedReelGateway(day: [theirs, mine]);
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        hold: const Duration(seconds: 30),
      );
      expect(
        find.text('Kofi - ${MyDateFormat.toTime(theirs.createdAt.toLocal())}'),
        findsOneWidget,
      );
      await tapRight(tester);
      expect(
        find.text('You - ${MyDateFormat.toTime(mine.createdAt.toLocal())}'),
        findsOneWidget,
      );
    });

    testWidgets('a very long name fits on one line (Review Focus 5)', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: [kitItem('a', createdAt: threeHoursAgo)],
      );
      await pumpReel(
        tester,
        gateway: gateway,
        partnerName: 'A' * 120,
        hold: const Duration(seconds: 30),
      );
      expect(tester.takeException(), isNull);
      final byline = tester.widget<Text>(
        find.byKey(const ValueKey('story-reel-byline')),
      );
      expect(byline.maxLines, 1);
      expect(find.byTooltip('Close story'), findsOneWidget);
    });

    testWidgets('the buttons sit below the progress bars, not on them', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        day: kitItems(['a'], author: kitMe),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        hold: const Duration(seconds: 30),
      );
      final barsBottom = tester.getRect(find.byType(StoryProgressBars)).bottom;
      expect(
        tester.getRect(find.byTooltip('Close story')).top,
        greaterThanOrEqualTo(barsBottom),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('story-reel-delete'))).top,
        greaterThanOrEqualTo(barsBottom),
      );
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_chrome_test.dart`
Expected: COMPILE FAIL (`story_reel_header.dart` does not exist). After Step 4 creates it, the widget tests still FAIL until Step 5.

- [ ] **Step 4: Create the header widget**

Create `lib/features/stories/presentation/widgets/story_reel_header.dart`:

```dart
/// The line under the reel's progress bars: whose story this is and when
/// it was posted (Wave 1 R6; review 06 #8), with the reel's own actions on
/// the right so they no longer sit on top of the bars (02 #21).
library;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:flutter/material.dart';

/// "Just now", "12m" or "3h" in the 24-hour reel. The time of day
/// ([MyDateFormat.toTime]) for a calendar or map story, or anything older
/// than a day.
String storyPostedLabel(
  DateTime createdAt, {
  required DateTime now,
  required bool clockTime,
}) {
  final local = createdAt.toLocal();
  if (clockTime) return MyDateFormat.toTime(local);
  final age = now.difference(createdAt);
  if (age < const Duration(minutes: 1)) return 'Just now';
  if (age < const Duration(hours: 1)) return '${age.inMinutes}m';
  if (age < const Duration(hours: 24)) return '${age.inHours}h';
  return MyDateFormat.toTime(local);
}

class StoryReelHeader extends StatelessWidget {
  const StoryReelHeader({
    super.key,
    required this.authorLabel,
    required this.postedLabel,
    this.trailing = const [],
  });

  /// "You", or the partner's name.
  final String authorLabel;
  final String postedLabel;

  /// The reel's actions (remove place, delete, close), 48 dp each.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Text(
            MyDateFormat.join([authorLabel, postedLabel]),
            key: const ValueKey('story-reel-byline'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelLarge?.copyWith(
              color: Colors.white,
              shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
          ),
        ),
        ...trailing,
      ],
    );
  }
}
```

Run: `dart format lib/features/stories/presentation/widgets/story_reel_header.dart` (new file only).

- [ ] **Step 5: Wire it into the reel**

(a) Add the imports `import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart' show partnerNameProvider;` and `import 'package:attune/features/stories/presentation/widgets/story_reel_header.dart';`.

(b) In `_buildLoaded`, after `isCurrentMine`:

```dart
          final partnerName = ref.watch(partnerNameProvider).valueOrNull;
          final authorLabel = isCurrentMine ? 'You' : (partnerName ?? 'Partner');
          final postedLabel = storyPostedLabel(
            currentItem.createdAt,
            now: DateTime.now(),
            clockTime: occurredOn != null || _placesMode,
          );
```

Pass `authorLabel: authorLabel, postedLabel: postedLabel` to `_ReelBody`, and add the matching `required` fields.

(c) In `_ReelBody.build`, replace the four top `Positioned` children (bars, close, delete, remove-place: `:1277-1358`) with this one:

```dart
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.sm,
                  Spacing.sm,
                  Spacing.xs,
                  0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StoryProgressBars(
                      itemCount: itemCount,
                      currentIndex: index,
                      currentProgress: progress,
                    ),
                    const SizedBox(height: Spacing.xs),
                    StoryReelHeader(
                      authorLabel: authorLabel,
                      postedLabel: postedLabel,
                      trailing: [
                        if (onRemovePlace != null)
                          IconButton(
                            key: const ValueKey('story-reel-remove-place'),
                            iconSize: IconSizes.md,
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            icon: const Icon(
                              Icons.wrong_location_outlined,
                              color: Colors.white,
                            ),
                            tooltip: 'Remove from map',
                            onPressed: onRemovePlace,
                          ),
                        if (onDelete != null)
                          IconButton(
                            key: const ValueKey('story-reel-delete'),
                            iconSize: IconSizes.md,
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                            ),
                            tooltip: 'Delete this story',
                            onPressed: deleting ? null : onDelete,
                          ),
                        IconButton(
                          iconSize: IconSizes.md,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                          tooltip: 'Close story',
                          onPressed: onDismiss,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
```

`itemCount` is `items.length`. If `_ReelBody` still holds `items`, use `items.length`. The close icon drops from 28 to `IconSizes.md` (24); flag this visual change in the task report.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_chrome_test.dart`
Expected: all PASS.

- [ ] **Step 7: Run tests (regression)**

Run: `flutter test test/features/stories test/features/couple_map test/features/timeline`
Expected: all PASS. This includes F4 "progress bars sit in the top quarter", `couple_map/accessibility_test.dart` (tap targets, labels, one node per name) and the places remove and delete tests.

---

### Task 13: The "Seen" chip on the poster's own story (spec §5.2; owner ruling 6)

Fixes 02 #10. `has_been_viewed` on your own story is already masked server-side when seen receipts are off, so no client privacy logic is needed.

**Files:**
- Modify: `story_reel_header.dart` (add the `seenBy` chip).
- Modify: `story_reel_screen.dart` (pass `seenBy`).
- Test: `test/features/stories/story_reel_chrome_test.dart` (append).

**Interfaces:**
- Produces: `StoryReelHeader(..., String? seenBy)`. When it is non-null, a chip keyed `story-reel-seen` shows `Seen` with the semantics label `Seen by $seenBy`. The reel passes `seenBy: isCurrentMine && currentItem.hasBeenViewed ? (partnerName ?? 'Partner') : null`.

- [ ] **Step 1: Write the failing tests**

Append inside `main()`:

```dart
  group('Seen on my own story', () {
    testWidgets('my story my partner has seen says Seen', (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a'], author: kitMe, viewed: {'a'}),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      expect(find.byKey(const ValueKey('story-reel-seen')), findsOneWidget);
      expect(find.bySemanticsLabel('Seen by Kofi'), findsOneWidget);
    });

    testWidgets('my story not yet seen shows nothing', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a'], author: kitMe));
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      expect(find.byKey(const ValueKey('story-reel-seen')), findsNothing);
    });

    testWidgets("a partner's story I have seen never says Seen", (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a'], viewed: {'a'}),
      );
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      expect(find.byKey(const ValueKey('story-reel-seen')), findsNothing);
    });

    testWidgets('Seen appears live when my partner watches', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a'], author: kitMe));
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      gateway.active[0] = kitItem(
        'a',
        author: kitMe,
        createdAt: gateway.active[0].createdAt,
        viewed: true,
      );
      gateway.emitSignal();
      await settle(tester);
      expect(find.byKey(const ValueKey('story-reel-seen')), findsOneWidget);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_chrome_test.dart --plain-name "Seen on my own story"`
Expected: tests 1 and 4 FAIL; tests 2 and 3 PASS (guards).

- [ ] **Step 3: Implement**

In `StoryReelHeader`:
- add `this.seenBy` and the field `final String? seenBy;` with the doc "Non-null on the poster's own story once the partner has seen it (spec §5.2). The server masks the flag when seen receipts are off.";
- insert `if (seenBy != null) _SeenChip(seenBy: seenBy!),` before `...trailing`;
- add:

```dart
class _SeenChip extends StatelessWidget {
  const _SeenChip({required this.seenBy});

  final String seenBy;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // container: true so the label is its own node rather than merging into
    // the reel's 'Story viewer' node above it.
    return Semantics(
      container: true,
      label: 'Seen by $seenBy',
      excludeSemantics: true,
      child: Padding(
        key: const ValueKey('story-reel-seen'),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.visibility_outlined,
              size: IconSizes.sm,
              color: Colors.white,
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              'Seen',
              style: textTheme.labelMedium?.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
```

In the reel's `_buildLoaded`, compute `final seenBy = isCurrentMine && currentItem.hasBeenViewed ? (partnerName ?? 'Partner') : null;`. Thread it through `_ReelBody` (a new `final String? seenBy;`) into `StoryReelHeader(seenBy: seenBy, ...)`.

Run: `dart format lib/features/stories/presentation/widgets/story_reel_header.dart`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_chrome_test.dart`
Expected: all PASS.

- [ ] **Step 5: Run tests (regression)**

Run: `flutter test test/features/stories test/features/couple_map`
Expected: all PASS.

---

### Task 14: Progress bars — white in both themes; watched segments faded

Fixes 06 #10 and the "faded" half of owner ruling 3 (STORIES.md:788-789).

**Files:**
- Modify: `lib/features/stories/presentation/widgets/story_progress_bars.dart`
- Modify: `story_reel_screen.dart` (pass `viewed`).
- Create: `test/features/stories/story_progress_bars_test.dart`
- Test: `story_reel_chrome_test.dart` (append one reel test).

**Interfaces:**
- Produces:
  - `StoryProgressBars({..., List<bool>? viewed})` and the public constants `StoryProgressBars.trackColor` (`0x59FFFFFF`), `.fillColor` (`Colors.white`) and `.seenColor` (`0x99FFFFFF`).
  - Each segment is wrapped in `KeyedSubtree(key: ValueKey('story-progress-segment-$i'))`.
  - The reel passes `viewed[i] = item.authorId != myId && (item.hasBeenViewed || _markedItemIds.contains(item.id))`. A partner's view of *my* story is never "faded".

- [ ] **Step 1: Write the failing tests**

Create `test/features/stories/story_progress_bars_test.dart`:

```dart
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/stories/presentation/widgets/story_progress_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  List<bool>? viewed,
  int current = 1,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: StoryProgressBars(
          itemCount: 3,
          currentIndex: current,
          currentProgress: 0.5,
          viewed: viewed,
        ),
      ),
    ),
  );
}

({double width, Color fill}) _segment(WidgetTester tester, int i) {
  final scope = find.byKey(ValueKey('story-progress-segment-$i'));
  final box = tester.widget<FractionallySizedBox>(
    find.descendant(of: scope, matching: find.byType(FractionallySizedBox)),
  );
  final fill = tester.widget<ColoredBox>(
    find.descendant(
      of: find.descendant(of: scope, matching: find.byType(FractionallySizedBox)),
      matching: find.byType(ColoredBox),
    ),
  );
  return (width: box.widthFactor!, fill: fill.color);
}

void main() {
  testWidgets('the fill stays white in dark mode', (tester) async {
    await _pump(tester, theme: AppTheme.darkTheme);
    expect(_segment(tester, 0).fill, Colors.white);
    expect(_segment(tester, 1).width, 0.5);
  });

  testWidgets('a story already seen ahead of the current one shows faded', (
    tester,
  ) async {
    await _pump(
      tester,
      theme: AppTheme.lightTheme,
      current: 0,
      viewed: const [false, false, true],
    );
    expect(_segment(tester, 1).width, 0.0);
    expect(_segment(tester, 2).width, 1.0);
    expect(_segment(tester, 2).fill, StoryProgressBars.seenColor);
  });
}
```

Append to `story_reel_chrome_test.dart` inside `main()`:

```dart
  testWidgets("the reel fades my partner's stories I have already seen", (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(
      active: kitItems(['a', 'b', 'c'], viewed: {'c'}),
    );
    await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
    final viewed =
        tester.widget<StoryProgressBars>(find.byType(StoryProgressBars)).viewed;
    expect(viewed![2], isTrue);
    expect(viewed[1], isFalse);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_progress_bars_test.dart test/features/stories/story_reel_chrome_test.dart --plain-name "fade"`
Expected: COMPILE FAIL (`viewed` and `seenColor` are undefined) = the failing state.

- [ ] **Step 3: Implement the bars**

In `story_progress_bars.dart`:
- add `this.viewed` to the constructor, with the field `final List<bool>? viewed;` and the doc "Per item: already seen by this viewer on an earlier visit. A segment after [currentIndex] that is seen draws fully, in [seenColor] (faded, not skipped: spec §5.5 / owner ruling 3)";
- add:

```dart
  /// The reel is a fixed black surface in both themes, so the bars are
  /// white regardless of theme (06 #10: dark `onPrimary` is near-black).
  static const Color trackColor = Color(0x59FFFFFF);
  static const Color fillColor = Colors.white;
  static const Color seenColor = Color(0x99FFFFFF);
```

Replace the segment loop body with:

```dart
          for (var i = 0; i < itemCount; i++) ...[
            if (i > 0) const SizedBox(width: Spacing.xs),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey('story-progress-segment-$i'),
                child: _segmentFor(i),
              ),
            ),
          ],
```

```dart
  Widget _segmentFor(int i) {
    final seenAhead =
        i > currentIndex && (viewed != null && i < viewed!.length && viewed![i]);
    return _Segment(
      fraction: i < currentIndex
          ? 1.0
          : i == currentIndex
          ? currentProgress
          : seenAhead
          ? 1.0
          : 0.0,
      trackColor: trackColor,
      fillColor: seenAhead ? seenColor : fillColor,
    );
  }
```

Remove the now-unused `colorScheme` local and the theme import, if unused.

- [ ] **Step 4: Pass `viewed` from the reel**

In `_buildLoaded`:

```dart
          final viewed = [
            for (final i in items)
              i.authorId != myId &&
                  (i.hasBeenViewed || _markedItemIds.contains(i.id)),
          ];
```

Thread it into `_ReelBody` (`final List<bool> viewed;`) and into `StoryProgressBars(viewed: viewed, ...)`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_progress_bars_test.dart test/features/stories/story_reel_chrome_test.dart`
Expected: all PASS.

- [ ] **Step 6: Run tests (regression)**

Run: `flutter test test/features/stories`
Expected: all PASS.

---

### Task 15: Open the partner's reel at the first unseen story; a story reply opens the quoted story

Fixes the resume half of owner ruling 3 (02 #8, 07a V8), plus 02 #11 / 06 #15.

**Files:**
- Modify: `story_reel_screen.dart`: the `forDay` constructor and fields; `_buildLoaded`'s start latch; a new `_beginPlayback` / `_resolveStartIndex`; the class doc (`:165-171`).
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart`, `_openStoryQuote`'s push (`:115-121`). This is a shared chat widget; the change only adds one named argument.
- Modify: `reel_test_kit.dart` (`initialStoryItemId` in `kitReel` / `pumpReel`).
- Test: `story_reel_chrome_test.dart` (append).

**Interfaces:**
- Produces:
  - `StoryReelScreen.forDay(..., String? initialStoryItemId)` and the field `final String? initialStoryItemId` (null on the other constructors).
  - `const int kStoryStartSearchMaxPages = 10`.
  - `Future<int> _resolveStartIndex()` and `Future<void> _beginPlayback()`.
- Rules (owner ruling 3, scoped):
  - The partner's active reel opens at the first `!hasBeenViewed`, else 0.
  - A day reel with `initialStoryItemId` opens at that item, paging until it is found.
  - Your own reel, a plain day reel and the map open at 0.

- [ ] **Step 1: Kit plumbing**

In `kitReel`, add the parameter `String? initialStoryItemId` and pass `initialStoryItemId: initialStoryItemId` to `StoryReelScreen.forDay(...)`. In `pumpReel`, add `String? initialStoryItemId` and forward it.

- [ ] **Step 2: Write the failing tests**

Append to `story_reel_chrome_test.dart` (add the imports `package:attune/features/auth/providers/auth_provider.dart`, `package:attune/features/chat/domain/entities/message.dart`, `package:attune/features/chat/presentation/widgets/message_bubble.dart`, `package:attune/features/stories/data/story_read_repository.dart`, `package:attune/features/stories/presentation/providers/story_providers.dart`, `package:attune/features/stories/presentation/screens/story_reel_screen.dart` and `package:flutter_riverpod/flutter_riverpod.dart`):

```dart
  group('where the reel opens (owner ruling 3)', () {
    testWidgets("my partner's reel opens at the first story I have not seen", (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a', 'b', 'c'], viewed: {'a', 'b'}),
      );
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      expect(shownItemId(tester), 'c');
      expect(bars(tester), (index: 2, count: 3));
    });

    testWidgets(
      'when everything is seen it starts again from the oldest '
      '(Review Focus 4)',
      (tester) async {
        final gateway = ScriptedReelGateway(
          active: kitItems(['a', 'b'], viewed: {'a', 'b'}),
        );
        await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
        expect(shownItemId(tester), 'a');
        expect(find.byType(StoryReelScreen), findsOneWidget);
      },
    );

    testWidgets('the first unseen story can be on a later page', (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a', 'b', 'c'], viewed: {'a', 'b'}),
      )..pageSize = 2;
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      expect(shownItemId(tester), 'c');
    });

    testWidgets('my own reel always opens at the oldest', (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a', 'b'], author: kitMe, viewed: {'a'}),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      expect(shownItemId(tester), 'a');
    });

    testWidgets('a day reel opened for one story starts at that story', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(day: kitItems(['x', 'y', 'z']));
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        initialStoryItemId: 'y',
        hold: const Duration(seconds: 30),
      );
      expect(shownItemId(tester), 'y');
    });

    testWidgets('tapping a story reply in chat opens the story it quotes', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        day: kitItems(['x', 'story-live', 'z'], author: kitMe),
      )..replyTargets['story-live'] = StoryReplyTarget(
          relationshipId: kitRel,
          authorId: kitMe,
          occurredOn: kitDay,
        );
      final message = Message(
        id: 'srv-1',
        clientMessageId: 'client-srv-1',
        relationshipId: kitRel,
        senderId: kitMe,
        content: 'love this',
        createdAt: DateTime(2026, 10, 20, 10),
        status: MessageStatus.sent,
        isMine: true,
        quotedText: 'Photo story',
        storyItemId: 'story-live',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(kitUser),
            storyReadGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            home: Scaffold(body: MessageBubble(message: message)),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Photo story'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);

      final reel = tester.widget<StoryReelScreen>(find.byType(StoryReelScreen));
      expect(reel.initialStoryItemId, 'story-live');
      expect(kitIdFrom(gateway.signCalls.first), 'story-live');
    });
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_chrome_test.dart --plain-name "where the reel opens"`
Expected: COMPILE FAIL (`initialStoryItemId` is undefined). After Step 4(a), tests 1, 3, 5 and 6 FAIL; tests 2 and 4 PASS (guards).

- [ ] **Step 4: Implement**

(a) Add `this.initialStoryItemId,` to `forDay`, and `initialStoryItemId = null` to the other two constructors' initializer lists. Add the field:

```dart
  /// Day mode: the story to start at (a story reply's quoted item, 02 #11).
  /// Pages forward until found; falls back to the first item.
  final String? initialStoryItemId;
```

(b) At file level: `const int kStoryStartSearchMaxPages = 10;`.

(c) Replace the `_started` block in `_buildLoaded` with:

```dart
          if (!_started) {
            _started = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_beginPlayback());
            });
          }
```

and add:

```dart
  Future<void> _beginPlayback() async {
    final index = await _resolveStartIndex();
    if (!mounted || _current != null) return;
    final items = _liveItems();
    if (items.isEmpty) return;
    _startItem(items, index.clamp(0, items.length - 1));
  }

  /// Where playback starts (owner ruling 3; STORIES.md §5.5 as amended):
  /// the quoted story when opened from a reply; the first unseen story in
  /// the partner's active reel (the oldest when all are seen); otherwise
  /// the oldest. Pages forward, at most [kStoryStartSearchMaxPages].
  Future<int> _resolveStartIndex() async {
    final targetId = widget.initialStoryItemId;
    final firstUnseen = targetId == null &&
        widget.occurredOn == null &&
        !_placesMode &&
        !widget.isOwnReel;
    if (targetId == null && !firstUnseen) return 0;
    bool matches(StoryItem i) =>
        targetId != null ? i.id == targetId : !i.hasBeenViewed;
    for (var page = 0; ; page++) {
      final at = _liveItems().indexWhere(matches);
      if (at >= 0) return at;
      if (!_pagerHasMore() || page >= kStoryStartSearchMaxPages) return 0;
      await _pagerLoadMore();
      if (!mounted) return 0;
    }
  }
```

(d) Rewrite the class doc above `StoryReelScreen` (`:165-171`) to:

```dart
/// The reel (spec §5.2). Where it opens (owner ruling 3, §5.5 as amended):
/// the partner's active reel at the first story the viewer has not seen
/// (the oldest when all are seen); a reply's quoted story via
/// [initialStoryItemId]; otherwise the oldest. Watched segments are faded,
/// not skipped ([StoryProgressBars.viewed]).
```

(e) `message_bubble.dart`, in `_openStoryQuote`'s builder:

```dart
          (_) => StoryReelScreen.forDay(
            relationshipId: target!.relationshipId,
            occurredOn: target.occurredOn,
            initialStoryItemId: storyItemId,
          ),
```

Update the doc paragraph above `_openStoryQuote` with one sentence: "Starts at the quoted story itself (`initialStoryItemId`), not the day's first item."

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_chrome_test.dart`
Expected: all PASS.

- [ ] **Step 6: Run tests (regression)**

Run: `flutter test test/features/stories test/features/timeline test/features/couple_map test/features/chat`
Expected: all PASS. `story_reel_test.dart` "opens at the OLDEST" still holds, because both its items are unseen. `story_reply_test.dart` "opens the reel at its day" still holds. The chat suite covers `message_bubble.dart`.

---

### Task 16: Screen-reader pause — a separate pause cause, a toggle action, named Pause/Play actions

Fixes 02 #18 / 06 #11 (WCAG 2.2.2).

**Files:**
- Modify: `story_reel_screen.dart`: `_GestureLayer` (its params and `Semantics`), plus a new `_toggleAccessibilityPause`.
- Test: `story_reel_chrome_test.dart` (append).

**Interfaces:**
- Consumes: `_PauseCause.accessibility` and `_setPaused` (Task 3).
- Produces:
  - `_GestureLayer({..., required VoidCallback onTogglePause, required bool accessibilityPaused})`.
  - The semantics node keeps `label: 'Story viewer'`, gets `onLongPress: onTogglePause`, and exposes a custom action named `Pause story` or `Play story`.
- The accessibility pause is **not** cleared by item changes; only the person plays it again.

- [ ] **Step 1: Write the failing tests**

Append inside `main()` (add `import 'package:flutter/semantics.dart';`):

```dart
  group('screen-reader pause (WCAG 2.2.2)', () {
    SemanticsNode viewer(WidgetTester tester) =>
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Story viewer')));

    void act(WidgetTester tester, SemanticsAction action) {
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        viewer(tester).id,
        action,
      );
    }

    testWidgets('the pause holds the story until it is played again', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 1));

      act(tester, SemanticsAction.longPress);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(shownItemId(tester), 'a');

      act(tester, SemanticsAction.longPress);
      await tester.pump(const Duration(milliseconds: 1100));
      await settle(tester);
      expect(shownItemId(tester), 'b');
      handle.dispose();
    });

    testWidgets('the pause carries over to the next story', (tester) async {
      final handle = tester.ensureSemantics();
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 1));
      act(tester, SemanticsAction.longPress);
      await settle(tester);
      act(tester, SemanticsAction.increase);
      await settle(tester);
      expect(shownItemId(tester), 'b');
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(shownItemId(tester), 'b');
      handle.dispose();
    });

    testWidgets('the pause is offered as a named action', (tester) async {
      final handle = tester.ensureSemantics();
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      final ids = viewer(tester).getSemanticsData().customSemanticsActionIds!;
      final labels = [
        for (final id in ids) CustomSemanticsAction.getAction(id)!.label,
      ];
      expect(labels, contains('Pause story'));
      handle.dispose();
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_chrome_test.dart --plain-name "screen-reader pause"`
Expected:
1. FAIL: shown `b` after 3 s.
2. FAIL: shown `c`.
3. FAIL: no custom actions (`customSemanticsActionIds` is null or empty).

- [ ] **Step 3: Implement**

In the screen:

```dart
  /// Screen-reader pause (02 #18): its own cause, so neither a hold release
  /// nor moving to the next story resumes it; only playing it again does.
  void _toggleAccessibilityPause() {
    final pausing = !_pauseCauses.contains(_PauseCause.accessibility);
    _setPaused(_PauseCause.accessibility, pausing);
    unawaited(
      SemanticsService.announce(
        pausing ? 'Paused' : 'Playing',
        Directionality.of(context),
      ),
    );
  }
```

Thread `onTogglePause: _toggleAccessibilityPause` and `accessibilityPaused: _pauseCauses.contains(_PauseCause.accessibility)` through `_ReelBody` into `_GestureLayer` (as new required fields on both). In `_GestureLayer.build`'s `Semantics`, replace `hint` and `onLongPress` with:

```dart
          hint:
              'Swipe up or right for the next story, swipe down or left for '
              'the previous one. Double-tap and hold to pause or play.',
          onLongPress: widget.onTogglePause,
          customSemanticsActions: {
            CustomSemanticsAction(
              label: widget.accessibilityPaused ? 'Play story' : 'Pause story',
            ): widget.onTogglePause,
          },
```

Note: `onIncrease` / `onDecrease` already call `widget.onTapRight` / `onTapLeft`, which since Task 3 are `_onTapNext` / `_onTapBack`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_chrome_test.dart`
Expected: all PASS.

- [ ] **Step 5: Run tests (regression)**

Run: `flutter test test/features/stories test/features/couple_map`
Expected: all PASS, including `couple_map/accessibility_test.dart`.

---

### Task 17: Gestures — the quick-exit band never pages the reel; tap back on the first story restarts it

Fixes 05 #7 and 02 #27 (the first-item Low).

**Files:**
- Modify: `story_reel_screen.dart`: `_GestureLayerState._onTapUp` (`:1516-1530`) and `_retreat`.
- Test: `story_reel_chrome_test.dart` (append).

**Interfaces:**
- Produces:
  - A tap whose `localPosition.dy < MediaQuery.paddingOf(context).top + kToolbarHeight` never navigates. That is `TripleTapDetector`'s band in `lib/features/safety/presentation/widgets/triple_tap_detector.dart:58-64`.
  - `_retreat()` on the first story restarts it.

- [ ] **Step 1: Write the failing tests**

Append inside `main()`:

```dart
  group('gestures', () {
    testWidgets('a quick-exit triple tap at the top does not page the reel', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c', 'd']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      final size = tester.getSize(find.byType(StoryReelScreen));
      for (var i = 0; i < 3; i++) {
        await tester.tapAt(Offset(size.width * 0.6, 20));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);
      expect(shownItemId(tester), 'a');
    });

    testWidgets('a tap lower down still pages (regression guard)', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      await tapRight(tester);
      expect(shownItemId(tester), 'b');
    });

    testWidgets('tapping back on the first story starts it again', (
      tester,
    ) async {
      // pumpReel leaves ~370 ms on the first story's clock; a 2 s hold makes
      // "no restart" cross the hold by the first check (1.57 s + 1.0 s).
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 1200));
      await tapLeft(tester);
      await tester.pump(const Duration(milliseconds: 1000));
      await settle(tester);
      expect(shownItemId(tester), 'a');

      await tester.pump(const Duration(milliseconds: 1100));
      await settle(tester);
      expect(shownItemId(tester), 'b');
    });
  });
```

`size.width * 0.6` keeps the taps off the header's buttons (the right-most 48–144 dp).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_chrome_test.dart --plain-name "gestures"`
Expected: test 1 FAILs (shown `d`); test 2 PASSes; test 3 FAILs (shown `b` at the first check).

- [ ] **Step 3: Implement**

In `_GestureLayerState._onTapUp`, after the `if (wasHolding) {...}` block:

```dart
    // TripleTapDetector's quick-exit band sits above every route; taps
    // there must not also page the reel and mark stories seen on the way
    // out (05 #7).
    final quickExitBand = MediaQuery.paddingOf(context).top + kToolbarHeight;
    if (details.localPosition.dy < quickExitBand) return;
```

Replace `_retreat`:

```dart
  void _retreat() {
    final items = _liveItems();
    final at = _currentIndexIn(items);
    if (at > 0) {
      _startItem(items, at - 1);
    } else if (at == 0) {
      // Reference apps restart the first story on tap-back (02 #27).
      _startItem(items, 0);
    }
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_chrome_test.dart`
Expected: all PASS.

- [ ] **Step 5: Run tests (regression)**

Run: `flutter test test/features/stories test/features/couple_map`
Expected: all PASS. `story_reel_test.dart` "tapping left on the first item stays put" still holds: the reel stays on `a`, and `_markedItemIds` stops a second mark.

---

### Task 18: Reply — one message id per composed reply, a 30 s bound, and 23505 counted as sent

Fixes 02 #17.

**Files:**
- Modify: `story_reel_screen.dart`, `_sendReply` (`:1046-1083`).
- Create: `test/features/stories/story_reel_reply_retry_test.dart`

**Interfaces:**
- Produces:
  - `const Duration kStoryReplySendTimeout = Duration(seconds: 30)`.
  - `String? _replyDraftId` and `String? _replyDraftKey` (`'$storyItemId|$text'`).
  - Snackbars replace each other (`removeCurrentSnackBar` first).
- The reply no longer drops its result on a generation change. A send is tied to its story, not to the current item; this removes a stuck-spinner path.

- [ ] **Step 1: Write the failing tests**

Create `test/features/stories/story_reel_reply_retry_test.dart`:

```dart
// 02 #17: a retried reply never lands twice, and a stalled send ends.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a retry after a lost answer reuses the message id and is not sent twice',
    (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      final rig = await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
      rig.chat
        ..enforceUniqueClientId = true
        ..errorAfterCommit = StateError('answer lost');

      await typeReply(tester, 'so pretty');
      await sendReply(tester);
      expect(find.text('Could not send your reply.'), findsOneWidget);
      final firstId = rig.chat.lastSendArgs!.clientMessageId;

      await sendReply(tester);
      expect(rig.chat.lastSendArgs!.clientMessageId, firstId);
      expect(rig.chat.serverMessages, hasLength(1));
      expect(find.text('Reply sent'), findsOneWidget);
    },
  );

  testWidgets('a stalled send gives up after 30 seconds and can be retried', (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(active: kitItems(['a']));
    final rig = await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
    rig.chat
      ..enforceUniqueClientId = true
      ..sendResponseGates.add(Completer<void>());

    await typeReply(tester, 'hello');
    await sendReply(tester);
    IconButton send() => tester.widget<IconButton>(
      find.byKey(const ValueKey('story-reel-reply-send')),
    );
    expect(send().onPressed, isNull);

    await tester.pump(const Duration(seconds: 31));
    await settle(tester);
    expect(find.text('Could not send your reply.'), findsOneWidget);
    expect(send().onPressed, isNotNull);

    await sendReply(tester);
    expect(find.text('Reply sent'), findsOneWidget);
    expect(rig.chat.serverMessages, hasLength(1));
  });

  testWidgets('changing the text after a failure sends it as a new message '
      '(regression guard)', (tester) async {
    final gateway = ScriptedReelGateway(active: kitItems(['a']));
    final rig = await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
    rig.chat.errorAfterCommit = StateError('answer lost');
    await typeReply(tester, 'first');
    await sendReply(tester);
    final firstId = rig.chat.lastSendArgs!.clientMessageId;

    await typeReply(tester, 'second');
    await sendReply(tester);
    expect(rig.chat.lastSendArgs!.clientMessageId, isNot(firstId));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_reply_retry_test.dart`
Expected:
1. FAIL: a new id, and 2 server rows.
2. FAIL: still spinning after 31 s.
3. PASS: guard.

- [ ] **Step 3: Implement**

At file level: `const Duration kStoryReplySendTimeout = Duration(seconds: 30);`. Add the import `import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;`. Add the fields `String? _replyDraftId;` and `String? _replyDraftKey;`. Replace `_sendReply` with the code below, keeping its existing doc comment and adding a paragraph on idempotency.

```dart
  Future<void> _sendReply() async {
    final item = _replyTarget ?? _current;
    final text = _replyController.text.trim();
    if (item == null || text.isEmpty || _sendingReply) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // One client id per composed reply (02 #17): retrying the same text to
    // the same story reuses it, so messages' (sender, client_message_id)
    // unique key drops a duplicate whose first answer was lost.
    final draftKey = '${item.id}|$text';
    if (_replyDraftKey != draftKey) {
      _replyDraftKey = draftKey;
      _replyDraftId = const Uuid().v4();
    }
    final clientMessageId = _replyDraftId!;

    setState(() => _sendingReply = true);
    var sent = false;
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendTextMessage(
            relationshipId: widget.relationshipId,
            senderId: user.id,
            clientMessageId: clientMessageId,
            content: text,
            storyItemId: item.id,
          )
          .timeout(kStoryReplySendTimeout);
      sent = true;
    } on PostgrestException catch (e) {
      // 23505: an earlier attempt with this id already landed.
      sent = e.code == '23505';
    } catch (_) {
      sent = false;
    }
    if (!mounted) return;
    setState(() => _sendingReply = false);
    // Replace, don't queue: a retry's "Reply sent" must not wait behind the
    // earlier "Could not send" for its full display time.
    final messenger = ScaffoldMessenger.of(context)..removeCurrentSnackBar();
    if (sent) {
      _replyDraftKey = null;
      _replyDraftId = null;
      _replyController.clear();
      _replyFocusNode.unfocus();
      messenger.showSnackBar(const SnackBar(content: Text('Reply sent')));
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send your reply.')),
      );
    }
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/stories/story_reel_reply_retry_test.dart`
Expected: all PASS.

- [ ] **Step 5: Run tests (regression)**

Run: `flutter test test/features/stories/story_reply_test.dart test/features/stories`
Expected: all PASS. `story_reply_test.dart` still sees `quotedText == null`, and `storyItemId` is the current item.

---

### Task 19: Amend STORIES.md where the owner rulings override it

**Files:**
- Modify: `lib/architecture/STORIES.md`, at §4.1 (`:362-366`), §5.2 (after `:705`), §5.3 (`:708-709`) and §5.5 (`:788-790`).
- Test: none (documentation). Verify with `grep`.

- [ ] **Step 1: §4.1.** Replace "Reads mint a signed URL per request, with the same 600-second TTL chat already uses (`_signedUrlTtl`), minted fresh on every call and never cached client-side." with:

> Reads mint a signed URL per request, with the same 600-second TTL chat already uses (`_signedUrlTtl`), and never persist one. The one exception is the reel (Wave 1, 2026-10-23). It may reuse a URL it minted itself for the same storage key while that URL is under 540 seconds old, and only while the reel screen is open. So the photo it preloads is the photo it shows, and stepping back does not re-sign. No URL outlives its 600-second TTL, so the §4.5 window is unchanged.

- [ ] **Step 2: §5.2.** Append after the paragraph ending "...not necessarily the URL that actually rendered.":

> **Wave 1 (2026-10-23 robustness review).** The reel follows the story on screen by id, not by position. Every refreshed list is reconciled against it, Delete steps off at once, and a reply goes to the story it was typed on. A refresh keeps the previous items on screen. An item counts as rendered only on its first decoded image frame or an initialized video player. Only then does its clock start and a view get recorded. A failed item says "Couldn't load this story." and offers Retry and Next, retrying itself at most three times (1 s, 2 s, 4 s). A video that is not ready in 15 seconds counts as failed. Completion and close are one-shot, and close pops only the reel's own route. Dialogs, typing, holding, backgrounding and a screen-reader pause are independent pause causes. The header names whose story it is ("You" or the partner's name) with a relative time, or the time of day for calendar and map playback. On the poster's own story it shows "Seen" once the partner has seen it; that flag is masked server-side when seen receipts are off. Taps inside the quick-exit band never page the reel.

- [ ] **Step 3: §5.3.** Replace "This is where deletion-from-the-past lives, and it is author-only." with:

> This is where deletion-from-the-past lives. Deletion is author-only, and an author can also delete a still-active story from their own reel (owner ruling, 2026-10-23, shipped after the reel tracked stories by id).

- [ ] **Step 4: §5.5.** Replace "The active reel opens at the oldest active item; viewed segments are still shown faded, not skipped." with:

> The partner's active reel opens at the first story the viewer has not seen, or at the oldest when every story is seen. Watched segments are shown faded, not skipped (owner ruling, 2026-10-23). Your own reel, a calendar day and the map open at the oldest item. A story reply opens its day's reel at the quoted story.

- [ ] **Step 5: Verify**

Run: `grep -n "opens at the oldest active item\|never cached client-side\|and it is author-only" lib/architecture/STORIES.md`
Expected: no output.

---

### Task 20: Whole-wave verification

**Files:** none (verification only).

- [ ] **Step 1: Full regression run**

```bash
cd /Users/user/attune
flutter test test/features/stories test/features/timeline test/features/couple_map test/features/chat
```
Expected: all PASS. The story and timeline count is the baseline plus the new tests.

- [ ] **Step 2: Analyzer on touched code**

```bash
flutter analyze lib/features/stories lib/features/chat/presentation/widgets/message_bubble.dart test/features/stories
```
Expected: no new errors or warnings compared with the baseline (run the same command on the baseline first if it reports pre-existing infos).

- [ ] **Step 3: Format check on new files only**

```bash
dart format --set-exit-if-changed lib/features/stories/presentation/widgets/story_reel_header.dart test/features/stories/support/reel_test_kit.dart test/features/stories/story_reel_identity_test.dart test/features/stories/story_pager_refresh_test.dart test/features/stories/story_reel_refresh_test.dart test/features/stories/story_reel_close_test.dart test/features/stories/story_reel_load_test.dart test/features/stories/story_reel_chrome_test.dart test/features/stories/story_progress_bars_test.dart test/features/stories/story_reel_reply_retry_test.dart
```
Expected: exit 0 (run `dart format` on any of these that changed). Never pass a pre-existing file.

- [ ] **Step 4: Working-tree hygiene**

Run: `git status --porcelain`
Expected: the user's original entries are unchanged, and the only new or modified paths are the ones this plan names. Nothing is staged (`git diff --cached --name-only` is empty).

- [ ] **Step 5: Device checks to hand to the owner (not runnable here)**

The test host has no video decoder, so these need a phone:
1. A real video in the reel: buffering spinner, a mid-play network drop leading to Retry, and the 15 s init bound on a throttled link.
2. VoiceOver: the "Pause story" action is in the rotor, and the "Paused" / "Playing" announcements are heard.
3. Triple-tap quick exit from inside the reel: the decoy appears and the reel did not advance.
4. Dark mode: the bars are visible.
5. Delete from your own ring's reel, then check that the ring updates through the signal.
