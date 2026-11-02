// Spec 1 W3b (§3.10 J4, §3.12): the Me home beyond the brief's cases. J4 on
// the Dating path, J4 waiting for a live path, the lifecycle card inside an
// ending's window, and the More ways sheet's accessibility.
import 'package:attune/features/me/presentation/me_providers.dart';
import 'package:attune/features/me/presentation/screens/me_home_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/widgets/relationship_lifecycle_card.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

Future<FakeHomeStateGateway> _pump(
  WidgetTester tester,
  HomeSnapshot home, {
  ({bool? hasNote, bool? hasQuiz}) first = (hasNote: true, hasQuiz: true),
}) async {
  await tester.pumpWidget(const SizedBox());
  final gateway = FakeHomeStateGateway(state: homeJson(path: 'dating'));
  await pumpFlowScreen(
    tester,
    () => MeHomeScreen(home: home),
    size: const Size(390, 1600),
    overrides: [
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-me2'))),
      homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
      relationshipLifecycleProvider.overrideWith((ref) async => null),
      firstActionInputsProvider.overrideWithValue(first),
    ],
  );
  return gateway;
}

Future<void> _openMoreWays(WidgetTester tester) async {
  await tester.tap(find.text('More ways to use Attune'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('J4 on Dating offers a partner and Just for me', (tester) async {
    await _pump(tester, snapshotOf(homeJson(path: 'dating')));
    await _openMoreWays(tester);
    expect(find.text('Invite a partner'), findsOneWidget);
    expect(find.text('Just for me'), findsOneWidget);
    expect(find.text('Single and open to dating'), findsNothing);
  });

  testWidgets('J4 "Invite a partner" opens R1 as a switch', (tester) async {
    final gateway = await _pump(tester, snapshotOf(homeJson(path: 'dating')));
    await _openMoreWays(tester);
    await tester.tap(find.text('Invite a partner'));
    await tester.pumpAndSettle();
    expect(find.text('at /invite-partner?switch=1'), findsOneWidget);
    expect(gateway.count('set_my_path'), 0);
  });

  testWidgets('J4 refused, a shared space is open: pause or end (M-2)', (
    tester,
  ) async {
    final gateway = await _pump(tester, snapshotOf(homeJson(path: 'just_me')));
    gateway.state = homeJson(
      path: 'relationship',
      link: 'linked',
      relationshipId: 'r1',
      partnerFirstName: 'Kofi',
    );
    gateway.failNext = FakeHomeStateGateway.refusal('path:relationship_open');
    await _openMoreWays(tester);
    await tester.tap(find.text('Single and open to dating'));
    await tester.pumpAndSettle();
    expect(gateway.count('set_my_path'), 1);
    expect(find.text("You're in a shared space with Kofi"), findsOneWidget);
    expect(find.text('Pause our shared space'), findsOneWidget);
    expect(find.text('End relationship'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('J4 waits for the live path (none from the cache)', (
    tester,
  ) async {
    await _pump(tester, const HomeSnapshot(tab: AppTab.me));
    expect(find.text('Journal'), findsOneWidget);
    expect(find.text('More ways to use Attune'), findsNothing);
  });

  testWidgets('the lifecycle card only inside an ending window', (
    tester,
  ) async {
    await _pump(
      tester,
      snapshotOf(
        homeJson(
          path: 'just_me',
          link: 'ended_window',
          windowEndsAt: '2026-11-20T10:00:00Z',
        ),
      ),
    );
    expect(find.byType(RelationshipLifecycleCard), findsOneWidget);
    await _pump(tester, snapshotOf(homeJson(path: 'just_me')));
    expect(find.byType(RelationshipLifecycleCard), findsNothing);
  });

  // Ruling M-4 (09 P15): inside an ending window, More ways offers no
  // Dating, as R3 offers none.
  testWidgets('inside an ending window, More ways offers no Dating', (
    tester,
  ) async {
    await _pump(
      tester,
      snapshotOf(
        homeJson(
          path: 'just_me',
          link: 'ended_window',
          windowEndsAt: '2026-11-20T10:00:00Z',
        ),
      ),
    );
    await _openMoreWays(tester);
    expect(find.text('Invite a partner'), findsOneWidget);
    expect(find.text('Single and open to dating'), findsNothing);
    expect(
      find.textContaining(RegExp('dating', caseSensitive: false)),
      findsNothing,
    );
  });

  testWidgets('J1 waits while its inputs are unknown', (tester) async {
    await _pump(
      tester,
      snapshotOf(homeJson(path: 'just_me')),
      first: (hasNote: null, hasQuiz: false),
    );
    expect(find.text('Start here'), findsNothing);
    expect(find.text('Saved, just for you.'), findsNothing);
  });

  testWidgets('the More ways sheet meets the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, snapshotOf(homeJson(path: 'just_me')));
    await _openMoreWays(tester);
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });
}
