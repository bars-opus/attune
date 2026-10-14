import 'package:attune/core/utils/timezone_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the device zone comes from the maintained timezone plugin', () async {
    TimezoneUtils.clearCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (
          call,
        ) async {
          if (call.method == 'getLocalTimezone') return 'Europe/London';
          return null;
        });
    expect(await TimezoneUtils.getDeviceTimezone(), 'Europe/London');
  });
}
