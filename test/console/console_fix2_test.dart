// Spec 2 W7b Task 7, fix round 2: the verification decisions wait for a
// confirm that names the consequence (Cancel focused; Enter and Esc
// cancel; nothing is sent on cancel); the console's Supabase session lives
// in the tab's own store (sessionStorage on the web), so closing the tab
// signs the moderator out and an aal2 session never outlives it.
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/console_auth.dart';
import 'package:attune/console/console_session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'console_fakes.dart';

class _DeviceStorage extends LocalStorage {
  final calls = <String>[];
  bool fail = false;

  @override
  Future<void> initialize() async {
    calls.add('initialize');
    if (fail) throw Exception('no storage');
  }

  @override
  Future<bool> hasAccessToken() async => false;

  @override
  Future<String?> accessToken() async => null;

  @override
  Future<void> removePersistedSession() async => calls.add('remove');

  @override
  Future<void> persistSession(String persistSessionString) async =>
      calls.add('persist');
}

/// An Auth whose session check throws once, then answers.
class _ThrowingAuth extends FakeConsoleAuth {
  _ThrowingAuth() : super(ConsoleSession.ready);

  bool thrown = false;

  @override
  Future<ConsoleSession> session() async {
    if (!thrown) {
      thrown = true;
      throw StateError('unexpected');
    }
    return state;
  }
}

void main() {
  testWidgets('a session check that throws reads as unreachable with Try '
      'again, never a spinner forever', (t) async {
    final api = FakeConsoleApi({'whoami': consoleMe, 'queue': consoleQueue});
    await t.pumpWidget(ConsoleApp(api: api, auth: _ThrowingAuth()));
    await t.pumpAndSettle();
    expect(
      find.text("Can't reach the server to check your sign-in."),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('console_retry')));
    await t.pumpAndSettle();
    expect(find.text('Moderator'), findsOneWidget);
  });

  group('the verification decisions wait for a confirm', () {
    Future<FakeConsoleApi> open(WidgetTester t) async {
      final api = await pumpHome(
        t,
        answers: {
          'verifications': const ConsoleAnswer(
            ok: true,
            data: {
              'ok': true,
              'sessions': [
                {
                  'id': 's1',
                  'step': 'human',
                  'kind': 'activation',
                  'gestures': ['smile'],
                  'review': [],
                  'photos': [],
                },
              ],
            },
          ),
        },
      );
      await t.tap(find.text('Verifications'));
      await t.pumpAndSettle();
      return api;
    }

    for (final (key, outcome, consequence) in [
      ('console_pass_s1', 'pass', kConfirmIdentityPass),
      ('console_fail_s1', 'fail', kConfirmIdentityFail),
      ('console_ask_id_s1', 'ask_for_id', kConfirmAskForId),
    ]) {
      testWidgets('$outcome: Cancel, Enter and Esc send nothing; confirm '
          'sends once', (t) async {
        final api = await open(t);
        final button = find.byKey(ValueKey(key));
        await t.tap(button);
        await t.pumpAndSettle();
        expect(find.text(consequence), findsOneWidget);
        expect(
          Focus.of(t.element(find.text('Cancel'))).hasPrimaryFocus,
          isTrue,
          reason: 'Cancel is the default focus',
        );
        await t.tap(find.byKey(const ValueKey('console_confirm_cancel')));
        await t.pumpAndSettle();
        await t.tap(button);
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        await t.tap(button);
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.text(consequence), findsNothing);
        expect(api.of('verification_decide'), isEmpty);
        await t.tap(button);
        await t.pumpAndSettle();
        await tapConfirm(t);
        expect(api.of('verification_decide'), [
          {'session_id': 's1', 'outcome': outcome},
        ]);
      });
    }
  });

  group('the session lives in the tab', () {
    test('it is kept in the tab store under the project key, read back '
        'and removed there', () async {
      final tab = MemoryTabStore();
      final s = ConsoleSessionStorage(tab, key: 'sb-abc-auth-token');
      await s.initialize();
      expect(await s.hasAccessToken(), isFalse);
      await s.persistSession('{"access_token":"t"}');
      expect(tab.values, {'sb-abc-auth-token': '{"access_token":"t"}'});
      expect(await s.hasAccessToken(), isTrue);
      expect(await s.accessToken(), '{"access_token":"t"}');
      await s.removePersistedSession();
      expect(tab.values, isEmpty);
      expect(await s.hasAccessToken(), isFalse);
    });

    test('a new tab starts signed out', () async {
      final first = ConsoleSessionStorage(MemoryTabStore(), key: 'k');
      await first.persistSession('session');
      final next = ConsoleSessionStorage(MemoryTabStore(), key: 'k');
      expect(await next.hasAccessToken(), isFalse);
      expect(await next.accessToken(), isNull);
    });

    test('the key is the Supabase client\'s own for the project', () {
      expect(
        consoleSessionKey('https://abcdefgh.supabase.co'),
        'sb-abcdefgh-auth-token',
      );
    });

    test('the auth options use the tab store and read no session from a '
        'link', () {
      final o = consoleAuthOptions(
        MemoryTabStore(),
        'https://abcdefgh.supabase.co',
      );
      expect(o.localStorage, isA<ConsoleSessionStorage>());
      expect(
        (o.localStorage! as ConsoleSessionStorage).key,
        'sb-abcdefgh-auth-token',
      );
      expect(o.detectSessionInUri, isFalse);
    });

    test('a session an older build kept on the device is removed; a device '
        'store that fails is ignored', () async {
      final device = _DeviceStorage();
      await consoleForgetDeviceSession(device);
      expect(device.calls, ['initialize', 'remove']);
      final broken = _DeviceStorage()..fail = true;
      await consoleForgetDeviceSession(broken);
      expect(broken.calls, ['initialize']);
    });
  });
}
