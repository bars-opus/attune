// Spec 1 W2b (§3.3 A3): the SIM country channel.
import 'dart:io';

import 'package:attune/core/platform/sim_country.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(SimCountry.channel, null));

  test('Android: the SIM country, upper case', () async {
    messenger.setMockMethodCallHandler(SimCountry.channel, (call) async {
      expect(call.method, 'simCountryIso');
      return 'gh';
    });
    expect(await SimCountry.read(platform: TargetPlatform.android), 'GH');
  });

  test('no SIM, a junk answer or a missing channel reads as none', () async {
    messenger.setMockMethodCallHandler(SimCountry.channel, (_) async => '');
    expect(await SimCountry.read(platform: TargetPlatform.android), isNull);
    messenger.setMockMethodCallHandler(
      SimCountry.channel,
      (_) async => 'ghana',
    );
    expect(await SimCountry.read(platform: TargetPlatform.android), isNull);
    messenger.setMockMethodCallHandler(
      SimCountry.channel,
      (_) async => throw PlatformException(code: 'x'),
    );
    expect(await SimCountry.read(platform: TargetPlatform.android), isNull);
  });

  test('iOS never asks', () async {
    var asked = false;
    messenger.setMockMethodCallHandler(SimCountry.channel, (_) async {
      asked = true;
      return 'GB';
    });
    expect(await SimCountry.read(platform: TargetPlatform.iOS), isNull);
    expect(asked, isFalse);
  });

  test('MainActivity answers simCountryIso on attune/device', () {
    final kotlin =
        File(
          'android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt',
        ).readAsStringSync();
    expect(kotlin, contains('"attune/device"'));
    expect(kotlin, contains('"simCountryIso"'));
    expect(kotlin, contains('getSystemService(Context.TELEPHONY_SERVICE)'));
    expect(kotlin, isNot(contains('READ_PHONE_STATE')));
  });
}
