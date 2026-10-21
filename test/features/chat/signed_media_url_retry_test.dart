import 'dart:async';
import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/screens/image_viewer_screen.dart';
import 'package:attune/features/chat/presentation/screens/video_viewer_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/chat/presentation/widgets/resolved_media_url.dart';
// Transitive through flutter_test; the plan adds no pub dependencies.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

const key = 'chat-media/photo.jpg';

ProviderContainer makeContainer(
  FakeChatRepository repo, {
  StreamController<bool>? connectivity,
  Duration refreshAfter = const Duration(minutes: 8),
}) {
  final container = ProviderContainer(
    overrides: [
      chatRepositoryProvider.overrideWithValue(repo),
      signedMediaUrlRefreshAfterProvider.overrideWithValue(refreshAfter),
      chatConnectivityProvider.overrideWith(
        (ref) => connectivity?.stream ?? Stream<bool>.value(true),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'a failed resolution is not cached: invalidate → next read succeeds',
    () async {
      final repo =
          FakeChatRepository(currentUserId: 'u1')
            ..signMediaUrls = true
            ..signMediaUrlFailuresBeforeSuccess = 3; // > in-provider retries
      final container = makeContainer(repo);
      final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
      addTearDown(sub.close);

      await expectLater(
        container.read(signedMediaUrlProvider(key).future),
        throwsA(isA<SignedMediaUrlUnavailable>()),
      );
      expect(repo.signedUrlRequests.length, 3, reason: '1 try + 2 retries');

      container.invalidate(signedMediaUrlProvider(key));
      expect(
        await container.read(signedMediaUrlProvider(key).future),
        'https://signed.test/$key?token=abc',
      );
    },
  );

  test(
    'with no listener left, an error is disposed and the next mount re-asks',
    () async {
      final repo =
          FakeChatRepository(currentUserId: 'u1')
            ..signMediaUrls = true
            ..signMediaUrlFailuresBeforeSuccess = 3;
      final container = makeContainer(repo);

      final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
      await expectLater(
        container.read(signedMediaUrlProvider(key).future),
        throwsA(isA<SignedMediaUrlUnavailable>()),
      );
      sub.close(); // the tile scrolled away
      await Future<void>.delayed(Duration.zero);

      final sub2 = container.listen(signedMediaUrlProvider(key), (_, __) {});
      addTearDown(sub2.close);
      expect(
        await container.read(signedMediaUrlProvider(key).future),
        contains('token=abc'),
      );
    },
  );

  test('a success is kept alive across unmount/remount (no re-sign)', () async {
    final repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
    final container = makeContainer(repo);
    final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
    await container.read(signedMediaUrlProvider(key).future);
    sub.close();
    await Future<void>.delayed(Duration.zero);
    final sub2 = container.listen(signedMediaUrlProvider(key), (_, __) {});
    addTearDown(sub2.close);
    await container.read(signedMediaUrlProvider(key).future);
    expect(repo.signedUrlRequests.length, 1);
  });

  // Fake time (M6): the refresh Timer and the grant's clock both run on the
  // test's clock, so the mark is exact instead of a race against load.
  group('the timed refresh (fake time)', () {
    test('re-signs itself before the token expires', () {
      fakeAsync((async) {
        final repo =
            FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
        final container = makeContainer(repo);
        final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
        async.flushMicrotasks();
        expect(repo.signedUrlRequests.length, 1);
        // 9-minute grant less the 60 s margin: the mark is at 8 minutes.
        async.elapse(const Duration(minutes: 7, seconds: 59));
        expect(repo.signedUrlRequests.length, 1, reason: 'not before');
        async.elapse(const Duration(seconds: 2));
        expect(repo.signedUrlRequests.length, 2);
        expect(repo.signedUrlForceRefreshes.last, isTrue);
        sub.close();
      });
    });

    test('a member nobody listens to is not re-signed at the mark (M1)', () {
      fakeAsync((async) {
        final repo =
            FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
        final container = makeContainer(repo);
        final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
        async.flushMicrotasks();
        sub.close(); // the tile scrolled away
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 9));
        expect(
          repo.signedUrlRequests.length,
          1,
          reason: 'a photo scrolled past costs no forced re-sign later',
        );
        // The next view resolves afresh (through the repository's cache in
        // production), not as a forced re-sign of a member kept for nobody.
        final again = container.listen(
          signedMediaUrlProvider(key),
          (_, __) {},
        );
        async.flushMicrotasks();
        expect(repo.signedUrlRequests.length, 2);
        expect(repo.signedUrlForceRefreshes.last, isFalse);
        again.close();
      });
    });

    test('a member listened again before the mark still refreshes', () {
      fakeAsync((async) {
        final repo =
            FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
        final container = makeContainer(repo);
        final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
        async.flushMicrotasks();
        sub.close();
        async.elapse(const Duration(minutes: 3));
        final back = container.listen(
          signedMediaUrlProvider(key),
          (_, __) {},
        );
        async.flushMicrotasks();
        expect(repo.signedUrlRequests.length, 1, reason: 'kept: no re-sign');
        async.elapse(const Duration(minutes: 5, seconds: 1));
        expect(repo.signedUrlRequests.length, 2);
        expect(repo.signedUrlForceRefreshes.last, isTrue);
        back.close();
      });
    });
  });

  test('connectivity returning re-resolves a broken tile', () async {
    // 4 failures: 3 for the first (online) build's try + 2 retries, 1 for
    // the offline rebuild (no retries offline), then success when online.
    final repo =
        FakeChatRepository(currentUserId: 'u1')
          ..signMediaUrls = true
          ..signMediaUrlFailuresBeforeSuccess = 4;
    final connectivity = StreamController<bool>.broadcast();
    addTearDown(connectivity.close);
    final container = makeContainer(repo, connectivity: connectivity);
    final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
    addTearDown(sub.close);
    await expectLater(
      container.read(signedMediaUrlProvider(key).future),
      throwsA(isA<SignedMediaUrlUnavailable>()),
    );

    connectivity.add(false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repo.signedUrlRequests.length, 4, reason: 'one try while offline');
    expect(container.read(signedMediaUrlProvider(key)).hasError, isTrue);

    connectivity.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      await container.read(signedMediaUrlProvider(key).future),
      contains('token=abc'),
    );
  });

  testWidgets('a broken tile is tappable and heals on tap', (tester) async {
    final repo =
        FakeChatRepository(currentUserId: 'u1')
          ..signMediaUrls = true
          ..signMediaUrlFailuresBeforeSuccess = 3;
    String? built;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          home: ResolvedMediaUrl(
            signedMediaUrl: null,
            mediaKey: key,
            builder: (context, url) {
              built = url;
              return const Text('image');
            },
            loading: const Text('loading'),
            error: const Text('broken'),
          ),
        ),
      ),
    );
    // Past the in-provider retry backoff (400 ms + 1200 ms): pumpAndSettle
    // alone stops once no frame is scheduled, before those timers fire.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('broken'), findsOneWidget);
    expect(find.bySemanticsLabel('Tap to retry'), findsOneWidget);

    await tester.tap(find.text('broken'));
    await tester.pumpAndSettle();
    expect(find.text('image'), findsOneWidget);
    expect(built, contains('token=abc'));
  });

  test('a resolved tile does not re-sign on a connectivity flip', () async {
    // Connectivity is listened, not watched: a watch would rebuild — and
    // re-sign — every listened tile in the list on each flip.
    final repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
    final connectivity = StreamController<bool>.broadcast();
    addTearDown(connectivity.close);
    final container = makeContainer(repo, connectivity: connectivity);
    final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
    addTearDown(sub.close);
    await container.read(signedMediaUrlProvider(key).future);

    connectivity.add(false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    connectivity.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repo.signedUrlRequests.length, 1);
    expect(
      container.read(signedMediaUrlProvider(key)).value,
      contains('token=abc'),
    );
  });

  test(
    'an unlistened read disposed mid-retry still settles (no hang)',
    () async {
      // The voice resolver reads `.future` without listening, so the member
      // is disposed while it waits on a retry. That must end in the error the
      // resolver falls back on, not a future that never completes.
      final repo =
          FakeChatRepository(currentUserId: 'u1')
            ..signMediaUrls = true
            ..signMediaUrlFailuresBeforeSuccess = 3;
      final container = makeContainer(repo);

      await expectLater(
        container
            .read(signedMediaUrlProvider(key).future)
            .timeout(const Duration(milliseconds: 300)),
        throwsA(isA<SignedMediaUrlUnavailable>()),
      );
      expect(
        repo.signedUrlRequests.length,
        lessThan(3),
        reason: 'a disposed member stops retrying',
      );
    },
  );

  testWidgets('a tile keeps its last good URL when a refresh fails', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
    String? built;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
          signedMediaUrlRefreshAfterProvider.overrideWithValue(
            const Duration(seconds: 1),
          ),
        ],
        child: MaterialApp(
          home: ResolvedMediaUrl(
            signedMediaUrl: null,
            mediaKey: key,
            builder: (context, url) {
              built = url;
              return const Text('image');
            },
            loading: const Text('loading'),
            error: const Text('broken'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('image'), findsOneWidget);

    // The pre-expiry re-sign fails every attempt (offline at the mark).
    repo.signMediaUrlFailuresBeforeSuccess = 99;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(repo.signedUrlRequests.length, 4, reason: '1 + refresh try + 2');
    expect(find.text('image'), findsOneWidget);
    expect(find.text('broken'), findsNothing);
    expect(find.text('loading'), findsNothing);
    expect(built, contains('token=abc'));
  });

  testWidgets('the retry button is a semantic button that retries', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repo =
        FakeChatRepository(currentUserId: 'u1')
          ..signMediaUrls = true
          ..signMediaUrlFailuresBeforeSuccess = 3;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          home: ResolvedMediaUrl(
            signedMediaUrl: null,
            mediaKey: key,
            builder: (context, url) => const Text('image'),
            loading: const Text('loading'),
            error: const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.bySemanticsLabel('Tap to retry'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(node.getSemanticsData().hasFlag(SemanticsFlag.isButton), isTrue);

    // A screen reader's activation, not a pointer tap.
    tester.semantics.tap(find.semantics.byLabel('Tap to retry'));
    await tester.pumpAndSettle();
    expect(find.text('image'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('retryOnTap: false leaves the error tile as it is', (
    tester,
  ) async {
    // The video poster: its broken tile still plays the video on tap.
    final repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = false;
    var played = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          home: ResolvedMediaUrl(
            signedMediaUrl: null,
            mediaKey: key,
            retryOnTap: false,
            builder: (context, url) => const Text('poster'),
            loading: const Text('loading'),
            error: TextButton(
              onPressed: () => played++,
              child: const Text('play'),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Tap to retry'), findsNothing);
    await tester.tap(find.text('play'));
    expect(played, 1);
    expect(repo.signedUrlRequests.length, 3, reason: 'no retry on tap');
  });

  test('a sign that lands after an unlistened read was disposed still '
      'returns its URL', () async {
    // The voice resolver reads `.future` without listening, so the member
    // is disposed while the sign is in flight. The fresh URL must still
    // come back (not an error, so not the stale stored URL), and nothing
    // may be registered on the dead member.
    final repo =
        FakeChatRepository(currentUserId: 'u1')
          ..signMediaUrls = true
          ..signMediaUrlGate = Completer<void>();
    final container = makeContainer(repo);

    final read = container.read(signedMediaUrlProvider(key).future);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.exists(signedMediaUrlProvider(key)),
      isFalse,
      reason: 'precondition: the unlistened member was disposed',
    );

    repo.signMediaUrlGate!.complete();
    expect(await read, 'https://signed.test/$key?token=abc');
  });

  test('a later listened member survives past the refresh interval', () async {
    // A success landing on a disposed member used to start a refresh timer
    // that later fired against the key — disposing the live member that
    // had mounted since.
    final repo =
        FakeChatRepository(currentUserId: 'u1')
          ..signMediaUrls = true
          ..signMediaUrlGate = Completer<void>();
    final container = makeContainer(
      repo,
      refreshAfter: const Duration(milliseconds: 100),
    );

    final unlistened = container.read(signedMediaUrlProvider(key).future);
    await Future<void>.delayed(Duration.zero);
    repo.signMediaUrlGate!.complete();
    await unlistened.then<void>((_) {}, onError: (_) {});
    repo.signMediaUrlGate = null;

    var disposedWhileListened = false;
    final sub = container.listen(signedMediaUrlProvider(key), (_, next) {
      if (!next.hasValue && !next.isLoading) disposedWhileListened = true;
    });
    addTearDown(sub.close);
    await container.read(signedMediaUrlProvider(key).future);

    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(disposedWhileListened, isFalse);
    expect(container.exists(signedMediaUrlProvider(key)), isTrue);
    expect(
      container.read(signedMediaUrlProvider(key)).value,
      'https://signed.test/$key?token=abc',
    );
  });

  group('refresh follows the token expiry (fake time)', () {
    Widget tile(
      FakeChatRepository repo, {
      void Function(String)? onBuilt,
      String? stored,
    }) {
      return ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          home: ResolvedMediaUrl(
            signedMediaUrl: stored,
            mediaKey: key,
            builder: (context, url) {
              onBuilt?.call(url);
              return const Text('image');
            },
            loading: const Text('loading'),
            error: const Text('broken'),
          ),
        ),
      );
    }

    testWidgets('a near-expiry cache hit is re-signed before it expires, '
        'with forceRefresh', (tester) async {
      // The repository's cache hands back an entry with 90 s left; trusting
      // it for the default 8 minutes would show a dead URL for 6.5 of them.
      final repo =
          FakeChatRepository(currentUserId: 'u1')
            ..signMediaUrls = true
            ..cachedSignedUrlLifetime = const Duration(seconds: 90);
      await tester.pumpWidget(tile(repo));
      await tester.pump();
      expect(repo.signedUrlForceRefreshes, [false]);

      await tester.pump(const Duration(seconds: 29));
      expect(repo.signedUrlForceRefreshes, [false], reason: 'not yet');

      await tester.pump(const Duration(seconds: 2));
      expect(
        repo.signedUrlForceRefreshes,
        [false, true],
        reason: '60 s before the entry expires, and past the cache',
      );
      expect(find.text('image'), findsOneWidget);
    });

    testWidgets('a cache hit already inside the margin is re-signed at once', (
      tester,
    ) async {
      final repo =
          FakeChatRepository(currentUserId: 'u1')
            ..signMediaUrls = true
            ..cachedSignedUrlLifetime = const Duration(seconds: 30);
      await tester.pumpWidget(tile(repo));
      await tester.pump();
      expect(repo.signedUrlForceRefreshes, [false, true]);
      expect(find.text('image'), findsOneWidget);
    });

    testWidgets('the timed refresh of a fresh URL signs afresh', (
      tester,
    ) async {
      final repo = FakeChatRepository(currentUserId: 'u1')
        ..signMediaUrls = true;
      await tester.pumpWidget(tile(repo));
      await tester.pump();
      // 9-minute trust window, 60 s margin → re-sign at 8 minutes.
      await tester.pump(const Duration(minutes: 8, seconds: 1));
      expect(repo.signedUrlForceRefreshes, [false, true]);
    });

    testWidgets('a kept URL past its expiry, whose refresh failed, becomes '
        'the retry tile', (tester) async {
      final repo =
          FakeChatRepository(currentUserId: 'u1')
            ..signMediaUrls = true
            ..signedUrlLifetime = const Duration(minutes: 2);
      await tester.pumpWidget(tile(repo));
      await tester.pump();
      expect(find.text('image'), findsOneWidget);

      // Offline at the refresh mark (60 s before the 2-minute expiry).
      repo.signMediaUrlFailuresBeforeSuccess = 99;
      await tester.pump(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 2)); // past the retries
      expect(
        find.text('image'),
        findsOneWidget,
        reason: 'still inside its token life: keep the picture',
      );

      await tester.pump(const Duration(seconds: 60));
      expect(find.text('image'), findsNothing);
      expect(find.text('broken'), findsOneWidget);
      expect(find.bySemanticsLabel('Tap to retry'), findsOneWidget);

      // A retry that fails too must not bring the expired URL back (the
      // error after it still carries it as the previous value).
      await tester.tap(find.text('broken'));
      await tester.pump();
      expect(find.text('loading'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('image'), findsNothing);
      expect(find.text('broken'), findsOneWidget);
      expect(find.bySemanticsLabel('Tap to retry'), findsOneWidget);
    });

    testWidgets('after a success, a failed sign never falls back to the '
        'stored URL', (tester) async {
      // The stored URL was baked on at row fetch — no fresher than the one
      // that just expired. Past the last good URL, the tile is a retry.
      final repo =
          FakeChatRepository(currentUserId: 'u1')
            ..signMediaUrls = true
            ..signedUrlLifetime = const Duration(minutes: 2);
      final built = <String>[];
      await tester.pumpWidget(
        tile(repo, onBuilt: built.add, stored: 'https://stored.test/old'),
      );
      await tester.pump();
      expect(built.last, contains('token=abc'));

      repo.signMediaUrlFailuresBeforeSuccess = 99;
      await tester.pump(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 60));

      expect(built, isNot(contains('https://stored.test/old')));
      expect(find.text('broken'), findsOneWidget);
      expect(find.bySemanticsLabel('Tap to retry'), findsOneWidget);
    });

    testWidgets('a first resolution that fails still uses the stored URL', (
      tester,
    ) async {
      // No sign has ever succeeded: the stored URL is the only candidate
      // and, for a row fetched moments ago, a live one.
      final repo = FakeChatRepository(currentUserId: 'u1');
      final built = <String>[];
      await tester.pumpWidget(
        tile(repo, onBuilt: built.add, stored: 'https://stored.test/fresh'),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(built.last, 'https://stored.test/fresh');
    });
  });

  group('the retry tile reads as one', () {
    Widget brokenTile({required Size size, String? label}) {
      final repo = FakeChatRepository(currentUserId: 'u1');
      return ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          home: Center(
            child: SizedBox.fromSize(
              size: size,
              child:
                  label == null
                      ? ResolvedMediaUrl(
                        signedMediaUrl: null,
                        mediaKey: key,
                        builder: (context, url) => const Text('image'),
                        loading: const Text('loading'),
                        error: const ColoredBox(color: Colors.grey),
                      )
                      : ResolvedMediaUrl(
                        signedMediaUrl: null,
                        mediaKey: key,
                        retryLabel: label,
                        builder: (context, url) => const Text('image'),
                        loading: const Text('loading'),
                        error: const ColoredBox(color: Colors.grey),
                      ),
            ),
          ),
        ),
      );
    }

    testWidgets('a broken tile carries a refresh glyph and keeps its size', (
      tester,
    ) async {
      await tester.pumpWidget(
        brokenTile(
          size: const Size(220, 220),
          label: "Photo didn't load. Tap to retry",
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(
        find.bySemanticsLabel("Photo didn't load. Tap to retry"),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byType(ColoredBox).last),
        const Size(220, 220),
      );
    });

    testWidgets('the glyph keeps a legible size on an ordinary tile', (
      tester,
    ) async {
      await tester.pumpWidget(brokenTile(size: const Size(120, 120)));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      final glyph = tester.getRect(find.byIcon(Icons.refresh_rounded));
      expect(glyph.width, greaterThanOrEqualTo(16));
      expect(
        glyph.right,
        lessThanOrEqualTo(tester.getRect(find.byType(ColoredBox).last).right),
      );
    });

    testWidgets('a tile too small for the glyph is still a retry button', (
      tester,
    ) async {
      await tester.pumpWidget(brokenTile(size: const Size(40, 40)));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(find.bySemanticsLabel('Tap to retry'), findsOneWidget);
    });

    for (final kind in ['image', 'video']) {
      testWidgets('the $kind viewer\'s broken tile is a proper retry target', (
        tester,
      ) async {
        final repo = FakeChatRepository(currentUserId: 'me');
        final message = Message(
          id: kind,
          clientMessageId: 'client-$kind',
          relationshipId: 'relationship',
          senderId: 'partner',
          content: '',
          createdAt: DateTime(2026, 8, 24, 12),
          status: MessageStatus.sent,
          isMine: false,
          mediaKey: '$kind.${kind == 'image' ? 'jpg' : 'mp4'}',
          mediaType: kind,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatRepositoryProvider.overrideWithValue(repo),
              chatConnectivityProvider.overrideWith(
                (ref) => Stream.value(true),
              ),
            ],
            child: MaterialApp(
              home:
                  kind == 'image'
                      ? ImageViewerScreen(images: [message], initialIndex: 0)
                      : VideoViewerScreen(videos: [message], initialIndex: 0),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();

        final label =
            kind == 'image'
                ? "Photo didn't load. Tap to retry"
                : "Video didn't load. Tap to retry";
        final target = tester.getRect(find.bySemanticsLabel(label));
        expect(target.shortestSide, greaterThanOrEqualTo(48));
        final glyph = tester.getRect(find.byIcon(Icons.refresh_rounded));
        expect(glyph.width, greaterThanOrEqualTo(16), reason: 'icon');
        expect(
          tester
              .getRect(
                find
                    .ancestor(
                      of: find.byIcon(Icons.refresh_rounded),
                      matching: find.byType(DecoratedBox),
                    )
                    .first,
              )
              .width,
          greaterThanOrEqualTo(24),
          reason: 'badge',
        );
      });
    }

    testWidgets("a bubble's broken photo names what didn't load", (
      tester,
    ) async {
      final repo = FakeChatRepository(currentUserId: 'me');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatRepositoryProvider.overrideWithValue(repo),
            chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: Message(
                  id: 'photo',
                  clientMessageId: 'client-photo',
                  relationshipId: 'relationship',
                  senderId: 'partner',
                  content: '',
                  createdAt: DateTime(2026, 8, 24, 12),
                  status: MessageStatus.sent,
                  isMine: false,
                  mediaKey: 'photo.jpg',
                  mediaType: 'image',
                ),
                onReply: () {},
                onTimestampRevealChanged: (_) {},
                onImageTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(
        find.bySemanticsLabel("Photo didn't load. Tap to retry"),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });
  });
}
