import 'package:attune/features/dating/data/dating_home.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every server state maps; an unknown or missing one is unavailable '
      '(fail closed: never "you\'re live")', () {
    for (final s in DatingHomeState.values) {
      expect(DatingHome.fromJson({'state': s.wire}).state, s);
    }
    expect(
      DatingHome.fromJson({'state': 'verifying'}).state,
      DatingHomeState.unavailable,
    );
    expect(DatingHome.fromJson({}).state, DatingHomeState.unavailable);
  });

  test('a closed country carries its notice', () {
    final h = DatingHome.fromJson({
      'state': 'region_closed',
      'country': 'GH',
      'region': 'TV',
      'open_regions': ['AA', 'AH'],
      'notify': {'available': true, 'requested': true},
    });
    expect(h.country, 'GH');
    expect(h.region, 'TV');
    expect(h.openRegions, ['AA', 'AH']);
    expect(h.notice.available, isTrue);
    expect(h.notice.requested, isTrue);
    expect(
      DatingHome.fromJson({'state': 'country_closed'}).notice.available,
      isFalse,
    );
  });

  test('every pause reason maps; NULL and unknown are unknown (carry 9)', () {
    const wires = {
      'user': DatingPauseReason.user,
      'relationship': DatingPauseReason.relationship,
      'path_change': DatingPauseReason.pathChange,
      'same_gender_switch': DatingPauseReason.sameGenderSwitch,
      'away': DatingPauseReason.away,
      'account_parked': DatingPauseReason.accountParked,
      'gates': DatingPauseReason.gates,
    };
    for (final e in wires.entries) {
      expect(
        DatingHome.fromJson({
          'state': 'paused',
          'pause_reason': e.key,
        }).pauseReason,
        e.value,
      );
    }
    expect(
      DatingHome.fromJson({
        'state': 'paused',
        'pause_reason': null,
      }).pauseReason,
      DatingPauseReason.unknown,
    );
    expect(
      DatingHome.fromJson({
        'state': 'paused',
        'pause_reason': 'age_review',
      }).pauseReason,
      DatingPauseReason.unknown,
    );
  });

  test('has_data is read in any state, and is false when missing (C-2)', () {
    expect(
      DatingHome.fromJson({'state': 'restricted', 'has_data': true}).hasData,
      isTrue,
    );
    expect(DatingHome.fromJson({'state': 'not_started'}).hasData, isFalse);
  });

  test('the dates are read as instants', () {
    final h = DatingHome.fromJson({
      'state': 'gentle_wait',
      'ended_at': '2026-11-01T10:00:00+00:00',
      'opens_at': '2026-12-01T10:00:00+00:00',
      'first_drop_at': '2026-12-01T19:00:00+00:00',
      'can_shorten': true,
      'next_step': 'where',
    });
    expect(h.endedAt, DateTime.utc(2026, 11, 1, 10));
    expect(h.opensAt, DateTime.utc(2026, 12, 1, 10));
    expect(h.firstDropAt, DateTime.utc(2026, 12, 1, 19));
    expect(h.canShorten, isTrue);
    expect(h.nextStep, 'where');
  });

  test('M-8: hasProfile is true only in the states with a profile', () {
    const withProfile = {
      DatingHomeState.setupInProgress,
      DatingHomeState.gentleWait,
      DatingHomeState.coolOff,
      DatingHomeState.active,
      DatingHomeState.paused,
    };
    for (final s in DatingHomeState.values) {
      expect(
        DatingHome(state: s).hasProfile,
        withProfile.contains(s),
        reason: s.wire,
      );
    }
  });

  test('availability: GB open everywhere, GH in two regions', () {
    final a = DatingAvailability.fromJson({
      'countries': [
        {'code': 'GB', 'open_regions': null},
        {
          'code': 'GH',
          'open_regions': [
            {'code': 'AA', 'name_key': 'dating_region_gh_aa'},
            {'code': 'AH', 'name_key': 'dating_region_gh_ah'},
          ],
        },
      ],
    });
    expect(a.countries.map((c) => c.code), ['GB', 'GH']);
    expect(a.countries.first.openRegionKeys, isNull);
    expect(a.countries.last.openRegionKeys, [
      'dating_region_gh_aa',
      'dating_region_gh_ah',
    ]);
    expect(a.isOpen('GH'), isTrue);
    expect(a.isOpen('NG'), isFalse);
  });
}
