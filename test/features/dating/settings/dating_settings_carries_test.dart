// Spec 2 W3c Task 12, the controller's carries on Dating settings and
// Leave: A every answer settles its key (Pause, Resume, Pause are three
// requests; busy and failed keep the key), B Resume by the section's rule,
// C Leave and Pause are never gated offline or by an unreadable home, D the
// clear in every state with data, F the rows open their step with
// ?from=settings, G D8, the dark theme and large text.
import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart'
    show GentleWaitSave;
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/settings/dating_leave_screen.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/ready_step.dart'
    show datingDropTimeLabel, datingDropTimes;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

const _pausedLine =
    'Dating is paused. Nobody new sees you, and your conversations stay open.';
const _offline = "You're offline. Dating needs a connection.";
const _busy =
    'This is taking a little longer than usual. Try again in a moment.';
const _generic = 'Something went wrong. Try again.';
const _leave = 'Leave Dating and delete my data';
const _clear = 'Clear my answers to the three questions';

typedef _Settings =
    ({
      FakeDatingHomeGateway home,
      FakeDatingLifecycleGateway life,
      FakeDatingSetupGateway setup,
      FakeDatingPhotosGateway photos,
      FakeWait wait,
    });

Future<_Settings> _settings(
  WidgetTester t, {
  DatingHome home = const DatingHome(state: DatingHomeState.active),
  bool online = true,
  double textScale = 1.0,
  Size size = const Size(390, 844),
  ThemeData? theme,
  DatingLifecycleResult result = const DatingLifecycleResult.done('paused'),
  Object? homeError,
}) async {
  await t.pumpWidget(const SizedBox());
  final homeGateway = FakeDatingHomeGateway(home: home)..readError = homeError;
  final life = FakeDatingLifecycleGateway()..result = result;
  final setup = FakeDatingSetupGateway(
    profile: const DatingMyProfile(
      dropTime: '19:00:00',
      minAge: 25,
      maxAge: 35,
    ),
  );
  final photos = FakeDatingPhotosGateway(
    afterMutualFrom: DateTime.utc(2026, 1, 1),
  );
  final wait = FakeWait();
  await pumpFlowScreen(
    t,
    () =>
        theme == null
            ? const DatingSettingsScreen()
            : Theme(data: theme, child: const DatingSettingsScreen()),
    textScale: textScale,
    size: size,
    overrides: [
      ...datingShellOverrides(
        home: homeGateway,
        life: life,
        wait: wait,
        online: online,
      ),
      datingSetupGatewayProvider.overrideWithValue(setup),
      datingPhotosGatewayProvider.overrideWithValue(photos),
      pushAskerProvider.overrideWithValue(FakePushAsker(granted: true)),
    ],
  );
  await t.pumpAndSettle();
  return (
    home: homeGateway,
    life: life,
    setup: setup,
    photos: photos,
    wait: wait,
  );
}

Future<FakeDatingLifecycleGateway> _leaveScreen(
  WidgetTester t, {
  DatingLifecycleResult result = const DatingLifecycleResult.done('exited'),
  bool online = true,
  double textScale = 1.0,
  ThemeData? theme,
}) async {
  await t.pumpWidget(const SizedBox());
  final life = FakeDatingLifecycleGateway()..result = result;
  await pumpFlowScreen(
    t,
    () =>
        theme == null
            ? const DatingLeaveScreen()
            : Theme(data: theme, child: const DatingLeaveScreen()),
    textScale: textScale,
    // Fix 1 (I-1): Pause instead is offered on an active home only.
    overrides: datingShellOverrides(
      home: FakeDatingHomeGateway(
        home: const DatingHome(state: DatingHomeState.active),
      ),
      life: life,
      online: online,
    ),
  );
  await t.pumpAndSettle();
  return life;
}

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(MaterialApp)));

Future<void> _tap(WidgetTester t, String text) async {
  await tapInReach(t, find.text(text));
  await t.pumpAndSettle();
}

void main() {
  group('A: keys settle', () {
    testWidgets('Pause, Resume, Pause on one screen: three different keys', (
      t,
    ) async {
      final s = await _settings(t);
      s.home.home = const DatingHome(state: DatingHomeState.paused);
      await _tap(t, 'Pause Dating');
      expect(find.text(_pausedLine), findsOneWidget);
      s.life.result = const DatingLifecycleResult.done('active');
      s.home.home = const DatingHome(state: DatingHomeState.active);
      await _tap(t, 'Resume Dating');
      expect(find.text(_pausedLine), findsNothing);
      s.life.result = const DatingLifecycleResult.done('paused');
      s.home.home = const DatingHome(state: DatingHomeState.paused);
      await _tap(t, 'Pause Dating');
      expect(s.life.calls, ['pause', 'resume', 'pause']);
      expect(s.life.keys.toSet(), hasLength(3));
    });

    testWidgets('busy and failed keep the key; the answer after a final '
        'one is a new request', (t) async {
      final s = await _settings(
        t,
        result: const DatingLifecycleResult.refused(DatingLifecycleError.busy),
      );
      await _tap(t, 'Pause Dating');
      expect(find.text(_busy), findsOneWidget);
      s.life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.failed,
      );
      await _tap(t, 'Pause Dating');
      expect(find.text(_generic), findsOneWidget);
      s.life.result = const DatingLifecycleResult.done('paused');
      await _tap(t, 'Pause Dating');
      // A named refusal is final too.
      s.life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.rateLimited,
      );
      await _tap(t, 'Pause Dating');
      await _tap(t, 'Pause Dating');
      final k = s.life.keys;
      expect(k, hasLength(5));
      expect({k[0], k[1], k[2]}, hasLength(1), reason: 'busy, failed, ok');
      expect(k[3], isNot(k[2]), reason: 'after ok: a new request');
      expect(k[4], isNot(k[3]), reason: 'after a named refusal: a new one');
    });

    testWidgets('Leave: busy keeps the key, a named refusal does not', (
      t,
    ) async {
      final life = await _leaveScreen(
        t,
        result: const DatingLifecycleResult.refused(DatingLifecycleError.busy),
      );
      await _tap(t, 'Leave and delete');
      await _tap(t, 'Leave and delete');
      life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.rateLimited,
      );
      await _tap(t, 'Leave and delete');
      await _tap(t, 'Leave and delete');
      expect(life.calls, ['exit', 'exit', 'exit', 'exit']);
      expect(life.keys[1], life.keys[0]);
      expect(life.keys[2], life.keys[1]);
      expect(life.keys[3], isNot(life.keys[2]));
    });

    testWidgets('a settings save settles: busy keeps the key, ok drops it', (
      t,
    ) async {
      final s = await _settings(t);
      s.setup.answer = DatingWrite.busy;
      final saver = find.widgetWithText(SwitchListTile, 'Data saver');
      await tapInReach(t, saver);
      await t.pumpAndSettle();
      expect(find.text(_busy), findsOneWidget, reason: 'never silent');
      await tapInReach(t, saver);
      await t.pumpAndSettle();
      s.setup.answer = const DatingWrite(ok: true);
      await tapInReach(t, saver);
      await t.pumpAndSettle();
      expect(find.text(_busy), findsNothing);
      String key(int i) =>
          s.setup.calls
                  .where((c) => c.$1 == 'saveSettings')
                  .elementAt(i)
                  .$2['key']
              as String;
      expect(key(1), key(0));
      expect(key(2), key(1));
      // The same answer again after a final one: a new request.
      s.setup.answer = const DatingWrite(ok: false, reason: 'invalid');
      await tapInReach(t, saver);
      await t.pumpAndSettle();
      expect(key(3), isNot(key(2)));
      expect(find.text(_generic), findsOneWidget);
    });
  });

  group('B: Resume by the section\'s rule', () {
    // Shown for the person's own pause, gates, a path change and an
    // unknown reason; a relationship pause only once can_resume is true;
    // never for travel, a parked number or a same-gender switch; never
    // while can_resume is false.
    bool expected(DatingPauseReason r, bool? canResume) {
      if (canResume == false) return false;
      return switch (r) {
        DatingPauseReason.user ||
        DatingPauseReason.gates ||
        DatingPauseReason.pathChange ||
        DatingPauseReason.unknown => true,
        DatingPauseReason.relationship => canResume == true,
        _ => false,
      };
    }

    for (final reason in DatingPauseReason.values) {
      for (final canResume in const [null, true, false]) {
        final shown = expected(reason, canResume);
        testWidgets('${reason.name}, can_resume $canResume: '
            '${shown ? 'Resume' : 'no Resume'}', (t) async {
          final home = DatingHome(
            state: DatingHomeState.paused,
            pauseReason: reason,
            canResume: canResume,
          );
          expect(home.resumeOffered, shown);
          await _settings(t, home: home);
          expect(
            find.text('Resume Dating'),
            shown ? findsOneWidget : findsNothing,
          );
          expect(find.text('Pause Dating'), findsNothing);
          expect(find.text(_leave), findsOneWidget);
        });
      }
    }

    test('only a paused home offers Resume', () {
      for (final state in DatingHomeState.values) {
        expect(
          DatingHome(state: state, canResume: true).resumeOffered,
          state == DatingHomeState.paused,
          reason: state.wire,
        );
      }
    });

    testWidgets('Resume is gated offline; Pause and Leave are not', (t) async {
      await _settings(
        t,
        home: const DatingHome(state: DatingHomeState.paused),
        online: false,
      );
      expect(
        _tappable(t, 'Resume Dating'),
        isFalse,
        reason: 'resuming needs the connection',
      );
      expect(_tappable(t, _leave), isTrue);
      await _settings(t, online: false);
      expect(_tappable(t, 'Pause Dating'), isTrue);
    });
  });

  group('C: Leave', () {
    testWidgets('never gated offline: the row opens Leave', (t) async {
      await _settings(t, online: false);
      await _tap(t, _leave);
      expect(find.text('at /dating/leave'), findsOneWidget);
    });

    testWidgets('an unreadable home (busy or offline) still offers Leave and '
        'Clear', (t) async {
      for (final error in <Object>[const DatingBusy(), StateError('net')]) {
        await _settings(t, homeError: error);
        expect(find.text(_leave), findsOneWidget, reason: '$error');
        expect(find.text(_clear), findsOneWidget, reason: '$error');
      }
    });

    testWidgets('not started with saved answers can leave; with nothing it '
        'can only clear', (t) async {
      await _settings(
        t,
        home: const DatingHome(
          state: DatingHomeState.notStarted,
          hasData: true,
        ),
      );
      expect(find.text(_leave), findsOneWidget);
      await _settings(
        t,
        home: const DatingHome(state: DatingHomeState.notStarted),
      );
      expect(find.text(_leave), findsNothing);
      expect(find.text(_clear), findsOneWidget);
    });

    testWidgets('a failed exit online is our own words; the button stays', (
      t,
    ) async {
      final life = await _leaveScreen(
        t,
        result: const DatingLifecycleResult.refused(
          DatingLifecycleError.failed,
        ),
      );
      await _tap(t, 'Leave and delete');
      expect(find.text(_generic), findsOneWidget);
      expect(find.text(_offline), findsNothing);
      life.result = const DatingLifecycleResult.done('exited');
      await _tap(t, 'Leave and delete');
      expect(
        find.text("You've left Dating. You can set it up again any time."),
        findsOneWidget,
      );
      expect(life.keys[1], life.keys[0], reason: 'the retry is the same exit');
    });

    testWidgets('offline: said once before the tap (fix 1, M-2), and a '
        'pause that can\'t be sent keeps it calm', (t) async {
      final life = await _leaveScreen(
        t,
        online: false,
        result: const DatingLifecycleResult.refused(
          DatingLifecycleError.failed,
        ),
      );
      expect(find.text(_offline), findsOneWidget);
      await _tap(t, 'Pause instead');
      expect(life.calls, ['pause']);
      expect(find.text(_offline), findsOneWidget);
      expect(find.byType(FlowErrorLine), findsNothing);
      expect(find.text('Pause instead'), findsOneWidget);
    });

    testWidgets('settings: an offline pause that fails says so calmly', (
      t,
    ) async {
      final s = await _settings(
        t,
        online: false,
        result: const DatingLifecycleResult.refused(
          DatingLifecycleError.failed,
        ),
      );
      await _tap(t, 'Pause Dating');
      expect(s.life.calls, ['pause']);
      // Fix 1 (M-2): the screen's own offline line, once.
      expect(find.text(_offline), findsOneWidget);
      expect(find.text(_generic), findsNothing);
    });
  });

  group('D: Clear my answers', () {
    for (final state in DatingHomeState.values) {
      testWidgets('${state.wire} with data: the clear sends the empty '
          'reflection; busy is calm', (t) async {
        final s = await _settings(
          t,
          home: DatingHome(state: state, hasData: true),
        );
        s.wait.result = GentleWaitSave.busy;
        await _tap(t, _clear);
        expect(s.wait.clears, 1);
        expect(
          find.text(
            'This is taking a little longer than usual. Try clearing again '
            'in a moment.',
          ),
          findsOneWidget,
        );
      });
    }
  });

  group('F: rows open their step with from=settings', () {
    for (final (row, step) in [
      ("Who I'd like to meet", 'meet'),
      ('Ages', 'meet'),
      ('How far', 'where'),
    ]) {
      testWidgets('$row opens $step', (t) async {
        await _settings(t);
        await _tap(t, row);
        expect(
          find.text('at /dating/setup/$step?from=settings'),
          findsOneWidget,
        );
      });
    }
  });

  group('G: shared code', () {
    testWidgets('D8: another account sees nothing of the last one, also '
        'while its reads are held', (t) async {
      final s = await _settings(
        t,
        result: const DatingLifecycleResult.refused(
          DatingLifecycleError.rateLimited,
        ),
      );
      await _tap(t, 'Pause Dating');
      expect(find.byType(FlowErrorLine), findsOneWidget);
      expect(find.text('25 to 35'), findsOneWidget);
      s.home.hold = Completer<DatingHome>();
      _container(t).read(datingTestAccount.notifier).state = 'kofi';
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
        expect(find.byType(FlowErrorLine), findsNothing);
        expect(find.text('25 to 35'), findsNothing);
        expect(find.text('Introduction time'), findsNothing);
        expect(find.text(_leave), findsNothing);
      }
      s.home.hold!.complete(
        const DatingHome(state: DatingHomeState.notStarted),
      );
      await t.pumpAndSettle();
      expect(find.text(_leave), findsNothing);
      expect(find.text(_clear), findsOneWidget);
    });

    testWidgets('every row is a 48 dp target, Clear, Pause and Leave '
        'included', (t) async {
      // A phone, and a tablet where every title fits on one line.
      for (final size in const [Size(390, 844), Size(820, 1180)]) {
        await _settings(t, size: size);
        for (final text in [
          'Introduction time',
          "Who I'd like to meet",
          'How far',
          _clear,
          'Pause Dating',
          _leave,
        ]) {
          final ink = find.ancestor(
            of: find.text(text),
            matching: find.byType(InkWell),
          );
          expect(
            t.getSize(ink.first).height,
            greaterThanOrEqualTo(48),
            reason: '$text at $size',
          );
        }
      }
    });

    testWidgets('D8: Leave starts over for another account', (t) async {
      await _leaveScreen(t);
      await tapInReach(t, find.byType(CheckboxListTile));
      await t.pump();
      await _tap(t, 'Leave and delete');
      expect(find.text('Leave and delete'), findsNothing);
      _container(t).read(datingTestAccount.notifier).state = 'kofi';
      await t.pumpAndSettle();
      expect(find.textContaining("You've left Dating"), findsNothing);
      expect(find.text('Leave and delete'), findsOneWidget);
      expect(
        t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
    });

    testWidgets('settings and Leave in the dark theme: the theme\'s colours, '
        'contrast holds, the theme\'s own error red', (t) async {
      final semantics = t.ensureSemantics();
      final dark = AppTheme.darkTheme;
      for (final (theme, red) in [
        (dark, dark.colorScheme.error),
        (AppTheme.lightTheme, const Color(0xFFC62828)),
      ]) {
        final icon = find.descendant(
          of: find.byType(FlowErrorLine),
          matching: find.byType(Icon),
        );
        await _settings(
          t,
          theme: theme,
          result: const DatingLifecycleResult.refused(
            DatingLifecycleError.rateLimited,
          ),
        );
        expect(
          Theme.of(t.element(find.byType(DatingSettingsScreen))).brightness,
          theme.brightness,
        );
        // The guidelines at rest (a scrolled list clips its top row), then
        // the refusal's contrast where the tap left it.
        await expectFlowGuidelines(t);
        await _tap(t, 'Pause Dating');
        expect(t.widget<Icon>(icon.first).color, red);
        await expectLater(t, meetsGuideline(textContrastGuideline));
        await _leaveScreen(
          t,
          theme: theme,
          result: const DatingLifecycleResult.refused(
            DatingLifecycleError.rateLimited,
          ),
        );
        expect(
          Theme.of(t.element(find.byType(DatingLeaveScreen))).brightness,
          theme.brightness,
        );
        await expectFlowGuidelines(t);
        await _tap(t, 'Leave and delete');
        expect(t.widget<Icon>(icon.first).color, red);
        await expectLater(t, meetsGuideline(textContrastGuideline));
      }
      expect(dark.colorScheme.error, const Color(0xFFEF5350));
      semantics.dispose();
    });

    testWidgets('2.0: the time sheet scales and every time is in reach; '
        'Leave\'s two buttons are in reach', (t) async {
      final s = await _settings(t, textScale: 2.0);
      await _tap(t, 'Introduction time');
      final title = find.text('Pick a time when you have a few quiet minutes.');
      expect(MediaQuery.textScalerOf(t.element(title)).scale(10), 20);
      // The last time, scrolled to in the sheet's own list.
      final last = find.text(datingDropTimeLabel(datingDropTimes.last));
      await t.scrollUntilVisible(
        last,
        200,
        scrollable:
            find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      await tapInReach(t, last);
      await t.pumpAndSettle();
      expect(s.setup.lastWrite.$2['values'], {
        'drop_time': datingDropTimes.last,
      });
      final life = await _leaveScreen(
        t,
        textScale: 2.0,
        result: const DatingLifecycleResult.done('paused'),
      );
      await _tap(t, 'Pause instead');
      expect(life.calls, ['pause']);
      await _leaveScreen(t, textScale: 2.0);
      await _tap(t, 'Leave and delete');
      expect(find.text('Done'), findsOneWidget);
    });
  });
}

/// An InfoRowWidget row is wrapped in an InkWell only while it has a tap.
bool _tappable(WidgetTester t, String text) {
  final ink = find.ancestor(
    of: find.text(text),
    matching: find.byType(InkWell),
  );
  return ink.evaluate().isNotEmpty &&
      t.widget<InkWell>(ink.first).onTap != null;
}
