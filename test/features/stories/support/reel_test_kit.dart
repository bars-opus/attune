// Shared fixtures for the Wave 1 reel suites
// (docs/superpowers/plans/2026-10-23-stories-wave1-reel.md): a scriptable
// gateway whose lists change under an open reel, a change signal the test
// fires, a fake video player, base routes under the reel, and readers for
// "which story is on screen". House pattern: fake the gateway, never the
// Supabase client or Riverpod internals.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart'
    show chatRepositoryProvider;
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    show partnerNameProvider;
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/features/stories/presentation/widgets/story_progress_bars.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../chat/support/chat_test_harness.dart' show FakeChatRepository;
import 'ring_test_kit.dart' show NoopImageCache;

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
    String? authorId,
  }) {
    dayAuthorIds.add(authorId);
    return _page(
      serverFiltersAuthor
          ? day.where((i) => authorId == null || i.authorId == authorId).toList()
          : List.of(day),
      after,
    );
  }

  /// The author each day read asked for (Wave 5), in call order.
  final List<String?> dayAuthorIds = [];

  /// True: a Wave 5 server that reads only the asked author's stories.
  /// False (default): an older server that ignores the author.
  bool serverFiltersAuthor = false;

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
  Future<StoryReplyTarget?> getReplyTarget({
    required String storyItemId,
  }) async => replyTargets[storyItemId];

  /// Home ring fetches (each `storyRingSummaryProvider` build).
  int ringSummaryCalls = 0;

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async {
    ringSummaryCalls++;
    return const [];
  }

  int dayCountCalls = 0;

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) async {
    dayCountCalls++;
    return const [];
  }

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
class KitPlayer implements StoryItemPlayer, StoryItemPlayerStatus {
  KitPlayer(this.uri, {this.initError, this.hangInit = false, this.initGate});

  final Uri uri;
  final Object? initError;
  final bool hangInit;

  /// Holds [initialize] until the test completes it (a slow first load).
  final Completer<void>? initGate;
  bool playing = false;
  bool disposed = false;
  Duration _position = Duration.zero;
  final _ended = StreamController<void>.broadcast();
  final _errors = StreamController<Object>.broadcast();

  @override
  Stream<Object> get onError => _errors.stream;

  @override
  bool isBuffering = false;

  /// Playback breaks after it started (a network drop, an expired link).
  void fail() {
    if (!_errors.isClosed) _errors.add(StateError('playback dropped'));
  }

  String get itemId => kitIdFrom(uri.toString())!;

  @override
  Duration duration = const Duration(seconds: 4);

  @override
  Future<void> initialize() async {
    if (hangInit) await Completer<void>().future;
    if (initGate != null) await initGate!.future;
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
    await _errors.close();
  }
}

class KitPlayers {
  final List<KitPlayer> all = [];
  Object? Function(String itemId)? initErrorFor;
  bool Function(String itemId)? hangInitFor;
  Completer<void>? Function(String itemId)? initGateFor;

  KitPlayer get last => all.last;

  StoryItemPlayer Function(Uri uri) get factory => (uri) {
    final id = kitIdFrom(uri.toString())!;
    final player = KitPlayer(
      uri,
      initError: initErrorFor?.call(id),
      hangInit: hangInitFor?.call(id) ?? false,
      initGate: initGateFor?.call(id),
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
    this.images,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final FakeChatRepository chat;
  final KitPlayers players;
  final KitImages? images;
}

Widget kitReel({
  required KitMode mode,
  required KitPlayers players,
  List<StoryItem> placeItems = const [],
  Duration hold = const Duration(seconds: 1),
  ImageProvider Function(String url) imageProviderBuilder = kitInstantImage,
  String? initialStoryItemId,
  String? dayAuthorId,
}) {
  return switch (mode) {
    KitMode.partnerReel => StoryReelScreen(
      relationshipId: kitRel,
      authorId: kitPartner,
      videoPlayerFactory: players.factory,
      imageHoldDuration: hold,
      imageProviderBuilder: imageProviderBuilder,
    ),
    KitMode.ownReel => StoryReelScreen(
      relationshipId: kitRel,
      authorId: kitMe,
      isOwnReel: true,
      videoPlayerFactory: players.factory,
      imageHoldDuration: hold,
      imageProviderBuilder: imageProviderBuilder,
    ),
    KitMode.day => StoryReelScreen.forDay(
      relationshipId: kitRel,
      occurredOn: kitDay,
      initialStoryItemId: initialStoryItemId,
      dayAuthorId: dayAuthorId,
      videoPlayerFactory: players.factory,
      imageHoldDuration: hold,
      imageProviderBuilder: imageProviderBuilder,
    ),
    KitMode.places => StoryReelScreen.forPlaces(
      relationshipId: kitRel,
      items: placeItems,
      videoPlayerFactory: players.factory,
      imageHoldDuration: hold,
      imageProviderBuilder: imageProviderBuilder,
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
  KitImages? images,
  String partnerName = 'Kofi',
  String? initialStoryItemId,
  String? dayAuthorId,
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
        partnerNameProvider.overrideWith((ref) async => partnerName),
        // A delete evicts the story's media (Wave 4): the real cache would
        // leave its store timeout pending. A test's own override wins.
        chatImageCacheProvider.overrideWithValue(NoopImageCache()),
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
              imageProviderBuilder: images?.build ?? kitInstantImage,
              initialStoryItemId: initialStoryItemId,
              dayAuthorId: dayAuthorId,
            ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await settle(tester);
  return ReelRig(
    navigatorKey: navigatorKey,
    chat: chat,
    players: kitPlayers,
    images: images,
  );
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
  KitImage.gated(this.url, Completer<void> bytes)
    : _bytes = bytes,
      _fails = false;
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
