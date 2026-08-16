import 'package:attune/features/chat/presentation/screens/ephemeral_camera_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('minimum hold duration', () {
    test('a hold shorter than 500ms is discarded, not sent', () {
      expect(
        EphemeralCameraScreenState.debugShouldDiscardHold(
          const Duration(milliseconds: 200),
        ),
        isTrue,
      );
    });

    test('a hold of exactly 500ms or longer is not discarded', () {
      expect(
        EphemeralCameraScreenState.debugShouldDiscardHold(
          const Duration(milliseconds: 500),
        ),
        isFalse,
      );
      expect(
        EphemeralCameraScreenState.debugShouldDiscardHold(
          const Duration(seconds: 3),
        ),
        isFalse,
      );
    });
  });

  group('10-second auto-stop cap', () {
    test('recording duration is clamped to at most 10 seconds', () {
      expect(
        EphemeralCameraScreenState.debugClampRecordingDuration(
          const Duration(seconds: 15),
        ),
        const Duration(seconds: 10),
      );
      expect(
        EphemeralCameraScreenState.debugClampRecordingDuration(
          const Duration(seconds: 7),
        ),
        const Duration(seconds: 7),
      );
    });
  });
}
