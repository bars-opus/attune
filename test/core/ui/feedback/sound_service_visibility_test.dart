// Stories Wave 3, batch 3 review #1: the app stays mounted behind the
// privacy cover and the lock check, so a one-shot UI sound (a partner's
// game move, the chat chirp) must not play while Attune is not on screen.
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/core/ui/feedback/audio_session.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingPlayer implements AudioPlayer {
  _RecordingPlayer(this.calls);
  final List<String> calls;

  @override
  Future<void> setAudioContext(AudioContext ctx) async {}
  @override
  Future<void> setSource(Source source) async {}
  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {}
  @override
  Future<void> setPlayerMode(PlayerMode mode) async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '${invocation.memberName} unused on the test host',
      );
}

void main() {
  testWidgets('a sound is a no-op while Attune is off screen or behind the '
      'lock check, and plays once it is back', (tester) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appContentVisibleProvider);
    final calls = <String>[];
    final service = AudioPlayerSoundService(
      session: AudioSessionCoordinator(
        port: FakeAudioSessionPort(),
        platform: TargetPlatform.iOS,
      ),
      createPlayer: () => _RecordingPlayer(calls),
      isVisible: () => container.read(appContentVisibleProvider),
    );
    await service.preload();

    container.read(appContentVisibleProvider.notifier).setLockOpen(false);
    service.play(AppSound.chatReceive);
    await tester.pump();
    expect(calls, isEmpty, reason: 'behind the lock check');

    container.read(appContentVisibleProvider.notifier).setLockOpen(true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    service.play(AppSound.gameDice);
    await tester.pump();
    expect(calls, isEmpty, reason: 'behind the privacy cover');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    service.play(AppSound.chatReceive);
    await tester.pump();
    expect(calls, ['resume']);
  });

  testWidgets('without a visibility check it plays as before', (tester) async {
    final calls = <String>[];
    final service = AudioPlayerSoundService(
      session: AudioSessionCoordinator(
        port: FakeAudioSessionPort(),
        platform: TargetPlatform.iOS,
      ),
      createPlayer: () => _RecordingPlayer(calls),
    );
    await service.preload();
    service.play(AppSound.chatReceive);
    await tester.pump();
    expect(calls, ['resume']);
  });
}
