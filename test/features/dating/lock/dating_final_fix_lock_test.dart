// Spec 2 W3 final fix (client I-1, I-2, M-14): the Dating lock end to end.
// I-1: when the unlock ends with the lock on, a Dating sheet open over Me
// goes with it (a sheet over another page stays). I-2: turning the lock on
// from inside Dating keeps the person where they are. M-14: a lock setting
// that can't be read still gives Me a way in (the PIN first), so Dating
// settings and Leave are always reachable.
import 'dart:async';

import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/setup/dating_preview_providers.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/me/presentation/widgets/dating_slot.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

final _slotRoute = GoRoute(
  path: '/slot',
  builder:
      (_, __) => Scaffold(
        body: SingleChildScrollView(
          child: DatingSlot(home: snapshotOf(homeJson(path: 'dating'))),
        ),
      ),
);

/// Spec 1's sheet opener (Quizzes, Healing, More ways on Me), with
/// something typed in it.
Future<void> _openSpec1Sheet(BuildContext context) =>
    BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      showButtons: false,
      widget: const Material(child: TextField(key: ValueKey('spec1_field'))),
    );

/// Me with the slot and a Spec 1 sheet of its own (final fix I-1b).
final _meRoute = GoRoute(
  path: '/me',
  builder:
      (context, __) => Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              DatingSlot(home: snapshotOf(homeJson(path: 'dating'))),
              TextButton(
                onPressed: () => _openSpec1Sheet(context),
                child: const Text('Open Quizzes'),
              ),
            ],
          ),
        ),
      ),
);

/// A page that isn't Dating, with a dialog of its own.
final _otherRoute = GoRoute(
  path: '/other',
  builder:
      (context, __) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed:
                () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(content: Text('OTHER')),
                ),
            child: const Text('Open other'),
          ),
        ),
      ),
);

const _switched = DatingHome(
  state: DatingHomeState.paused,
  pauseReason: DatingPauseReason.sameGenderSwitch,
  country: 'GH',
  hasData: true,
);

List<Override> _screens() => [
  datingPreviewGatewayProvider.overrideWithValue(FakeDatingPreviewGateway()),
  datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
  datingPhotosGatewayProvider.overrideWithValue(FakeDatingPhotosGateway()),
  pushAskerProvider.overrideWithValue(FakePushAsker()),
];

Future<void> _putAwayAndBack(WidgetTester t) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    t.binding.handleAppLifecycleStateChanged(state);
    await t.pump();
  }
  await t.pumpAndSettle();
}

void main() {
  group('I-1: a Dating sheet over Me ends with the unlock', () {
    testWidgets('the Why? sheet goes when the app is put away', (t) async {
      final s = await pumpDatingShell(
        t,
        initial: '/slot',
        locked: true,
        home: FakeDatingHomeGateway(home: _switched),
        extraRoutes: [_slotRoute],
      );
      // No PIN on this phone: the slot's confirm lets it through.
      await tapInReach(t, find.text('Dating is locked'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Why?'));
      await t.pumpAndSettle();
      expect(find.textContaining('legal risk'), findsOneWidget);
      await _putAwayAndBack(t);
      expect(s.container.read(datingUnlockedProvider), isFalse);
      expect(find.textContaining('legal risk'), findsNothing);
      expect(find.text('Dating is locked'), findsOneWidget);
    });

    testWidgets('another account: the sheet goes too (D8)', (t) async {
      final s = await pumpDatingShell(
        t,
        initial: '/slot',
        locked: true,
        home: FakeDatingHomeGateway(home: _switched),
        extraRoutes: [_slotRoute],
      );
      await tapInReach(t, find.text('Dating is locked'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Why?'));
      await t.pumpAndSettle();
      expect(find.textContaining('legal risk'), findsOneWidget);
      s.container.read(datingTestAccount.notifier).state = 'kofi';
      await t.pump();
      await t.pumpAndSettle();
      expect(find.textContaining('legal risk'), findsNothing);
    });

    testWidgets('lock off: nothing over Me is closed', (t) async {
      await pumpDatingShell(
        t,
        initial: '/slot',
        home: FakeDatingHomeGateway(home: _switched),
        extraRoutes: [_slotRoute],
      );
      await tapInReach(t, find.text('Why?'));
      await t.pumpAndSettle();
      await _putAwayAndBack(t);
      expect(find.textContaining('legal risk'), findsOneWidget);
    });

    testWidgets('a dialog over another page (not Me) stays', (t) async {
      final s = await pumpDatingShell(
        t,
        initial: '/slot',
        locked: true,
        home: FakeDatingHomeGateway(home: _switched),
        extraRoutes: [_slotRoute, _otherRoute],
      );
      await tapInReach(t, find.text('Dating is locked'));
      await t.pumpAndSettle();
      s.router.push('/other');
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Open other'));
      await t.pumpAndSettle();
      expect(find.text('OTHER'), findsOneWidget);
      await _putAwayAndBack(t);
      expect(s.container.read(datingUnlockedProvider), isFalse);
      expect(find.text('OTHER'), findsOneWidget);
    });
  });

  // Final fix I-1b: only Dating sheets go; Spec 1's sheets on Me stay.
  group('I-1b: only Dating sheets close', () {
    Future<DatingShell> me(WidgetTester t) async {
      final s = await pumpDatingShell(
        t,
        initial: '/me',
        locked: true,
        home: FakeDatingHomeGateway(home: _switched),
        extraRoutes: [_meRoute],
      );
      await tapInReach(t, find.text('Dating is locked'));
      await t.pumpAndSettle();
      return s;
    }

    testWidgets('a Spec 1 sheet over Me stays, with what was typed', (t) async {
      final s = await me(t);
      await tapInReach(t, find.text('Open Quizzes'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('spec1_field')), 'my answer');
      await _putAwayAndBack(t);
      expect(s.container.read(datingUnlockedProvider), isFalse);
      expect(find.byKey(const ValueKey('spec1_field')), findsOneWidget);
      expect(find.text('my answer'), findsOneWidget);
    });

    testWidgets('the Why? sheet still goes', (t) async {
      await me(t);
      await tapInReach(t, find.text('Why?'));
      await t.pumpAndSettle();
      await _putAwayAndBack(t);
      expect(
        find.textContaining('legal risk', skipOffstage: false),
        findsNothing,
      );
      expect(find.text('Dating is locked'), findsOneWidget);
    });

    testWidgets('a Spec 1 sheet over the Why? sheet: the Why? sheet goes, '
        'the Spec 1 sheet and its text stay', (t) async {
      await me(t);
      await tapInReach(t, find.text('Why?'));
      await t.pumpAndSettle();
      // Opened from inside the Dating sheet, so it sits above it.
      unawaited(_openSpec1Sheet(t.element(find.textContaining('legal risk'))));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('spec1_field')), 'my answer');
      expect(
        find.textContaining('legal risk', skipOffstage: false),
        findsOneWidget,
      );
      await _putAwayAndBack(t);
      // Nothing of the Dating sheet is left anywhere in the stack.
      expect(
        find.textContaining('legal risk', skipOffstage: false),
        findsNothing,
      );
      expect(find.text('my answer'), findsOneWidget);
      // Closing the Spec 1 sheet shows Me, locked: no Dating text under it.
      Navigator.of(t.element(find.byKey(const ValueKey('spec1_field')))).pop();
      await t.pumpAndSettle();
      expect(
        find.textContaining('legal risk', skipOffstage: false),
        findsNothing,
      );
      expect(find.text('Dating is locked'), findsOneWidget);
    });
  });

  group('I-2: the lock turned on from inside Dating', () {
    testWidgets('D13 on its route: still D13, Yes kept, no PIN screen', (
      t,
    ) async {
      final s = await pumpDatingShell(t, pinSet: true, overrides: _screens());
      s.router.push(DatingPaths.step('preview'));
      await t.pumpAndSettle();
      s.router.push(DatingPaths.step('ready'));
      await t.pumpAndSettle();
      expect(find.text("You're all set"), findsOneWidget);
      await tapInReach(t, find.text('Yes'));
      await t.pumpAndSettle();
      await tapInReach(
        t,
        find.widgetWithText(SwitchListTile, 'Lock Dating with your PIN'),
      );
      await t.pumpAndSettle();
      expect(s.lock.on, isTrue);
      expect(s.container.read(datingUnlockedProvider), isTrue);
      expect(find.text('Enter your Safety PIN'), findsNothing);
      expect(find.text('Enter my PIN'), findsNothing);
      expect(find.text("You're all set"), findsOneWidget);
      // The Yes is kept: the every-open switch is still offered.
      expect(
        find.widgetWithText(
          SwitchListTile,
          'Ask for my PIN every time Attune opens',
        ),
        findsOneWidget,
      );
      // And the step stack: Back goes to D12, not Me.
      await tapInReach(t, find.byTooltip('Back'));
      await t.pumpAndSettle();
      expect(find.text('This is what others see'), findsOneWidget);
    });

    testWidgets('Dating settings: still Dating settings, no PIN screen', (
      t,
    ) async {
      final s = await pumpDatingShell(
        t,
        pinSet: true,
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active, hasData: true),
        ),
        overrides: _screens(),
      );
      s.router.push(DatingPaths.settings);
      await t.pumpAndSettle();
      expect(find.text('Dating settings'), findsOneWidget);
      await tapInReach(
        t,
        find.widgetWithText(SwitchListTile, 'Dating lock').first,
      );
      await t.pumpAndSettle();
      expect(s.lock.on, isTrue);
      expect(find.text('Enter your Safety PIN'), findsNothing);
      expect(find.text('Enter my PIN'), findsNothing);
      expect(find.text('Dating settings'), findsOneWidget);
    });

    testWidgets('the unlock it gives still ends when the app is put away', (
      t,
    ) async {
      final s = await pumpDatingShell(t, pinSet: true, overrides: _screens());
      s.router.push(DatingPaths.step('ready'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Yes'));
      await t.pumpAndSettle();
      await tapInReach(
        t,
        find.widgetWithText(SwitchListTile, 'Lock Dating with your PIN'),
      );
      await t.pumpAndSettle();
      await _putAwayAndBack(t);
      expect(find.text("You're all set"), findsNothing);
      expect(find.text('Enter your Safety PIN'), findsOneWidget);
    });
  });

  group('M-14: an unreadable lock setting', () {
    testWidgets('Me shows the locked row; the PIN, then settings and Leave', (
      t,
    ) async {
      final s = await pumpDatingShell(
        t,
        initial: '/slot',
        lockUnreadable: true,
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active, hasData: true),
        ),
        extraRoutes: [_slotRoute],
        overrides: _screens(),
      );
      expect(s.container.read(datingLockProvider).hasError, isTrue);
      expect(find.text('Dating is locked'), findsOneWidget);
      expect(
        find.text('Dating is on. Your introductions will show here.'),
        findsNothing,
      );
      await tapInReach(t, find.text('Dating is locked'));
      await t.pumpAndSettle();
      expect(s.container.read(datingUnlockedProvider), isTrue);
      await tapInReach(t, find.text('Dating settings'));
      await t.pumpAndSettle();
      expect(find.text('Enter my PIN'), findsNothing);
      await t.scrollUntilVisible(
        find.text('Leave Dating and delete my data'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Leave Dating and delete my data'), findsOneWidget);
    });

    testWidgets('with a PIN set, the locked row asks for it first', (t) async {
      await pumpDatingShell(
        t,
        initial: '/slot',
        lockUnreadable: true,
        pinSet: true,
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active, hasData: true),
        ),
        extraRoutes: [_slotRoute],
      );
      await tapInReach(t, find.text('Dating is locked'));
      await t.pumpAndSettle();
      expect(find.text('Enter your Safety PIN'), findsOneWidget);
    });
  });
}
