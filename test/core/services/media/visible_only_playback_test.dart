import 'dart:io';

import 'package:attune/core/services/media/visible_only_playback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../../helpers/recording_video_platform.dart';

void main() {
  late VideoPlayerPlatform original;
  late RecordingVideoPlatform platform;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    platform = RecordingVideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() => VideoPlayerPlatform.instance = original);

  Future<VideoPlayerController> ready() async {
    final c = VideoPlayerController.file(File('/tmp/visible_only.mp4'));
    await c.initialize();
    platform.calls.clear();
    return c;
  }

  testWidgets('starts at once while Attune is on screen', (t) async {
    final c = await ready();
    VisibleOnlyPlayback(isVisible: () => true).start(c);
    await t.pump();
    expect(platform.calls, contains('play'));
    await t.runAsync(c.dispose);
  });

  testWidgets('started while off screen, it waits for the return', (t) async {
    final c = await ready();
    final p = VisibleOnlyPlayback(isVisible: () => false)..start(c);
    await t.pump();
    expect(platform.calls, isNot(contains('play')));
    p.onVisibility(true);
    await t.pump();
    expect(platform.calls, contains('play'));
    await t.runAsync(c.dispose);
  });

  testWidgets('leaving pauses it; coming back plays it again', (t) async {
    final c = await ready();
    final p = VisibleOnlyPlayback(isVisible: () => true)..start(c);
    await t.pump();
    platform.calls.clear();
    p.onVisibility(false);
    await t.pump();
    expect(platform.calls, ['pause']);
    expect(c.value.isPlaying, isFalse);
    p.onVisibility(true);
    await t.pump();
    expect(platform.calls, contains('play'));
    await t.runAsync(c.dispose);
  });

  testWidgets('a pause the person chose stays paused on return', (t) async {
    final c = await ready();
    final p = VisibleOnlyPlayback(isVisible: () => true)..start(c);
    await t.pump();
    await c.pause();
    platform.calls.clear();
    p
      ..onVisibility(false)
      ..onVisibility(true);
    await t.pump();
    expect(platform.calls, isNot(contains('play')));
    await t.runAsync(c.dispose);
  });

  testWidgets('clear() forgets the controller', (t) async {
    final c = await ready();
    final p = VisibleOnlyPlayback(isVisible: () => true)..start(c);
    await t.pump();
    p
      ..onVisibility(false)
      ..clear();
    platform.calls.clear();
    p.onVisibility(true);
    await t.pump();
    expect(platform.calls, isEmpty);
    await t.runAsync(c.dispose);
  });
}
