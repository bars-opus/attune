// Spec 2 W3a Task 4 carries (T1 I-1, R-45, T3 M-5): every lifecycle answer
// the section receives settles its key, so the next deliberate tap is a new
// request while a busy or failed one is retried with the same key; "Tell me
// when it's here" refused by the 20-a-day cap or the adult check has its
// own calm words, in the section and on the not-open screen.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

const _rateLimited = "You've done this a lot today. Try again tomorrow.";
const _notEligible = "We can't set this up on this account.";
const _generic = 'Something went wrong. Try again.';

Widget _section() => const Scaffold(
  body: SingleChildScrollView(
    padding: EdgeInsets.all(16),
    child: DatingSection(),
  ),
);

Future<(FakeDatingHomeGateway, FakeDatingLifecycleGateway)> _pump(
  WidgetTester t,
  Widget Function() screen,
  DatingHome state,
) async {
  await t.pumpWidget(const SizedBox());
  final home = FakeDatingHomeGateway(home: state);
  final life = FakeDatingLifecycleGateway();
  await pumpFlowScreen(
    t,
    screen,
    overrides: [
      ...datingShellOverrides(home: home, life: life),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(
        HomeStateService(FakeHomeStateGateway(state: homeJson(path: 'dating'))),
      ),
    ],
  );
  return (home, life);
}

const _paused = DatingHome(state: DatingHomeState.paused);
const _closed = DatingHome(
  state: DatingHomeState.countryClosed,
  country: 'NG',
  notice: DatingNotice(available: true),
);

void main() {
  group('carry A: settle', () {
    testWidgets('Resume, paused again, Resume, paused again, Resume: three '
        'different keys', (t) async {
      final (home, life) = await _pump(t, _section, _paused);
      for (var i = 0; i < 3; i++) {
        // Paused again elsewhere (another phone, a guard): the home still
        // reads paused after this Resume.
        home.home = _paused;
        await tapInReach(t, find.text('Resume'));
        await t.pumpAndSettle();
      }
      expect(life.calls, ['resume', 'resume', 'resume']);
      expect(life.keys.toSet(), hasLength(3));
    });

    testWidgets('a busy or failed Resume keeps its key; the answer after it '
        'settles it', (t) async {
      final (_, life) = await _pump(t, _section, _paused);
      for (final error in [
        DatingLifecycleError.busy,
        DatingLifecycleError.failed,
      ]) {
        life.result = DatingLifecycleResult.refused(error);
        await tapInReach(t, find.text('Resume'));
        await t.pumpAndSettle();
      }
      // The retry that gets through is still the same request...
      life.result = const DatingLifecycleResult.done('paused');
      await tapInReach(t, find.text('Resume'));
      await t.pumpAndSettle();
      // ...and the tap after a final answer is a new one.
      await tapInReach(t, find.text('Resume'));
      await t.pumpAndSettle();
      expect(life.keys, hasLength(4));
      expect(life.keys.take(3).toSet(), hasLength(1));
      expect(life.keys[3], isNot(life.keys[0]));
    });

    testWidgets('a named refusal is final: the next tap is a new request', (
      t,
    ) async {
      final (_, life) = await _pump(t, _section, _paused);
      life.result = const DatingLifecycleResult.refused(
        DatingLifecycleError.resumeGatesNotMet,
      );
      await tapInReach(t, find.text('Resume'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Resume'));
      await t.pumpAndSettle();
      expect(life.keys, hasLength(2));
      expect(life.keys[1], isNot(life.keys[0]));
    });
  });

  group('carry B: the notice answers', () {
    test('the repository maps not_eligible and rate_limited', () async {
      for (final (reason, result) in [
        ('not_eligible', DatingNoticeResult.notEligible),
        ('rate_limited', DatingNoticeResult.rateLimited),
      ]) {
        final s = ScriptedRpc([
          (_, __) => {'ok': false, 'reason': reason},
        ]);
        expect(
          await DatingHomeRepository(s.rpc).requestNotice('NG'),
          result,
          reason: reason,
        );
      }
    });

    test('the words never name the feature, blame or say "they"', () {
      final loc = AppLocalizationsEn();
      for (final text in [
        loc.dating_errorRateLimited,
        loc.dating_noticeNotEligible,
      ]) {
        final lower = text.toLowerCase();
        expect(lower, isNot(contains('dating')), reason: text);
        expect(lower, isNot(contains('they')), reason: text);
        expect(lower, isNot(contains('your fault')), reason: text);
      }
    });

    for (final (result, text) in [
      (DatingNoticeResult.rateLimited, _rateLimited),
      (DatingNoticeResult.notEligible, _notEligible),
    ]) {
      testWidgets('the section: ${result.name} has its own calm words', (
        t,
      ) async {
        final (home, _) = await _pump(t, _section, _closed);
        home.noticeResult = result;
        await tapInReach(t, find.text("Tell me when it's here"));
        await t.pumpAndSettle();
        expect(find.text(text), findsOneWidget);
        expect(find.text(_generic), findsNothing);
      });

      testWidgets('the not-open screen: ${result.name} has its own calm '
          'words', (t) async {
        final (home, _) = await _pump(
          t,
          () => const DatingNotOpenScreen(country: 'NG'),
          _closed,
        );
        home.noticeResult = result;
        await tapInReach(t, find.text("Tell me when it's here"));
        await t.pumpAndSettle();
        expect(find.text(text), findsOneWidget);
        expect(find.text(_generic), findsNothing);
      });
    }
  });
}
