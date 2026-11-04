// Spec 1 W9e (D8, shared phones): Healing's journey, start context and
// readiness answers belong to the signed-in account. When another account
// signs in on the same phone, the Healing screen never shows the last
// account's journey: not while the next account's read is out, not after
// it fails, and not when a read answers for another account.
import 'dart:async';

import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/screens/healing_journey_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import 'support/healing_fakes.dart';

final _signedIn = StateProvider<String?>((ref) => 'ama');

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(Scaffold).first));

Future<FakeHealingRepository> _pumpAma(WidgetTester t) async {
  final repo =
      FakeHealingRepository()
        ..latest['ama'] = testJourney(userId: 'ama', stage: 2)
        ..latest['kofi'] = testJourney(id: 'j2', userId: 'kofi', stage: 4);
  await pumpFlowScreen(
    t,
    () => const HealingJourneyScreen(),
    // The stage row is wider than a phone in the test font (Ahem), which
    // is not what this test is about.
    size: const Size(900, 1200),
    overrides: [
      healingRepositoryProvider.overrideWithValue(repo),
      healingAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
    ],
  );
  expect(find.text('Stage 2 of 5'), findsOneWidget);
  return repo;
}

void main() {
  testWidgets(
    'the next account never sees the last one\'s journey while its read is out',
    (t) async {
      final repo = await _pumpAma(t);
      repo
        ..account = 'kofi'
        ..hold = Completer<void>();
      _container(t).read(_signedIn.notifier).state = 'kofi';
      // Frame by frame while Kofi's read is out: never Ama's journey.
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(find.text('Stage 2 of 5'), findsNothing, reason: 'frame $i');
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }
      repo.hold!.complete();
      await t.pumpAndSettle();
      expect(find.text('Stage 4 of 5'), findsOneWidget);
      expect(find.text('Stage 2 of 5'), findsNothing);
    },
  );

  testWidgets('the next account\'s read fails: an error, never the last '
      'account\'s journey', (t) async {
    final repo = await _pumpAma(t);
    final hold = Completer<void>();
    repo
      ..account = 'kofi'
      ..hold = hold;
    _container(t).read(_signedIn.notifier).state = 'kofi';
    await t.pump();
    hold.completeError(Exception('offline'));
    await t.pump();
    await t.pump();
    expect(find.text('Stage 2 of 5'), findsNothing);
    expect(find.textContaining('offline'), findsOneWidget);
  });

  testWidgets('a read that answers for another account is never shown', (
    t,
  ) async {
    final repo = await _pumpAma(t);
    // The phone's session still answers for Ama after Kofi signed in.
    repo.latest['kofi'] = testJourney(userId: 'ama', stage: 2);
    repo.account = 'kofi';
    _container(t).read(_signedIn.notifier).state = 'kofi';
    await t.pumpAndSettle();
    expect(find.text('Stage 2 of 5'), findsNothing);
    expect(
      find.textContaining('a healing journey is available'),
      findsOneWidget,
    );
  });
}
