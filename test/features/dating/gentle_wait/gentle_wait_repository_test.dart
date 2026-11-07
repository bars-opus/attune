// Spec 2 W2: D0's repository (§3.2 D0, §4.4). What the two reflection RPCs
// answer, mapped for the screen: the answers and the dates read, the save's
// reasons, and `busy` (B3 fix round 1: the clear answers {ok:false,
// reason:'busy'}; a save behind a switch raises dating:busy, retried once)
// becoming a calm retry, never an error.
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Answers each call from [answers] in turn (an [Exception] is thrown).
class _Rpc {
  _Rpc(this.answers);

  final List<Object?> answers;
  final calls = <(String, Map<String, dynamic>?)>[];

  Future<dynamic> call(String fn, Map<String, dynamic>? params) async {
    calls.add((fn, params));
    final next = answers.removeAt(0);
    if (next is Exception) throw next;
    return next;
  }
}

const _busy = PostgrestException(message: 'dating:busy', code: '55P03');

void main() {
  group('read', () {
    test('reads the answers and both dates; ignores anything else', () async {
      final rpc = _Rpc([
        {
          'ok': true,
          'answers': {'q1': 'Patience', 'q3': 7, 'q9': 'stray'},
          'saved_at': '2026-11-02T10:00:00Z',
          'ended_at': '2026-11-01T12:00:00Z',
          'opens_at': '2026-12-01T12:00:00Z',
        },
      ]);
      final wait = await GentleWaitRepository.withRpc(rpc.call).read();
      expect(rpc.calls.single.$1, 'get_my_gentle_wait_reflection');
      expect(wait.answers, {'q1': 'Patience'});
      expect(wait.endedAt, DateTime.utc(2026, 11, 1, 12));
      expect(wait.opensAt, DateTime.utc(2026, 12, 1, 12));
    });

    test('can_shorten: only a literal true promises the shortcut (final '
        'review M-4)', () async {
      final rpc = _Rpc([
        {'ok': true, 'answers': {}, 'can_shorten': true},
        {'ok': true, 'answers': {}, 'can_shorten': false},
        {'ok': true, 'answers': {}},
        {'ok': true, 'answers': {}, 'can_shorten': 'true'},
      ]);
      final repo = GentleWaitRepository.withRpc(rpc.call);
      expect(
        [for (var i = 0; i < 4; i++) (await repo.read()).canShorten],
        [true, false, false, false],
      );
    });

    test('after the wait: no dates', () async {
      final rpc = _Rpc([
        {'ok': true, 'answers': {}, 'ended_at': null, 'opens_at': null},
      ]);
      final wait = await GentleWaitRepository.withRpc(rpc.call).read();
      expect(wait.endedAt, isNull);
      expect(wait.opensAt, isNull);
      expect(wait.answers, isEmpty);
    });

    test('ok:false is unavailable, with its reason', () async {
      final rpc = _Rpc([
        {'ok': false, 'reason': 'reverify_device'},
      ]);
      await expectLater(
        GentleWaitRepository.withRpc(rpc.call).read(),
        throwsA(
          isA<GentleWaitUnavailable>().having(
            (e) => e.reason,
            'reason',
            'reverify_device',
          ),
        ),
      );
    });

    test('dating:busy once is retried silently', () async {
      final rpc = _Rpc([
        _busy,
        {
          'ok': true,
          'answers': {'q2': 'Kind'},
        },
      ]);
      final wait = await GentleWaitRepository.withRpc(rpc.call).read();
      expect(rpc.calls, hasLength(2));
      expect(wait.answers, {'q2': 'Kind'});
    });

    test(
      'dating:busy twice is busy (a calm retry), never a raw error',
      () async {
        final rpc = _Rpc([_busy, _busy]);
        await expectLater(
          GentleWaitRepository.withRpc(rpc.call).read(),
          throwsA(isA<GentleWaitBusy>()),
        );
        expect(rpc.calls, hasLength(2));
      },
    );

    test('any other server error is not busy', () async {
      final rpc = _Rpc([const PostgrestException(message: 'boom')]);
      await expectLater(
        GentleWaitRepository.withRpc(rpc.call).read(),
        throwsA(isA<PostgrestException>()),
      );
      expect(rpc.calls, hasLength(1));
    });
  });

  group('save', () {
    test('sends the three answers as p_answers', () async {
      final rpc = _Rpc([
        {'ok': true, 'saved_at': '2026-11-02T10:00:00Z'},
      ]);
      final result = await GentleWaitRepository.withRpc(
        rpc.call,
      ).save({'q1': 'a', 'q2': '', 'q3': 'c'});
      expect(result, GentleWaitSave.saved);
      expect(rpc.calls.single.$1, 'save_gentle_wait_reflection');
      expect(rpc.calls.single.$2, {
        'p_answers': {'q1': 'a', 'q2': '', 'q3': 'c'},
      });
    });

    for (final (reason, expected) in [
      ('not_eligible', GentleWaitSave.notEligible),
      ('reverify_device', GentleWaitSave.reverifyDevice),
      ('busy', GentleWaitSave.busy),
      ('invalid', GentleWaitSave.failed),
      (null, GentleWaitSave.failed),
    ]) {
      test('reason $reason is $expected', () async {
        final rpc = _Rpc([
          {'ok': false, 'reason': reason},
        ]);
        final result = await GentleWaitRepository.withRpc(
          rpc.call,
        ).save(const {'q1': '', 'q2': '', 'q3': ''});
        expect(result, expected);
      });
    }

    test('dating:busy once is retried, then saved', () async {
      final rpc = _Rpc([
        _busy,
        {'ok': true},
      ]);
      final result = await GentleWaitRepository.withRpc(
        rpc.call,
      ).save(const {'q1': 'a'});
      expect(result, GentleWaitSave.saved);
      expect(rpc.calls, hasLength(2));
    });

    test('dating:busy twice is busy, never failed', () async {
      final rpc = _Rpc([_busy, _busy]);
      final result = await GentleWaitRepository.withRpc(
        rpc.call,
      ).save(const {'q1': 'a'});
      expect(result, GentleWaitSave.busy);
      expect(rpc.calls, hasLength(2));
    });
  });

  group('clear (fix round 1, I-1)', () {
    test(
      "sends an empty object: the server's never-gated clear branch",
      () async {
        final rpc = _Rpc([
          {'ok': true, 'saved_at': null},
        ]);
        final result = await GentleWaitRepository.withRpc(rpc.call).clear();
        expect(result, GentleWaitSave.saved);
        expect(rpc.calls.single.$1, 'save_gentle_wait_reflection');
        expect(rpc.calls.single.$2, {'p_answers': <String, String>{}});
      },
    );

    test('busy is busy', () async {
      final rpc = _Rpc([
        {'ok': false, 'reason': 'busy'},
      ]);
      expect(
        await GentleWaitRepository.withRpc(rpc.call).clear(),
        GentleWaitSave.busy,
      );
    });

    test('dating:busy twice is busy', () async {
      final rpc = _Rpc([_busy, _busy]);
      expect(
        await GentleWaitRepository.withRpc(rpc.call).clear(),
        GentleWaitSave.busy,
      );
    });
  });
}
