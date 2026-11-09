// Spec 2 W3a (§3.10; R-36): the not-open screens, built from the open
// countries; Tell me once; Turn this off; offline disabled; no animation.
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

List<Override> _overrides(
  FakeDatingHomeGateway home, {
  bool online = true,
  FakeHomeStateGateway? spec1,
}) => [
  ...datingShellOverrides(home: home, online: online),
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
  homeStateServiceProvider.overrideWithValue(
    HomeStateService(
      spec1 ?? FakeHomeStateGateway(state: homeJson(path: 'dating')),
    ),
  ),
];

void main() {
  testWidgets('a closed country: the open list is built, never hard-coded', (
    t,
  ) async {
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: _overrides(FakeDatingHomeGateway()),
    );
    expect(find.text("Dating isn't open in Nigeria yet"), findsOneWidget);
    expect(
      find.text(
        'Attune opens Dating one country at a time, so we can keep it safe '
        "and well looked after. It's open in the United Kingdom and Ghana "
        '(Greater Accra and Ashanti) now.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Tell me, then Turn this off', (t) async {
    final home = FakeDatingHomeGateway();
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: _overrides(home),
    );
    await tapInReach(t, find.text("Tell me when it's here"));
    await t.pumpAndSettle();
    expect(home.requests, [('NG', null)]);
    expect(
      find.text("We'll let you know. You can turn this off in Settings."),
      findsOneWidget,
    );
    await tapInReach(t, find.text('Turn this off'));
    await t.pumpAndSettle();
    expect(home.cancels, 1);
    expect(find.text("Tell me when it's here"), findsOneWidget);
  });

  testWidgets('the region variant', (t) async {
    final home = FakeDatingHomeGateway();
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'GH', region: 'TV'),
      overrides: _overrides(home),
    );
    expect(
      find.text('Dating is open in Greater Accra and Ashanti for now'),
      findsOneWidget,
    );
    expect(
      find.text(
        "We're opening other regions as soon as we can look after them well.",
      ),
      findsOneWidget,
    );
    await tapInReach(t, find.text("Tell me when it's open in Volta"));
    await t.pumpAndSettle();
    expect(home.requests, [('GH', 'TV')]);
  });

  testWidgets('offline: Tell me is disabled', (t) async {
    final home = FakeDatingHomeGateway();
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: _overrides(home, online: false),
    );
    await tapInReach(t, find.text("Tell me when it's here"));
    await t.pumpAndSettle();
    expect(home.requests, isEmpty);
    expect(
      find.text("You're offline. Dating needs a connection."),
      findsOneWidget,
    );
  });

  testWidgets('an answer the server refuses is said calmly', (t) async {
    final home =
        FakeDatingHomeGateway()..noticeResult = DatingNoticeResult.busy;
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: _overrides(home),
    );
    await tapInReach(t, find.text("Tell me when it's here"));
    await t.pumpAndSettle();
    expect(
      find.text(
        'This is taking a little longer than usual. Try again in a moment.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no country known: choose one first (kept in memory only)', (
    t,
  ) async {
    final h = await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(),
      overrides: _overrides(FakeDatingHomeGateway()),
    );
    expect(find.text("Dating isn't open yet"), findsOneWidget);
    expect(find.text('Choose your country'), findsOneWidget);
    expect(h.prefs.getKeys(), isEmpty);
  });

  testWidgets('"Use Attune just for me" switches in one tap', (t) async {
    final spec1 = FakeHomeStateGateway(state: homeJson(path: 'dating'));
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: _overrides(FakeDatingHomeGateway(), spec1: spec1),
    );
    // The path is Spec 1's home state, which Me's shell reads; read it here.
    await ProviderScope.containerOf(
      t.element(find.byType(DatingNotOpenScreen)),
    ).read(homeStateProvider('ama').notifier).refresh();
    await t.pumpAndSettle();
    await tapInReach(t, find.text('Use Attune just for me'));
    await t.pumpAndSettle();
    expect(spec1.count('set_my_path'), 1);
  });

  testWidgets('guidelines', (t) async {
    final semantics = t.ensureSemantics();
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: _overrides(FakeDatingHomeGateway()),
    );
    await expectFlowGuidelines(t);
    semantics.dispose();
  });

  for (final (name, country, region) in [
    ('not_open_country', 'NG', null),
    ('not_open_region', 'GH', 'TV'),
  ]) {
    testWidgets('$name goldens', (t) async {
      await expectFlowGoldens(
        t,
        name,
        () => DatingNotOpenScreen(country: country, region: region),
        overrides: _overrides(FakeDatingHomeGateway()),
      );
    });
  }
}
