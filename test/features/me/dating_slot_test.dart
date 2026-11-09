// Spec 1 §3.9 slot, Spec 2 W3a body: the Dating lock's one row, then
// DatingSection; the unlock is shared with the Dating routes and ends when
// the app is put away.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/me/presentation/screens/me_home_screen.dart';
import 'package:attune/features/me/presentation/me_providers.dart';
import 'package:attune/features/me/data/journal_reminder_service.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/fake_reminder_rpc.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';
import '../../helpers/tap_in_reach.dart';
import '../dating/support/dating_fakes.dart';
import '../dating/support/dating_shell.dart';

List<Override> _overrides({
  bool locked = false,
  // Fix round 1 (Minor 7): J1's card under the slot, as Spec 1 had it.
  ({bool? hasNote, bool? hasQuiz}) first = (hasNote: true, hasQuiz: true),
  DatingHome home = const DatingHome(state: DatingHomeState.notStarted),
}) {
  final json = homeJson(path: 'dating', datingEnabled: true);
  return [
    ...datingHomeOnlyOverrides(
      home: FakeDatingHomeGateway(home: home),
      account: 'u-slot',
    ),
    datingLockStoreProvider.overrideWithValue(FakeLock(locked)),
    homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-slot'))),
    homeStateServiceProvider.overrideWithValue(
      HomeStateService(FakeHomeStateGateway(state: json)),
    ),
    relationshipLifecycleProvider.overrideWith((ref) async => null),
    firstActionInputsProvider.overrideWithValue(first),
    journalReminderRpcProvider.overrideWithValue(FakeReminderRpc().call),
  ];
}

Future<void> _pump(
  WidgetTester t, {
  bool locked = false,
  DatingHome? home,
  ({bool? hasNote, bool? hasQuiz}) first = (hasNote: true, hasQuiz: true),
}) async {
  await t.pumpWidget(const SizedBox());
  FlutterSecureStorage.setMockInitialValues({});
  await pumpFlowScreen(
    t,
    () => MeHomeScreen(
      home: snapshotOf(homeJson(path: 'dating', datingEnabled: true)),
    ),
    overrides: _overrides(
      locked: locked,
      home: home ?? const DatingHome(state: DatingHomeState.notStarted),
      first: first,
    ),
  );
}

void main() {
  testWidgets('no lock: the section shows at once', (t) async {
    await _pump(t);
    expect(find.text('Set up Dating'), findsOneWidget);
    expect(find.text('Dating is locked'), findsNothing);
  });

  testWidgets('the Dating lock: one row until the PIN is entered', (t) async {
    await _pump(t, locked: true);
    expect(find.text('Dating is locked'), findsOneWidget);
    expect(find.text('Set up Dating'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Dating, locked')), findsOneWidget);
    // No PIN on this phone: confirmSafetyPin lets it through.
    await tapInReach(t, find.text('Dating is locked'));
    await t.pumpAndSettle();
    expect(find.text('Set up Dating'), findsOneWidget);
    final c = ProviderScope.containerOf(t.element(find.byType(MeHomeScreen)));
    expect(c.read(datingUnlockedProvider), isTrue);
  });

  testWidgets('the unlock ends when the app is put away', (t) async {
    await _pump(t, locked: true);
    await tapInReach(t, find.text('Dating is locked'));
    await t.pumpAndSettle();
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
    expect(find.text('Dating is locked'), findsOneWidget);
    expect(find.text('Set up Dating'), findsNothing);
  });

  testWidgets('carry 3: both partners ended the space early: no wait card', (
    t,
  ) async {
    await t.pumpWidget(const SizedBox());
    final json = homeJson(
      path: 'dating',
      datingEnabled: true,
      link: 'ended_window',
      windowEndsAt: '2026-11-20T12:00:00Z',
    );
    await pumpFlowScreen(
      t,
      () => MeHomeScreen(home: snapshotOf(json)),
      overrides: _overrides(),
    );
    expect(find.textContaining('Dating opens for you on'), findsNothing);
    expect(find.text('Set up Dating'), findsOneWidget);
  });

  testWidgets('guidelines, locked and not', (t) async {
    final semantics = t.ensureSemantics();
    for (final locked in [true, false]) {
      await _pump(t, locked: locked, first: (hasNote: false, hasQuiz: false));
      await expectFlowGuidelines(t);
    }
    semantics.dispose();
  });

  testWidgets('me_dating_open goldens', (t) async {
    final json = homeJson(path: 'dating', datingEnabled: true);
    await expectFlowGoldens(
      t,
      'me_dating_open',
      () => MeHomeScreen(home: snapshotOf(json)),
      overrides: _overrides(first: (hasNote: false, hasQuiz: false)),
    );
  });
}
