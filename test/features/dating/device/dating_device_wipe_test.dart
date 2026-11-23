// Spec 2 W8a (§6.7, §7.4, §7.7; C-2, C-3; carries 3, 4): quick exit and
// sign-out reach Dating only through Spec 1's device wipe registry, and
// leave no Dating data in memory: the other people's photos and their
// decoded copies, the unsent dismissals, the report and appeal request
// keys (what was typed), the meet plan. The Dating lock and the Safety PIN
// stay (sign-out clears the lock: Spec 1), a scheduled check-in is never
// cancelled, a hanging entry never stalls the exit, and no frame of Dating
// shows once quick exit is pressed (the W6 decoy carry).
import 'dart:async';

import 'package:attune/app/device_wipes.dart';
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/chat/chat_sheets.dart';
import 'package:attune/features/dating/chat/dating_chat_providers.dart';
import 'package:attune/features/dating/chat/plan_meet_screen.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/device/dating_surface.dart';
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/report/appeal_sheet.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/dating_report_providers.dart';
import 'package:attune/features/dating/report/report_sheet.dart';
import 'package:attune/features/dating/routes/dating_page_watch.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/section/dating_why_sheet.dart';
import 'package:attune/features/dating/settings/never_introduce_sheets.dart';
import 'package:attune/features/dating/setup/country_note_screen.dart';
import 'package:attune/features/dating/setup/dating_picker_sheet.dart';
import 'package:attune/features/dating/setup/dating_support_sheet.dart';
import 'package:attune/features/dating/today/block_sheet.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/verify/dating_capture.dart';
import 'package:attune/features/me/presentation/widgets/dating_slot.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:attune/home/home_seams.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/home_harness.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_report_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

Future<void> _quickExit(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.tap(find.byKey(const Key('quick_exit_zone')), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Every Dating memory W8a wipes, filled as a person using Dating fills it.
Future<({String photo, String reportKey, Set<String> dismissals})> _fill(
  DatingShell s,
) async {
  final key = DatingPhotoMemory.key('introduction', 'i9', 1);
  DatingPhotoMemory.put(key, datingTestPng);
  final reportKey = s.container.read(datingReportKeysProvider('ama')).keyFor(
    'report:m1',
    ['harassment', 'What they wrote to me', false],
  );
  final dismissals = s.container.read(
    datingPendingCardDismissalsProvider('ama'),
  )..add('card-1');
  DatingPlanMemory.place = 'Accra Mall food court';
  DatingPlanMemory.at = DateTime(2026, 11, 22, 18);
  DatingPlanMemory.account = 'ama';
  DatingPlanMemory.checkinAt = DateTime(2026, 11, 22, 21);
  return (photo: key, reportKey: reportKey, dismissals: dismissals);
}

void _expectWiped(
  DatingShell s,
  ({String photo, String reportKey, Set<String> dismissals}) filled,
) {
  expect(DatingPhotoMemory.get(filled.photo), isNull);
  expect(DatingPhotoMemory.length, 0);
  expect(
    PaintingBinding.instance.imageCache.containsKey(MemoryImage(datingTestPng)),
    isFalse,
  );
  expect(filled.dismissals, isEmpty);
  // The same report again is a new request: the old key (and the words
  // it was made from) is gone.
  expect(
    s.container.read(datingReportKeysProvider('ama')).keyFor('report:m1', [
      'harassment',
      'What they wrote to me',
      false,
    ]),
    isNot(filled.reportKey),
  );
  expect(DatingPlanMemory.place, isNull);
  expect(DatingPlanMemory.checkinAt, isNull);
}

const _me = '/w8-me';
const _kit = '/w8-kit';
const _slot = '/w8-slot';
const _typed = 'He threatened me SECRETWORDS';

/// Me's Dating section on a page of its own (Me itself is Spec 1's).
Future<DatingShell> _pumpMe(
  WidgetTester t, {
  String initial = _me,
  bool exitZone = false,
  List<Override> overrides = const [],
}) => pumpDatingShell(
  t,
  initial: initial,
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
    ...overrides,
  ],
  wrap:
      exitZone
          ? (router, child) => QuickExitZone(router: router, child: child)
          : null,
);

bool _sectionShown(WidgetTester t) =>
    t
        .widget<Visibility>(
          find.byKey(const ValueKey('dating_section_surface')),
        )
        .visible;

void main() {
  setUp(() {
    DeviceWipeRegistry.instance.clear();
    registerDeviceWipes();
    QuickExitService.clearStories = () async {};
    QuickExitService.exitOverride = () async {};
    // Round 4 (Re-2-M1): the quiet window's stopwatch on the test's clock,
    // which pump advances (production: a monotonic Stopwatch).
    DatingSurface.stopwatch = () => clock.stopwatch();
    addTearDown(() {
      DatingSurface.stopwatch = Stopwatch.new;
      QuickExitService.clearStories = clearStoryDeviceCaches;
      QuickExitService.exitOverride = null;
      DeviceWipeRegistry.instance.clear();
      DatingSurface.reset();
    });
  });

  test('Dating registers its entries: none protective, the sweep at 20', () {
    final registry = DeviceWipeRegistry();
    registerDatingDeviceWipes(registry);
    final ids = {for (final e in registry.entries) e.id: e};
    expect(ids.keys, {
      'spec2.dating_session',
      'spec2.dating_photos',
      'spec2.dating_plan',
      'spec2.dating_surface',
      'spec2.section_view',
      'spec2.section_caches',
    });
    final sweep = ids['spec2.section_caches']!;
    expect(sweep.order, 20);
    expect(sweep.moments, {WipeMoment.quickExit, WipeMoment.signOut});
    expect(sweep.bound, const Duration(seconds: 1));
    expect(ids['spec2.dating_surface']!.order, 0);
    for (final e in registry.entries) {
      expect(e.protective, isFalse, reason: e.id);
      // Spec 2 W8b: the same-gender note's mark is the one device key.
      expect(
        e.keys,
        e.id == 'spec2.section_view' ? {'me_section_view'} : isEmpty,
        reason: e.id,
      );
    }
  });

  for (final (place, path, overrides) in [
    ('Today', DatingPaths.today, datingTodayOverrides(FakeDatingToday())),
    ('a chat', DatingPaths.chat('m1'), datingChatOverrides(FakeDatingChat())),
    (
      'the meeting kit',
      DatingPaths.plan('m1'),
      datingChatOverrides(FakeDatingChat()),
    ),
  ]) {
    testWidgets('quick exit from $place: Dating memory empty; the lock and '
        'the Safety PIN unchanged', (t) async {
      final s = await pumpDatingShell(
        t,
        initial: path,
        locked: true,
        pinSet: true,
        overrides: overrides,
        wrap: (router, child) => QuickExitZone(router: router, child: child),
      );
      // The PIN was asked for on the way in (the lock is on).
      s.container.read(datingUnlockedProvider.notifier).unlock();
      s.router.go(path);
      await t.pumpAndSettle();
      expect(s.location, path);
      final filled = await _fill(s);
      await _quickExit(t);
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('DECOY'), findsOneWidget);
      expect(DatingPageWatch.open, 0);
      _expectWiped(s, filled);
      expect(s.lock.on, isTrue);
      expect(
        await const FlutterSecureStorage().read(key: 'safety_pin_hash'),
        isNotNull,
      );
    });
  }

  testWidgets('quick exit never cancels a scheduled check-in', (t) async {
    final chat = FakeDatingChat()..checkinAt = DateTime(2026, 11, 22, 21);
    await pumpDatingShell(
      t,
      initial: DatingPaths.plan('m1'),
      overrides: datingChatOverrides(chat),
      wrap: (router, child) => QuickExitZone(router: router, child: child),
    );
    final before = List.of(chat.checkins);
    await _quickExit(t);
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('DECOY'), findsOneWidget);
    expect(chat.checkins, before);
    expect(chat.checkinAt, isNotNull);
  });

  testWidgets('no frame of Dating shows once quick exit is pressed', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: datingTodayOverrides(FakeDatingToday()),
      wrap: (router, child) => QuickExitZone(router: router, child: child),
    );
    expect(find.textContaining('Kofi'), findsWidgets);
    for (var i = 0; i < 3; i++) {
      await t.tap(
        find.byKey(const Key('quick_exit_zone')),
        warnIfMissed: false,
      );
      if (i < 2) await t.pump(const Duration(milliseconds: 50));
    }
    // The decoy's first frame: its transition has only begun, and the
    // Today page under it is already blank.
    await t.pump();
    expect(find.textContaining('Kofi', skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('dating_blank_page')), findsWidgets);
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('DECOY'), findsOneWidget);
    // Dating opened again afterwards shows as before.
    s.router.go(DatingPaths.today);
    await t.pumpAndSettle();
    expect(find.textContaining('Kofi'), findsWidgets);
    expect(find.byKey(const ValueKey('dating_blank_page')), findsNothing);
  });

  testWidgets('sign-out empties the same memory; the Safety PIN stays '
      '(the lock is Spec 1\'s to clear at sign-out)', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      pinSet: true,
      overrides: datingTodayOverrides(FakeDatingToday()),
    );
    final filled = await _fill(s);
    await DeviceWipeRegistry.instance.run(WipeMoment.signOut);
    await t.pump();
    expect(find.byKey(const ValueKey('dating_blank_page')), findsWidgets);
    _expectWiped(s, filled);
    expect(
      await const FlutterSecureStorage().read(key: 'safety_pin_hash'),
      isNotNull,
    );
  });

  testWidgets('a hanging Dating entry never stalls the exit', (t) async {
    DeviceWipeRegistry.instance.register(
      DeviceWipeEntry(
        id: 'spec2.test_hang',
        order: 20,
        moments: const {WipeMoment.quickExit},
        run: () => Completer<void>().future,
      ),
    );
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: datingTodayOverrides(FakeDatingToday()),
      wrap: (router, child) => QuickExitZone(router: router, child: child),
    );
    final filled = await _fill(s);
    await _quickExit(t);
    await t.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('DECOY'), findsOneWidget);
    _expectWiped(s, filled);
  });

  // Fix round 1 (I-1): a Dating sheet over a Dating page, with the other
  // person's name and what was typed, is blank in the decoy's first frame
  // and stays blank under its transition.
  testWidgets('no frame of a Dating sheet shows once quick exit is pressed: '
      'the report sheet, its name and what was typed', (t) async {
    await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: [
        ...datingTodayOverrides(FakeDatingToday()),
        ...datingReportOverrides(FakeDatingReport()),
      ],
      wrap: (router, child) => QuickExitZone(router: router, child: child),
    );
    unawaited(
      showDatingReportSheet(
        t.element(find.byType(DatingPageWatch)),
        account: 'ama',
        name: 'Kofi',
        target: const DatingReportMatch('m1'),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('dating_report_details')),
      _typed,
    );
    await t.pump();
    expect(find.text(_typed), findsOneWidget);
    expect(find.byType(DatingReportSheet), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await t.tap(
        find.byKey(const Key('quick_exit_zone')),
        warnIfMissed: false,
      );
      if (i < 2) await t.pump(const Duration(milliseconds: 50));
    }
    for (final at in [Duration.zero, const Duration(milliseconds: 150)]) {
      await t.pump(at);
      expect(
        find.text(_typed, skipOffstage: false),
        findsNothing,
        reason: '$at',
      );
      expect(
        find.textContaining('Kofi', skipOffstage: false),
        findsNothing,
        reason: '$at',
      );
      expect(
        find.byType(DatingReportSheet, skipOffstage: false),
        findsNothing,
        reason: '$at',
      );
    }
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('DECOY'), findsOneWidget);
  });

  // Fix round 1: an answer that lands under the decoy's transition and
  // opens a Dating sheet then shows nothing, and shows nothing else again.
  testWidgets('a Dating sheet opened under the decoy\'s transition: the '
      'opener refuses it (round 2), and one pushed anyway is held blank', (
    t,
  ) async {
    await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: [
        ...datingTodayOverrides(FakeDatingToday()),
        ...datingReportOverrides(FakeDatingReport()),
      ],
      wrap: (router, child) => QuickExitZone(router: router, child: child),
    );
    final page = t.element(find.byType(DatingPageWatch));
    for (var i = 0; i < 3; i++) {
      await t.tap(
        find.byKey(const Key('quick_exit_zone')),
        warnIfMissed: false,
      );
      if (i < 2) await t.pump(const Duration(milliseconds: 50));
    }
    await t.pump();
    // Round 2 (Re-1-M2): the report sheet's opener pushes nothing.
    final answers = <Object?>[];
    unawaited(
      showDatingReportSheet(
        page,
        account: 'ama',
        name: 'Kofi',
        target: const DatingReportMatch('m1'),
      ).then(answers.add),
    );
    await t.pump();
    expect(answers, [null]);
    expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    // The backstop: a tracked sheet pushed anyway stays blank.
    unawaited(
      showModalBottomSheet<void>(
        context: page,
        isScrollControlled: true,
        builder: (_) => const DatingSheetTracker(child: Text('Report Kofi')),
      ),
    );
    for (final at in [Duration.zero, const Duration(milliseconds: 150)]) {
      await t.pump(at);
      expect(
        find.textContaining('Kofi', skipOffstage: false),
        findsNothing,
        reason: '$at',
      );
      expect(find.byType(BottomSheet, skipOffstage: false), findsOneWidget);
    }
    // Every page has gone by now; the late sheet over the decoy is still
    // blank.
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(DatingPageWatch.open, 0);
    expect(find.textContaining('Kofi', skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('dating_blank_page')), findsOneWidget);
  });

  // Round 2 (Re-1-M2): every Dating sheet, dialog and picker opener
  // refuses while Dating is blank, answering as if dismissed.
  testWidgets('once quick exit or sign-out has run, no Dating sheet opens: '
      'each opener answers as if dismissed', (t) async {
    await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: [
        ...datingTodayOverrides(FakeDatingToday()),
        ...datingReportOverrides(FakeDatingReport()),
      ],
    );
    final c = t.element(find.byType(DatingPageWatch));
    await DatingSurface.hide();
    final answers = <String, Object?>{};
    void note(String name, Future<Object?> answer) =>
        unawaited(answer.then((v) => answers[name] = v));
    note(
      'safety',
      showDatingSafetySheet(c, account: 'ama', name: 'Kofi', ended: false),
    );
    note('unmatch', showDatingUnmatchSheet(c, account: 'ama', name: 'Kofi'));
    note('swap', showDatingSwapSheet(c, account: 'ama'));
    note('call', showDatingCallSheet(c, account: 'ama', number: '0200'));
    note('checkin', showDatingCheckinHelpSheet(c, account: 'ama'));
    note('masked', showDatingMaskedSheet(c, account: 'ama'));
    note('kindly', showDatingCloseKindlySheet(c, account: 'ama'));
    note(
      'guided',
      showDatingGuidedAnswerSheet(c, account: 'ama', question: 'Why?'),
    );
    note('never', showDatingNeverRemoveSheet(c, account: 'ama'));
    note(
      'confirm',
      showDatingConfirmSheet(
        c,
        account: 'ama',
        name: 'w8',
        title: 't',
        body: 'b',
        keep: 'k',
        act: 'a',
      ),
    );
    note('more', showDatingCardMoreSheet(c, account: 'ama', name: 'Kofi'));
    note('block', showDatingBlockSheet(c, account: 'ama', name: 'Kofi'));
    note('why', showDatingWhySheet(c, country: 'GH'));
    note('picker', showDatingPicker<int>(c, title: 't', items: [(1, 'one')]));
    note('support', showDatingSupportSheet(c, country: 'GH'));
    note(
      'appeal',
      showDatingAppealSheet(c, account: 'ama', restrictionId: 'r1'),
    );
    note(
      'report',
      showDatingReportSheet(
        c,
        account: 'ama',
        name: 'Kofi',
        target: const DatingReportMatch('m1'),
      ),
    );
    note('country', showDatingCountryNote(c, country: 'GH'));
    note(
      'capture',
      const DatingDevCaptureLauncher().liveness(
        c,
        vendor: 'fake',
        vendorRef: 'v1',
      ),
    );
    await t.pump();
    expect(answers, {
      'safety': null,
      'unmatch': false,
      'swap': false,
      'call': false,
      'checkin': null,
      'masked': null,
      'kindly': false,
      'guided': null,
      'never': false,
      'confirm': false,
      'more': null,
      'block': false,
      'why': null,
      'picker': null,
      'support': null,
      'appeal': false,
      'report': null,
      'capture': DatingCaptureResult.cancelled,
      'country': DatingNoteChoice.back,
    });
    expect(find.byType(DatingSheetTracker, skipOffstage: false), findsNothing);
    expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    await t.pumpAndSettle();
  });

  // Round 3 (Re-2-I1): the D6 country note, a full-screen route of its own
  // over the meet step, says what it is about (the person's orientation,
  // the country's risk): blank in the decoy's first frame and under its
  // transition.
  testWidgets('the D6 country note shows nothing once quick exit is pressed', (
    t,
  ) async {
    await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: datingTodayOverrides(FakeDatingToday()),
      wrap: (router, child) => QuickExitZone(router: router, child: child),
    );
    unawaited(
      showDatingCountryNote(
        t.element(find.byType(DatingPageWatch)),
        country: 'GH',
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Before you save this'), findsOneWidget);
    expect(find.textContaining('same gender'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await t.tap(
        find.byKey(const Key('quick_exit_zone')),
        warnIfMissed: false,
      );
      if (i < 2) await t.pump(const Duration(milliseconds: 50));
    }
    for (final at in [Duration.zero, const Duration(milliseconds: 150)]) {
      await t.pump(at);
      expect(
        find.text('Before you save this', skipOffstage: false),
        findsNothing,
        reason: '$at',
      );
      expect(
        find.textContaining('same gender', skipOffstage: false),
        findsNothing,
        reason: '$at',
      );
    }
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('DECOY'), findsOneWidget);
  });

  // Round 3 (sweep): Today's "Not for me." bar is in Today's own messenger,
  // inside the page, so it goes with the page's first blank frame.
  testWidgets('Today\'s "Not for me." bar shows nothing once quick exit is '
      'pressed', (t) async {
    await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: datingTodayOverrides(FakeDatingToday()),
      wrap: (router, child) => QuickExitZone(router: router, child: child),
    );
    final notForMe = find.text('Not for me').first;
    await t.ensureVisible(notForMe);
    await t.tap(notForMe);
    await t.pumpAndSettle();
    expect(find.text('Not for me.'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await t.tap(
        find.byKey(const Key('quick_exit_zone')),
        warnIfMissed: false,
      );
      if (i < 2) await t.pump(const Duration(milliseconds: 50));
    }
    for (final at in [Duration.zero, const Duration(milliseconds: 150)]) {
      await t.pump(at);
      expect(
        find.text('Not for me.', skipOffstage: false),
        findsNothing,
        reason: '$at',
      );
    }
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('DECOY'), findsOneWidget);
    await t.pump(const Duration(seconds: 30));
  });

  // Round 4 (Re-2-M1): the quiet window is measured on a monotonic
  // stopwatch, so the phone's clock set back after quick exit never keeps
  // the unlock off.
  testWidgets('a phone clock set back after a wipe never keeps the Dating '
      'unlock off', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: datingTodayOverrides(FakeDatingToday()),
    );
    await DatingSurface.hide();
    await t.pump(const Duration(seconds: 3));
    // An hour back (a time zone change, the network's time): the window
    // ended all the same.
    withClock(
      Clock.fixed(clock.now().subtract(const Duration(hours: 1))),
      () => s.container.read(datingUnlockedProvider.notifier).unlock(),
    );
    expect(s.container.read(datingUnlockedProvider), isTrue);
  });

  // Round 4: the Dating lock closes the D6 country note as it closes every
  // other Dating sheet (closeDatingSheets: the unlock ended with Me
  // mounted), and the meet step's wait for it ends (Go back's answer).
  testWidgets('the Dating lock closes the D6 country note, and its opener '
      'hears Go back', (t) async {
    await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: datingTodayOverrides(FakeDatingToday()),
    );
    final answers = <DatingNoteChoice>[];
    unawaited(
      showDatingCountryNote(
        t.element(find.byType(DatingPageWatch)),
        country: 'GH',
      ).then(answers.add),
    );
    await t.pumpAndSettle();
    expect(find.text('Before you save this'), findsOneWidget);
    closeDatingSheets();
    await t.pumpAndSettle();
    expect(find.text('Before you save this'), findsNothing);
    expect(answers, [DatingNoteChoice.back]);
  });

  // Round 2: the setup picker (untracked until now) is blank once quick
  // exit or sign-out runs, like every Dating sheet.
  testWidgets('the setup picker shows nothing once quick exit or sign-out '
      'runs', (t) async {
    await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: datingTodayOverrides(FakeDatingToday()),
    );
    unawaited(
      showDatingPicker<int>(
        t.element(find.byType(DatingPageWatch)),
        title: 'Pick one',
        items: [(1, 'The first')],
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('The first'), findsOneWidget);
    await DatingSurface.hide();
    await t.pump();
    expect(find.text('The first', skipOffstage: false), findsNothing);
    expect(find.text('Pick one', skipOffstage: false), findsNothing);
  });

  // Round 2 (Re-1-M2): the kit's pickers, opened on a kit no blank covers.
  testWidgets('the meeting kit opens no picker once quick exit or sign-out '
      'has run', (t) async {
    await pumpDatingShell(
      t,
      initial: _kit,
      overrides: datingChatOverrides(FakeDatingChat()),
      extraRoutes: [
        GoRoute(
          path: _kit,
          builder: (_, __) => const DatingPlanMeetScreen(matchId: 'm1'),
        ),
      ],
    );
    await DatingSurface.hide();
    final when = find.byKey(const ValueKey('dating_plan_when'));
    await t.ensureVisible(when);
    await t.tap(when);
    await t.pumpAndSettle();
    expect(find.byType(DatePickerDialog, skipOffstage: false), findsNothing);
    expect(find.byType(TimePickerDialog, skipOffstage: false), findsNothing);
  });

  // Round 2 (Re-1-M1): Spec 1's PIN sheet on Me's slot answers just after
  // quick exit: nothing unlocks and nothing of the section shows under the
  // decoy; the next PIN, later, unlocks as before.
  testWidgets('a PIN check that finishes under the decoy unlocks nothing and '
      'shows nothing of the Dating section', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: _slot,
      locked: true,
      extraRoutes: [
        GoRoute(
          path: _slot,
          builder:
              (_, __) => Scaffold(
                body: SingleChildScrollView(
                  child: DatingSlot(home: snapshotOf(homeJson(path: 'dating'))),
                ),
              ),
        ),
      ],
      overrides: [
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
        homeStateServiceProvider.overrideWithValue(
          HomeStateService(
            FakeHomeStateGateway(state: homeJson(path: 'dating')),
          ),
        ),
      ],
      wrap: (router, child) => QuickExitZone(router: router, child: child),
    );
    expect(find.text('Dating is locked'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await t.tap(
        find.byKey(const Key('quick_exit_zone')),
        warnIfMissed: false,
      );
      if (i < 2) await t.pump(const Duration(milliseconds: 50));
    }
    await t.pump();
    // The slot's PIN check passes now and asks for the unlock.
    s.container.read(datingUnlockedProvider.notifier).unlock();
    for (final at in [Duration.zero, const Duration(milliseconds: 150)]) {
      await t.pump(at);
      expect(s.container.read(datingUnlockedProvider), isFalse);
      expect(find.byType(DatingSection, skipOffstage: false), findsNothing);
    }
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('DECOY'), findsOneWidget);
    // Later: the PIN entered again on Me unlocks (never a dead end).
    await t.pump(const Duration(seconds: 3));
    s.container.read(datingUnlockedProvider.notifier).unlock();
    expect(s.container.read(datingUnlockedProvider), isTrue);
    expect(DatingSurface.hidden.value, isFalse);
  });

  // Fix round 1: a reset asked for inside a frame lands after it, and a
  // hide in that same frame wins.
  testWidgets('a hide after a reset asked for in the same frame wins', (
    t,
  ) async {
    await DatingSurface.hide();
    await t.pumpWidget(
      Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => DatingSurface.hide(),
          );
          DatingSurface.reset();
          return const SizedBox();
        },
      ),
    );
    expect(DatingSurface.hidden.value, isTrue);
  });

  // Fix round 1 (I-1): the meeting kit's pickers (the day, then the time).
  for (final picker in ['date', 'time']) {
    testWidgets('the meeting kit\'s $picker picker shows nothing once quick '
        'exit is pressed', (t) async {
      await pumpDatingShell(
        t,
        initial: DatingPaths.plan('m1'),
        overrides: datingChatOverrides(FakeDatingChat()),
        wrap: (router, child) => QuickExitZone(router: router, child: child),
      );
      final when = find.byKey(const ValueKey('dating_plan_when'));
      await t.ensureVisible(when);
      await t.tap(when);
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      if (picker == 'time') {
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
        expect(find.byType(TimePickerDialog), findsOneWidget);
      }
      for (var i = 0; i < 3; i++) {
        await t.tap(
          find.byKey(const Key('quick_exit_zone')),
          warnIfMissed: false,
        );
        if (i < 2) await t.pump(const Duration(milliseconds: 50));
      }
      await t.pump();
      expect(find.byType(DatePickerDialog, skipOffstage: false), findsNothing);
      expect(find.byType(TimePickerDialog, skipOffstage: false), findsNothing);
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('DECOY'), findsOneWidget);
    });
  }

  // Fix round 1 (M-1): a wipe run while no Dating page is open (quick exit
  // from Me, sign-out from Settings) never leaves the next Dating page
  // blank.
  testWidgets('a wipe with no Dating page open: the next Dating page shows '
      'as before', (t) async {
    final s = await pumpDatingShell(
      t,
      overrides: datingTodayOverrides(FakeDatingToday()),
    );
    expect(DatingPageWatch.open, 0);
    await DeviceWipeRegistry.instance.run(WipeMoment.quickExit);
    expect(DatingSurface.hidden.value, isTrue);
    s.router.go(DatingPaths.today);
    await t.pumpAndSettle();
    expect(find.textContaining('Kofi'), findsWidgets);
    expect(find.byKey(const ValueKey('dating_blank_page')), findsNothing);
  });

  // Fix round 1 (M-3): Me's Dating section under the decoy.
  testWidgets('quick exit from Me: the Dating section shows nothing in the '
      'decoy\'s first frame, and as before when Me is opened again', (t) async {
    final s = await _pumpMe(t, exitZone: true);
    expect(_sectionShown(t), isTrue);
    for (var i = 0; i < 3; i++) {
      await t.tap(
        find.byKey(const Key('quick_exit_zone')),
        warnIfMissed: false,
      );
      if (i < 2) await t.pump(const Duration(milliseconds: 50));
    }
    await t.pump();
    expect(_sectionShown(t), isFalse);
    await t.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('DECOY'), findsOneWidget);
    s.router.go(_me);
    await t.pumpAndSettle();
    expect(_sectionShown(t), isTrue);
  });

  testWidgets('a sign-out that didn\'t finish: the Dating section shows again '
      'once Me is on top again', (t) async {
    final s = await _pumpMe(t);
    unawaited(s.router.push(RouteNames.reflectionJournal));
    await t.pumpAndSettle();
    await DeviceWipeRegistry.instance.run(WipeMoment.signOut);
    await t.pump();
    expect(DatingSurface.hidden.value, isTrue);
    s.router.pop();
    await t.pumpAndSettle();
    expect(_sectionShown(t), isTrue);
  });

  testWidgets('a sign-out that didn\'t finish over a Dating page: back on Me, '
      'the section shows again (the page goes inside a frame)', (t) async {
    final s = await _pumpMe(
      t,
      overrides: datingTodayOverrides(FakeDatingToday()),
    );
    unawaited(s.router.push(DatingPaths.today));
    await t.pumpAndSettle();
    expect(DatingPageWatch.open, 1);
    await DeviceWipeRegistry.instance.run(WipeMoment.signOut);
    await t.pump();
    expect(find.byKey(const ValueKey('dating_blank_page')), findsWidgets);
    s.router.pop();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(DatingPageWatch.open, 0);
    expect(_sectionShown(t), isTrue);
  });

  // Fix round 1 (Task 3 carry): a Dating page left blank while it stays
  // open (a sign-out that didn't finish) shows again once the Dating
  // unlock succeeds (the Safety PIN sheet is Spec 1's, over the blank).
  testWidgets('a Dating page left blank shows again once the Dating unlock '
      'succeeds', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      locked: true,
      pinSet: true,
      overrides: datingTodayOverrides(FakeDatingToday()),
    );
    s.container.read(datingUnlockedProvider.notifier).unlock();
    s.router.go(DatingPaths.today);
    await t.pumpAndSettle();
    expect(find.textContaining('Kofi'), findsWidgets);
    await DeviceWipeRegistry.instance.run(WipeMoment.signOut);
    await t.pump();
    expect(find.byKey(const ValueKey('dating_blank_page')), findsWidgets);
    expect(DatingPageWatch.open, greaterThan(0));
    // The PIN, entered after the wipe's quiet window (round 2, Re-1-M1).
    await t.pump(const Duration(seconds: 3));
    s.container.read(datingUnlockedProvider.notifier).unlock();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('dating_blank_page')), findsNothing);
    expect(find.textContaining('Kofi'), findsWidgets);
  });
}
