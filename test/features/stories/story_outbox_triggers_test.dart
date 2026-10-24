import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_triggers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/outbox_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('outbox_triggers'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Real time, bounded: the sign-in pass now runs the account-switch wipe
  /// first, whose default vault asks the engine for Application Support (a
  /// platform round trip), so a fixed number of event-loop turns is not
  /// enough under a loaded parallel run.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// The cold-start pass has reached its flush (it creates the controller)
  /// and that flush, on an empty queue, has settled.
  Future<void> coldStartDone(OutboxHarness h) async {
    await until(() => h.container.exists(storyOutboxProvider));
    await pumpEventQueue(times: 20);
  }

  /// A row waiting out a long backoff, as after an offline failure.
  Future<void> seedWaiting(OutboxHarness h) => h.store.put(
    outboxUserId,
    outboxRecord(dir).copyWith(
      attempts: 6,
      lastErrorCode: StoryErrorCodes.network,
      nextAttemptAt: DateTime.now().add(const Duration(minutes: 5)),
    ),
  );

  test('connectivity coming back flushes a waiting story at once', () async {
    final online = StreamController<bool>();
    addTearDown(online.close);
    final h = outboxHarness(
      extra: [chatConnectivityProvider.overrideWith((ref) => online.stream)],
    );
    addTearDown(h.container.dispose);
    // Let the cold-start pass run first; it would post anything already
    // queued, which is a different test.
    h.container.read(storyOutboxTriggersProvider);
    await coldStartDone(h);
    await seedWaiting(h);
    online.add(false);
    await pumpEventQueue();
    expect(h.gateway.finalizes, isEmpty);

    online.add(true);
    await pumpEventQueue(times: 50);
    expect(h.gateway.finalizes, hasLength(1));
    // The success path deletes the local files (real file IO, not a
    // microtask) before removing the row: let the in-flight pass settle.
    await h.controller().flush();
    expect(await h.store.readAll(outboxUserId), isEmpty);
  });

  test('coming back to the foreground flushes a waiting story', () async {
    final h = outboxHarness(
      extra: [
        chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    addTearDown(h.container.dispose);
    h.container.read(storyOutboxTriggersProvider);
    await coldStartDone(h); // the cold-start pass, on an empty queue
    await seedWaiting(h);
    final before = h.gateway.finalizes.length;

    final binding = TestWidgetsFlutterBinding.instance;
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(s);
    }
    await pumpEventQueue(times: 50);
    expect(h.gateway.finalizes.length, before + 1);
  });

  test(
    'a cold start with someone signed in drains without opening Conversations',
    () async {
      final h = outboxHarness(
        extra: [
          chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
        ],
      );
      addTearDown(h.container.dispose);
      await h.store.put(outboxUserId, outboxRecord(dir));
      h.container.read(storyOutboxTriggersProvider); // what App.initState does
      await until(() => h.gateway.finalizes.isNotEmpty);
      await pumpEventQueue(times: 50);
      expect(h.gateway.finalizes, hasLength(1));
    },
  );

  test('a user-metadata change keeps the same controller', () async {
    final user = StateProvider<User?>((_) => outboxUser());
    final h = outboxHarness(
      user: currentUserProvider.overrideWith((ref) => ref.watch(user)),
    );
    addTearDown(h.container.dispose);
    final first = h.controller();
    h.container.read(user.notifier).state = User(
      id: outboxUserId,
      appMetadata: const {},
      userMetadata: const {'name': 'renamed'},
      aud: 'authenticated',
      createdAt: '2026-10-01T00:00:00Z',
    );
    expect(identical(h.controller(), first), isTrue);
  });

  test(
    'a disposed controller cancels its retry timer and writes nothing',
    () async {
      final h = outboxHarness();
      h.gateway.intentScript.add(StoryApiError.network());
      final controller = h.controller();
      await controller.enqueue(outboxRecord(dir));
      expect(controller.debugHasRetryTimer, isTrue);
      h.container.dispose();
      expect(controller.debugHasRetryTimer, isFalse);
      await controller
          .flush(); // must not throw (StateError) or touch the store
      expect(h.gateway.intentCalls, isEmpty);
    },
  );

  test('a wipe mid-upload: the in-flight drive never writes the row back '
      '(Review Focus 2)', () async {
    final h = outboxHarness();
    addTearDown(h.container.dispose);
    h.gateway.uploadGate = Completer<void>();
    final drive = h.controller().enqueue(outboxRecord(dir));
    await pumpEventQueue();
    await h.store.wipeAll();
    h.gateway.uploadGate!.complete();
    await drive;
    expect(await h.store.readAll(outboxUserId), isEmpty);
    expect(h.gateway.finalizes, isEmpty);
  });

  test('App starts the story outbox triggers (01 #9)', () {
    final src = File('lib/app/app.dart').readAsStringSync();
    expect(src, contains('ref.read(storyOutboxTriggersProvider)'));
  });

  test('an account switch wipes the other person\'s queued stories and files',
      () async {
    final support = Directory.systemTemp.createTempSync('switch_support');
    addTearDown(() => support.deleteSync(recursive: true));
    final vault = StoryMediaVault(supportDirectory: () async => support);
    final user = StateProvider<User?>((_) => outboxUser('previous'));
    final h = outboxHarness(
      user: currentUserProvider.overrideWith((ref) => ref.watch(user)),
      extra: [
        storyMediaVaultProvider.overrideWithValue(vault),
        chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    addTearDown(h.container.dispose);
    // Keep it queued: the controller's own first pass and the sign-in
    // pass both fail offline, so the row is still there at the switch.
    h.gateway.intentScript.addAll([
      StoryApiError.network(),
      StoryApiError.network(),
      StoryApiError.network(),
    ]);
    final raw = outboxRecord(dir);
    final stored = await vault.adopt(
      userId: 'previous', clientStoryId: raw.clientStoryId,
      mediaPath: raw.localMediaPath, thumbnailPath: raw.localThumbnailPath,
    );
    await h.store.put('previous',
        StoryRecordPaths.withPaths(raw, stored.media, stored.thumbnail));
    h.container.read(storyOutboxTriggersProvider);
    await coldStartDone(h);

    expect(await h.store.readAll('previous'), hasLength(1),
        reason: 'still queued before the switch');
    h.container.read(user.notifier).state = outboxUser('next');
    await pumpEventQueue(times: 50);
    final gone = Directory('${support.path}/story_outbox/previous');
    await until(() => !gone.existsSync());

    expect(await h.store.readAll('previous'), isEmpty);
    expect(Directory('${support.path}/story_outbox/previous').existsSync(), isFalse);
  });
}
