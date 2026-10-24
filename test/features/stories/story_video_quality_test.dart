// Batch-5 review #2: stories record at veryHigh (1080p), so their video
// preparer opts into the oversize step-down. Chat and streaks keep the
// default preparer (one 720p encode, refused when over 25 MB).
import 'dart:io';

import 'package:attune/features/stories/presentation/state/story_post_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_compress/video_compress.dart';

void main() {
  test('the story preparer steps down to 960x540 when oversize', () {
    final preparer = StoryPostPipeline.storyVideoPreparer();
    expect(preparer.oversizeRetryQuality, VideoQuality.Res960x540Quality);
  });

  test(
    'Share prepares with that preparer unless a test seam is passed',
    () {
      // Task 16: preparing moved from the camera to StoryPostPipeline.
      final pipeline =
          File(
            'lib/features/stories/presentation/state/story_post_pipeline.dart',
          ).readAsStringSync();
      expect(pipeline, contains('videoPreparer ?? storyVideoPreparer'));
      // The camera passes only its test seam (null in the app), so the
      // pipeline's default applies.
      final camera =
          File(
            'lib/features/stories/presentation/screens/story_camera_screen.dart',
          ).readAsStringSync();
      expect(camera, contains('videoPreparer: widget.videoPreparerFactory'));
    },
  );

  test('chat and streaks do not opt in', () {
    for (final path in [
      'lib/features/chat/presentation/state/chat_state.dart',
      'lib/features/chat/presentation/widgets/video_prepare_progress_dialog.dart',
      'lib/features/chat/presentation/screens/capture_camera_screen.dart',
      'lib/features/chat/presentation/screens/streak_camera_screen.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, isNot(contains('oversizeRetryQuality')), reason: path);
    }
  });
}
