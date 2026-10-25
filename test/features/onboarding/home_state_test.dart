// Spec 1 W1b (§5.1, §7.3): the HomeState model parses get_my_home_state()
// exactly as the SQL contract pins it, and maps paths and link states.
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a full server answer', () {
    final state = HomeState.fromJson({
      'has_account': true,
      'path': 'relationship',
      'tab': 'chat',
      'path_previous': 'just_me',
      'needs': <String>[],
      'hold': false,
      'eula_version': '2',
      'dating': {'enabled': true, 'enrolled': false},
      'link': {
        'state': 'ended_window',
        'relationship_id': '5f1a0000-0000-0000-0000-000000000103',
        'partner_first_name': 'Kwabena',
        'invite_expires_at': null,
        'window_ends_at': '2026-11-22T09:00:00+00:00',
      },
    });
    expect(state.path, AppPath.relationship);
    expect(state.pathPrevious, AppPath.justMe);
    expect(state.tab, AppTab.chat);
    expect(state.isComplete, isTrue);
    expect(state.dating.enabled, isTrue);
    expect(state.dating.enrolled, isFalse);
    expect(state.link.state, LinkState.endedWindow);
    expect(state.link.partnerFirstName, 'Kwabena');
    expect(state.link.windowEndsAt, DateTime.utc(2026, 11, 22, 9));
    expect(state.link.inviteExpiresAt, isNull);
  });

  test('every link state and need round-trips its wire value', () {
    for (final state in LinkState.values) {
      expect(LinkState.fromWire(state.wire), state);
    }
    expect(HomeNeed.listFromWire(['consent', 'birth_date', 'name', 'path']), [
      HomeNeed.consent,
      HomeNeed.birthDate,
      HomeNeed.name,
      HomeNeed.path,
    ]);
    expect(HomeNeed.fromWire(HomeNeed.unknown.wire), HomeNeed.unknown);
    expect(AppPath.fromWire('just_me'), AppPath.justMe);
  });

  test('unknown or missing values fall to the safe side', () {
    final state = HomeState.fromJson({
      'tab': 'dating',
      'needs': ['consent', 'telepathy'],
      'link': {'state': 'married'},
    });
    expect(state.hasAccount, isFalse);
    expect(state.isComplete, isFalse);
    expect(state.path, isNull);
    expect(state.tab, AppTab.me);
    // Final review M-5: the unknown need is kept as unknown, not skipped.
    expect(state.needs, [HomeNeed.consent, HomeNeed.unknown]);
    expect(state.hold, isFalse);
    expect(state.dating, same(DatingSummary.off));
    expect(state.link.state, LinkState.none);
  });

  test('path to tab: Relationship is Chat, Dating and Just for me are Me', () {
    expect(AppTab.forPath(AppPath.relationship), AppTab.chat);
    expect(AppTab.forPath(AppPath.dating), AppTab.me);
    expect(AppTab.forPath(AppPath.justMe), AppTab.me);
  });

  // Batch 4 extra: complete needs an account as well as no open needs.
  test('an answer without an account is never complete', () {
    final state = HomeState.fromJson({
      'has_account': false,
      'needs': <String>[],
    });
    expect(state.isComplete, isFalse);
  });

  // Final review M-5: a need this build doesn't know keeps the account
  // incomplete, so an older build never skips a later required step.
  test('an unknown need keeps the account incomplete', () {
    final state = HomeState.fromJson({
      'has_account': true,
      'needs': ['some_future_need'],
    });
    expect(state.isComplete, isFalse);
    expect(state.needs, [HomeNeed.unknown]);
  });
}
