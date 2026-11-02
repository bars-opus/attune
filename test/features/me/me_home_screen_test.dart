// Spec 1 W3b (§3.10, §3.12): the Me home. Your space (Journal, Quizzes,
// Healing after a breakup or a loss); J1 and its one celebration; J4's
// More ways to use Attune.
import 'package:attune/features/me/data/journal_reminder_service.dart';
import 'package:attune/features/me/presentation/me_providers.dart';
import 'package:attune/features/me/presentation/screens/me_home_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/fake_reminder_rpc.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

const _uid = 'u-me';

User _user(String phone) => User(
  id: _uid,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
  phone: phone,
);

List<Override> _overrides(
  FakeHomeStateGateway gateway, {
  String phone = '+233244123456',
  ({bool? hasNote, bool? hasQuiz}) first = (hasNote: true, hasQuiz: true),
}) => [
  homeAuthProvider.overrideWithValue(FakeHomeAuth(_user(phone))),
  homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
  relationshipLifecycleProvider.overrideWith((ref) async => null),
  firstActionInputsProvider.overrideWithValue(first),
  // W3c: J3's row reads the reminder; never Supabase in a test.
  journalReminderRpcProvider.overrideWithValue(FakeReminderRpc().call),
];

Future<(FlowHarness, FakeHomeStateGateway)> _pump(
  WidgetTester tester,
  Map<String, dynamic> json, {
  String phone = '+233244123456',
  List<String> open = const ['GB', 'GH'],
  ({bool? hasNote, bool? hasQuiz}) first = (hasNote: true, hasQuiz: true),
  Map<String, Object> prefsValues = const {},
}) async {
  // A fresh ProviderScope each time (pumpWidget would reuse the last one).
  await tester.pumpWidget(const SizedBox());
  final gateway = FakeHomeStateGateway(state: json);
  final h = await pumpFlowScreen(
    tester,
    () => MeHomeScreen(home: snapshotOf(json)),
    openCountries: open,
    prefsValues: prefsValues,
    overrides: _overrides(gateway, phone: phone, first: first),
  );
  return (h, gateway);
}

void main() {
  testWidgets('Just for me: your space, no Dating slot', (tester) async {
    await _pump(tester, homeJson(path: 'just_me', datingEnabled: true));
    expect(find.text('Your space'), findsOneWidget);
    for (final row in ['Journal', 'Quizzes', 'Healing']) {
      expect(find.text(row, skipOffstage: false), findsOneWidget);
    }
    expect(
      find.text('After a breakup or a loss', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Set up Dating'), findsNothing);
  });

  testWidgets('J3: "Remind me to write" in Your space, before J4', (
    tester,
  ) async {
    await _pump(tester, homeJson(path: 'just_me'));
    final j3 = find.text('Remind me to write', skipOffstage: false);
    expect(j3, findsOneWidget);
    expect(find.text('Off', skipOffstage: false), findsOneWidget);
    final j4 = find.text('More ways to use Attune', skipOffstage: false);
    expect(tester.getTopLeft(j3).dy, lessThan(tester.getTopLeft(j4).dy));
  });

  testWidgets('J1: "Start here" before any note or quiz', (tester) async {
    final (h, _) = await _pump(
      tester,
      homeJson(path: 'just_me'),
      first: (hasNote: false, hasQuiz: false),
    );
    expect(find.text('Start here'), findsOneWidget);
    expect(find.text('Write your first note'), findsOneWidget);
    expect(
      find.text('Take a 3-minute look at how you connect'),
      findsOneWidget,
    );
    expect(h.prefs.getString('attune.flow.$_uid.first_action'), 'started');
  });

  testWidgets('J1: "Saved, just for you." once, after the first note', (
    tester,
  ) async {
    final (h, _) = await _pump(
      tester,
      homeJson(path: 'just_me'),
      first: (hasNote: true, hasQuiz: false),
      prefsValues: {'attune.flow.$_uid.first_action': 'started'},
    );
    expect(find.text('Saved, just for you.'), findsOneWidget);
    expect(h.prefs.getString('attune.flow.$_uid.first_action'), 'celebrated');

    await _pump(
      tester,
      homeJson(path: 'just_me'),
      first: (hasNote: true, hasQuiz: false),
      prefsValues: {'attune.flow.$_uid.first_action': 'celebrated'},
    );
    expect(find.text('Saved, just for you.'), findsNothing);
    expect(find.text('Start here'), findsNothing);
  });

  testWidgets('J4: More ways offers the other two paths', (tester) async {
    final (_, gateway) = await _pump(tester, homeJson(path: 'just_me'));
    await tester.scrollUntilVisible(
      find.text('More ways to use Attune'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('More ways to use Attune'));
    await tester.pumpAndSettle();
    expect(find.text('Invite a partner'), findsOneWidget);
    expect(find.text('Single and open to dating'), findsOneWidget);
    expect(find.text('Just for me'), findsNothing);
    gateway.state = homeJson(path: 'dating');
    await tester.tap(find.text('Single and open to dating'));
    await tester.pumpAndSettle();
    expect(gateway.calls.firstWhere((c) => c.$1 == 'set_my_path').$2, {
      'p_path': 'dating',
      'p_confirmed': false,
    });
  });

  testWidgets('meets the tap-target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      homeJson(path: 'just_me'),
      first: (hasNote: false, hasQuiz: false),
    );
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('Me goldens', (tester) async {
    await expectFlowGoldens(
      tester,
      'me_just_me',
      () => MeHomeScreen(home: snapshotOf(homeJson(path: 'just_me'))),
      overrides: _overrides(
        FakeHomeStateGateway(state: homeJson(path: 'just_me')),
        first: (hasNote: false, hasQuiz: false),
      ),
    );
  });
}
