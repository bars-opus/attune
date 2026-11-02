// Spec 1 W3a (§4.3 W1b, §3.15): the home's server calls, each refusal by
// its code, and every transient failure as "offline".
import 'dart:async';

import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_home_state.dart';

void main() {
  test('fetch reads get_my_home_state', () async {
    final gateway = FakeHomeStateGateway(
      state: homeJson(path: 'relationship', link: 'pending'),
    );
    final state = await HomeStateService(gateway).fetch();
    expect(gateway.calls.single.$1, 'get_my_home_state');
    expect(state.path, AppPath.relationship);
    expect(state.tab, AppTab.chat);
    expect(state.link.state, LinkState.pending);
  });

  test('setPath sends the wire value and the confirmation', () async {
    final gateway = FakeHomeStateGateway();
    await HomeStateService(gateway).setPath(AppPath.justMe);
    await HomeStateService(
      gateway,
    ).setPath(AppPath.relationship, confirmed: true);
    expect(gateway.calls.map((c) => c.$1), ['set_my_path', 'set_my_path']);
    expect(gateway.calls[0].$2, {'p_path': 'just_me', 'p_confirmed': false});
    expect(gateway.calls[1].$2, {
      'p_path': 'relationship',
      'p_confirmed': true,
    });
  });

  test('each set_my_path refusal is named', () async {
    for (final (message, reason) in [
      ('path:relationship_open', PathRefusal.relationshipOpen),
      ('path:confirm_withdraw', PathRefusal.confirmWithdraw),
      ('path:confirm_pause_dating', PathRefusal.confirmPauseDating),
      ('path:needs_signup', PathRefusal.needsSignUp),
      ('path:invalid', PathRefusal.invalid),
    ]) {
      final gateway =
          FakeHomeStateGateway()
            ..failNext = FakeHomeStateGateway.refusal(message);
      await expectLater(
        HomeStateService(gateway).setPath(AppPath.dating),
        throwsA(isA<PathRefused>().having((e) => e.reason, 'reason', reason)),
      );
    }
  });

  test('a transient failure is offline', () async {
    for (final failure in <Object>[
      TimeoutException('slow'),
      FakeHomeStateGateway.refusal(
        'canceling statement due to statement timeout',
      ),
    ]) {
      final gateway = FakeHomeStateGateway()..failNext = failure;
      await expectLater(
        HomeStateService(gateway).fetch(),
        throwsA(isA<HomeOffline>()),
      );
    }
  });

  test('the date of birth catch-up: ok, under 18, already set', () async {
    final gateway = FakeHomeStateGateway();
    final service = HomeStateService(gateway);
    expect(
      await service.setBirthDate(DateTime.utc(1991, 11, 8)),
      BirthDateOutcome.ok,
    );
    expect(gateway.calls.last.$2, {'p_birth_date': '1991-11-08'});
    gateway.birthDateStatus = 'not_eligible';
    expect(
      await service.setBirthDate(DateTime.utc(2012, 1, 1)),
      BirthDateOutcome.notEligible,
    );
    gateway.failNext = FakeHomeStateGateway.refusal('birth_date:already_set');
    expect(
      await service.setBirthDate(DateTime.utc(1991, 1, 1)),
      BirthDateOutcome.alreadySet,
    );
  });

  test('updated terms, the name and the withdrawal', () async {
    final gateway = FakeHomeStateGateway();
    final service = HomeStateService(gateway);
    await service.acceptUpdatedTerms();
    expect(gateway.calls.last.$1, 'record_eula_acceptance');
    expect(gateway.calls.last.$2, {'p_version': '2'});
    await service.saveDisplayName('u1', 'Ama');
    expect(gateway.savedNames.single, ('u1', 'Ama'));
    expect(await service.withdrawPendingInvites(returnToPreviousPath: true), 1);
    expect(gateway.calls.last.$1, 'withdraw_my_pending_invites');
    expect(gateway.calls.last.$2, {'p_return_to_previous_path': true});
  });
}
