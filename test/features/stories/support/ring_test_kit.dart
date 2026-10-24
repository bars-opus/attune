// Shared doubles for the Wave 4 ring and calendar suites.
import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart'
    show ChatUploadCancelToken;
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/data/story_ring_last_known_store.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:attune/features/stories/presentation/widgets/story_rings_row.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

const ringMe = 'me-1';
const ringPartner = 'partner-1';
const ringRel = 'rel-1';

const ringUser = User(
  id: ringMe,
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
);

StoryRingSummary ringRow({
  String author = ringPartner,
  int active = 1,
  int unviewed = 1,
  String? key,
  DateTime? newest,
  DateTime? nextExpiresAt,
  DateTime? serverNow,
}) => StoryRingSummary(
  authorId: author,
  activeCount: active,
  unviewedCount: unviewed,
  newestThumbnailKey: key ?? 'story-media/$author-thumb.jpg',
  newestCreatedAt: newest ?? clock.now().subtract(const Duration(hours: 1)),
  nextExpiresAt: nextExpiresAt,
  serverNow: serverNow,
);

/// Server truth a test can change, then announce with [emitSignal].
class RingGateway implements StoryReadGateway {
  RingGateway({List<StoryRingSummary> summary = const []})
    : summary = [...summary];

  List<StoryRingSummary> summary;
  Object? summaryError;
  Completer<void>? summaryGate;
  int summaryCalls = 0;

  /// key -> URL; a key mapped to null fails to sign. Unlisted keys sign
  /// as `https://signed.example/<key>`.
  final Map<String, String?> urls = {};
  final List<String> signCalls = [];

  List<StoryDayCount> dayCounts = [];
  Object? dayCountsError;
  Completer<void>? dayCountsGate;
  int dayCountCalls = 0;

  List<StoryItem> dayItems = [];
  Object? dayItemsError;
  Completer<void>? dayItemsGate;
  int dayItemCalls = 0;

  final _signals = StreamController<void>.broadcast();
  void emitSignal() => _signals.add(null);

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async {
    summaryCalls++;
    final gate = summaryGate;
    if (gate != null) await gate.future;
    final error = summaryError;
    if (error != null) throw error;
    return List.of(summary);
  }

  @override
  Future<String?> signMediaUrl(String storageKey) async {
    signCalls.add(storageKey);
    return urls.containsKey(storageKey)
        ? urls[storageKey]
        : 'https://signed.example/$storageKey';
  }

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) async {
    dayCountCalls++;
    final gate = dayCountsGate;
    if (gate != null) await gate.future;
    final error = dayCountsError;
    if (error != null) throw error;
    return List.of(dayCounts);
  }

  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
    String? authorId,
  }) async {
    dayItemCalls++;
    final gate = dayItemsGate;
    if (gate != null) await gate.future;
    final error = dayItemsError;
    if (error != null) throw error;
    return StoryItemPage(items: List.of(dayItems), nextCursor: null);
  }

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) async => const StoryItemPage(items: [], nextCursor: null);

  @override
  Future<void> markViewed({required String storyItemId}) async {}

  @override
  Future<void> deleteItem({required String storyItemId}) async {}

  @override
  Future<StoryReplyTarget?> getReplyTarget({
    required String storyItemId,
  }) async => null;

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      _signals.stream;

  @override
  void disposeChannel(String relationshipId) {}

  @override
  void disposeAllChannels() {}
}

/// Attune's content visibility under the test's control.
class FixedVisibility extends AppContentVisibility {
  FixedVisibility([this._initial = true]);
  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool visible) => state = visible;
}

class NoopImageCache implements ChatImageCache {
  final removed = <String>[];
  int clears = 0;

  @override
  Future<void> clear() async => clears++;

  @override
  Future<void> removeKeys(Iterable<String> keys) async => removed.addAll(keys);
}

class RecordingEvictor implements StoryMediaEvictor {
  final evicted = <String>[];

  @override
  Future<void> evict(Iterable<String> storageKeys) async =>
      evicted.addAll(storageKeys);
}

ProviderContainer ringContainer(
  RingGateway gateway, {
  NoopImageCache? images,
  StoryRingLastKnownStore? lastKnown,
  List<Override> overrides = const [],
}) => ProviderContainer(
  overrides: [
    currentUserProvider.overrideWithValue(ringUser),
    storyReadGatewayProvider.overrideWithValue(gateway),
    chatImageCacheProvider.overrideWithValue(images ?? NoopImageCache()),
    appContentVisibleProvider.overrideWith(FixedVisibility.new),
    storyRingLastKnownStoreProvider.overrideWithValue(
      lastKnown ?? MemoryStoryRingLastKnownStore(),
    ),
    ...overrides,
  ],
);

FixedVisibility visibilityOf(ProviderContainer c) =>
    c.read(appContentVisibleProvider.notifier) as FixedVisibility;

/// Every outbox call hangs: seeded records stay in the state given.
class HangingStoryGateway implements StoryGateway {
  @override
  Future<StoryUploadIntent> createUploadIntent({
    required String relationshipId,
    required String objectKind,
    required String mediaType,
    required String mimeType,
  }) => Completer<StoryUploadIntent>().future;

  @override
  Future<void> uploadObject({
    required String bucket,
    required String storageKey,
    required String localPath,
    required String mimeType,
    void Function(int sent, int total)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) => Completer<void>().future;

  @override
  Future<StoryFinalizeResult> finalizeStory({
    required String relationshipId,
    required String clientStoryId,
    required String mediaIntentId,
    required String thumbnailIntentId,
    required int mediaWidth,
    required int mediaHeight,
    int? durationMs,
    required int utcOffsetMinutes,
    Map<String, dynamic>? place,
    DateTime? capturedAt,
  }) => Completer<StoryFinalizeResult>().future;
}

Future<void> pumpRings(
  WidgetTester tester,
  RingGateway gateway, {
  List<StoryOutboxRecord> outbox = const [],
  VoidCallback? onOpenMine,
  VoidCallback? onOpenPartner,
  VoidCallback? onCapture,
  List<Override> overrides = const [],
  TextDirection direction = TextDirection.ltr,
  double width = 400,
  double textScale = 1,
  String relationshipId = ringRel,
  StoryRingLastKnownStore? lastKnown,
}) async {
  final store = StoryOutboxStore.forTesting(stub.createStoryOutboxBackend());
  for (final record in outbox) {
    await store.put(ringMe, record);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(ringUser),
        storyReadGatewayProvider.overrideWithValue(gateway),
        storyOutboxStoreProvider.overrideWithValue(store),
        storyGatewayProvider.overrideWithValue(HangingStoryGateway()),
        chatImageCacheProvider.overrideWithValue(NoopImageCache()),
        storyRingLastKnownStoreProvider.overrideWithValue(
          lastKnown ?? MemoryStoryRingLastKnownStore(),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Directionality(
          textDirection: direction,
          child: Builder(
            builder:
                (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: width,
                        child: StoryRingsRow(
                          relationshipId: relationshipId,
                          partnerId: ringPartner,
                          partnerName: 'Ama',
                          onOpenMine: onOpenMine,
                          onOpenPartner: onOpenPartner,
                          onCapture: onCapture,
                        ),
                      ),
                    ),
                  ),
                ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// My ring's StoryRing, whichever wrapper carries the key.
StoryRing mineRing(WidgetTester tester) {
  final keyed = find.byKey(const ValueKey('story-ring-mine'));
  final widget = tester.widget(keyed);
  if (widget is StoryRing) return widget;
  return tester.widget<StoryRing>(
    find.descendant(of: keyed, matching: find.byType(StoryRing)),
  );
}
