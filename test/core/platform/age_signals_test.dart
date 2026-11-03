// Spec 1 W6b (§3.3 A2, §5.1): the platform age signal through its channel,
// with fakes. Only a status comes back; a failure or a slow answer is
// unavailable; nothing is asked off iOS and Android.
import 'package:attune/core/platform/age_signals.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(AgeSignals.channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(AgeSignals.channel, null));

  test('each status the native side sends is read', () async {
    for (final status in AgeSignalStatus.values) {
      answer((_) async => {'status': status.name});
      final signal = await AgeSignals.read(const [
        'USA',
      ], platform: TargetPlatform.android);
      expect(signal.status, status);
      expect(signal.source, 'play_age_signals');
    }
  });

  test(
    'iOS asks with the storefronts; its source is Declared Age Range',
    () async {
      answer((_) async => {'status': 'adult'});
      final signal = await AgeSignals.read(const [
        'USA',
        'BRA',
      ], platform: TargetPlatform.iOS);
      expect(signal.source, 'apple_declared_age_range');
      expect(calls.single.method, 'read');
      expect(calls.single.arguments, {
        'storefronts': ['USA', 'BRA'],
      });
    },
  );

  test('a minor or supervised answer stops sign-up; nothing else does', () {
    bool stops(AgeSignalStatus s) => AgeSignal('x', s).stopsSignUp;
    expect(stops(AgeSignalStatus.minor), isTrue);
    expect(stops(AgeSignalStatus.supervised), isTrue);
    expect(stops(AgeSignalStatus.adult), isFalse);
    expect(stops(AgeSignalStatus.unknown), isFalse);
    expect(stops(AgeSignalStatus.unavailable), isFalse);
  });

  test(
    'rubbish is unknown; an error, a missing channel or a slow answer is unavailable',
    () async {
      answer((_) async => {'status': 'teen'});
      expect(
        (await AgeSignals.read(
          const [],
          platform: TargetPlatform.android,
        )).status,
        AgeSignalStatus.unknown,
      );
      answer((_) async => 'adult');
      expect(
        (await AgeSignals.read(
          const [],
          platform: TargetPlatform.android,
        )).status,
        AgeSignalStatus.unknown,
      );
      answer((_) async => throw PlatformException(code: 'boom'));
      expect(
        (await AgeSignals.read(
          const [],
          platform: TargetPlatform.android,
        )).status,
        AgeSignalStatus.unavailable,
      );
      messenger.setMockMethodCallHandler(AgeSignals.channel, null);
      expect(
        (await AgeSignals.read(
          const [],
          platform: TargetPlatform.android,
        )).status,
        AgeSignalStatus.unavailable,
      );
    },
  );

  // Batch 6 (Play Age Signals terms): the signal, its failure included, is
  // never logged.
  test('nothing about the signal is ever logged', () async {
    final logged = <String?>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logged.add(message);
    addTearDown(() => debugPrint = original);
    for (final status in AgeSignalStatus.values) {
      answer((_) async => {'status': status.name});
      await AgeSignals.read(const ['USA'], platform: TargetPlatform.android);
    }
    answer((_) async => throw PlatformException(code: 'boom'));
    await AgeSignals.read(const ['USA'], platform: TargetPlatform.iOS);
    messenger.setMockMethodCallHandler(AgeSignals.channel, null);
    await AgeSignals.read(const ['USA'], platform: TargetPlatform.android);
    expect(logged, isEmpty);
  });

  test('another platform is never asked', () async {
    answer((_) async => {'status': 'minor'});
    final signal = await AgeSignals.read(const [
      'USA',
    ], platform: TargetPlatform.macOS);
    expect(signal.status, AgeSignalStatus.unavailable);
    expect(calls, isEmpty);
  });
}
