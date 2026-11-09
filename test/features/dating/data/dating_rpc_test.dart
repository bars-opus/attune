import 'dart:async';
import 'dart:convert';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/dating_fakes.dart';

PostgrestException _raised(String message) =>
    PostgrestException(message: message, code: '22023');

void main() {
  group('DatingRpc', () {
    test('dating:busy is retried once, silently', () async {
      final s = ScriptedRpc([
        (_, __) => _raised('dating:busy'),
        (_, __) => {'ok': true},
      ]);
      expect(await s.rpc.call('get_dating_home'), {'ok': true});
      expect(s.calls.length, 2);
    });

    test('a second dating:busy is DatingBusy', () async {
      final s = ScriptedRpc([
        (_, __) => _raised('dating:busy'),
        (_, __) => _raised('dating:busy'),
      ]);
      await expectLater(
        s.rpc.call('get_dating_home'),
        throwsA(isA<DatingBusy>()),
      );
    });

    test('any other refusal is raised as it came, never retried', () async {
      final s = ScriptedRpc([(_, __) => _raised('path_not_dating')]);
      await expectLater(
        s.rpc.call('resume_dating_mode'),
        throwsA(isA<PostgrestException>()),
      );
      expect(s.calls.length, 1);
    });

    testWidgets('M-8: a call that never answers ends at the 30 s bound', (
      tester,
    ) async {
      Object? error;
      DatingRpc.withCall((_, __) => Completer<dynamic>().future)
          .call('get_dating_home')
          .then<void>(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      await tester.pump(const Duration(seconds: 29));
      expect(error, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(error, isA<TimeoutException>());
    });
  });

  group('DatingLifecycleError (carries 1, 13)', () {
    final cases = {
      'path_not_dating': DatingLifecycleError.pathNotDating,
      'not_paused': DatingLifecycleError.notPaused,
      'activation_required': DatingLifecycleError.activationRequired,
      'resume_gates_not_met': DatingLifecycleError.resumeGatesNotMet,
      'activation_gates_not_met': DatingLifecycleError.activationGatesNotMet,
      'enrollment_incomplete': DatingLifecycleError.enrollmentIncomplete,
      'consent_required': DatingLifecycleError.consentRequired,
      'terms_consent_required': DatingLifecycleError.consentRequired,
      'dating_opt_in_required': DatingLifecycleError.consentRequired,
      'profile_or_preferences_incomplete':
          DatingLifecycleError.profileIncomplete,
      'reverify_device': DatingLifecycleError.reverifyDevice,
      'not_eligible': DatingLifecycleError.notEligible,
      'rate_limited': DatingLifecycleError.rateLimited,
      'something new': DatingLifecycleError.failed,
    };
    for (final entry in cases.entries) {
      test('${entry.key} -> ${entry.value.name}', () {
        expect(DatingLifecycleError.of(_raised(entry.key)), entry.value);
      });
    }
    test('busy and anything else', () {
      expect(
        DatingLifecycleError.of(const DatingBusy()),
        DatingLifecycleError.busy,
      );
      expect(
        DatingLifecycleError.of(StateError('x')),
        DatingLifecycleError.failed,
      );
    });
  });

  group('DatingWrite', () {
    test('ok with the next step', () {
      final w = DatingWrite.fromJson({'ok': true, 'next_step': 'where'});
      expect(w.ok, isTrue);
      expect(w.nextStep, 'where');
      expect(w.reason, isNull);
    });
    test('a refusal with its field and position', () {
      final w = DatingWrite.fromJson({
        'ok': false,
        'reason': 'contact_details',
        'position': 2,
      });
      expect(w.ok, isFalse);
      expect(w.reason, 'contact_details');
      expect(w.position, 2);
    });
    test('anything malformed is failed, never ok', () {
      expect(DatingWrite.fromJson(null).ok, isFalse);
      expect(DatingWrite.fromJson('ok').reason, 'failed');
      expect(DatingWrite.fromJson({'ok': 'true'}).ok, isFalse);
    });
    test('datingWrite maps DatingBusy and errors', () async {
      expect(
        (await datingWrite(() => throw const DatingBusy())).reason,
        'busy',
      );
      expect((await datingWrite(() => throw StateError('x'))).reason, 'failed');
    });
  });

  group('DatingActionKeys (Fable H3c)', () {
    test('a double tap sends one key; a changed answer a new one', () {
      var n = 0;
      final keys = DatingActionKeys(newKey: () => 'k${++n}');
      final a = keys.keyFor('d2', {'intention': 'marriage'});
      expect(keys.keyFor('d2', {'intention': 'marriage'}), a);
      final b = keys.keyFor('d2', {'intention': 'committed'});
      expect(b, isNot(a));
      expect(keys.keyFor('d3', {'intention': 'committed'}), isNot(b));
    });
    test('real keys fit the server rule (8-200 of [A-Za-z0-9_:.-])', () {
      final key = DatingActionKeys().keyFor('d2');
      expect(RegExp(r'^[A-Za-z0-9_:.-]{8,200}$').hasMatch(key), isTrue);
    });

    test('I-1: a settled action gets a fresh key (pause, resume, pause '
        'sends three keys)', () {
      var n = 0;
      final keys = DatingActionKeys(newKey: () => 'k${++n}');
      final pause = keys.keyFor('pause', 'ama');
      keys.settle('pause');
      final resume = keys.keyFor('resume', 'ama');
      keys.settle('resume');
      final again = keys.keyFor('pause', 'ama');
      expect({pause, resume, again}.length, 3);
      // A named refusal is a final answer too.
      keys.settle('pause', error: DatingLifecycleError.notPaused);
      expect(keys.keyFor('pause', 'ama'), isNot(again));
      final d2 = keys.keyFor('d2', {'intention': 'marriage'});
      keys.settle('d2', reason: 'contact_details');
      expect(keys.keyFor('d2', {'intention': 'marriage'}), isNot(d2));
    });

    test('I-1: busy or failed keeps the key, so the retry is the same '
        'request', () {
      var n = 0;
      final keys = DatingActionKeys(newKey: () => 'k${++n}');
      final pause = keys.keyFor('pause', 'ama');
      keys.settle('pause', error: DatingLifecycleError.busy);
      expect(keys.keyFor('pause', 'ama'), pause);
      keys.settle('pause', error: DatingLifecycleError.failed);
      expect(keys.keyFor('pause', 'ama'), pause);
      final d2 = keys.keyFor('d2', {'intention': 'marriage'});
      keys.settle('d2', reason: 'busy');
      expect(keys.keyFor('d2', {'intention': 'marriage'}), d2);
      keys.settle('d2', reason: 'failed');
      expect(keys.keyFor('d2', {'intention': 'marriage'}), d2);
    });

    test('I-1, D8: keys stay per account, and settling one action keeps '
        'the others', () {
      var n = 0;
      final keys = DatingActionKeys(newKey: () => 'k${++n}');
      final ama = keys.keyFor('pause', 'ama');
      final kofi = keys.keyFor('pause', 'kofi');
      expect(kofi, isNot(ama));
      expect(keys.keyFor('pause', 'kofi'), kofi);
      final resume = keys.keyFor('resume', 'kofi');
      keys.settle('pause');
      expect(keys.keyFor('resume', 'kofi'), resume);
      final next = keys.keyFor('pause', 'kofi');
      expect(next, isNot(kofi));
      expect(next, isNot(ama));
    });

    test('M-7: the signature is the payload as JSON, so an object with no '
        'value text is refused, never collided', () {
      final keys = DatingActionKeys();
      expect(
        () => keys.keyFor('d2', Object()),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });
  });
}
