import 'dart:async';
import 'dart:io';

import 'package:attune/core/ui/feedback/audio_session.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records setAudioContext; every other platform call throws, so preload's
/// per-asset guard skips the clip without a real player ever existing.
class _ContextOnlyPlayer implements AudioPlayer {
  _ContextOnlyPlayer(this.seen);
  final List<AudioContext> seen;

  @override
  Future<void> setAudioContext(AudioContext ctx) async => seen.add(ctx);

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {}

  @override
  Future<void> setPlayerMode(PlayerMode mode) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} unused on the test host',
  );
}

/// A player double that can be told to fail at preload, and records what
/// play() and dispose() did to it.
class _RecordingPlayer implements AudioPlayer {
  _RecordingPlayer({this.failContext = false, this.failSource = false});
  final bool failContext;
  final bool failSource;
  final List<String> calls = [];
  bool disposed = false;

  @override
  Future<void> setAudioContext(AudioContext ctx) async {
    calls.add('context');
    if (failContext) throw StateError('platform refused the context');
  }

  @override
  Future<void> setSource(Source source) async {
    calls.add('source');
    if (failSource) throw StateError('asset missing');
  }

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {}

  @override
  Future<void> setPlayerMode(PlayerMode mode) async {}

  @override
  Future<void> seek(Duration position) async => calls.add('seek');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} unused on the test host',
  );
}

/// Counts beforeChirp and can make it fail, asynchronously or (a
/// misbehaving override) synchronously.
class _SpyCoordinator extends AudioSessionCoordinator {
  _SpyCoordinator({this.fail = false, this.failSync = false})
    : super(port: FakeAudioSessionPort(), platform: TargetPlatform.iOS);
  final bool fail;
  final bool failSync;
  int beforeChirpCalls = 0;

  @override
  Future<void> beforeChirp(PlayerContextSetter set) {
    beforeChirpCalls++;
    if (failSync) throw StateError('session refused synchronously');
    if (fail) return Future.error(StateError('session refused'));
    return super.beforeChirp(set);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FakeSoundService records played sounds and preloads', () async {
    final s = FakeSoundService();
    await s.preload();
    s.play(ChatSound.send);
    s.play(ChatSound.receive);
    s.play(ChatSound.send);
    expect(s.preloadCount, 1);
    expect(s.played, [ChatSound.send, ChatSound.receive, ChatSound.send]);
  });

  test('AudioPlayerSoundService constructs and play() never throws '
      'even before preload', () {
    // Fake port + throwing factory: the default port would hit the missing
    // audioplayers plugin and surface its init error after the test ends.
    final s = AudioPlayerSoundService(
      session: AudioSessionCoordinator(port: FakeAudioSessionPort()),
      createPlayer: () => throw StateError('no audio on the test host'),
    );
    // Must not throw synchronously in a headless test (no audio device).
    expect(() => s.play(ChatSound.send), returnsNormally);
    s.dispose();
  });

  test('ChatSound back-compat aliases map onto AppSound values', () {
    expect(ChatSound.send, AppSound.chatSend);
    expect(ChatSound.receive, AppSound.chatReceive);
  });

  test('FakeSoundService records the universal game sounds', () {
    final s = FakeSoundService();
    s.play(AppSound.gameTap);
    s.play(AppSound.gameCardFlip);
    s.play(AppSound.gameMatch);
    s.play(AppSound.gameReveal);
    s.play(AppSound.gameComplete);
    s.play(AppSound.gameFire);
    s.play(AppSound.gameHit);
    s.play(AppSound.gameMiss);
    s.play(AppSound.gameKnockout);
    s.play(AppSound.gamePenaltyReveal);
    expect(s.played, [
      AppSound.gameTap,
      AppSound.gameCardFlip,
      AppSound.gameMatch,
      AppSound.gameReveal,
      AppSound.gameComplete,
      AppSound.gameFire,
      AppSound.gameHit,
      AppSound.gameMiss,
      AppSound.gameKnockout,
      AppSound.gamePenaltyReveal,
    ]);
  });

  test('FakeSoundService records streak capture sounds', () {
    final s = FakeSoundService();
    s.play(AppSound.streakCaptureReady);
    s.play(AppSound.streakSend);
    expect(s.played, [AppSound.streakCaptureReady, AppSound.streakSend]);
  });

  test('FakeSoundService records voice-note sounds', () {
    final s = FakeSoundService();
    s.play(AppSound.voiceSend);
    s.play(AppSound.voiceDelete);
    expect(s.played, [AppSound.voiceSend, AppSound.voiceDelete]);
  });

  test('preload puts the whole process on the chirp context first', () async {
    final port = FakeAudioSessionPort();
    final s = AudioPlayerSoundService(
      session: AudioSessionCoordinator(port: port),
      createPlayer: () => throw StateError('no audio on the test host'),
    );
    await s.preload();
    expect(port.globalContexts, [AppAudioContexts.chirp]);
    s.dispose();
  });

  test('every preloaded chirp player gets the chirp context itself', () async {
    final seen = <AudioContext>[];
    final port = FakeAudioSessionPort();
    final s = AudioPlayerSoundService(
      session: AudioSessionCoordinator(port: port),
      createPlayer: () => _ContextOnlyPlayer(seen),
    );
    await s.preload();
    expect(seen.length, AppSound.values.length);
    expect(seen.toSet(), {AppAudioContexts.chirp});
    s.dispose();
  });

  test('the sound service no longer builds contexts from the config helper', () {
    final source =
        File('lib/core/ui/feedback/sound_service.dart').readAsStringSync();
    expect(source, isNot(contains('AudioContextConfig(')));
    expect(source, contains('AppAudioContexts'));
  });

  group('play() after preload', () {
    Future<(AudioPlayerSoundService, List<_RecordingPlayer>)> ready(
      AudioSessionCoordinator session,
    ) async {
      final players = <_RecordingPlayer>[];
      final s = AudioPlayerSoundService(
        session: session,
        createPlayer: () {
          final p = _RecordingPlayer();
          players.add(p);
          return p;
        },
      );
      await s.preload();
      for (final p in players) {
        p.calls.clear();
      }
      return (s, players);
    }

    test('re-asserts the chirp session, then plays from the start', () async {
      final session = _SpyCoordinator();
      final (s, players) = await ready(session);
      s.play(AppSound.chatSend);
      await pumpEventQueue();
      expect(session.beforeChirpCalls, 1);
      final player = players[AppSound.values.indexOf(AppSound.chatSend)];
      // iOS: beforeChirp sets the chirp context on this player first.
      expect(player.calls, ['context', 'seek', 'resume']);
      s.dispose();
    });

    test('a beforeChirp that fails is swallowed and the chirp skipped', () async {
      final session = _SpyCoordinator(fail: true);
      final (s, players) = await ready(session);
      final errors = <Object>[];
      await runZonedGuarded(() async {
        s.play(AppSound.chatSend);
        await pumpEventQueue();
      }, (error, _) => errors.add(error));
      expect(errors, isEmpty, reason: 'never an unhandled async error');
      expect(session.beforeChirpCalls, 1);
      final player = players[AppSound.values.indexOf(AppSound.chatSend)];
      expect(player.calls, isNot(contains('resume')));
      s.dispose();
    });

    test('a beforeChirp that throws synchronously never reaches the caller',
        () async {
      final session = _SpyCoordinator(failSync: true);
      final (s, _) = await ready(session);
      final errors = <Object>[];
      await runZonedGuarded(() async {
        expect(() => s.play(AppSound.chatSend), returnsNormally);
        await pumpEventQueue();
      }, (error, _) => errors.add(error));
      expect(errors, isEmpty);
      s.dispose();
    });
  });

  test('a player whose context fails at preload is released', () async {
    final players = <_RecordingPlayer>[];
    final s = AudioPlayerSoundService(
      session: AudioSessionCoordinator(port: FakeAudioSessionPort()),
      createPlayer: () {
        final p = _RecordingPlayer(failContext: true);
        players.add(p);
        return p;
      },
    );
    await s.preload();
    expect(players, hasLength(AppSound.values.length));
    expect(players.where((p) => !p.disposed), isEmpty);
    s.dispose();
  });

  test('a player whose source fails at preload is released', () async {
    final players = <_RecordingPlayer>[];
    final s = AudioPlayerSoundService(
      session: AudioSessionCoordinator(port: FakeAudioSessionPort()),
      createPlayer: () {
        final p = _RecordingPlayer(failSource: true);
        players.add(p);
        return p;
      },
    );
    await s.preload();
    expect(players.where((p) => !p.disposed), isEmpty);
    // And nothing failed is kept for play() to reach.
    s.play(AppSound.chatSend);
    await pumpEventQueue();
    expect(players.expand((p) => p.calls), isNot(contains('resume')));
    s.dispose();
  });
}
