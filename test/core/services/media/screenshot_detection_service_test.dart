import 'package:attune/core/services/media/screenshot_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('platform channel degradation in test host', () {
    test('constructing the service and listening does not throw even with no real platform channel implementation', () async {
      // Mirrors the established pattern for VoiceRecorderService/
      // ChatVideoPreparer's native-call degradation: a pure-Dart
      // flutter test VM host has no real iOS/Android screenshot-detection
      // implementation registered, so any MethodChannel call this service
      // makes will throw MissingPluginException — the service itself must
      // catch this and simply never emit, not crash the caller.
      final service = ScreenshotDetectionService();
      var eventCount = 0;
      final subscription = service.onScreenshotDetected.listen((_) => eventCount++);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(eventCount, 0); // no crash, no spurious emission
      await subscription.cancel();
      service.dispose();
    });
  });
}
