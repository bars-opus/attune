// Spec 1 W5 final review M-4: a switch to Dating deletes the server's
// draft (set_user_path_internal), and the phone's queued draft answers for
// that account go with it, so a later flush can't rebuild the draft from
// them. Just for me keeps both (the server keeps the draft there too).
import 'package:attune/features/couple_profile/data/about_us_outbox.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';

const _uid = 'u-switch';
const _draft = AboutUsTarget.draft();
const _shared = AboutUsTarget.shared('rel-old');

Future<(FlowHarness, FakeHomeStateGateway, List<PathChoiceOutcome>)> _pump(
  WidgetTester tester,
  AppPath to, {
  Object? failNext,
}) async {
  final gateway = FakeHomeStateGateway(
    state: homeJson(path: 'relationship', link: 'pending'),
  )..failNext = failNext;
  gateway.onSetPath =
      (params) => gateway.state = homeJson(path: params['p_path'] as String?);
  final outcomes = <PathChoiceOutcome>[];
  final harness = await pumpFlowScreen(
    tester,
    () => Consumer(
      builder:
          (context, ref, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed:
                    () async => outcomes.add(
                      await choosePath(context, ref, userId: _uid, path: to),
                    ),
                child: const Text('CHOOSE'),
              ),
            ),
          ),
    ),
    overrides: [
      homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
    ],
  );
  return (harness, gateway, outcomes);
}

Future<void> _queue(SharedPreferences prefs, String uid) async {
  final box = AboutUsOutbox(prefs, userId: uid);
  await box.enqueue(_draft, AboutUsPatch.living(Living.together));
  await box.enqueue(_draft, AboutUsPatch.children(Children.none));
}

void main() {
  testWidgets('a switch to Dating clears this account\'s queued draft '
      'answers, and only those', (tester) async {
    final (h, _, outcomes) = await _pump(tester, AppPath.dating);
    await _queue(h.prefs, _uid);
    await AboutUsOutbox(
      h.prefs,
      userId: _uid,
    ).enqueue(_shared, AboutUsPatch.living(Living.apartNearby));
    await _queue(h.prefs, 'u-other');

    await tester.tap(find.text('CHOOSE'));
    await tester.pumpAndSettle();

    expect(outcomes, [PathChoiceOutcome.done]);
    final mine = AboutUsOutbox(h.prefs, userId: _uid);
    expect(mine.pending(_draft), isNull, reason: 'the draft answers went');
    expect(mine.pending(_shared), isNotNull, reason: 'only the draft');
    expect(
      AboutUsOutbox(h.prefs, userId: 'u-other').pendingPatches(_draft),
      hasLength(2),
      reason: 'another account on the phone is untouched',
    );
    for (final key in h.prefs.getKeys()) {
      expect(key.toLowerCase(), isNot(contains('dating')));
      expect('${h.prefs.get(key)}'.toLowerCase(), isNot(contains('dating')));
    }
  });

  testWidgets('Just for me keeps the queued draft answers', (tester) async {
    final (h, _, outcomes) = await _pump(tester, AppPath.justMe);
    await _queue(h.prefs, _uid);
    await tester.tap(find.text('CHOOSE'));
    await tester.pumpAndSettle();
    expect(outcomes, [PathChoiceOutcome.done]);
    expect(
      AboutUsOutbox(h.prefs, userId: _uid).pendingPatches(_draft),
      hasLength(2),
    );
  });

  testWidgets('a Dating switch that never happened keeps them', (tester) async {
    final (h, _, outcomes) = await _pump(
      tester,
      AppPath.dating,
      failNext: FakeHomeStateGateway.refusal('path:invalid'),
    );
    await _queue(h.prefs, _uid);
    await tester.tap(find.text('CHOOSE'));
    await tester.pumpAndSettle();
    expect(outcomes, [PathChoiceOutcome.failed]);
    expect(
      AboutUsOutbox(h.prefs, userId: _uid).pendingPatches(_draft),
      hasLength(2),
    );
  });
}
