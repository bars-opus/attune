// Spec 2 W3a Task 4 fix round 1 (I-1, R-5; Minors 2, 3, 8): the not-open
// screen offers "Tell me when it's here" only for a place that is closed;
// an open place reads neutrally; already_open is never a silent no-op; the
// deep link's region is checked; "Use Attune just for me" follows the
// switch's outcome; the screen calls nothing but the notice and its reads.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

const _tellMe = "Tell me when it's here";
const _neutralTitle = "Dating isn't open yet";
const _neutralBody =
    'It opens one country at a time. Your journal, quizzes and Healing are '
    'here meanwhile.';

Future<(FakeDatingHomeGateway, FakeDatingLifecycleGateway)> _pump(
  WidgetTester t,
  Widget Function() screen, {
  FakeDatingHomeGateway? home,
  FakeHomeStateGateway? spec1,
}) async {
  await t.pumpWidget(const SizedBox());
  final gateway = home ?? FakeDatingHomeGateway();
  final life = FakeDatingLifecycleGateway();
  await pumpFlowScreen(
    t,
    screen,
    overrides: [
      ...datingShellOverrides(home: gateway, life: life),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(
          spec1 ?? FakeHomeStateGateway(state: homeJson(path: 'dating')),
        ),
      ),
    ],
  );
  return (gateway, life);
}

void main() {
  testWidgets('R-5: feature_unavailable where the country is open (GH, '
      'Dating off): no Tell me, and no "isn\'t open in Ghana"', (t) async {
    await _pump(
      t,
      () => const DatingNotOpenScreen(country: 'GH'),
      home: FakeDatingHomeGateway(
        home: const DatingHome(
          state: DatingHomeState.featureUnavailable,
          country: 'GH',
          notice: DatingNotice(available: false),
        ),
      ),
    );
    expect(find.text(_tellMe), findsNothing);
    expect(find.textContaining("isn't open in Ghana"), findsNothing);
    expect(find.text(_neutralTitle), findsOneWidget);
    expect(find.text(_neutralBody), findsOneWidget);
  });

  testWidgets('R-5: an open country picked in the picker: no Tell me', (
    t,
  ) async {
    await _pump(t, () => const DatingNotOpenScreen());
    await tapInReach(t, find.text('Choose your country'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Ghana');
    await t.pumpAndSettle();
    await tapInReach(t, find.text('+233 • GH'));
    await t.pumpAndSettle();
    expect(find.text(_tellMe), findsNothing);
    expect(find.textContaining("isn't open in Ghana"), findsNothing);
    expect(find.text(_neutralBody), findsOneWidget);
  });

  testWidgets('R-5: a closed country picked in the picker: Tell me', (t) async {
    await _pump(t, () => const DatingNotOpenScreen());
    await tapInReach(t, find.text('Choose your country'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Nigeria');
    await t.pumpAndSettle();
    await tapInReach(t, find.text('+234 • NG'));
    await t.pumpAndSettle();
    expect(find.text("Dating isn't open in Nigeria yet"), findsOneWidget);
    expect(find.text(_tellMe), findsOneWidget);
  });

  testWidgets('an open region in the deep link: neutral, no Tell me', (
    t,
  ) async {
    await _pump(
      t,
      () => const DatingNotOpenScreen(country: 'GH', region: 'AA'),
    );
    expect(find.textContaining("Tell me when it's open in"), findsNothing);
    expect(find.text(_neutralTitle), findsOneWidget);
  });

  testWidgets('already_open: the home is read again and Me opens, never a '
      'silent tap', (t) async {
    final home =
        FakeDatingHomeGateway()..noticeResult = DatingNoticeResult.alreadyOpen;
    await _pump(t, () => const DatingNotOpenScreen(country: 'NG'), home: home);
    final reads = home.reads;
    await tapInReach(t, find.text(_tellMe));
    await t.pumpAndSettle();
    expect(home.requests, [('NG', null)]);
    expect(find.textContaining('at /home?tab=me'), findsOneWidget);
    expect(home.reads, greaterThan(reads));
  });

  testWidgets('Minor 3: a region that is not a code is ignored, never shown', (
    t,
  ) async {
    final (home, _) = await _pump(
      t,
      () => const DatingNotOpenScreen(country: 'NG', region: 'Call 0800 now'),
    );
    expect(find.textContaining('0800'), findsNothing);
    expect(find.text("Dating isn't open in Nigeria yet"), findsOneWidget);
    await tapInReach(t, find.text(_tellMe));
    await t.pumpAndSettle();
    expect(home.requests, [('NG', null)]);
  });

  testWidgets('Minor 8: only the notice and its reads; no lifecycle or setup '
      'call', (t) async {
    final (home, life) = await _pump(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
    );
    await tapInReach(t, find.text(_tellMe));
    await t.pumpAndSettle();
    await tapInReach(t, find.text('Turn this off'));
    await t.pumpAndSettle();
    expect(life.calls, isEmpty);
    expect(
      home.log.toSet().difference({
        'read',
        'availability',
        'request',
        'cancel',
      }),
      isEmpty,
    );
    expect(home.log.where((c) => c == 'request'), hasLength(1));
    expect(home.log.where((c) => c == 'cancel'), hasLength(1));
  });

  group('Minor 2: "Use Attune just for me" follows the outcome', () {
    Future<FakeHomeStateGateway> pumpOnDating(WidgetTester t) async {
      final spec1 = FakeHomeStateGateway(state: homeJson(path: 'dating'));
      await _pump(
        t,
        () => const DatingNotOpenScreen(country: 'NG'),
        spec1: spec1,
      );
      await ProviderScope.containerOf(
        t.element(find.byType(DatingNotOpenScreen)),
      ).read(homeStateProvider('ama').notifier).refresh();
      await t.pumpAndSettle();
      return spec1;
    }

    testWidgets('done: Me', (t) async {
      final spec1 = await pumpOnDating(t);
      await tapInReach(t, find.text('Use Attune just for me'));
      await t.pumpAndSettle();
      expect(spec1.count('set_my_path'), 1);
      expect(find.textContaining('at /home?tab=me'), findsOneWidget);
    });

    testWidgets('a shared space is open: its sheet, and no Me', (t) async {
      final spec1 = await pumpOnDating(t);
      spec1.state = homeJson(
        path: 'relationship',
        link: 'paused',
        relationshipId: 'r1',
      );
      spec1.failNext = FakeHomeStateGateway.refusal('path:relationship_open');
      await tapInReach(t, find.text('Use Attune just for me'));
      await t.pumpAndSettle();
      expect(
        find.text("You're in a shared space with your partner"),
        findsOneWidget,
      );
      expect(find.textContaining('at /home?tab=me'), findsNothing);
    });

    testWidgets('failed: stays here', (t) async {
      final spec1 = await pumpOnDating(t);
      spec1.failNext = FakeHomeStateGateway.refusal('path:unknown');
      await tapInReach(t, find.text('Use Attune just for me'));
      await t.pumpAndSettle();
      expect(find.textContaining('at /home?tab=me'), findsNothing);
      expect(find.byType(DatingNotOpenScreen), findsOneWidget);
    });
  });
}
