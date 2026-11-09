// Spec 2 W3c Task 12, fix round 1: I-1 "Pause instead" only where a pause
// can happen, and the paused line only for a paused answer; I-2 a
// restricted, held or age-review home (or an unknown one) never reads "set
// it up again"; the section's error card reaches Dating settings (M-3,
// re-graded); one offline line on each screen (M-2); the bottoms of both
// screens in goldens (M-4); the toggles line up with the rows (M-5).
import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/settings/dating_leave_screen.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
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
const _leftDone = "You've left Dating. You can set it up again any time.";
const _leftHeld = "You've left Dating.";

Future<FakeDatingLifecycleGateway> _leave(
  WidgetTester t, {
  DatingHome home = const DatingHome(state: DatingHomeState.active),
  Object? homeError,
  DatingLifecycleResult result = const DatingLifecycleResult.done('exited'),
  bool online = true,
}) async {
  await t.pumpWidget(const SizedBox());
  final life = FakeDatingLifecycleGateway()..result = result;
  await pumpFlowScreen(
    t,
    () => const DatingLeaveScreen(),
    overrides: datingShellOverrides(
      home: FakeDatingHomeGateway(home: home)..readError = homeError,
      life: life,
      online: online,
    ),
  );
  await t.pumpAndSettle();
  return life;
}

List<Override> _settingsOverrides({
  DatingHome home = const DatingHome(state: DatingHomeState.active),
  FakeDatingLifecycleGateway? life,
  bool online = true,
}) => [
  ...datingShellOverrides(
    home: FakeDatingHomeGateway(home: home),
    life: life,
    online: online,
  ),
  datingSetupGatewayProvider.overrideWithValue(
    FakeDatingSetupGateway(
      profile: const DatingMyProfile(
        dropTime: '19:00:00',
        minAge: 25,
        maxAge: 35,
      ),
    ),
  ),
  datingPhotosGatewayProvider.overrideWithValue(
    FakeDatingPhotosGateway(afterMutualFrom: DateTime.utc(2026, 1, 1)),
  ),
  pushAskerProvider.overrideWithValue(FakePushAsker(granted: true)),
];

Future<void> _tap(WidgetTester t, String text) async {
  await tapInReach(t, find.text(text));
  await t.pumpAndSettle();
}

Future<void> _toBottom(WidgetTester t) async {
  await t.drag(
    find.byType(SingleChildScrollView).first,
    const Offset(0, -4000),
  );
  await t.pumpAndSettle();
}

void main() {
  group('I-1: Pause instead', () {
    for (final state in DatingHomeState.values) {
      final offered =
          state == DatingHomeState.active || state == DatingHomeState.coolOff;
      testWidgets(
        '${state.wire}: ${offered ? '' : 'no '}Pause instead (R-41)',
        (t) async {
          await _leave(t, home: DatingHome(state: state, hasData: true));
          expect(
            find.text('Pause instead'),
            offered ? findsOneWidget : findsNothing,
          );
          expect(find.text('Leave and delete'), findsOneWidget);
        },
      );
    }

    testWidgets('an unreadable home offers no Pause instead, still Leave', (
      t,
    ) async {
      await _leave(t, homeError: const DatingBusy());
      expect(find.text('Pause instead'), findsNothing);
      expect(find.text('Leave and delete'), findsOneWidget);
    });

    for (final state in const ['suspended', 'exited', null]) {
      testWidgets('a pause that answers $state never says "paused"', (t) async {
        final life = await _leave(t, result: DatingLifecycleResult.done(state));
        await _tap(t, 'Pause instead');
        expect(life.calls, ['pause']);
        expect(find.text(_pausedLine), findsNothing);
        expect(find.text('Leave and delete'), findsOneWidget);
      });
    }

    testWidgets('a pause that answers paused says so', (t) async {
      await _leave(t, result: const DatingLifecycleResult.done('paused'));
      await _tap(t, 'Pause instead');
      expect(find.text(_pausedLine), findsOneWidget);
    });
  });

  group('I-2: the Done copy for a restricted account', () {
    for (final state in const [
      DatingHomeState.restricted,
      DatingHomeState.hold,
      DatingHomeState.ageReview,
    ]) {
      testWidgets('home ${state.wire}, exit answers exited: '
          '"You\'ve left Dating." alone', (t) async {
        await _leave(t, home: DatingHome(state: state, hasData: true));
        await _tap(t, 'Leave and delete');
        expect(find.text(_leftHeld), findsOneWidget);
        expect(find.textContaining('set it up again'), findsNothing);
      });
    }

    testWidgets('an unread home: the safe copy', (t) async {
      await _leave(t, homeError: StateError('net'));
      await _tap(t, 'Leave and delete');
      expect(find.text(_leftHeld), findsOneWidget);
      expect(find.textContaining('set it up again'), findsNothing);
    });

    testWidgets('an active home that leaves may set it up again', (t) async {
      await _leave(t);
      await _tap(t, 'Leave and delete');
      expect(find.text(_leftDone), findsOneWidget);
    });
  });

  testWidgets('M-3: the section\'s error card links to Dating settings', (
    t,
  ) async {
    await t.pumpWidget(const SizedBox());
    final home = FakeDatingHomeGateway()..readError = const DatingBusy();
    await pumpFlowScreen(
      t,
      () => const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: DatingSection(),
        ),
      ),
      overrides: datingShellOverrides(home: home),
    );
    await t.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    await _tap(t, 'Dating settings');
    expect(find.text('at /dating/settings'), findsOneWidget);
  });

  group('M-2: one offline line on each screen', () {
    testWidgets('Leave says it before the tap, keeps the buttons, and never '
        'repeats it', (t) async {
      final life = await _leave(
        t,
        online: false,
        result: const DatingLifecycleResult.refused(
          DatingLifecycleError.failed,
        ),
      );
      expect(find.text(_offline), findsOneWidget);
      await _tap(t, 'Leave and delete');
      expect(life.calls, ['exit']);
      expect(find.text(_offline), findsOneWidget);
      expect(find.text('Something went wrong. Try again.'), findsNothing);
      expect(find.text('Leave and delete'), findsOneWidget);
    });

    testWidgets('settings: a failed offline pause adds no second line', (
      t,
    ) async {
      final life =
          FakeDatingLifecycleGateway()
            ..result = const DatingLifecycleResult.refused(
              DatingLifecycleError.failed,
            );
      await t.pumpWidget(const SizedBox());
      await pumpFlowScreen(
        t,
        () => const DatingSettingsScreen(),
        overrides: _settingsOverrides(life: life, online: false),
      );
      await t.pumpAndSettle();
      await _tap(t, 'Pause Dating');
      expect(life.calls, ['pause']);
      expect(find.text(_offline), findsOneWidget);
      expect(find.text('Something went wrong. Try again.'), findsNothing);
    });
  });

  testWidgets('I-3: the manual quotes both push lines and every kept item', (
    t,
  ) async {
    late BuildContext context;
    await t.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    final docs = DatingModeDocs();
    String content(String id) =>
        docs
            .getSections(context)
            .expand((s) => s.contents)
            .firstWhere((c) => c.id == id)
            .content;
    final push = content('dating_notifications');
    // The server's own lines (private.dating_queue_me_update).
    expect(push, contains('"You have something new in Attune."'));
    expect(push, contains('"Something you asked about is ready in Attune."'));
    expect(push, isNot(contains('only ever say')));
    final faq =
        docs
            .getFAQs(context)
            .firstWhere((f) => f.id == 'faq_dating_leave')
            .answer;
    for (final text in [content('dating_leave'), faq]) {
      expect(
        text,
        contains(
          "Only if your account is restricted or you've blocked someone, a "
          'code made from your phone number, never the number itself, is '
          'kept for safety for up to 2 years.',
        ),
      );
      expect(text, contains('"Never introduce me" list is kept only if you'));
      expect(text, contains("when you agreed to Dating's terms"));
    }
  });

  testWidgets('M-5: every switch has its icon, in line with the rows', (
    t,
  ) async {
    await t.pumpWidget(const SizedBox());
    await pumpFlowScreen(
      t,
      () => const DatingSettingsScreen(),
      overrides: _settingsOverrides(),
    );
    await t.pumpAndSettle();
    for (final tile in t.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    )) {
      expect(tile.secondary, isNotNull, reason: '${tile.title}');
    }
    double textX(String s) => t.getTopLeft(find.text(s).first).dx;
    expect(textX('Data saver'), closeTo(textX('How far'), 4));
  });

  testWidgets('M-4: goldens of the bottom of settings and of Leave\'s '
      'actions', (t) async {
    await expectFlowGoldens(
      t,
      'dating_settings_bottom',
      () => const DatingSettingsScreen(),
      overrides: _settingsOverrides(),
      before: _toBottom,
    );
    // A fresh scope: the two screens take different overrides.
    await t.pumpWidget(const SizedBox());
    await expectFlowGoldens(
      t,
      'dating_leave_actions',
      () => const DatingLeaveScreen(),
      overrides: datingShellOverrides(
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active),
        ),
      ),
      before: _toBottom,
    );
  });
}
