// Spec 2 W8b (§2.3, §2.5, §3.1 away, §3.11, §3.14, §3.15, §7.4; R-75..R-79;
// D8): the device check, the away card, the trip's note and its four
// choices, the note's own page; and the restricted screen's lines in
// testing (W7 carry M-6). The check runs only for someone with Dating
// data on a phone Dating can use, at most once per 15 minutes while the
// section shows, sends the network country, and reads the home again
// when a trip began or ended. The note names the place only while this
// phone's check said so. Never animated; every choice waits offline;
// busy is calm; another account sees nothing of the last one's trip.
// R-T4-9 (carry 1): a same-gender trip's note and choice are this phone's
// own (no server call); Today reads again on resume and when a card is
// gone (carry 5).
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/device/dating_surface.dart';
import 'package:attune/features/dating/device/dating_trip.dart';
import 'package:attune/features/dating/device/network_country.dart';
import 'package:attune/features/dating/device/trip_note.dart';
import 'package:attune/features/dating/device/trip_phone.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/today/dating_today_repository.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_report_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';
import '../support/dating_trip_fakes.dart';

final loc = AppLocalizationsEn();

const _away = DatingHome(
  state: DatingHomeState.away,
  hasData: true,
  trip: DatingTrip(kind: DatingTripKind.away, note: true),
);
// R-T4-9: the home names only the kind; the phone decides the note.
const _sameGender = DatingHome(
  state: DatingHomeState.active,
  hasData: true,
  trip: DatingTrip(kind: DatingTripKind.sameGender),
);

class _Section {
  _Section(this.home, this.trip, this.life);
  final FakeDatingHomeGateway home;
  final FakeDatingTrip trip;
  final FakeDatingLifecycleGateway life;
}

Future<_Section> _pump(
  WidgetTester t,
  DatingHome state, {
  DatingDeviceCheck answer = const DatingDeviceCheck(ok: true, trusted: true),
  String? network,
  bool online = true,
}) async {
  await t.pumpWidget(const SizedBox());
  final home = FakeDatingHomeGateway(home: state);
  final trip = FakeDatingTrip(answer: answer);
  final life = FakeDatingLifecycleGateway();
  await pumpFlowScreen(
    t,
    () => const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: DatingSection(),
      ),
    ),
    overrides: [
      ...datingShellOverrides(home: home, life: life, online: online),
      ...datingTripOverrides(trip, network: network),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(FakeHomeStateGateway(state: homeJson(path: 'dating'))),
      ),
    ],
  );
  await t.pumpAndSettle();
  return _Section(home, trip, life);
}

const _me = '/w8-me';

class _Shell {
  _Shell(this.shell, this.trip);
  final DatingShell shell;
  final FakeDatingTrip trip;
}

/// Me's Dating section on a page of its own, in the Dating shell (so
/// "What this means" opens the real /dating/away).
Future<_Shell> _pumpMe(
  WidgetTester t,
  DatingHome state, {
  DatingDeviceCheck answer = const DatingDeviceCheck(ok: true, trusted: true),
  List<Override> overrides = const [],
}) async {
  final trip = FakeDatingTrip(answer: answer);
  final shell = await pumpDatingShell(
    t,
    initial: _me,
    home: FakeDatingHomeGateway(home: state),
    extraRoutes: [
      GoRoute(
        path: _me,
        builder:
            (_, __) => const Scaffold(
              body: SingleChildScrollView(child: DatingSection()),
            ),
      ),
    ],
    overrides: [
      ...datingTripOverrides(trip),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(FakeHomeStateGateway(state: homeJson(path: 'dating'))),
      ),
      ...overrides,
    ],
  );
  return _Shell(shell, trip);
}

/// /dating/away alone, in the Dating shell.
Future<_Shell> _pumpPage(
  WidgetTester t,
  DatingHome state, {
  bool online = true,
}) async {
  final trip = FakeDatingTrip();
  final shell = await pumpDatingShell(
    t,
    initial: DatingPaths.away,
    online: online,
    home: FakeDatingHomeGateway(home: state),
    overrides: datingTripOverrides(trip),
  );
  return _Shell(shell, trip);
}

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(MaterialApp)));

Future<void> _resume(WidgetTester t) async {
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await t.pumpAndSettle();
}

void main() {
  // A fresh phone in every test: no same-gender mark held in memory.
  setUp(DatingTripPhone.reset);

  group('the models', () {
    test('the home reads away, the trip and the plain-icon offer', () {
      final h = DatingHome.fromJson({
        'state': 'away',
        'has_data': true,
        'trip': {'kind': 'away', 'note': true, 'show_here': false},
        'offer_plain_icon': true,
      });
      expect(h.state, DatingHomeState.away);
      expect(h.trip?.kind, DatingTripKind.away);
      expect(h.trip?.note, isTrue);
      expect(h.offerPlainIcon, isTrue);
      final shown = DatingHome.fromJson({
        'state': 'away',
        'trip': {'kind': 'away', 'note': false, 'show_here': true},
      });
      expect(shown.trip?.showHere, isTrue);
      expect(shown.trip?.note, isFalse);
      // R-T4-9: a same-gender trip is its kind alone; anything else the
      // answer carried is not the phone's (it decides from its own mark).
      final s = DatingHome.fromJson({
        'state': 'active',
        'trip': {'kind': 'same_gender', 'note': false, 'show_here': true},
      });
      expect(s.trip?.kind, DatingTripKind.sameGender);
      expect(s.trip?.showHere, isFalse);
      expect(s.trip?.note, isFalse);
      expect(DatingHome.fromJson({'state': 'active'}).trip, isNull);
      expect(
        DatingHome.fromJson({
          'state': 'active',
          'trip': {'kind': 'x'},
        }).trip,
        isNull,
      );
      expect(DatingHome.fromJson({'state': 'active'}).offerPlainIcon, isFalse);
      // Carry 4: the gentle wait reads away while Dating isn't allowed.
      expect(
        DatingHome.fromJson({
          'state': 'cool_off',
          'trip': {'kind': 'same_gender'},
        }).trip?.kind,
        DatingTripKind.sameGender,
      );
    });

    test('withTrip keeps everything else the home said', () {
      final h = DatingHome.fromJson({
        'state': 'cool_off',
        'country': 'GH',
        'region': 'aa',
        'open_regions': ['aa'],
        'pause_reason': 'user',
        'first_drop_at': '2026-11-24T19:00:00Z',
        'ended_at': '2026-11-01T10:00:00Z',
        'opens_at': '2026-12-01T10:00:00Z',
        'can_shorten': true,
        'can_resume': true,
        'has_data': true,
        'next_step': 'how',
        'notify': {'available': true, 'requested': true},
        'variant': 'setup_restart',
        'check': 'needed',
        'appeal_accepted': true,
        'trip': {'kind': 'same_gender'},
        'offer_plain_icon': true,
      });
      final w = h.withTrip(
        const DatingTrip(kind: DatingTripKind.sameGender, note: true),
      );
      expect(w.trip?.note, isTrue);
      expect(
        [
          w.state,
          w.country,
          w.region,
          w.openRegions,
          w.pauseReason,
          w.firstDropAt,
          w.endedAt,
          w.opensAt,
          w.canShorten,
          w.canResume,
          w.hasData,
          w.nextStep,
          w.notice.available,
          w.notice.requested,
          w.reverifyVariant,
          w.check,
          w.appealAccepted,
          w.offerPlainIcon,
        ],
        [
          h.state,
          h.country,
          h.region,
          h.openRegions,
          h.pauseReason,
          h.firstDropAt,
          h.endedAt,
          h.opensAt,
          h.canShorten,
          h.canResume,
          h.hasData,
          h.nextStep,
          true,
          true,
          h.reverifyVariant,
          h.check,
          h.appealAccepted,
          true,
        ],
      );
    });

    test('the check\'s answer, and when it disagrees with the home shown', () {
      final a = DatingDeviceCheck.fromJson({
        'ok': true,
        'trusted': true,
        'away': true,
        'note': {'country': 'AE'},
      });
      expect(
        [a.ok, a.trusted, a.away, a.noteCountry],
        [true, true, true, 'AE'],
      );
      expect(
        DatingDeviceCheck.fromJson({'ok': false, 'reason': 'busy'}).ok,
        isFalse,
      );
      expect(
        DatingDeviceCheck.fromJson({
          'ok': true,
          'note': {'country': 'Dubai'},
        }).noteCountry,
        isNull,
      );
      expect(DatingDeviceCheck.fromJson({'ok': true, 'note': null}).ok, isTrue);
      const home = DatingHome(state: DatingHomeState.active);
      expect(a.disagreesWith(home), isTrue);
      expect(a.disagreesWith(_away), isFalse);
      // Task 6: away with the place unresolved (note null) is still away.
      expect(
        const DatingDeviceCheck(ok: true, away: true).disagreesWith(_away),
        isFalse,
      );
      expect(
        const DatingDeviceCheck(
          ok: true,
          away: true,
        ).disagreesWith(const DatingHome(state: DatingHomeState.away)),
        isTrue,
      );
      const there = DatingDeviceCheck(ok: true, noteCountry: 'GH');
      expect(there.disagreesWith(_sameGender), isFalse);
      // An away trip that ended where same-gender introductions still
      // aren't allowed: the home shown (away) is from before.
      expect(there.disagreesWith(_away), isTrue);
      const back = DatingDeviceCheck(ok: true);
      expect(back.disagreesWith(_sameGender), isTrue);
      expect(back.disagreesWith(home), isFalse);
    });

    test(
      'the network country: Android only, two letters, upper case',
      () async {
        final calls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NetworkCountry.channel, (call) async {
              calls.add(call.method);
              return calls.length == 1 ? 'ae' : 'United';
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(NetworkCountry.channel, null),
        );
        expect(
          await NetworkCountry.read(platform: TargetPlatform.android),
          'AE',
        );
        expect(
          await NetworkCountry.read(platform: TargetPlatform.android),
          isNull,
        );
        expect(await NetworkCountry.read(platform: TargetPlatform.iOS), isNull);
        expect(calls, ['networkCountryIso', 'networkCountryIso']);
      },
    );

    test('the network country: no channel answers null', () async {
      expect(
        await NetworkCountry.read(platform: TargetPlatform.android),
        isNull,
      );
    });

    test('the repository: the check\'s body, and the away choice', () async {
      final bodies = <Map<String, Object?>>[];
      final rpc = ScriptedRpc([
        (fn, p) => {'ok': true},
      ]);
      final repo = DatingTripRepository(rpc.rpc, (body) async {
        bodies.add(body);
        return {
          'ok': true,
          'trusted': true,
          'away': false,
          'note': {'country': 'GH'},
        };
      });
      final a = await repo.check(networkCountry: 'GH');
      expect(a.noteCountry, 'GH');
      await repo.check();
      expect(bodies, [
        {'network_country': 'GH'},
        <String, Object?>{},
      ]);
      expect((await repo.choose('k1', showHere: true)).ok, isTrue);
      expect(rpc.calls.single.$1, 'set_dating_trip_choice');
      expect(rpc.calls.single.$2, {
        'p_idempotency_key': 'k1',
        'p_show_here': true,
      });
      final broken = DatingTripRepository(
        rpc.rpc,
        (body) async => throw StateError('down'),
      );
      expect((await broken.check()).ok, isFalse);
    });
  });

  group('the device check', () {
    testWidgets('someone with Dating data: once per 15 minutes, with the '
        'network country; a trip that began reads the home again', (t) async {
      final s = await _pump(
        t,
        const DatingHome(state: DatingHomeState.active, hasData: true),
        answer: const DatingDeviceCheck(ok: true, trusted: true, away: true),
        network: 'AE',
      );
      expect(s.trip.checks, ['AE']);
      expect(s.home.reads, 2);
      // The app comes back: the home is read again, the check waits.
      await _resume(t);
      expect(s.home.reads, greaterThan(2));
      expect(s.trip.checks, ['AE']);
    });

    testWidgets('an answer that agrees with the home reads nothing again', (
      t,
    ) async {
      final s = await _pump(
        t,
        const DatingHome(state: DatingHomeState.active, hasData: true),
      );
      expect(s.trip.checks, [null]);
      expect(s.home.reads, 1);
    });

    testWidgets('a failed check changes nothing and reads nothing again', (
      t,
    ) async {
      final s = await _pump(t, _away, answer: DatingDeviceCheck.failed);
      expect(s.trip.checks, [null]);
      expect(s.home.reads, 1);
      expect(find.text(loc.dating_sectionAway), findsOneWidget);
    });

    testWidgets('another account on the phone is checked for itself', (
      t,
    ) async {
      final s = await _pump(
        t,
        const DatingHome(state: DatingHomeState.active, hasData: true),
      );
      expect(s.trip.checks, hasLength(1));
      _container(t).read(datingTestAccount.notifier).state = 'kofi';
      await t.pumpAndSettle();
      expect(s.trip.checks, hasLength(2));
    });

    for (final home in [
      const DatingHome(state: DatingHomeState.notStarted),
      const DatingHome(state: DatingHomeState.active),
      const DatingHome(state: DatingHomeState.reverifyDevice, hasData: true),
      const DatingHome(
        state: DatingHomeState.countryClosed,
        hasData: true,
        country: 'NG',
      ),
      const DatingHome(
        state: DatingHomeState.featureUnavailable,
        hasData: true,
      ),
      const DatingHome(state: DatingHomeState.regionClosed, hasData: true),
    ]) {
      testWidgets('no check for ${home.state.wire} (data: ${home.hasData})', (
        t,
      ) async {
        final s = await _pump(t, home);
        expect(s.trip.checks, isEmpty);
      });
    }
  });

  group('Me says only the neutral line and the link (fix round 1, I-2)', () {
    // Nothing on Me (no FLAG_SECURE, no capture cover) names a gender, a
    // place, or offers the choices.
    void expectNothingRevealing() {
      for (final text in [
        'Ghana',
        'United Arab Emirates',
        'same gender',
        'While you',
        loc.dating_tripKeepHidden,
        loc.dating_tripShowAnyway,
        loc.dating_tripPause,
        loc.dating_tripSetPin,
      ]) {
        expect(find.textContaining(text), findsNothing, reason: text);
      }
    }

    testWidgets('away: the away card, its link and settings; no words of '
        'the note, no place, no choices; nothing moves', (t) async {
      await _pump(
        t,
        _away,
        answer: const DatingDeviceCheck(
          ok: true,
          trusted: true,
          away: true,
          noteCountry: 'AE',
        ),
      );
      expect(find.text(loc.dating_sectionAway), findsOneWidget);
      expect(find.text(loc.dating_tripMore), findsOneWidget);
      expect(find.text(loc.dating_settingsTitle), findsOneWidget);
      expect(find.text(loc.dating_chatsTitle), findsNothing);
      expectNothingRevealing();
      expect(find.byType(AnimatedOpacity), findsNothing);
      await expectFlowGuidelines(t);
    });

    testWidgets('away, shown on this phone anyway: the away card offers the '
        'conversations', (t) async {
      await _pump(
        t,
        const DatingHome(
          state: DatingHomeState.away,
          hasData: true,
          trip: DatingTrip(kind: DatingTripKind.away, showHere: true),
        ),
      );
      expect(find.text(loc.dating_chatsTitle), findsOneWidget);
      expect(find.text(loc.dating_tripMore), findsOneWidget);
    });

    testWidgets('a same-gender trip on the active card: the neutral title and '
        '"What this means", under the card\'s own line', (t) async {
      await _pump(
        t,
        _sameGender,
        answer: const DatingDeviceCheck(
          ok: true,
          trusted: true,
          noteCountry: 'GH',
        ),
      );
      expect(find.text(loc.dating_sectionOpenToday), findsOneWidget);
      expect(find.text(loc.dating_tripSameGenderTitle), findsOneWidget);
      expect(find.text(loc.dating_tripMore), findsOneWidget);
      expect(
        t.getTopLeft(find.text(loc.dating_sectionActive)).dy,
        lessThan(t.getTopLeft(find.text(loc.dating_tripSameGenderTitle)).dy),
      );
      expectNothingRevealing();
    });

    testWidgets('carry 4: the same in the gentle wait', (t) async {
      await _pump(
        t,
        const DatingHome(
          state: DatingHomeState.coolOff,
          hasData: true,
          trip: DatingTrip(kind: DatingTripKind.sameGender),
        ),
        answer: const DatingDeviceCheck(ok: true, noteCountry: 'GH'),
      );
      expect(find.text(loc.dating_tripSameGenderTitle), findsOneWidget);
      expect(find.text(loc.dating_tripMore), findsOneWidget);
      expect(find.text(loc.dating_settingsTitle), findsOneWidget);
      expectNothingRevealing();
    });

    testWidgets('no trip: neither', (t) async {
      await _pump(
        t,
        const DatingHome(state: DatingHomeState.active, hasData: true),
      );
      expect(find.text(loc.dating_tripSameGenderTitle), findsNothing);
      expect(find.text(loc.dating_tripMore), findsNothing);
    });

    testWidgets('"What this means" opens /dating/away, where the note names '
        'the place this phone\'s check said; Keep it hidden first', (t) async {
      await _pumpMe(
        t,
        _sameGender,
        answer: const DatingDeviceCheck(ok: true, noteCountry: 'GH'),
      );
      await tapInReach(t, find.text(loc.dating_tripMore));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_tripSameGenderBody('Ghana')), findsOneWidget);
      expect(
        t.getTopLeft(find.byKey(const ValueKey('dating_trip_hide'))).dy,
        lessThan(
          t.getTopLeft(find.byKey(const ValueKey('dating_trip_show'))).dy,
        ),
      );
    });
  });

  group('the note on its page', () {
    testWidgets('away: the four choices; no place known: "while you\'re '
        'away"; nothing moves', (t) async {
      await _pumpPage(t, _away);
      expect(find.text(loc.dating_tripAwayTitle), findsOneWidget);
      expect(find.text(loc.dating_tripAwayBodyNoPlace), findsOneWidget);
      for (final label in [
        loc.dating_tripKeepHidden,
        loc.dating_tripShowAnyway,
        loc.dating_tripPause,
        loc.dating_tripSetPin,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.byType(AnimatedOpacity), findsNothing);
    });

    testWidgets('Keep it hidden: the choice under one key, then the home '
        'again; nothing kept on the phone', (t) async {
      final p = await _pumpPage(t, _away);
      final before = p.shell.home.reads;
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(p.trip.choices.single.$2, isFalse);
      expect(p.shell.home.reads, greaterThan(before));
      expect(await DatingTripPhone.markFor('ama'), isNull);
    });

    testWidgets('Show it on this phone anyway: shown; then only Keep it '
        'hidden is offered (M-7)', (t) async {
      final p = await _pumpPage(t, _away);
      p.shell.home.home = const DatingHome(
        state: DatingHomeState.away,
        hasData: true,
        trip: DatingTrip(kind: DatingTripKind.away, showHere: true),
      );
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_show')));
      await t.pumpAndSettle();
      expect(p.trip.choices.single.$2, isTrue);
      expect(find.byKey(const ValueKey('dating_trip_show')), findsNothing);
      expect(find.byKey(const ValueKey('dating_trip_hide')), findsOneWidget);
    });

    testWidgets('Pause Dating: kept hidden first, then paused', (t) async {
      final p = await _pumpPage(t, _away);
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_pause')));
      await t.pumpAndSettle();
      expect(p.trip.choices.single.$2, isFalse);
      expect(p.shell.life.calls, ['pause']);
    });

    testWidgets('a failed pause says so and stays', (t) async {
      final p = await _pumpPage(t, _away);
      p.shell.life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.busy,
      );
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_pause')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_busy), findsOneWidget);
      expect(find.text(loc.dating_tripAwayTitle), findsOneWidget);
      p.shell.life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.failed,
      );
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_pause')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
    });

    testWidgets('busy is a calm line; a failure the error line; no trip any '
        'more just reads the home', (t) async {
      final p = await _pumpPage(t, _away);
      p.trip.choice = DatingWrite.busy;
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_busy), findsOneWidget);
      p.trip.choice = DatingWrite.failed;
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
      // The same key both times: the outcome was unknown.
      expect(p.trip.choices[0].$1, p.trip.choices[1].$1);
      p.trip.choice = const DatingWrite(ok: false, reason: 'no_trip');
      p.shell.home.home = const DatingHome(
        state: DatingHomeState.active,
        hasData: true,
      );
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_errorGeneric), findsNothing);
      expect(find.text(loc.dating_tripAwayTitle), findsNothing);
      expect(find.text(loc.dating_cardGone), findsOneWidget);
    });

    testWidgets('reverify_device on the choice is the error line and stays', (
      t,
    ) async {
      final p = await _pumpPage(t, _away);
      p.trip.choice = const DatingWrite(ok: false, reason: 'reverify_device');
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
      expect(find.text(loc.dating_tripAwayTitle), findsOneWidget);
    });

    testWidgets('offline every choice waits', (t) async {
      final p = await _pumpPage(t, _away, online: false);
      expect(find.text(loc.dating_offline), findsWidgets);
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(p.trip.choices, isEmpty);
    });

    testWidgets('the Dating lock already on: no Set a PIN', (t) async {
      await t.pumpWidget(const SizedBox());
      await pumpFlowScreen(
        t,
        () => const Scaffold(
          body: SingleChildScrollView(
            child: DatingTripNote(
              trip: DatingTrip(kind: DatingTripKind.away, note: true),
              country: null,
              onDone: _noop,
            ),
          ),
        ),
        overrides: [
          ...datingShellOverrides(),
          ...datingTripOverrides(FakeDatingTrip()),
          datingLockStoreProvider.overrideWithValue(FakeLock(true)),
        ],
      );
      expect(find.byKey(const ValueKey('dating_trip_pin')), findsNothing);
      expect(find.byKey(const ValueKey('dating_trip_pause')), findsOneWidget);
    });
  });

  group('a same-gender trip lives on this phone (R-T4-9)', () {
    testWidgets('Keep it hidden: no server call; answered on this phone', (
      t,
    ) async {
      final p = await _pumpPage(t, _sameGender);
      final before = p.shell.home.reads;
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(p.trip.choices, isEmpty);
      expect(p.shell.home.reads, greaterThan(before));
      expect((await DatingTripPhone.markFor('ama'))?.show, isFalse);
      expect(await DatingTripPhone.showFor('ama'), isFalse);
    });

    testWidgets('Show it on this phone anyway: no server call; the reads ask '
        'for it; then only Keep it hidden is offered', (t) async {
      final p = await _pumpPage(t, _sameGender);
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_show')));
      await t.pumpAndSettle();
      expect(p.trip.choices, isEmpty);
      expect(await DatingTripPhone.showFor('ama'), isTrue);
      expect(find.byKey(const ValueKey('dating_trip_show')), findsNothing);
      expect(find.byKey(const ValueKey('dating_trip_hide')), findsOneWidget);
      // D8: nobody else on the phone.
      expect(await DatingTripPhone.showFor('kofi'), isFalse);
      p.shell.container.read(datingTestAccount.notifier).state = 'kofi';
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dating_trip_show')), findsOneWidget);
    });

    testWidgets('Pause Dating: answered on the phone, then paused', (t) async {
      final p = await _pumpPage(t, _sameGender);
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_pause')));
      await t.pumpAndSettle();
      expect(p.trip.choices, isEmpty);
      expect(p.shell.life.calls, ['pause']);
      expect((await DatingTripPhone.markFor('ama'))?.show, isFalse);
    });

    testWidgets('the way back (I-3): from Me, Show it anyway; Me still links '
        'to the page, where Keep it hidden takes it back, and the reads then '
        'ask for nothing', (t) async {
      final calls = <(String, Map<String, dynamic>?)>[];
      // The app's Today repository on a recording RPC, reading the signed-in
      // account's choice as datingTodayGatewayProvider does (that wiring is
      // pinned in trip_phone_test.dart).
      final s = await _pumpMe(
        t,
        _sameGender,
        overrides: [
          datingTodayGatewayProvider.overrideWith(
            (ref) => DatingTodayRepository(
              DatingRpc.withCall((fn, p) async {
                calls.add((fn, p));
                return {'ok': true};
              }),
              (body) async => null,
              showSameGender:
                  () =>
                      DatingTripPhone.showFor(ref.read(datingAccountProvider)),
            ),
          ),
        ],
      );
      Future<Object?> asked() async {
        calls.clear();
        await s.shell.container.read(datingTodayGatewayProvider).today();
        return calls.single.$2?['p_show_same_gender'];
      }

      expect(await asked(), isFalse);
      await tapInReach(t, find.text(loc.dating_tripMore));
      await t.pumpAndSettle();
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_show')));
      await t.pumpAndSettle();
      // Back on Me: the same neutral line and the link.
      expect(find.byType(DatingTripNote), findsNothing);
      expect(find.text(loc.dating_tripSameGenderTitle), findsOneWidget);
      expect(await asked(), isTrue);
      await tapInReach(t, find.text(loc.dating_tripMore));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dating_trip_show')), findsNothing);
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(find.byType(DatingTripNote), findsNothing);
      expect(await DatingTripPhone.showFor('ama'), isFalse);
      expect(await asked(), isFalse);
      expect(s.trip.choices, isEmpty);
    });

    testWidgets('nothing is done once quick exit has run', (t) async {
      final p = await _pumpPage(t, _sameGender);
      final show = find.byKey(const ValueKey('dating_trip_show'));
      await bringIntoReach(t, show);
      // Hidden, and tapped before the next frame takes the page away: the
      // note itself refuses.
      await DatingSurface.hide();
      await t.tap(show);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(await DatingTripPhone.markFor('ama'), isNull);
      expect(p.shell.life.calls, isEmpty);
      DatingSurface.reset();
    });
  });

  group('the page', () {
    testWidgets('/dating/away: the note for this account\'s trip; the gone '
        'line without one', (t) async {
      final trip = FakeDatingTrip();
      await pumpDatingShell(
        t,
        initial: DatingPaths.away,
        home: FakeDatingHomeGateway(home: _away),
        overrides: datingTripOverrides(trip),
      );
      expect(find.text(loc.dating_tripAwayTitle), findsOneWidget);
      expect(find.text(loc.dating_tripAwayBodyNoPlace), findsOneWidget);
      await pumpDatingShell(
        t,
        initial: DatingPaths.away,
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active, hasData: true),
        ),
      );
      expect(find.text(loc.dating_cardGone), findsOneWidget);
      expect(find.text(loc.dating_tripAwayTitle), findsNothing);
    });

    testWidgets('/dating/away: a choice there, alone, reads the home and '
        'stays; the way back is Me', (t) async {
      final trip = FakeDatingTrip();
      final home = FakeDatingHomeGateway(home: _away);
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.away,
        home: home,
        overrides: datingTripOverrides(trip),
      );
      final before = home.reads;
      expect(find.byKey(const ValueKey('dating_root_back')), findsOneWidget);
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_hide')));
      await t.pumpAndSettle();
      expect(trip.choices.single.$2, isFalse);
      expect(home.reads, greaterThan(before));
      expect(s.location, DatingPaths.away);
      await t.tap(find.byKey(const ValueKey('dating_root_back')));
      await t.pumpAndSettle();
      expect(find.text('ME me'), findsOneWidget);
    });

    testWidgets('/dating/away is behind the Dating lock', (t) async {
      await pumpDatingShell(
        t,
        initial: DatingPaths.away,
        locked: true,
        pinSet: true,
        home: FakeDatingHomeGateway(home: _away),
      );
      expect(find.text(loc.dating_tripAwayTitle), findsNothing);
    });

    testWidgets('D8: another account sees nothing of an open note', (t) async {
      final home = FakeDatingHomeGateway(home: _away);
      final s = await pumpDatingShell(t, initial: DatingPaths.away, home: home);
      expect(find.text(loc.dating_tripAwayTitle), findsOneWidget);
      home.home = const DatingHome(
        state: DatingHomeState.active,
        hasData: true,
      );
      s.container.read(datingTestAccount.notifier).state = 'kofi';
      await t.pump();
      expect(find.text(loc.dating_tripAwayTitle), findsNothing);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_tripAwayTitle), findsNothing);
      expect(find.text(loc.dating_cardGone), findsOneWidget);
    });
  });

  testWidgets('the page: goldens at 1.0, 1.3, 2.0 and RTL; the three '
      'guidelines', (t) async {
    Widget screen() => const DatingAwayScreen();
    final overrides = [
      ...datingShellOverrides(home: FakeDatingHomeGateway(home: _away)),
      ...datingTripOverrides(FakeDatingTrip()),
    ];
    await expectFlowGoldens(t, 'dating_away', screen, overrides: overrides);
    await pumpFlowScreen(t, screen, overrides: overrides);
    await expectFlowGuidelines(t);
  });

  group('stale screens (carry 5)', () {
    setUp(() async {
      datingFetched.clear();
      await DatingPhotoMemory.clear();
    });

    testWidgets('Today reads again when the app comes back', (t) async {
      final fake = FakeDatingToday();
      await pumpDatingShell(
        t,
        initial: DatingPaths.today,
        overrides: datingTodayOverrides(fake),
      );
      final before = fake.reads;
      await _resume(t);
      expect(fake.reads, before + 1);
    });

    testWidgets('a card gone on the server: a calm line, Today reads again '
        'and the card leaves', (t) async {
      final fake =
          FakeDatingToday()
            ..answer =
                (id, action) => const DatingActAnswer(
                  ok: false,
                  reason: 'introduction_unavailable',
                );
      await pumpDatingShell(
        t,
        initial: DatingPaths.today,
        overrides: datingTodayOverrides(fake),
      );
      final before = fake.reads;
      fake.json = datingTodayJson({'cards': <Object?>[]});
      await tapInReach(t, find.text(loc.dating_cardInterested));
      await t.pumpAndSettle();
      expect(fake.reads, before + 1);
      expect(find.text(loc.dating_cardInterested), findsNothing);
      expect(find.text(loc.dating_errorGeneric), findsNothing);
    });
  });

  group('what a read no longer lists (Task 5 review carries a, b)', () {
    setUp(() async {
      datingFetched.clear();
      await DatingPhotoMemory.clear();
    });

    test('Today\'s read: an introduction it no longer lists leaves memory '
        'with its photos; the others and every match stay', () async {
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'cards': [datingCardJson('i1')],
          'waiting': [datingCardJson('i3')],
        }),
      );
      for (final (kind, id) in [
        ('introduction', 'i1'),
        ('introduction', 'i2'),
        ('introduction', 'i3'),
        ('match', 'm1'),
      ]) {
        DatingPhotoMemory.put(
          DatingPhotoMemory.key(kind, id, 1),
          datingTestPng,
        );
      }
      final container = ProviderContainer(
        overrides: datingTodayOverrides(fake),
      );
      addTearDown(container.dispose);
      await container.read(datingTodayProvider('ama').future);
      expect(
        DatingPhotoMemory.get(DatingPhotoMemory.key('introduction', 'i2', 1)),
        isNull,
      );
      for (final (kind, id) in [
        ('introduction', 'i1'),
        ('introduction', 'i3'),
        ('match', 'm1'),
      ]) {
        expect(
          DatingPhotoMemory.get(DatingPhotoMemory.key(kind, id, 1)),
          isNotNull,
          reason: '$kind $id',
        );
      }
    });

    testWidgets('Today: a card a read drops leaves with its photos; listed '
        'again, its photos are fetched afresh', (t) async {
      final fake = FakeDatingToday();
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.today,
        overrides: datingTodayOverrides(fake),
      );
      expect(fake.photoCalls, [('introduction', 'i1')]);
      fake.json = datingTodayJson({'cards': <Object?>[]});
      s.container.invalidate(datingTodayProvider('ama'));
      await t.pumpAndSettle();
      expect(DatingPhotoMemory.length, 0);
      fake.json = datingTodayJson();
      s.container.invalidate(datingTodayProvider('ama'));
      await t.pumpAndSettle();
      expect(fake.photoCalls, [('introduction', 'i1'), ('introduction', 'i1')]);
    });

    testWidgets('an act replay\'s match a trip hides opens no moment, nor '
        'another in its place', (t) async {
      Map<String, Object?> moment(String id, String name) => {
        'match_id': id,
        'display_name': name,
      };
      final fake = FakeDatingToday(
          today: datingTodayJson({
            'moments': [moment('m1', 'Yaw')],
          }),
        )
        ..answer =
            (id, action) => DatingActAnswer(
              ok: true,
              action: action,
              matched: true,
              matchId: 'm9',
            );
      await pumpDatingShell(
        t,
        initial: DatingPaths.today,
        overrides: datingTodayOverrides(fake),
      );
      expect(find.text(loc.dating_momentTitle('Yaw')), findsOneWidget);
      fake.json = datingTodayJson();
      await tapInReach(t, find.text(loc.dating_momentLater));
      await t.pumpAndSettle();
      // The replay names m9, which this read doesn't list (hidden); Kofi's
      // m2 arrived from the other side and keeps "one moment per visit".
      fake.json = datingTodayJson({
        'cards': <Object?>[],
        'moments': [moment('m2', 'Kofi')],
      });
      await tapInReach(t, find.text(loc.dating_cardInterested));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_momentTitle('Kofi')), findsNothing);
      expect(fake.seen, ['m1']);
    });
  });

  group('the restricted screen in testing (W7 carry M-6)', () {
    Future<void> open(WidgetTester t, Map<String, Object?> json) async {
      final fake =
          FakeDatingReport()..read = DatingRestrictionRead.fromJson(json);
      await pumpDatingShell(
        t,
        initial: DatingPaths.restricted,
        overrides: datingReportOverrides(fake),
      );
    }

    Map<String, Object?> hold(String? review) => {
      'ok': true,
      if (review != null) 'review': review,
      'restriction': {
        'id': 'r1',
        'type': 'hold',
        'category': 'threat_to_life',
        'source': 'p0_interim',
        'can_appeal': false,
      },
    };

    Map<String, Object?> appealed(String? review) => {
      'ok': true,
      if (review != null) 'review': review,
      'restriction': {
        'id': 'r2',
        'type': 'suspended',
        'category': 'harassment',
        'source': 'moderator',
        'ends_at': '2026-12-20T10:00:00Z',
        'can_appeal': false,
        'appeal': {'state': 'open', 'submitted_at': '2026-11-22T10:00:00Z'},
      },
    };

    for (final review in [null, 'testing']) {
      testWidgets('review $review: no review time anywhere', (t) async {
        await open(t, hold(review));
        expect(find.text(loc.dating_restrictedHoldPlain), findsOneWidget);
        expect(find.text(loc.dating_restrictedHold), findsNothing);
        await open(t, appealed(review));
        expect(find.text(loc.dating_appealSentTesting), findsOneWidget);
        expect(find.text(loc.dating_appealSent), findsNothing);
      });
    }

    testWidgets('fix round 1 (M-2): a read built in code promises no review '
        'time unless it says a person reviews', (t) async {
      final r = DatingRestrictionRead.fromJson(hold('staffed')).restriction;
      for (final (read, line) in [
        (
          DatingRestrictionRead(ok: true, restriction: r),
          loc.dating_restrictedHoldPlain,
        ),
        (
          DatingRestrictionRead(ok: true, restriction: r, staffed: true),
          loc.dating_restrictedHold,
        ),
      ]) {
        await pumpDatingShell(
          t,
          initial: DatingPaths.restricted,
          overrides: datingReportOverrides(FakeDatingReport()..read = read),
        );
        expect(find.text(line), findsOneWidget);
      }
    });

    testWidgets(
      'staffed: the interim hold\'s 24 hours and the appeal\'s 7 days',
      (t) async {
        await open(t, hold('staffed'));
        expect(find.text(loc.dating_restrictedHold), findsOneWidget);
        await open(t, appealed('staffed'));
        expect(find.text(loc.dating_appealSent), findsOneWidget);
      },
    );
  });
}

void _noop() {}
