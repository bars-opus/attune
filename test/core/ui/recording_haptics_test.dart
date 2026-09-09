import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('attune/recording_haptics_test');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('iOS enables and disables haptics during audio recording', () async {
    final haptics = PlatformRecordingHaptics(
      channel: channel,
      platform: TargetPlatform.iOS,
    );

    await haptics.enable();
    await haptics.disable();

    expect(calls, [
      isA<MethodCall>()
          .having((call) => call.method, 'method', 'setEnabled')
          .having((call) => call.arguments, 'arguments', true),
      isA<MethodCall>()
          .having((call) => call.method, 'method', 'setEnabled')
          .having((call) => call.arguments, 'arguments', false),
    ]);
  });

  test('non-iOS platforms do not invoke the native channel', () async {
    final haptics = PlatformRecordingHaptics(
      channel: channel,
      platform: TargetPlatform.android,
    );

    await haptics.enable();
    await haptics.disable();

    expect(calls, isEmpty);
  });

  test('fake records the screen lifecycle', () async {
    final haptics = FakeRecordingHaptics();

    await haptics.enable();
    await haptics.enable();
    await haptics.disable();

    expect(haptics.enableCount, 2);
    expect(haptics.disableCount, 1);
  });
}
