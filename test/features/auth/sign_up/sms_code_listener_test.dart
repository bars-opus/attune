// Spec 1 W2c (P-20, review B8 m-3, m-4): Android's SMS listener talks to
// smart_auth's platform side. Release builds use the SMS Retriever (no
// prompt; the message carries the app hash), every other build the one-tap
// User Consent prompt, and stop() removes the same one. Only a code of
// exactly six ASCII digits is ever handed on.
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _api = 'dev.flutter.pigeon.smart_auth.SmartAuthApi.';
const _methods = [
  'getSmsWithRetrieverApi',
  'getSmsWithUserConsentApi',
  'removeSmsRetrieverListener',
  'removeUserConsentListener',
];

/// The platform side: every call is recorded, and each "get" answers [sms].
List<String> _platform(String sms) {
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final method in _methods) {
    messenger.setMockMessageHandler('$_api$method', (_) async {
      calls.add(method);
      return const StandardMessageCodec().encodeMessage(<Object?>[
        method.startsWith('get') ? sms : null,
      ]);
    });
  }
  addTearDown(() {
    for (final method in _methods) {
      messenger.setMockMessageHandler('$_api$method', null);
    }
  });
  return calls;
}

const _attune =
    "<#> Your Attune code is 561166. It expires in 10 minutes. Don't share "
    'it.\nFA+9qCX9VSu';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('which Android API (P-20)', () {
    test(
      'a release build listens with the SMS Retriever and removes it',
      () async {
        final calls = _platform(_attune);
        final listener = SmartAuthCodeListener(
          platform: TargetPlatform.android,
          release: true,
        );
        expect(await listener.next(), '561166');
        await listener.stop();
        expect(calls, ['getSmsWithRetrieverApi', 'removeSmsRetrieverListener']);
      },
    );

    test('any other build asks with User Consent and removes it', () async {
      final calls = _platform(_attune);
      final listener = SmartAuthCodeListener(
        platform: TargetPlatform.android,
        release: false,
      );
      expect(await listener.next(), '561166');
      await listener.stop();
      expect(calls, ['getSmsWithUserConsentApi', 'removeUserConsentListener']);
    });

    test(
      'the build mode decides when none is given (a test is not release)',
      () async {
        final calls = _platform(_attune);
        await SmartAuthCodeListener(platform: TargetPlatform.android).next();
        expect(calls, ['getSmsWithUserConsentApi']);
      },
    );

    test('iOS never calls the platform side', () async {
      final calls = _platform(_attune);
      final listener = SmartAuthCodeListener(
        platform: TargetPlatform.iOS,
        release: true,
      );
      expect(await listener.next(), isNull);
      await listener.stop();
      expect(calls, isEmpty);
    });
  });

  group('only six ASCII digits are a code (review B8 m-4)', () {
    for (final (sms, code) in [
      ('Your PIN is 12345678', null),
      ('Your PIN is 1234', null),
      ('Your code: 12345', null),
      ('Your code: \u0661\u0662\u0663\u0664\u0665\u0666', null),
      ('Ref 1234. Your Attune code is 567890.', '567890'),
      (_attune, '561166'),
    ]) {
      for (final release in [true, false]) {
        test(
          '"${sms.split('\n').first}" (release: $release) gives $code',
          () async {
            _platform(sms);
            final listener = SmartAuthCodeListener(
              platform: TargetPlatform.android,
              release: release,
            );
            expect(await listener.next(), code);
          },
        );
      }
    }
  });
}
