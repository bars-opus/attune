// Spec 1 W2a: G1 (the guest birth-year gate) and X1 (the under-18 stop).
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/domain/guest_year.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/guest_age_gate_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/flow_harness.dart';

DateTime _now() => DateTime.utc(2026, 10, 25, 12);

/// Prefs whose string writes fail (a full disk); reads go to [_real].
class _PrefsThatFailWrites implements SharedPreferences {
  _PrefsThatFailWrites(this._real);

  final SharedPreferences _real;

  @override
  Future<bool> setString(String key, String value) =>
      Future.error(StateError('disk full'));

  @override
  String? getString(String key) => _real.getString(key);

  @override
  bool? getBool(String key) => _real.getBool(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts keystore reads (batch 2 review I-1).
class _CountingSecure extends Fake implements FlutterSecureStorage {
  var reads = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    return null;
  }
}

void main() {
  test('the current year is the local calendar year (review M-3)', () {
    // 20:00 on 31 December in New York: UTC is already in 2027.
    expect(
      localCalendarYear(
        DateTime.utc(2027, 1, 1, 1),
        utcOffset: const Duration(hours: -5),
      ),
      2026,
    );
    // 01:00 on 1 January in Accra.
    expect(
      localCalendarYear(DateTime.utc(2027, 1, 1, 1), utcOffset: Duration.zero),
      2027,
    );
    // 05:00 on 1 January in Tokyo, still 31 December in UTC.
    expect(
      localCalendarYear(
        DateTime.utc(2026, 12, 31, 20),
        utcOffset: const Duration(hours: 9),
      ),
      2027,
    );
  });

  group('validateGuestYear', () {
    test('four digits, not after this year, not before 1900', () {
      expect(
        validateGuestYear('', currentYear: 2026),
        GuestYearError.fourDigits,
      );
      expect(
        validateGuestYear('94', currentYear: 2026),
        GuestYearError.fourDigits,
      );
      expect(
        validateGuestYear('2027', currentYear: 2026),
        GuestYearError.future,
      );
      expect(
        validateGuestYear('1899', currentYear: 2026),
        GuestYearError.check,
      );
      expect(validateGuestYear(' 1994 ', currentYear: 2026), isNull);
    });

    test('exactly 18 by year passes; 17 does not', () {
      expect(isUnder18ByYear(2008, currentYear: 2026), isFalse);
      expect(isUnder18ByYear(2009, currentYear: 2026), isTrue);
    });
  });

  testWidgets('G1: an adult year opens the guest home and is kept for A2', (
    tester,
  ) async {
    final h = await pumpFlowScreen(tester, () => GuestAgeGateScreen(now: _now));
    expect(find.text('What year were you born?'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Year you were born, 4 digits'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '1994');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(h.location, '/home');
    expect(h.routing.guestAgeOk, isTrue);
    expect(AgeGateStore.readGuestOk(h.prefs), isTrue);
    expect(await AgeGateStore(h.prefs).guestBirthYear(), 1994);
    expect(h.metrics, ['guest_age_ok']);
  });

  testWidgets(
    'G1: a year under 18 opens X1 and blocks the device for 30 days',
    (tester) async {
      final h = await pumpFlowScreen(
        tester,
        () => GuestAgeGateScreen(now: _now),
      );
      await tester.enterText(find.byType(TextField), '2012');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(h.location, '/age-stop');
      expect(h.routing.underAgeBlocked, isTrue);
      expect(AgeGateStore.readBlocked(h.prefs, DateTime.now()), isTrue);
      expect(
        AgeGateStore.readBlocked(
          h.prefs,
          DateTime.now().add(const Duration(days: 31)),
        ),
        isFalse,
        reason: 'the block clears itself after 30 days',
      );
      expect(AgeGateStore.readGuestOk(h.prefs), isFalse);
      expect(h.metrics, isEmpty);
    },
  );

  testWidgets('G1: each mistake says what to fix, inline', (tester) async {
    await pumpFlowScreen(tester, () => GuestAgeGateScreen(now: _now));
    for (final (typed, message) in [
      ('94', 'Enter the year with 4 digits, like 1994.'),
      ('2030', 'That year is in the future.'),
      ('1850', 'Check the year.'),
    ]) {
      await tester.enterText(find.byType(TextField), typed);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(tester.takeAnnouncements().map((a) => a.message), [message]);
    }

    // The same mistake again is said again (review M-4).
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(tester.takeAnnouncements().map((a) => a.message), [
      'Check the year.',
    ]);
  });

  testWidgets('G1: Done and then Continue count the pass once (review M-2)', (
    tester,
  ) async {
    final h = await pumpFlowScreen(tester, () => GuestAgeGateScreen(now: _now));
    await tester.enterText(find.byType(TextField), '1994');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(h.location, '/home');
    expect(h.metrics, ['guest_age_ok']);
  });

  testWidgets(
    'G1: under 18 still stops at X1 when the block cannot be saved (review M-2)',
    (tester) async {
      final h = await pumpFlowScreen(
        tester,
        () => GuestAgeGateScreen(now: _now),
        overrides: [
          ageGateStoreProvider.overrideWith(
            (ref) => AgeGateStore(
              _PrefsThatFailWrites(ref.watch(sharedPreferencesProvider)),
            ),
          ),
        ],
      );
      await tester.enterText(find.byType(TextField), '2012');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(h.location, '/age-stop');
      expect(h.routing.underAgeBlocked, isTrue);
    },
  );

  testWidgets('G1 meets the tap-target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(tester, () => GuestAgeGateScreen(now: _now));
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets(
    'X1 says nothing was saved, offers youth support, and never animates',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await pumpFlowScreen(tester, () => const UnderAgeStopScreen());
      expect(find.text('Attune is for adults'), findsOneWidget);
      expect(
        find.text(
          "You need to be 18 or older to use Attune. We haven't saved anything you entered.",
        ),
        findsOneWidget,
      );
      expect(find.text('Support for young people'), findsOneWidget);
      await expectFlowGuidelines(tester);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(h.location, '/welcome');
      semantics.dispose();
    },
  );

  testWidgets('X1 starts no animation on its first frame (spec §2.2, §7.4)', (
    tester,
  ) async {
    await pumpFlowScreen(tester, () => const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const UnderAgeStopScreen(),
      ),
    );
    // A running animation is a ticker, and a ticker is a transient callback.
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'X1 after a server refusal leads with "We couldn\'t create your account."',
    (tester) async {
      await pumpFlowScreen(
        tester,
        () => const UnderAgeStopScreen(serverRefused: true),
      );
      expect(
        find.textContaining("We couldn't create your account."),
        findsOneWidget,
      );
    },
  );

  group('AgeGateStore', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test(
      'a Keychain block comes back after a reinstall; an expired one goes',
      () async {
        await AgeGateStore(prefs).block();
        // A reinstall: the prefs copy is gone, the Keychain item stays.
        await prefs.remove(AgeGateStore.blockUntilKey);
        expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isFalse);

        await AgeGateStore.restoreBlock(prefs, platform: TargetPlatform.iOS);
        expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isTrue);

        await AgeGateStore.restoreBlock(
          prefs,
          now: () => DateTime.now().add(const Duration(days: 31)),
          platform: TargetPlatform.iOS,
        );
        expect(prefs.getString(AgeGateStore.blockUntilKey), isNull);
      },
    );

    test(
      'an expired Keychain copy never removes a block still in force in prefs '
      '(review M-8)',
      () async {
        // A block 40 days ago, in both places, now long expired...
        await AgeGateStore(
          prefs,
          now: () => DateTime.now().subtract(const Duration(days: 40)),
        ).block();
        // ...then a new one whose Keychain write failed.
        final newer =
            DateTime.now()
                .toUtc()
                .add(const Duration(days: 20))
                .toIso8601String();
        await prefs.setString(AgeGateStore.blockUntilKey, newer);

        await AgeGateStore.restoreBlock(prefs, platform: TargetPlatform.iOS);
        expect(prefs.getString(AgeGateStore.blockUntilKey), newer);
        expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isTrue);
      },
    );

    test('a Keychain block in force replaces an expired prefs copy', () async {
      await AgeGateStore(prefs).block();
      // The prefs copy is an old, expired one (a re-block's prefs write
      // failed).
      await prefs.setString(
        AgeGateStore.blockUntilKey,
        DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 5))
            .toIso8601String(),
      );
      expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isFalse);

      await AgeGateStore.restoreBlock(prefs, platform: TargetPlatform.iOS);
      expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isTrue);
    });

    test(
      'restoreBlock never opens the keystore on Android (review I-1)',
      () async {
        // The Android keystore file is excluded from backup, so it can never
        // outlive a reinstall: the prefs copy is the Android carrier (§3.6).
        final secure = _CountingSecure();
        await AgeGateStore.restoreBlock(
          prefs,
          secure: secure,
          platform: TargetPlatform.android,
        );
        expect(secure.reads, 0);

        await AgeGateStore.restoreBlock(
          prefs,
          secure: secure,
          platform: TargetPlatform.iOS,
        );
        expect(secure.reads, 1, reason: 'iOS still reads the Keychain copy');
      },
    );

    test('an under-18 block also ends the guest pass (ruling N-1)', () async {
      final store = AgeGateStore(prefs);
      await store.passGuestGate(1990);
      expect(AgeGateStore.readGuestOk(prefs), isTrue);

      await store.block();
      expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isTrue);
      expect(
        AgeGateStore.readGuestOk(prefs),
        isFalse,
        reason: 'a blocked device reads guest Opinions only after G1 again',
      );
    });

    test('block() never throws, even when prefs cannot be written', () async {
      await expectLater(
        AgeGateStore(_PrefsThatFailWrites(prefs)).block(),
        completes,
      );
    });

    test(
      'signing out keeps the block and the passed gate (review M-7)',
      () async {
        final store = AgeGateStore(prefs);
        // Block first: a block clears an earlier guest pass (ruling N-1).
        await store.block();
        await store.passGuestGate(1990);
        await prefs.setBool('some_user_thing', true);

        await PreferencesService(prefs).clearUserData();
        expect(AgeGateStore.readBlocked(prefs, DateTime.now()), isTrue);
        expect(AgeGateStore.readGuestOk(prefs), isTrue);
        expect(prefs.containsKey('some_user_thing'), isFalse);
      },
    );

    test('the guest year is cleared once sign-up completes', () async {
      final store = AgeGateStore(prefs);
      await store.passGuestGate(1990);
      expect(await store.guestBirthYear(), 1990);
      await store.clearGuestBirthYear();
      expect(await store.guestBirthYear(), isNull);
      expect(store.guestOk, isTrue, reason: 'the gate stays passed');
    });
  });
}
