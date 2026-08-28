import 'dart:io';

import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Walks the same loop the camera's timer runs, so the end-to-end
/// segmentation arithmetic is pinned without a device.
({int completed, bool stopped}) _hold(Duration total) {
  var completed = 0;
  var elapsed = Duration.zero;
  var stopped = false;

  for (var second = 1; second <= total.inSeconds; second++) {
    elapsed += const Duration(seconds: 1);
    if (StreakRecordingSession.shouldSplitAt(elapsed)) {
      completed += 1;
      elapsed = Duration.zero;
      if (StreakRecordingSession.shouldStopAt(completed)) {
        stopped = true;
        break;
      }
    }
  }
  return (completed: completed, stopped: stopped);
}

void main() {
  test('a three-minute hold produces three segments', () {
    final r = _hold(const Duration(minutes: 3));
    expect(r.completed, 3);
    expect(r.stopped, isFalse);
    expect(StreakRecordingSession.showPreviews(r.completed), isTrue);
  });

  test('recording stops at the five-segment cap', () {
    final r = _hold(const Duration(minutes: 10));
    expect(r.completed, 5, reason: 'ten minutes must not queue ten clips');
    expect(r.stopped, isTrue);
  });

  test('a 40-second hold produces one clip and no previews', () {
    final r = _hold(const Duration(seconds: 40));
    expect(r.completed, 0, reason: 'no split below the threshold');
    expect(StreakRecordingSession.showPreviews(r.completed), isFalse);
  });

  test('the camera is configured to record audio', () {
    // A streak is someone talking to their partner. A muted format
    // removes most of what makes it worth sending, and the flag is easy
    // to lose in a later refactor.
    final src = File(
      'lib/features/chat/presentation/screens/streak_camera_screen.dart',
    ).readAsStringSync();
    expect(src, contains('enableAudio: true'));
  });

  test('the preview is cover-cropped, never stretched', () {
    // A bare CameraPreview in a StackFit.expand Stack scales the sensor
    // image to the screen's shape and elongates everything — the bug
    // fixed in 6db5763d on the ephemeral camera.
    final src = File(
      'lib/features/chat/presentation/screens/streak_camera_screen.dart',
    ).readAsStringSync();
    expect(src, contains('BoxFit.cover'));
  });
}
