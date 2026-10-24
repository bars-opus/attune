import 'dart:async';

import 'package:attune/core/ui/feedback/audio_session.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/chat_test_harness.dart';
import 'support/fake_voice_engine.dart';

// Top level: Dart has no local getters.
late FakeVoiceEngine engine;
late ProviderContainer container;
VoicePlaybackController get controller =>
    container.read(voicePlaybackControllerProvider.notifier);
VoicePlaybackState get state => container.read(voicePlaybackControllerProvider);
Future<String?> url() async => 'https://example.com/a.m4a';
Future<String?> localFile() async => '/tmp/voice/a.m4a';
Future<void> tick() => Future<void>.delayed(Duration.zero);

/// The real session port is a platform channel, absent on the test host
/// (chat review #40: every pause/complete/stop returns the session).
Override fakeAudioSession() => audioSessionProvider.overrideWith(
  (ref) => AudioSessionCoordinator(port: FakeAudioSessionPort()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    engine = FakeVoiceEngine();
    container = ProviderContainer(
      overrides: [
        voicePlaybackEngineProvider.overrideWithValue(engine),
        fakeAudioSession(),
        voicePlaybackStallAfterProvider.overrideWithValue(
          const Duration(milliseconds: 60),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  test(
    'toggle plays the resolved source and publishes the current id',
    () async {
      await controller.toggle('m1', url);
      expect(engine.lastSource, 'https://example.com/a.m4a');
      expect(engine.lastIsLocalFile, isFalse);
      expect(state.messageId, 'm1');
      expect(state.isPlaying, isTrue);
      expect(state.isLoading, isFalse);
      expect(container.read(currentlyPlayingVoiceMessageIdProvider), 'm1');
    },
  );

  test('a local file plays as a file source', () async {
    await controller.toggle('m1', () async => '/tmp/voice/a.m4a');
    expect(engine.lastIsLocalFile, isTrue);
  });

  test('the controller, not the bubble, owns position', () async {
    await controller.toggle('m1', url);
    engine.positionsController.add(const Duration(seconds: 7));
    await tick();
    expect(state.positionFor('m1'), const Duration(seconds: 7));
    expect(state.positionFor('other'), Duration.zero);
  });

  test('second toggle pauses, third resumes from where it was', () async {
    await controller.toggle('m1', url);
    engine.positionsController.add(const Duration(seconds: 3));
    await tick();
    await controller.toggle('m1', url);
    expect(state.isPlaying, isFalse);
    expect(state.position, const Duration(seconds: 3));
    expect(container.read(currentlyPlayingVoiceMessageIdProvider), isNull);

    await controller.toggle('m1', url);
    expect(engine.calls.last, 'resume');
    expect(engine.calls.where((c) => c == 'play').length, 1);
    expect(state.isPlaying, isTrue);
  });

  test(
    'starting another message stops the first and resets position',
    () async {
      await controller.toggle('m1', url);
      engine.positionsController.add(const Duration(seconds: 5));
      await tick();
      await controller.toggle('m2', () async => 'https://example.com/b.m4a');
      expect(engine.calls, containsAllInOrder(['play', 'stop', 'play']));
      expect(state.messageId, 'm2');
      expect(state.position, Duration.zero, reason: 'no carry-over');
      expect(state.positionFor('m1'), Duration.zero);
    },
  );

  test('completion returns the bubble to the start', () async {
    await controller.toggle('m1', url);
    engine.positionsController.add(const Duration(seconds: 2));
    engine.completionsController.add(null);
    await tick();
    expect(state.isPlaying, isFalse);
    expect(state.positionFor('m1'), Duration.zero);
    expect(container.read(currentlyPlayingVoiceMessageIdProvider), isNull);
  });

  test('an OS interruption reported by the engine shows as paused', () async {
    await controller.toggle('m1', url);
    engine.playingController.add(false);
    await tick();
    expect(state.isPlaying, isFalse);
    await controller.toggle('m1', url);
    expect(engine.calls.last, 'resume');
  });

  // Fake time (M6): the watchdog's Timer and clock both run on the test's
  // clock, so neither the stall nor its absence depends on machine load.
  ProviderContainer stallContainer(FakeVoiceEngine e) => ProviderContainer(
    overrides: [
      voicePlaybackEngineProvider.overrideWithValue(e),
      fakeAudioSession(),
      voicePlaybackStallAfterProvider.overrideWithValue(
        const Duration(milliseconds: 60),
      ),
    ],
  );

  testWidgets(
    'a stalled position (interruption the plugin did not report) pauses',
    (tester) async {
      final e = FakeVoiceEngine();
      final c = stallContainer(e);
      VoicePlaybackState s() => c.read(voicePlaybackControllerProvider);
      // A local file cannot be buffering: no advance means interrupted.
      await c
          .read(voicePlaybackControllerProvider.notifier)
          .toggle('m1', localFile);
      e.positionsController.add(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 40));
      expect(s().isPlaying, isTrue, reason: 'inside the stall bound');
      await tester.pump(const Duration(milliseconds: 60));
      expect(s().isPlaying, isFalse);
      expect(e.calls.last, 'pause');
      c.dispose();
    },
  );

  testWidgets(
    'a position repeated every frame without advancing is still a stall',
    (tester) async {
      final e = FakeVoiceEngine();
      final c = stallContainer(e);
      VoicePlaybackState s() => c.read(voicePlaybackControllerProvider);
      // audioplayers' FramePositionUpdater reports the position every frame
      // while it believes it is playing, so an interruption it missed shows
      // as the SAME value arriving over and over, not as silence.
      await c
          .read(voicePlaybackControllerProvider.notifier)
          .toggle('m1', localFile);
      for (var i = 0; i < 8; i++) {
        e.positionsController.add(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(s().isPlaying, isFalse);
      expect(e.calls.last, 'pause');
      c.dispose();
    },
  );

  test('a video taking the floor pauses the voice note', () async {
    await controller.toggle('m1', url);
    container.read(currentlyPlayingVoiceMessageIdProvider.notifier).state =
        null;
    await tick();
    expect(state.isPlaying, isFalse);
    expect(engine.calls.last, 'pause');
  });

  test('starting a voice note clears any playing video', () async {
    container.read(currentlyPlayingVideoMessageIdProvider.notifier).state =
        'v1';
    await controller.toggle('m1', url);
    expect(container.read(currentlyPlayingVideoMessageIdProvider), isNull);
  });

  test('speed cycles 1 → 1.5 → 2 → 1 and sticks for the next note', () async {
    await controller.toggle('m1', url);
    await controller.cycleRate();
    expect(state.rate, 1.5);
    expect(engine.lastRate, 1.5);
    await controller.cycleRate();
    expect(state.rate, 2.0);
    await controller.cycleRate();
    expect(state.rate, 1.0);
    await controller.cycleRate();
    await controller.toggle('m2', url);
    expect(engine.lastRate, 1.5, reason: 'rate is passed into play');
  });

  test('seek only applies to the current message', () async {
    await controller.toggle('m1', url);
    await controller.seek('m2', const Duration(seconds: 9));
    expect(engine.lastSeek, isNull);
    await controller.seek('m1', const Duration(seconds: 9));
    expect(engine.lastSeek, const Duration(seconds: 9));
    expect(state.position, const Duration(seconds: 9));
  });

  test('an unresolvable source reports a failure for that message', () async {
    await controller.toggle('m1', () async => null);
    expect(state.failureCount, 1);
    expect(state.failedMessageId, 'm1');
    expect(state.messageId, isNull);
    expect(container.read(currentlyPlayingVoiceMessageIdProvider), isNull);
  });

  test(
    'an engine error reports a failure and leaves nothing playing',
    () async {
      engine.nextPlayError = StateError('codec');
      await controller.toggle('m1', url);
      expect(state.failureCount, 1);
      expect(state.isPlaying, isFalse);
    },
  );

  test('backgrounding the app pauses (no background playback)', () async {
    await controller.toggle('m1', url);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tick();
    expect(state.isPlaying, isFalse);
  });

  test('an inactive blip pauses too: the privacy cover is up and the chat '
      'stays mounted behind it (stories Wave 3)', () async {
    await controller.toggle('m1', url);
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tick();
    expect(state.isPlaying, isFalse);
  });

  test('coming back does not start the note again on its own', () async {
    await controller.toggle('m1', url);
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tick();
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tick();
    expect(state.isPlaying, isFalse);
  });

  test('stop() clears everything (leaving the chat screen)', () async {
    await controller.toggle('m1', url);
    await controller.stop();
    expect(state, VoicePlaybackState.idle.copyWith(rate: state.rate));
    expect(engine.calls.last, 'stop');
    expect(container.read(currentlyPlayingVoiceMessageIdProvider), isNull);
  });

  group('signing a voice note (signedMediaUrlProvider)', () {
    // Plan 2 Task 6 made signedMediaUrlProvider an autoDispose notifier that
    // retries in place. An unlistened `.future` read disposes the member
    // before the first retry, so play got ONE sign attempt; the controller
    // keeps it listened for the read so the retries apply.
    late FakeChatRepository repo;
    late ProviderContainer chat;
    VoicePlaybackController voice() =>
        chat.read(voicePlaybackControllerProvider.notifier);

    setUp(() {
      repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
      chat = buildChatContainer(
        repository: repo,
        userId: 'u1',
        extraOverrides: [
          voicePlaybackEngineProvider.overrideWithValue(FakeVoiceEngine()),
        ],
      );
      addTearDown(chat.dispose);
    });

    test('a sign that fails once is retried, not given up on', () async {
      repo.signMediaUrlFailuresBeforeSuccess = 1;
      final url = await voice().signedUrlFor('chat-media/v.m4a');
      expect(url, 'https://signed.test/chat-media/v.m4a?token=abc');
      expect(repo.signedUrlRequests, hasLength(2));
    });

    test('a key that cannot be signed yields null after the retries', () async {
      repo.signMediaUrls = false;
      final url = await voice().signedUrlFor('chat-media/v.m4a');
      expect(url, isNull);
      expect(
        repo.signedUrlRequests,
        hasLength(3),
        reason: 'first try plus the provider\'s two backoff retries',
      );
      await tick();
      expect(
        chat.exists(signedMediaUrlProvider('chat-media/v.m4a')),
        isFalse,
        reason: 'the subscription is closed once the read settles',
      );
    });
  });

  test('a finished note replays from the start on the next tap', () async {
    // audioplayers' default ReleaseMode.release frees the source on
    // completion: resuming it would do nothing.
    await controller.toggle('m1', url);
    engine.positionsController.add(const Duration(seconds: 2));
    engine.completionsController.add(null);
    await tick();
    expect(state.messageId, isNull, reason: 'a finished note is not held');

    await controller.toggle('m1', url);
    expect(engine.resumesWithoutSource, 0);
    expect(engine.calls.where((c) => c == 'play').length, 2);
    expect(engine.calls.last, 'play');
    expect(state.isPlaying, isTrue);
    expect(state.messageId, 'm1');
  });

  group('cancelling a note that is still loading', () {
    test('backgrounding the app cancels the pending play', () async {
      final gate = Completer<String?>();
      final pending = controller.toggle('m1', () => gate.future);
      expect(state.isLoading, isTrue);
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tick();
      gate.complete('https://example.com/a.m4a');
      await pending;
      expect(engine.calls, isNot(contains('play')));
      expect(state.messageId, isNull);
      expect(state.isLoading, isFalse);
      expect(state.isPlaying, isFalse);
    });

    test('a second tap on the loading note cancels it (M2)', () async {
      final gate = Completer<String?>();
      final pending = controller.toggle('m1', () => gate.future);
      expect(state.isLoading, isTrue);
      await controller.toggle('m1', () => gate.future);
      expect(state.messageId, isNull, reason: 'the tap stops the fetch');
      expect(state.isLoading, isFalse);
      expect(container.read(currentlyPlayingVoiceMessageIdProvider), isNull);
      gate.complete('https://example.com/a.m4a');
      await pending;
      expect(engine.calls, isNot(contains('play')));
      expect(state.messageId, isNull);
      expect(state.isPlaying, isFalse);
    });

    test('a video taking the floor cancels the pending play', () async {
      final gate = Completer<String?>();
      final pending = controller.toggle('m1', () => gate.future);
      container.read(currentlyPlayingVoiceMessageIdProvider.notifier).state =
          null;
      await tick();
      gate.complete('https://example.com/a.m4a');
      await pending;
      expect(engine.calls, isNot(contains('play')));
      expect(state.messageId, isNull);
      expect(state.isLoading, isFalse);
    });
  });

  test(
    'leaving while the previous note is still stopping leaves nothing loading',
    () async {
      await controller.toggle('m1', url);
      engine.stopGate = Completer<void>();
      final switching = controller.toggle(
        'm2',
        () async => 'https://example.com/b.m4a',
      );
      final leaving = controller.stop();
      engine.stopGate!.complete();
      await Future.wait([switching, leaving]);
      expect(state.messageId, isNull);
      expect(state.isLoading, isFalse);
      expect(engine.lastSource, 'https://example.com/a.m4a');
      expect(container.read(currentlyPlayingVoiceMessageIdProvider), isNull);
    },
  );

  group('owner (the conversation a note was started in)', () {
    test('stop(ifOwnedBy:) leaves another chat\'s note alone', () async {
      await controller.toggle('m1', url, ownerId: 'rel-b');
      await controller.stop(ifOwnedBy: 'rel-a');
      expect(state.isPlaying, isTrue);
      await controller.stop(ifOwnedBy: 'rel-b');
      expect(state.messageId, isNull);
    });

    test('an unowned note stops on any leave', () async {
      await controller.toggle('m1', url);
      await controller.stop(ifOwnedBy: 'rel-a');
      expect(state.messageId, isNull);
    });

    test('stopIfOwnedByAnother stops only a different chat\'s note', () async {
      await controller.toggle('m1', url, ownerId: 'rel-a');
      await controller.stopIfOwnedByAnother('rel-a');
      expect(state.isPlaying, isTrue);
      await controller.stopIfOwnedByAnother('rel-b');
      expect(state.messageId, isNull);
      expect(engine.calls.last, 'stop');
    });

    test('stopMessage stops only that note', () async {
      await controller.toggle('m1', url);
      await controller.stopMessage('m2');
      expect(state.isPlaying, isTrue);
      await controller.stopMessage('m1');
      expect(state.messageId, isNull);
    });
  });

  test('signing out or switching account stops playback', () async {
    final user = StateProvider<User?>((ref) => testUser('u1'));
    final c = ProviderContainer(
      overrides: [
        voicePlaybackEngineProvider.overrideWithValue(FakeVoiceEngine()),
        fakeAudioSession(),
        currentUserProvider.overrideWith((ref) => ref.watch(user)),
      ],
    );
    addTearDown(c.dispose);
    final voice = c.read(voicePlaybackControllerProvider.notifier);

    await voice.toggle('m1', url);
    c.read(user.notifier).state = testUser('u2');
    await tick();
    expect(c.read(voicePlaybackControllerProvider).messageId, isNull);

    await voice.toggle('m1', url);
    c.read(user.notifier).state = null;
    await tick();
    expect(c.read(voicePlaybackControllerProvider).messageId, isNull);
    await voice.stop();
  });

  group('buffering a remote note (fake time)', () {
    ProviderContainer fakeTimeContainer(FakeVoiceEngine e) {
      final c = ProviderContainer(
        overrides: [
          voicePlaybackEngineProvider.overrideWithValue(e),
          fakeAudioSession(),
        ],
      );
      return c;
    }

    testWidgets(
      'no progress shows the loading ring at 1.5 s and pauses only at 8 s',
      (tester) async {
        final e = FakeVoiceEngine();
        final c = fakeTimeContainer(e);
        VoicePlaybackState s() => c.read(voicePlaybackControllerProvider);
        await c
            .read(voicePlaybackControllerProvider.notifier)
            .toggle('m1', url);
        e.positionsController.add(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 1200));
        expect(s().isBuffering, isFalse);

        await tester.pump(const Duration(milliseconds: 500));
        expect(s().isBuffering, isTrue, reason: 'the ring, not a pause');
        expect(s().isPlaying, isTrue);
        expect(e.calls, isNot(contains('pause')));

        await tester.pump(const Duration(seconds: 7));
        expect(s().isPlaying, isFalse, reason: 'past 8 s: give up, paused');
        expect(s().isBuffering, isFalse);
        expect(e.calls.last, 'pause');
        c.dispose();
      },
    );

    testWidgets('progress again clears buffering and restarts the clock', (
      tester,
    ) async {
      final e = FakeVoiceEngine();
      final c = fakeTimeContainer(e);
      VoicePlaybackState s() => c.read(voicePlaybackControllerProvider);
      await c.read(voicePlaybackControllerProvider.notifier).toggle('m1', url);
      await tester.pump(const Duration(seconds: 2));
      expect(s().isBuffering, isTrue);

      e.positionsController.add(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 10));
      expect(s().isBuffering, isFalse);
      await tester.pump(const Duration(seconds: 7));
      expect(s().isPlaying, isTrue, reason: '7 s since the last advance');
      c.dispose();
    });

    testWidgets('a local file still pauses at 1.5 s', (tester) async {
      final e = FakeVoiceEngine();
      final c = fakeTimeContainer(e);
      VoicePlaybackState s() => c.read(voicePlaybackControllerProvider);
      await c
          .read(voicePlaybackControllerProvider.notifier)
          .toggle('m1', localFile);
      await tester.pump(const Duration(milliseconds: 1700));
      expect(s().isPlaying, isFalse);
      expect(s().isBuffering, isFalse);
      expect(e.calls.last, 'pause');
      c.dispose();
    });
  });

  test(
    'a late completion from the previous source cannot reset a new note',
    () async {
      await controller.toggle('m1', url);
      engine.positionsController.add(const Duration(seconds: 3));
      await tick();
      await controller.toggle('m2', () async => 'https://example.com/b.m4a');
      // m1's completion lands after m2 started, before m2 played a frame.
      engine.completionsController.add(null);
      await tick();
      expect(state.messageId, 'm2');
      expect(state.isPlaying, isTrue);
      expect(container.read(currentlyPlayingVoiceMessageIdProvider), 'm2');

      // m2's own completion, once it has played, still resets.
      engine.positionsController.add(const Duration(seconds: 1));
      engine.completionsController.add(null);
      await tick();
      expect(state.messageId, isNull);
    },
  );

  test('stopMessages matches the client id or the server id', () async {
    await controller.toggle('c1', url, serverMessageId: 's1');
    await controller.stopMessages({'other'});
    expect(state.isPlaying, isTrue);
    await controller.stopMessages({'s1'});
    expect(state.messageId, isNull);

    await controller.toggle('c1', url, serverMessageId: 's1');
    await controller.stopMessages({'c1'});
    expect(state.messageId, isNull);
  });

  group('audio session (chat review #40)', () {
    late FakeAudioSessionPort port;
    late AudioSessionCoordinator session;

    setUp(() {
      port = FakeAudioSessionPort();
      session = AudioSessionCoordinator(
        port: port,
        platform: TargetPlatform.iOS,
      );
      container = ProviderContainer(
        overrides: [
          voicePlaybackEngineProvider.overrideWithValue(engine),
          voicePlaybackStallAfterProvider.overrideWithValue(
            const Duration(milliseconds: 60),
          ),
          audioSessionProvider.overrideWithValue(session),
        ],
      );
      addTearDown(container.dispose);
    });

    test('play borrows the voice-note context on the engine; completion '
        'returns it and ambient comes back', () async {
      await controller.toggle('m1', url);
      expect(engine.contexts, [AppAudioContexts.voiceNote]);
      expect(session.playbackHeld, isTrue);
      expect(port.globalContexts, isEmpty, reason: 'nothing restored yet');

      engine.positionsController.add(const Duration(seconds: 1));
      await tick();
      engine.completionsController.add(null);
      await tick();
      expect(state.messageId, isNull);
      expect(session.playbackHeld, isFalse);
      expect(
        port.globalContexts,
        [AppAudioContexts.chirp],
        reason: 'the chirp context is restored the moment the note ends',
      );
    });

    test('pause returns the session; resume borrows it again — once each',
        () async {
      await controller.toggle('m1', url);
      await controller.toggle('m1', url); // pause
      expect(session.playbackHeld, isFalse);
      expect(port.globalContexts, [AppAudioContexts.chirp]);
      await controller.toggle('m1', url); // resume
      expect(engine.calls.last, 'resume');
      expect(session.playbackHeld, isTrue);
      expect(engine.contexts.length, 2);
    });

    test('stop (leaving the chat) and an OS pause both return it', () async {
      await controller.toggle('m1', url);
      await controller.stop();
      expect(session.playbackHeld, isFalse);

      await controller.toggle('m1', url);
      engine.playingController.add(false); // interruption reported
      await tick();
      expect(session.playbackHeld, isFalse);
      expect(port.globalContexts.length, 2);
    });

    test('a play that fails to start never leaves a hold behind', () async {
      engine.nextPlayError = Exception('no codec');
      await controller.toggle('m1', url);
      expect(state.failedMessageId, 'm1');
      expect(session.playbackHeld, isFalse);
      expect(port.globalContexts, [AppAudioContexts.chirp]);
    });

    test('a chirp during a voice note does not yank the session (Review '
        'Focus 1, end to end)', () async {
      await controller.toggle('m1', url);
      final chirp = <AudioContext>[];
      await session.beforeChirp((c) async => chirp.add(c));
      expect(chirp, isEmpty);
    });

    test('disposing mid-playback returns the session', () async {
      await controller.toggle('m1', url);
      container.dispose();
      await tick();
      expect(session.playbackHeld, isFalse);
    });
  });

  group('audio session pairing (one hold per playing note)', () {
    late _SpySession spy;

    ProviderContainer spyContainer(
      _SpySession s, {
      List<Override> extra = const [],
    }) => ProviderContainer(
      overrides: [
        voicePlaybackEngineProvider.overrideWithValue(engine),
        voicePlaybackStallAfterProvider.overrideWithValue(
          const Duration(hours: 1),
        ),
        audioSessionProvider.overrideWithValue(s),
        ...extra,
      ],
    );

    setUp(() {
      spy = _SpySession();
      container = spyContainer(spy);
      addTearDown(container.dispose);
    });

    Future<void> finish() async {
      engine.positionsController.add(const Duration(seconds: 1));
      await tick();
      engine.completionsController.add(null);
      await tick();
    }

    test('completion returns exactly once; a replay borrows again', () async {
      await controller.toggle('m1', url);
      await finish();
      expect((spy.begins, spy.ends), (1, 1));
      expect(spy.playbackHeld, isFalse);

      await controller.toggle('m1', url); // replay from the start
      expect(engine.calls.where((c) => c == 'play').length, 2);
      expect((spy.begins, spy.ends), (2, 1));
      expect(spy.playbackHeld, isTrue);
      await finish();
      expect((spy.begins, spy.ends), (2, 2));
    });

    test('switching notes while one plays keeps ONE hold', () async {
      await controller.toggle('m1', url);
      await controller.toggle('m2', () async => 'https://example.com/b.m4a');
      expect(state.messageId, 'm2');
      expect(spy.begins - spy.ends, 1, reason: 'never two holds at once');
      expect(spy.playbackHeld, isTrue);
      await finish();
      expect(spy.begins, spy.ends);
      expect(spy.playbackHeld, isFalse);
    });

    test('switching from a paused note borrows for the new one', () async {
      await controller.toggle('m1', url);
      await controller.toggle('m1', url); // pause: returned
      await controller.toggle('m2', () async => 'https://example.com/b.m4a');
      expect((spy.begins, spy.ends), (2, 1));
      expect(spy.playbackHeld, isTrue);
    });

    test('nothing to return is never returned (no double end)', () async {
      await controller.toggle('m1', url);
      await controller.toggle('m1', url); // pause
      engine.playingController.add(false); // the plugin echoes the pause
      await tick();
      await controller.stop();
      container.dispose();
      await tick();
      expect((spy.begins, spy.ends), (1, 1));
    });

    test('cancelling a note still loading neither borrows nor returns',
        () async {
      final gate = Completer<String?>();
      final playing = controller.toggle('m1', () => gate.future);
      await tick();
      await controller.toggle('m1', url); // second tap while loading: cancel
      gate.complete('https://example.com/a.m4a');
      await playing;
      expect((spy.begins, spy.ends), (0, 0));
      expect(state.messageId, isNull);
    });

    test('a note removed elsewhere, or another chat taking the screen, '
        'returns it', () async {
      await controller.toggle('c1', url, serverMessageId: 's1', ownerId: 'a');
      await controller.stopMessages({'s1'});
      expect((spy.begins, spy.ends), (1, 1));

      await controller.toggle('c2', url, ownerId: 'a');
      await controller.stopIfOwnedByAnother('b');
      expect((spy.begins, spy.ends), (2, 2));
      expect(spy.playbackHeld, isFalse);
    });

    test('a session that cannot be borrowed fails the play and holds '
        'nothing', () async {
      final refusing = _SpySession(failBegin: true);
      container = spyContainer(refusing);
      addTearDown(container.dispose);

      await controller.toggle('m1', url);
      expect(state.failedMessageId, 'm1');
      expect(engine.calls, isNot(contains('play')));
      expect((refusing.begins, refusing.ends), (1, 0));
      expect(refusing.playbackHeld, isFalse);
    });

    test('a release that throws never surfaces (best effort)', () async {
      final broken = _SpySession(failEnd: true);
      container = spyContainer(broken);
      addTearDown(container.dispose);

      await controller.toggle('m1', url);
      await controller.toggle('m1', url); // pause → release throws
      await tick();
      expect(state.isPlaying, isFalse);
      await controller.toggle('m1', url); // resume borrows again
      expect((broken.begins, broken.ends), (2, 1));
      expect(state.isPlaying, isTrue);
    });

    /// Lets the in-flight toggle reach the gated borrow.
    Future<void> untilBorrowing(int begins) async {
      for (var i = 0; i < 20 && spy.begins < begins; i++) {
        await tick();
      }
      expect(spy.begins, begins, reason: 'the borrow is in flight');
    }

    List<String> callsAfterLast(String call) =>
        engine.calls.sublist(engine.calls.lastIndexOf(call) + 1);

    test('a pause during the resume\'s borrow wins (review I1)', () async {
      await controller.toggle('m1', url);
      await controller.toggle('m1', url); // pause
      final gate = spy.beginGate = Completer<void>();
      final resuming = controller.toggle('m1', url); // resume
      await untilBorrowing(2);
      await controller.toggle('m1', url); // pause, mid-borrow
      gate.complete();
      await resuming;

      expect(callsAfterLast('pause'), isNot(contains('resume')));
      expect(state.isPlaying, isFalse);
      expect(state.messageId, 'm1', reason: 'still paused, resumable');
      expect((spy.begins, spy.ends), (2, 2));
      expect(spy.playbackHeld, isFalse);

      spy.beginGate = null;
      await controller.toggle('m1', url); // a later resume still works
      expect(engine.calls.last, 'resume');
      expect((spy.begins, spy.ends), (3, 2));
      expect(spy.playbackHeld, isTrue);
    });

    test('a resume borrow that fails after another note took over leaves '
        'that note alone (T3 carry)', () async {
      await controller.toggle('m1', url);
      await controller.toggle('m1', url); // pause
      final gate = spy.beginGate = Completer<void>();
      spy.beginGateError = StateError('setCategory failed');
      final resuming = controller.toggle('m1', url); // resume
      await untilBorrowing(2);
      spy.beginGate = null;
      spy.beginGateError = null;
      await controller.toggle(
        'm2',
        () async => 'https://example.com/b.m4a',
      ); // the person taps another note while m1's borrow is in flight
      expect(state.messageId, 'm2');
      expect(state.isPlaying, isTrue);
      gate.complete(); // m1's borrow now throws
      await resuming;
      await tick();

      expect(state.messageId, 'm2', reason: 'm1 failing must not reset m2');
      expect(state.isPlaying, isTrue);
      expect(state.failedMessageId, isNull);
      // m2 still holds the session (it was borrowed for it afresh).
      expect(spy.playbackHeld, isTrue);
      await controller.toggle('m2', () async => 'https://example.com/b.m4a');
      await tick();
      expect(spy.playbackHeld, isFalse, reason: 'pausing m2 returns it');
    });

    test('leaving the chat during the resume\'s borrow silences it (review '
        'I1)', () async {
      await controller.toggle('m1', url);
      await controller.toggle('m1', url); // pause
      final gate = spy.beginGate = Completer<void>();
      final resuming = controller.toggle('m1', url); // resume
      await untilBorrowing(2);
      await controller.stop(); // the chat screen went away
      gate.complete();
      await resuming;

      expect(callsAfterLast('stop'), isNot(contains('resume')));
      expect(state.messageId, isNull);
      expect((spy.begins, spy.ends), (2, 2));
      expect(spy.playbackHeld, isFalse);
    });

    test('a note cancelled during its first borrow never plays (review '
        'M1)', () async {
      final gate = spy.beginGate = Completer<void>();
      final starting = controller.toggle('m1', url);
      await untilBorrowing(1);
      await controller.toggle('m1', url); // second tap while loading: cancel
      gate.complete();
      await starting;

      expect(engine.calls, isNot(contains('play')));
      expect(state.messageId, isNull);
      expect((spy.begins, spy.ends), (1, 1));
      expect(spy.playbackHeld, isFalse);
    });

    test('a device that reports "stopped" mid-switch re-borrows for the new '
        'note (review M4)', () async {
      await controller.toggle('m1', url);
      final gate = engine.stopGate = Completer<void>();
      final switching = controller.toggle(
        'm2',
        () async => 'https://example.com/b.m4a',
      );
      await tick();
      expect(engine.calls.last, 'stop');
      engine.playingController.add(false); // audioplayers: stop → stopped
      await tick();
      expect((spy.begins, spy.ends), (1, 1), reason: 'm1 returned it');
      engine.stopGate = null;
      gate.complete();
      await switching;

      expect(state.messageId, 'm2');
      expect(state.isPlaying, isTrue);
      expect((spy.begins, spy.ends), (2, 1));
      expect(spy.playbackHeld, isTrue);
      await finish();
      expect((spy.begins, spy.ends), (2, 2));
      expect(spy.playbackHeld, isFalse);
    });
  });

  testWidgets('the 8 s buffering give-up returns the session (fake time)', (
    tester,
  ) async {
    final e = FakeVoiceEngine();
    final spy = _SpySession();
    final c = ProviderContainer(
      overrides: [
        voicePlaybackEngineProvider.overrideWithValue(e),
        audioSessionProvider.overrideWithValue(spy),
      ],
    );
    addTearDown(c.dispose);
    await c.read(voicePlaybackControllerProvider.notifier).toggle('m1', url);
    e.positionsController.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(c.read(voicePlaybackControllerProvider).isBuffering, isTrue);
    expect(spy.playbackHeld, isTrue, reason: 'buffering still holds it');
    await tester.pump(const Duration(seconds: 7));
    expect(c.read(voicePlaybackControllerProvider).isPlaying, isFalse);
    expect((spy.begins, spy.ends), (1, 1));
    c.dispose();
  });
}

/// Counts session borrows/returns; optionally refuses or breaks them.
class _SpySession extends AudioSessionCoordinator {
  _SpySession({this.failBegin = false, this.failEnd = false})
    : super(port: FakeAudioSessionPort());

  final bool failBegin;
  final bool failEnd;
  int begins = 0;
  int ends = 0;

  /// When set, the platform's context switch waits on it — a slow
  /// AVAudioSession.setCategory (it blocks while it interrupts Spotify).
  Completer<void>? beginGate;

  /// When set, the gated switch throws this once the gate opens.
  Object? beginGateError;

  @override
  Future<void> beginPlayback(PlayerContextSetter set) async {
    begins++;
    if (failBegin) {
      return super.beginPlayback((_) async => throw StateError('refused'));
    }
    final gate = beginGate;
    if (gate == null) return super.beginPlayback(set);
    final error = beginGateError;
    await super.beginPlayback((context) async {
      await gate.future;
      if (error != null) throw error;
      await set(context);
    });
  }

  @override
  Future<void> endPlayback() async {
    ends++;
    await super.endPlayback();
    if (failEnd) throw StateError('release failed');
  }
}
