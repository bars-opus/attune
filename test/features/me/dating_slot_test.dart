// Spec 1 W3b (§3.9, §3.12, D20): the Dating slot at the top of Me, Dating
// path only, from the live answer, calling no Dating RPC: open, not open,
// closed and gentle-wait states; the Dating lock; "Not ready?"; nothing
// about Dating left on the phone.
import 'package:attune/features/me/data/journal_reminder_service.dart';
import 'package:attune/features/me/presentation/me_providers.dart';
import 'package:attune/features/me/presentation/screens/me_home_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

class _Lock extends DatingLockStore {
  _Lock(this.on);
  bool on;
  @override
  Future<bool> isOn() async => on;
  @override
  Future<void> setOn(bool value) async => on = value;
}

List<Override> _overrides(
  FakeHomeStateGateway gateway, {
  String phone = '+233244123456',
  bool locked = false,
  ({bool? hasNote, bool? hasQuiz}) first = (hasNote: true, hasQuiz: true),
}) => [
  homeAuthProvider.overrideWithValue(FakeHomeAuth(_user(phone))),
  homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
  relationshipLifecycleProvider.overrideWith((ref) async => null),
  datingLockStoreProvider.overrideWithValue(_Lock(locked)),
  firstActionInputsProvider.overrideWithValue(first),
  // W3c: J3's row reads the reminder; never Supabase in a test.
  journalReminderRpcProvider.overrideWithValue(FakeReminderRpc().call),
];

Future<(FlowHarness, FakeHomeStateGateway)> _pump(
  WidgetTester tester,
  Map<String, dynamic> json, {
  String phone = '+233244123456',
  bool locked = false,
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
    overrides: _overrides(gateway, phone: phone, locked: locked, first: first),
  );
  return (h, gateway);
}

void main() {
  testWidgets('Dating, open here: "Set up Dating" and "Not ready?"', (
    tester,
  ) async {
    await _pump(tester, homeJson(path: 'dating', datingEnabled: true));
    expect(find.text('Dating'), findsOneWidget);
    expect(
      find.text(
        'Up to 3 introductions a day. A match only when you both say yes.',
      ),
      findsOneWidget,
    );
    expect(find.text('Set up Dating'), findsOneWidget);
    expect(find.text('Not ready? Use Attune just for me'), findsOneWidget);
  });

  testWidgets('Dating, not open here: says where it is, offers a change', (
    tester,
  ) async {
    await _pump(
      tester,
      homeJson(path: 'dating', datingEnabled: true),
      phone: '+2348031234567',
    );
    expect(find.text("Dating isn't open in Nigeria yet"), findsOneWidget);
    expect(
      find.text(
        "Dating is open in the UK and Ghana. We're adding countries one at a time.",
      ),
      findsOneWidget,
    );
    expect(find.text('Not in Nigeria? Change'), findsOneWidget);
    expect(find.text('Set up Dating'), findsNothing);
  });

  testWidgets('a chosen country is kept on this phone under a neutral key', (
    tester,
  ) async {
    final (h, _) = await _pump(
      tester,
      homeJson(path: 'dating', datingEnabled: true),
      phone: '+2348031234567',
      prefsValues: {'attune.flow.$_uid.country_override': 'GH'},
    );
    expect(find.text('Set up Dating'), findsOneWidget);
    expect(h.prefs.getString('attune.flow.$_uid.country_override'), 'GH');
  });

  testWidgets('Dating switched off everywhere: closed, no country claim', (
    tester,
  ) async {
    await _pump(tester, homeJson(path: 'dating'));
    expect(find.text("Dating isn't open yet"), findsOneWidget);
    expect(find.textContaining('Ghana'), findsNothing);
  });

  testWidgets('inside an ending window: the gentle wait', (tester) async {
    await _pump(
      tester,
      homeJson(
        path: 'dating',
        datingEnabled: true,
        link: 'ended_window',
        windowEndsAt: '2026-11-20T12:00:00Z',
      ),
    );
    expect(find.textContaining('Dating opens for you on'), findsOneWidget);
    expect(find.textContaining('November 20, 2026'), findsOneWidget);
    expect(
      find.text(
        "This pause is because your relationship ended here. It isn't a judgement about you.",
      ),
      findsOneWidget,
    );
    expect(find.text('Healing is here if you want it'), findsOneWidget);
    expect(find.text('Set up Dating'), findsNothing);
  });

  testWidgets('inside an ending window with no date: still the gentle '
      'wait, never "Set up Dating" (M-1)', (tester) async {
    await _pump(
      tester,
      homeJson(path: 'dating', datingEnabled: true, link: 'ended_window'),
    );
    expect(find.text('Dating opens for you after a pause.'), findsOneWidget);
    expect(
      find.text(
        "This pause is because your relationship ended here. It isn't a judgement about you.",
      ),
      findsOneWidget,
    );
    expect(find.text('Healing is here if you want it'), findsOneWidget);
    expect(find.text('Set up Dating'), findsNothing);
    expect(find.text('Not ready? Use Attune just for me'), findsNothing);
  });

  testWidgets('an unlocked slot locks again when the app is put away (M-2)', (
    tester,
  ) async {
    await _pump(
      tester,
      homeJson(path: 'dating', datingEnabled: true),
      locked: true,
    );
    await tester.tap(find.text('Dating is locked'));
    await tester.pumpAndSettle();
    expect(find.text('Set up Dating'), findsOneWidget);
    final binding = tester.binding;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(find.text('Dating is locked'), findsOneWidget);
    expect(find.text('Set up Dating'), findsNothing);
  });

  testWidgets('the Dating lock: one row until the PIN is entered', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await _pump(
      tester,
      homeJson(path: 'dating', datingEnabled: true),
      locked: true,
    );
    expect(find.text('Dating is locked'), findsOneWidget);
    expect(find.text('Set up Dating'), findsNothing);
    // No PIN set on this phone: confirmSafetyPin lets it through.
    await tester.tap(find.text('Dating is locked'));
    await tester.pumpAndSettle();
    expect(find.text('Set up Dating'), findsOneWidget);
  });

  testWidgets('"Not ready?" with nothing enrolled is one tap', (tester) async {
    final (_, gateway) = await _pump(
      tester,
      homeJson(path: 'dating', datingEnabled: true),
    );
    gateway.state = homeJson(path: 'just_me');
    await tester.tap(find.text('Not ready? Use Attune just for me'));
    await tester.pumpAndSettle();
    expect(find.text('Use Attune just for you?'), findsNothing);
    expect(gateway.calls.firstWhere((c) => c.$1 == 'set_my_path').$2, {
      'p_path': 'just_me',
      'p_confirmed': false,
    });
  });

  testWidgets('"Not ready?" refused, a shared space is open (M-2)', (
    tester,
  ) async {
    final (_, gateway) = await _pump(
      tester,
      homeJson(path: 'dating', datingEnabled: true),
    );
    gateway.state = homeJson(
      path: 'relationship',
      link: 'paused',
      relationshipId: 'r1',
    );
    gateway.failNext = FakeHomeStateGateway.refusal('path:relationship_open');
    await tester.tap(find.text('Not ready? Use Attune just for me'));
    await tester.pumpAndSettle();
    expect(
      find.text("You're in a shared space with your partner"),
      findsOneWidget,
    );
    expect(find.text('Pause our shared space'), findsNothing);
    expect(find.text('End relationship'), findsOneWidget);
  });

  testWidgets('"Not ready?" while enrolled asks first (§3.12)', (tester) async {
    final (_, gateway) = await _pump(
      tester,
      homeJson(path: 'dating', datingEnabled: true, datingEnrolled: true),
    );
    await tester.tap(find.text('Not ready? Use Attune just for me'));
    await tester.pumpAndSettle();
    expect(find.text('Use Attune just for you?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gateway.count('set_my_path'), 0);
  });

  testWidgets(
    'after a Dating session no device key or value names Dating (D20)',
    (tester) async {
      final (h, _) = await _pump(
        tester,
        homeJson(path: 'dating', datingEnabled: true, datingEnrolled: true),
        phone: '+2348031234567',
        first: (hasNote: false, hasQuiz: false),
        prefsValues: {'attune.flow.$_uid.country_override': 'GH'},
      );
      for (final key in h.prefs.getKeys()) {
        expect(key.toLowerCase(), isNot(contains('dating')), reason: key);
        expect(
          '${h.prefs.get(key)}'.toLowerCase(),
          isNot(contains('dating')),
          reason: key,
        );
      }
    },
  );

  testWidgets('meets the tap-target, label and contrast guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      homeJson(path: 'dating', datingEnabled: true),
      first: (hasNote: false, hasQuiz: false),
    );
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  // M-4: every other state of the slot meets them too.
  for (final (name, json, phone, locked) in [
    (
      'locked',
      homeJson(path: 'dating', datingEnabled: true),
      '+233244123456',
      true,
    ),
    (
      'not open here',
      homeJson(path: 'dating', datingEnabled: true),
      '+2348031234567',
      false,
    ),
    ('closed', homeJson(path: 'dating'), '+233244123456', false),
    (
      'gentle wait',
      homeJson(
        path: 'dating',
        datingEnabled: true,
        link: 'ended_window',
        windowEndsAt: '2026-11-20T12:00:00Z',
      ),
      '+233244123456',
      false,
    ),
  ]) {
    testWidgets('$name meets the tap-target, label and contrast guidelines', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        json,
        phone: phone,
        locked: locked,
        first: (hasNote: false, hasQuiz: false),
      );
      await expectFlowGuidelines(tester);
      semantics.dispose();
    });
  }

  for (final (name, json) in [
    ('me_dating_open', homeJson(path: 'dating', datingEnabled: true)),
  ]) {
    testWidgets('$name goldens', (tester) async {
      await expectFlowGoldens(
        tester,
        name,
        () => MeHomeScreen(home: snapshotOf(json)),
        openCountries: const ['GB', 'GH'],
        overrides: _overrides(
          FakeHomeStateGateway(state: json),
          first: (hasNote: false, hasQuiz: false),
        ),
      );
    });
  }
}
