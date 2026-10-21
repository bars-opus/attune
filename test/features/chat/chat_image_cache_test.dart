// I3: photo and poster bytes live in DefaultCacheManager (CachedNetworkImage's
// default, keyed by the stable storage key). ChatImageCache is the chat's
// handle on that store: sign-out empties it, removed messages take their
// entries with them. Both bounded and never throwing.
import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/chat/domain/services/chat_poster_prewarmer.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingCacheManager implements BaseCacheManager {
  int emptied = 0;
  final List<String> removed = [];
  Completer<void>? hold;
  Object? failRemoveOf;

  @override
  Future<void> emptyCache() async {
    emptied++;
    final gate = hold;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> removeFile(String key) async {
    if (key == failRemoveOf) throw StateError('locked');
    removed.add(key);
    final gate = hold;
    if (gate != null) await gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used');
}

void main() {
  late _RecordingCacheManager manager;
  late Directory dir;

  setUp(() async {
    manager = _RecordingCacheManager();
    dir = await Directory.systemTemp.createTemp('chat_image_cache');
    ChatPosterPrewarmer.debugClearReadyPosterPaths();
  });

  tearDown(() async {
    ChatPosterPrewarmer.debugClearReadyPosterPaths();
    await dir.delete(recursive: true);
  });

  test(
    'clear empties the image store and forgets ready poster paths',
    () async {
      final poster = File('${dir.path}/poster.jpg')..writeAsBytesSync([1, 2]);
      ChatPosterPrewarmer.debugRememberReadyPosterPath(
        'chat-media/p.jpg',
        poster.path,
      );

      await ChatImageCache(manager: manager).clear();

      expect(manager.emptied, 1);
      expect(
        ChatPosterPrewarmer.readyPosterPathFor('chat-media/p.jpg'),
        isNull,
      );
    },
  );

  test('a clear that hangs returns within its bound', () async {
    manager.hold = Completer<void>();
    final cache = ChatImageCache(
      manager: manager,
      bound: const Duration(milliseconds: 100),
    );
    await cache.clear().timeout(
      const Duration(seconds: 2),
      onTimeout: () => fail('clear() held the caller past its bound'),
    );
    expect(manager.emptied, 1);
    manager.hold!.complete();
  });

  test('removeKeys drops each key (media and poster) from the store', () async {
    final poster = File('${dir.path}/poster.jpg')..writeAsBytesSync([1, 2]);
    ChatPosterPrewarmer.debugRememberReadyPosterPath(
      'chat-media/p.jpg',
      poster.path,
    );

    await ChatImageCache(
      manager: manager,
    ).removeKeys(const ['chat-media/v.mp4', 'chat-media/p.jpg', '']);

    expect(manager.removed, ['chat-media/v.mp4', 'chat-media/p.jpg']);
    expect(ChatPosterPrewarmer.readyPosterPathFor('chat-media/p.jpg'), isNull);
  });

  test('one key that cannot be removed never stops the others', () async {
    manager.failRemoveOf = 'chat-media/a.jpg';
    await ChatImageCache(
      manager: manager,
    ).removeKeys(const ['chat-media/a.jpg', 'chat-media/b.jpg']);
    expect(manager.removed, ['chat-media/b.jpg']);
  });

  test('a removal that hangs returns within its bound', () async {
    manager.hold = Completer<void>();
    final cache = ChatImageCache(
      manager: manager,
      bound: const Duration(milliseconds: 100),
    );
    await cache
        .removeKeys(const ['chat-media/a.jpg'])
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('removeKeys() held the caller past its bound'),
        );
    manager.hold!.complete();
  });

  test('every chat image surface reads the store this cache clears', () {
    // CachedNetworkImage / CachedNetworkImageProvider with no cacheManager
    // use DefaultCacheManager — the store ChatImageCache empties. A widget
    // that switched to its own manager would escape sign-out and delete.
    for (final path in const [
      'lib/features/chat/presentation/widgets/message_bubble.dart',
      'lib/features/chat/presentation/widgets/chat_media_group.dart',
      'lib/features/chat/presentation/widgets/video_message_thumbnail.dart',
      'lib/features/chat/presentation/screens/image_viewer_screen.dart',
      'lib/features/chat/presentation/screens/chat_media_screen.dart',
      'lib/features/chat/presentation/screens/chat_couples_locked_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        RegExp(r'cacheManager:\s*(?!widget\.cacheManager)').hasMatch(source),
        isFalse,
        reason: '$path must not use a private image cache manager',
      );
    }
  });

  // Static state: this file's isolate fails the default store at the end.
  test('N6: store-failure listening is attached once, not per call; a '
      'failing store ends waiting calls at once', () async {
    for (var i = 0; i < 200; i++) {
      await ChatImageCache.debugRaceStoreFailure(
        Future<void>.value(),
        const Duration(seconds: 1),
      );
    }
    expect(
      ChatImageCache.debugFailureWaiters,
      0,
      reason: 'a finished call leaves nothing behind',
    );

    final hung = Completer<void>();
    final waiting = ChatImageCache.debugRaceStoreFailure(
      hung.future,
      const Duration(seconds: 5),
    );
    expect(ChatImageCache.debugFailureWaiters, 1);
    ChatImageCache.debugFailStore(StateError('store down'));
    await expectLater(waiting, throwsStateError);
    expect(ChatImageCache.debugFailureWaiters, 0);
    await expectLater(
      ChatImageCache.debugRaceStoreFailure(
        hung.future,
        const Duration(seconds: 5),
      ),
      throwsStateError,
    );
  });
}
