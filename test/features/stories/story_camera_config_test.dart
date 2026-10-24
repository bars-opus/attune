import 'dart:io';

import 'package:attune/features/stories/presentation/screens/story_camera_screen.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/capture_fakes.dart';

void main() {
  late Directory dir;
  late CameraPlatform original;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('story_camera_config');
    original = CameraPlatform.instance;
  });
  tearDown(() {
    CameraPlatform.instance = original;
    dir.deleteSync(recursive: true);
  });

  testWidgets('stories capture at veryHigh (01 #5)', (tester) async {
    final platform = FakeCameraPlatform(
      videoPath: '${dir.path}/clip.mp4',
      photoPath: await writeJpeg(tester, dir, 'photo.jpg'),
    );
    CameraPlatform.instance = platform;
    final h = storyCameraContainer(dir);
    await pumpStoryCamera(tester, h.container, const StoryCameraScreen(relationshipId: 'rel-1'));
    expect(platform.settings.last.resolutionPreset, ResolutionPreset.veryHigh);
  });

  testWidgets('the story camera never says "streak", and photos survive a denied mic',
      (tester) async {
    final platform = FakeCameraPlatform(
      videoPath: '${dir.path}/clip.mp4',
      photoPath: await writeJpeg(tester, dir, 'photo.jpg'),
    )..audioDenied = CameraException('AudioAccessDeniedWithoutPrompt', 'denied');
    CameraPlatform.instance = platform;
    final h = storyCameraContainer(dir);
    await pumpStoryCamera(tester, h.container, const StoryCameraScreen(relationshipId: 'rel-1'));
    expect(platform.settings.last.enableAudio, isFalse);
    expect(find.textContaining('streak'), findsNothing);
  });
}
