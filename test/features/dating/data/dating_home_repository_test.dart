// Spec 2 W3a fix round 1 (review M-3, M-4, M-6): the real home repository
// over a scripted transport: each RPC's name and params, the notice answers,
// and a malformed answer failing closed.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/dating_fakes.dart';

typedef _Answer = Object? Function(String fn, Map<String, dynamic>? params);

PostgrestException _raised(String message) =>
    PostgrestException(message: message, code: '22023');

void main() {
  test('read calls get_dating_home with no params', () async {
    final s = ScriptedRpc([
      (_, __) => {'state': 'active', 'has_data': true},
    ]);
    final h = await DatingHomeRepository(s.rpc).read();
    expect(h.state, DatingHomeState.active);
    expect(h.hasData, isTrue);
    expect(s.calls.single.$1, 'get_dating_home');
    expect(s.calls.single.$2, isNull);
  });

  test('availability calls get_dating_availability with no params', () async {
    final s = ScriptedRpc([
      (_, __) => {
        'countries': [
          {'code': 'GB', 'open_regions': null},
        ],
      },
    ]);
    final a = await DatingHomeRepository(s.rpc).availability();
    expect(a.isOpen('GB'), isTrue);
    expect(s.calls.single.$1, 'get_dating_availability');
    expect(s.calls.single.$2, isNull);
  });

  test('M-6: an answer that is not an object fails closed, never '
      'throws', () async {
    for (final raw in <Object?>[
      null,
      'x',
      3,
      const [1],
    ]) {
      final home =
          await DatingHomeRepository(ScriptedRpc([(_, __) => raw]).rpc).read();
      expect(home.state, DatingHomeState.unavailable, reason: '$raw');
      expect(home.hasData, isFalse);
      final open =
          await DatingHomeRepository(
            ScriptedRpc([(_, __) => raw]).rpc,
          ).availability();
      expect(open.countries, isEmpty, reason: '$raw');
    }
  });

  test('requestNotice sends the country and the region', () async {
    final s = ScriptedRpc([
      (_, __) => {'ok': true},
      (_, __) => {'ok': true},
    ]);
    final repo = DatingHomeRepository(s.rpc);
    expect(
      await repo.requestNotice('GH', region: 'TV'),
      DatingNoticeResult.saved,
    );
    expect(await repo.requestNotice('NG'), DatingNoticeResult.saved);
    expect(s.calls.map((c) => c.$1), [
      'request_dating_country_notice',
      'request_dating_country_notice',
    ]);
    expect(s.calls.first.$2, {'p_country': 'GH', 'p_region': 'TV'});
    expect(s.calls.last.$2, {'p_country': 'NG', 'p_region': null});
  });

  test('cancelNotice calls the cancel RPC with no params', () async {
    final s = ScriptedRpc([
      (_, __) => {'ok': true},
    ]);
    expect(
      await DatingHomeRepository(s.rpc).cancelNotice(),
      DatingNoticeResult.saved,
    );
    expect(s.calls.single.$1, 'cancel_dating_country_notice');
    expect(s.calls.single.$2, isNull);
  });

  test('M-3: every notice answer maps; rate_limited is its own '
      'answer', () async {
    final cases = <(String, List<_Answer> Function(), DatingNoticeResult)>[
      (
        'ok',
        () => [
          (_, __) => {'ok': true},
        ],
        DatingNoticeResult.saved,
      ),
      (
        'already_open',
        () => [
          (_, __) => {'ok': false, 'reason': 'already_open'},
        ],
        DatingNoticeResult.alreadyOpen,
      ),
      (
        'invalid',
        () => [
          (_, __) => {'ok': false, 'reason': 'invalid', 'field': 'country'},
        ],
        DatingNoticeResult.invalid,
      ),
      (
        'rate_limited',
        () => [
          (_, __) => {'ok': false, 'reason': 'rate_limited'},
        ],
        DatingNoticeResult.rateLimited,
      ),
      (
        'busy answer',
        () => [
          (_, __) => {'ok': false, 'reason': 'busy'},
        ],
        DatingNoticeResult.busy,
      ),
      (
        'busy raised twice',
        () => [
          (_, __) => _raised('dating:busy'),
          (_, __) => _raised('dating:busy'),
        ],
        DatingNoticeResult.busy,
      ),
      (
        'raised',
        () => [(_, __) => _raised('something')],
        DatingNoticeResult.failed,
      ),
      (
        'unknown reason',
        () => [
          (_, __) => {'ok': false, 'reason': 'new_reason'},
        ],
        DatingNoticeResult.failed,
      ),
      ('null', () => [(_, __) => null], DatingNoticeResult.failed),
    ];
    for (final (name, answers, expected) in cases) {
      expect(
        await DatingHomeRepository(
          ScriptedRpc(answers()).rpc,
        ).requestNotice('GH'),
        expected,
        reason: 'request: $name',
      );
      expect(
        await DatingHomeRepository(ScriptedRpc(answers()).rpc).cancelNotice(),
        expected,
        reason: 'cancel: $name',
      );
    }
  });
}
