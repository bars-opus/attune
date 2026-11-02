// Spec 1 W3c (§3.12, B7 review M-1): in the real shell, a switch refused
// because a shared space is open re-reads the home, which turns Tab 2 from
// Me into Chat and disposes Me. The shared-space sheet still shows, and its
// Pause and End still open the Spec 3a confirmations.
import 'package:attune/features/me/data/journal_reminder_service.dart';
import 'package:attune/features/me/presentation/me_providers.dart';
import 'package:attune/features/me/presentation/screens/me_home_screen.dart';
import 'package:attune/features/onboarding/data/home_state_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/fake_reminder_rpc.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

Future<HomeHarness> _pumpShell(
  WidgetTester tester,
  Map<String, dynamic> server,
) async {
  FlutterSecureStorage.setMockInitialValues({});
  final h = await pumpHome(
    tester,
    server: server,
    // A finished account with a cached Me layout (no onboarding detour).
    prefsValues: {
      HomeStateStore.keyFor('u-home'):
          '{"tab":"me","link":"none","needs":[],"hold":false,'
          '"at":"2026-10-26T08:00:00.000Z"}',
    },
    initialLocation: '/home?tab=me',
    tabTwo:
        (tab, home, _) =>
            tab == AppTab.me
                ? MeHomeScreen(home: home)
                : Text('CHAT ${home.link.wire}'),
    overrides: [
      relationshipLifecycleProvider.overrideWith((ref) async => null),
      firstActionInputsProvider.overrideWithValue((
        hasNote: true,
        hasQuiz: true,
      )),
      journalReminderRpcProvider.overrideWithValue(FakeReminderRpc().call),
      publicAppConfigGatewayProvider.overrideWithValue(
        FakePublicConfigGateway(),
      ),
    ],
  );
  await tester.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('J4 refused: the sheet shows over the new home; Pause acts', (
    tester,
  ) async {
    final h = await _pumpShell(tester, homeJson(path: 'just_me'));
    expect(find.text('More ways to use Attune'), findsOneWidget);
    await tester.tap(find.text('More ways to use Attune'));
    await tester.pumpAndSettle();
    h.gateway.state = homeJson(
      path: 'relationship',
      link: 'linked',
      relationshipId: 'r1',
      partnerFirstName: 'Kofi',
    );
    h.gateway.failNext = FakeHomeStateGateway.refusal('path:relationship_open');
    await tester.tap(find.text('Single and open to dating'));
    await tester.pumpAndSettle();
    expect(find.text('CHAT linked'), findsOneWidget);
    expect(find.byType(MeHomeScreen), findsNothing);
    expect(find.text("You're in a shared space with Kofi"), findsOneWidget);
    await tester.tap(find.text('Pause our shared space'));
    await tester.pumpAndSettle();
    expect(find.text('Pause your shared space?'), findsOneWidget);
  });

  testWidgets('"Not ready?" refused: the sheet shows; End acts', (
    tester,
  ) async {
    final h = await _pumpShell(tester, homeJson(path: 'dating'));
    expect(find.text('Not ready? Use Attune just for me'), findsOneWidget);
    h.gateway.state = homeJson(
      path: 'relationship',
      link: 'paused',
      relationshipId: 'r1',
    );
    h.gateway.failNext = FakeHomeStateGateway.refusal('path:relationship_open');
    await tester.tap(find.text('Not ready? Use Attune just for me'));
    await tester.pumpAndSettle();
    expect(find.byType(MeHomeScreen), findsNothing);
    expect(
      find.text("You're in a shared space with your partner"),
      findsOneWidget,
    );
    await tester.tap(find.text('End relationship'));
    await tester.pumpAndSettle();
    expect(find.text('End your shared space?'), findsOneWidget);
  });
}
