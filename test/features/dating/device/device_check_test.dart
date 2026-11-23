// Spec 2 W8 final client fix (I-1; §2.3, §2.5): the device check is
// Dating's own. It starts when the app comes back, on the first Dating
// page and from Today's, the conversations' and the messages' reads; those
// reads wait for a check under way (at most 3 s); an answer that differs
// from the last one this phone kept (per account, in memory) reads the
// home, Today, the conversations and the open chat again. A same-gender
// trip that begins (a place now, none before) is the case Me's home check
// never caught. The throttle runs on a monotonic stopwatch or the wall
// clock, whichever says the 15 minutes are up.
import 'dart:async';

import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_providers.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/device/dating_device_check.dart';
import 'package:attune/features/dating/device/dating_trip.dart';
import 'package:attune/features/dating/device/trip_phone.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart'
    show DatingSessionMemory;
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';
import '../support/dating_trip_fakes.dart';

final loc = AppLocalizationsEn();

const _active = DatingHome(state: DatingHomeState.active, hasData: true);

/// London: no restriction. Accra, for someone who meets men: a place
/// that restricts same-gender introductions (the check's note).
const _london = DatingDeviceCheck(ok: true, trusted: true);
const _accra = DatingDeviceCheck(ok: true, trusted: true, noteCountry: 'GH');

/// The test's monotonic time (DatingDeviceChecker.monotonic).
var _mono = Duration.zero;

/// Today as the server reads it: each read's cards are recorded, so a
/// read drawn from the last place shows in [cardsRead].
class _Today extends FakeDatingToday {
  final cardsRead = <int>[];

  @override
  Future<DatingToday> today() async {
    final read = await super.today();
    cardsRead.add(read.cards.length);
    return read;
  }
}

/// The conversations as the server reads them, recorded the same way.
class _Chat extends FakeDatingChat {
  final rowsRead = <int>[];

  @override
  Future<DatingConversations> conversations({bool ended = false}) async {
    final read = await super.conversations(ended: ended);
    rowsRead.add(read.conversations.length);
    return read;
  }
}

/// The trip: London first; [fly] makes the next check land in Accra,
/// held until [land] (when the server's context row has moved: [moved]).
class _Trip extends FakeDatingTrip {
  _Trip() : super(answer: _london);

  void Function()? moved;

  void fly() {
    answer = _accra;
    checkHold = Completer<void>();
    // The 15 minutes are up (monotonic).
    _mono += const Duration(minutes: 16);
  }

  void land() {
    moved?.call();
    checkHold!.complete();
  }
}

/// The app comes back; the pages' reads are asked again (a frame for the
/// invalidation, one for the read).
Future<void> _resume(WidgetTester t) async {
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await t.pump();
  await t.pump();
}

const _me = '/w8-me';

Future<DatingShell> _shell(
  WidgetTester t, {
  required String initial,
  required List<Override> overrides,
}) => pumpDatingShell(
  t,
  initial: initial,
  home: FakeDatingHomeGateway(home: _active),
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
    homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
    homeStateServiceProvider.overrideWithValue(
      HomeStateService(FakeHomeStateGateway(state: homeJson(path: 'dating'))),
    ),
    datingChatPollJitterProvider.overrideWithValue(() => Duration.zero),
    ...overrides,
  ],
);

void main() {
  final realMonotonic = DatingDeviceChecker.monotonic;
  setUp(() async {
    _mono = Duration.zero;
    DatingDeviceChecker.monotonic = () => _mono;
    DatingTripPhone.reset();
    datingFetched.clear();
    await DatingPhotoMemory.clear();
  });
  tearDown(() => DatingDeviceChecker.monotonic = realMonotonic);

  group('resume on Today', () {
    testWidgets('a check that begins a same-gender trip: Today waits for '
        'it, and the hidden card leaves without a second resume', (t) async {
      final today = _Today();
      final trip = _Trip();
      await _shell(
        t,
        initial: DatingPaths.today,
        overrides: [
          ...datingTodayOverrides(today),
          ...datingTripOverrides(trip),
        ],
      );
      expect(find.text(loc.dating_cardInterested), findsOneWidget);
      expect(trip.checks, hasLength(1));
      final before = today.reads;
      trip
        ..fly()
        ..moved = () => today.json = datingTodayJson({'cards': <Object?>[]});
      await _resume(t);
      expect(trip.checks, hasLength(2));
      await t.pump(const Duration(seconds: 1));
      // Nothing is read against the last place while the check is under way.
      expect(today.reads, before);
      trip.land();
      await t.pumpAndSettle();
      expect(find.text(loc.dating_cardInterested), findsNothing);
      // One read after the resume, after the check: no card drawn again.
      expect(today.reads, before + 1);
      expect(today.cardsRead.last, 0);
    });

    testWidgets('a check slower than 3 s: Today reads as before at 3 s, and '
        'the answer, when it lands, reads it again', (t) async {
      final today = _Today();
      final trip = _Trip();
      await _shell(
        t,
        initial: DatingPaths.today,
        overrides: [
          ...datingTodayOverrides(today),
          ...datingTripOverrides(trip),
        ],
      );
      final before = today.reads;
      trip
        ..fly()
        ..moved = () => today.json = datingTodayJson({'cards': <Object?>[]});
      await _resume(t);
      await t.pump(const Duration(milliseconds: 2900));
      expect(today.reads, before);
      await t.pump(const Duration(milliseconds: 200));
      await t.pump();
      expect(today.reads, before + 1);
      expect(find.text(loc.dating_cardInterested), findsOneWidget);
      trip.land();
      await t.pumpAndSettle();
      expect(today.reads, before + 2);
      expect(find.text(loc.dating_cardInterested), findsNothing);
    });

    testWidgets('the same answer again reads nothing again (a man-woman '
        'person in a place that restricts)', (t) async {
      final today = _Today();
      final trip = FakeDatingTrip(answer: _accra);
      final s = await _shell(
        t,
        initial: DatingPaths.today,
        overrides: [
          ...datingTodayOverrides(today),
          ...datingTripOverrides(trip),
        ],
      );
      final before = today.reads;
      final homes = s.home.reads;
      _mono += const Duration(minutes: 16);
      await _resume(t);
      await t.pumpAndSettle();
      expect(trip.checks, hasLength(2));
      // The resume's own read only; the home isn't read again.
      expect(today.reads, before + 1);
      expect(s.home.reads, homes);
      final checker = s.container.read(datingDeviceCheckerProvider.notifier);
      expect(checker.changesFor('ama'), 1);
    });
  });

  group('resume on Conversations', () {
    testWidgets('a check that begins a same-gender trip: the list waits for '
        'it, and the hidden conversation leaves without a second resume', (
      t,
    ) async {
      final chat = _Chat();
      final trip = _Trip();
      await _shell(
        t,
        initial: DatingPaths.chats,
        overrides: [...datingChatOverrides(chat), ...datingTripOverrides(trip)],
      );
      expect(find.textContaining('Kofi'), findsWidgets);
      final before = chat.listReads;
      trip
        ..fly()
        ..moved =
            () =>
                chat.listJson = datingConversationsJson(
                  rows: const <Map<String, Object?>>[],
                );
      await _resume(t);
      await t.pump(const Duration(seconds: 1));
      expect(chat.listReads, before);
      trip.land();
      await t.pumpAndSettle();
      expect(find.textContaining('Kofi'), findsNothing);
      expect(chat.listReads, before + 1);
      expect(chat.rowsRead.last, 0);
    });

    testWidgets('a check slower than 3 s: the answer, when it lands, reads '
        'the list again', (t) async {
      final chat = _Chat();
      final trip = _Trip();
      await _shell(
        t,
        initial: DatingPaths.chats,
        overrides: [...datingChatOverrides(chat), ...datingTripOverrides(trip)],
      );
      final before = chat.listReads;
      trip
        ..fly()
        ..moved =
            () =>
                chat.listJson = datingConversationsJson(
                  rows: const <Map<String, Object?>>[],
                );
      await _resume(t);
      await t.pump(const Duration(milliseconds: 3100));
      await t.pump();
      expect(chat.listReads, before + 1);
      expect(find.textContaining('Kofi'), findsWidgets);
      trip.land();
      await t.pumpAndSettle();
      expect(find.textContaining('Kofi'), findsNothing);
    });
  });

  group('the open chat', () {
    testWidgets('resume: the messages wait for the check; a trip that hides '
        'the match shows its gone line', (t) async {
      final chat = FakeDatingChat();
      final trip = _Trip();
      await _shell(
        t,
        initial: DatingPaths.chat('m1'),
        overrides: [...datingChatOverrides(chat), ...datingTripOverrides(trip)],
      );
      expect(find.text(loc.dating_cardGone), findsNothing);
      final before = chat.reads.length;
      trip
        ..fly()
        ..moved = () => chat.refusals['messages'] = 'match_unavailable';
      await _resume(t);
      await t.pump(const Duration(seconds: 1));
      expect(chat.reads.length, before);
      trip.land();
      await t.pumpAndSettle();
      expect(find.text(loc.dating_cardGone), findsOneWidget);
    });

    testWidgets('an answer that lands after the read reads the chat again', (
      t,
    ) async {
      final chat = FakeDatingChat();
      final trip = _Trip();
      await _shell(
        t,
        initial: DatingPaths.chat('m1'),
        overrides: [...datingChatOverrides(chat), ...datingTripOverrides(trip)],
      );
      trip
        ..fly()
        ..moved = () => chat.refusals['messages'] = 'match_unavailable';
      await _resume(t);
      await t.pump(const Duration(milliseconds: 3100));
      await t.pump();
      expect(find.text(loc.dating_cardGone), findsNothing);
      trip.land();
      await t.pumpAndSettle();
      expect(find.text(loc.dating_cardGone), findsOneWidget);
    });
  });

  testWidgets('cold start: Open Today tapped before the first check lands '
      'shows no same-gender card', (t) async {
    final today = _Today();
    final trip =
        _Trip()
          ..answer = _accra
          ..checkHold = Completer<void>()
          ..moved = () {};
    await _shell(
      t,
      initial: _me,
      overrides: [...datingTodayOverrides(today), ...datingTripOverrides(trip)],
    );
    // Me's section started the check after its home read.
    expect(trip.checks, hasLength(1));
    await tapInReach(t, find.text(loc.dating_sectionOpenToday));
    await t.pump(const Duration(seconds: 1));
    expect(today.reads, 0);
    trip.moved = () => today.json = datingTodayJson({'cards': <Object?>[]});
    trip.land();
    await t.pumpAndSettle();
    expect(find.text(loc.dating_cardInterested), findsNothing);
    expect(today.cardsRead, [0]);
    // Me's line came with the answer (the home read again).
    expect(trip.checks, hasLength(1));
  });

  testWidgets('resume on Me: the check starts at once (not after the home '
      'read), and a same-gender trip it begins shows Me\'s trip line', (
    t,
  ) async {
    final trip = _Trip();
    final s = await _shell(
      t,
      initial: _me,
      overrides: datingTripOverrides(trip),
    );
    expect(trip.checks, hasLength(1));
    expect(find.text(loc.dating_tripSameGenderTitle), findsNothing);
    trip
      ..fly()
      ..moved =
          () =>
              s.home.home = const DatingHome(
                state: DatingHomeState.active,
                hasData: true,
                trip: DatingTrip(kind: DatingTripKind.sameGender),
              );
    final held = s.home.hold = Completer<DatingHome>();
    await _resume(t);
    // The lifecycle hook: the check is under way while the home read waits.
    expect(trip.checks, hasLength(2));
    s.home.hold = null;
    held.complete(_active);
    await t.pump();
    trip.land();
    await t.pumpAndSettle();
    expect(find.text(loc.dating_tripSameGenderTitle), findsOneWidget);
  });

  testWidgets('the first Dating page starts the check (a home known to have '
      'Dating data)', (t) async {
    final trip = FakeDatingTrip();
    await _shell(t, initial: _me, overrides: datingTripOverrides(trip));
    expect(trip.checks, hasLength(1));
    _mono += const Duration(minutes: 16);
    unawaited(
      GoRouter.of(
        t.element(find.byType(DatingSection)),
      ).push(DatingPaths.settings),
    );
    await t.pumpAndSettle();
    expect(trip.checks, hasLength(2));
  });

  group('the throttle (a monotonic stopwatch or the wall clock)', () {
    late FakeDatingTrip trip;
    late ProviderContainer container;
    late DatingDeviceChecker checker;
    var wall = DateTime.utc(2026, 11, 23, 9);

    setUp(() {
      wall = DateTime.utc(2026, 11, 23, 9);
      trip = FakeDatingTrip();
      container = ProviderContainer(
        overrides: [
          ...datingTripOverrides(trip),
          datingAccountProvider.overrideWithValue('ama'),
        ],
      );
      container.listen(datingDeviceCheckerProvider, (_, __) {});
      checker = container.read(datingDeviceCheckerProvider.notifier);
    });
    tearDown(() => container.dispose());

    Future<void> check() async {
      final run = checker.ensure('ama', home: _active);
      if (run != null) await run;
    }

    test('within 15 minutes on both clocks: no second check', () async {
      await withClock(Clock(() => wall), () async {
        await check();
        _mono += const Duration(minutes: 14);
        wall = wall.add(const Duration(minutes: 14));
        await check();
        expect(trip.checks, hasLength(1));
        _mono += const Duration(minutes: 1);
        await check();
        expect(trip.checks, hasLength(2));
      });
    });

    test('the clock set back a day never stalls it', () async {
      await withClock(Clock(() => wall), () async {
        await check();
        wall = wall.subtract(const Duration(days: 1));
        _mono += const Duration(minutes: 15);
        await check();
        expect(trip.checks, hasLength(2));
      });
    });

    test('a phone asleep (the stopwatch barely moved, hours on the wall '
        'clock): the check runs', () async {
      await withClock(Clock(() => wall), () async {
        await check();
        _mono += const Duration(seconds: 30);
        wall = wall.add(const Duration(hours: 6));
        await check();
        expect(trip.checks, hasLength(2));
      });
    });

    test('a home without Dating data, or closed here, is never checked', () {
      for (final home in const [
        DatingHome(state: DatingHomeState.active),
        DatingHome(state: DatingHomeState.countryClosed, hasData: true),
        DatingHome(state: DatingHomeState.featureUnavailable, hasData: true),
        DatingHome(state: DatingHomeState.regionClosed, hasData: true),
        DatingHome(state: DatingHomeState.reverifyDevice, hasData: true),
      ]) {
        expect(checker.ensure('ama', home: home), isNull, reason: '$home');
      }
      // The lifecycle hook needs a home known here.
      expect(checker.ensure('ama', needHome: true), isNull);
      expect(trip.checks, isEmpty);
    });
  });

  test('the answers are per account, in memory, and the wipe empties them '
      '(D8, §6.7)', () async {
    final trip = FakeDatingTrip(answer: _accra);
    final container = ProviderContainer(
      overrides: [
        ...datingTripOverrides(trip),
        datingAccountProvider.overrideWithValue('ama'),
      ],
    );
    addTearDown(container.dispose);
    container.listen(datingDeviceCheckerProvider, (_, __) {});
    final checker = container.read(datingDeviceCheckerProvider.notifier);
    final run = await checker.ensure('ama', home: _active);
    expect(run!.changed, isTrue);
    expect(container.read(datingTripPlaceProvider('ama')), 'GH');
    expect(container.read(datingTripPlaceProvider('kofi')), isNull);
    expect(checker.changesFor('ama'), 1);
    expect(checker.changesFor('kofi'), 0);
    await DatingSessionMemory.clear();
    expect(container.read(datingDeviceCheckerProvider).answers, isEmpty);
    expect(container.read(datingTripPlaceProvider('ama')), isNull);
    // The throttle went with it: the next check runs at once.
    expect(checker.ensure('ama', home: _active), isNotNull);
  });
}
