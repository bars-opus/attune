// Spec 2 W4a (§3.3, D8): the verification answers read fail-closed; the
// repository sends the action and the consent, never shows a server's
// text, and answers `failed` on any error; one status entry per account.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';
import 'package:attune/features/dating/verify/dating_verification_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, PostgrestException, StorageException;

import '../support/dating_verify_fakes.dart';

void main() {
  group('the answers, fail closed', () {
    test('a status that is not ok, or not an object, runs nothing', () {
      for (final raw in [
        null,
        'x',
        <String, Object?>{},
        {'ok': false},
        // Fix round 1 (M-2): a refusal's other fields are never read.
        {'ok': false, 'available': true, 'age': 'pass', 'identity': 'pass'},
      ]) {
        final v = DatingVerification.fromJson(raw);
        expect(v.available, isFalse, reason: '$raw');
        expect(v.verified, isFalse, reason: '$raw');
      }
    });

    test('a full status reads every field; unknown codes are none', () {
      final v = DatingVerification.fromJson({
        'ok': true,
        'available': true,
        'device': 'trusted',
        'age': 'pass',
        'identity': 'review',
        'session': {
          'id': 's-1',
          'kind': 'activation',
          'step': 'human',
          'state': 'awaiting_review',
          'attempts': 0,
          'outcome': 'human_pending',
          'position': null,
          'open': true,
          'gestures': ['left_ear', 'thumbs_up'],
        },
        'id_documents': [
          {'code': 'ghana_card', 'name_key': 'dating_id_ghana_card'},
          {'code': 7},
        ],
        'photos_ready': true,
      });
      expect(v.available, isTrue);
      expect(v.trustedDevice, isTrue);
      expect(v.age, DatingCheck.pass);
      expect(v.identity, DatingCheck.review);
      expect(v.verified, isFalse);
      expect(v.waiting, isTrue);
      expect(v.session!.gestures, ['left_ear', 'thumbs_up']);
      expect(v.session!.outcome, DatingVerifyOutcome.humanPending);
      expect(v.idDocuments.map((d) => d.code), ['ghana_card']);
      expect(DatingCheck.of('passed'), DatingCheck.none);
      expect(DatingVerifyOutcome.of('you_are_in'), DatingVerifyOutcome.unknown);
      expect(DatingVerifyRefusal.of('server text'), DatingVerifyRefusal.failed);
    });

    test(
      'R-13: a failed or an uncertain estimate reads as its own outcome',
      () {
        expect(DatingVerifyOutcome.of('needs_id'), DatingVerifyOutcome.needsId);
        expect(
          DatingVerifyOutcome.of('age_uncertain'),
          DatingVerifyOutcome.ageUncertain,
        );
      },
    );

    test('an untrusted device reads as such (W4b)', () {
      final v = DatingVerification.fromJson({
        'ok': true,
        'device': 'untrusted',
        'available': true,
        'session': null,
      });
      expect(v.trustedDevice, isFalse);
      expect(v.session, isNull);
      // Fix round 1 (M-1): a missing or unknown device is not trusted.
      for (final device in [null, 'unbound', 7]) {
        expect(
          DatingVerification.fromJson({
            'ok': true,
            'available': true,
            if (device != null) 'device': device,
          }).trustedDevice,
          isFalse,
          reason: '$device',
        );
      }
    });

    // Task 3 deviation (T1 fix round 1, M-2; contract E2): get_dating_home
    // says can_resume false while a verification pause's age check fails
    // and true once a new check passes, and resume_dating_mode then
    // resumes it; so Resume shows only when can_resume is true AND the
    // reason allows it, the rule of a relationship pause.
    test('the home reads verifying, and a verification pause offers Resume '
        'only once the server says the check holds (carry 1)', () {
      final h = DatingHome.fromJson({'state': 'verifying', 'has_data': true});
      expect(h.state, DatingHomeState.verifying);
      expect(h.hasProfile, isTrue);
      for (final (canResume, offered) in const [
        (true, true),
        (false, false),
        (null, false),
      ]) {
        final p = DatingHome.fromJson({
          'state': 'paused',
          'pause_reason': 'verification',
          if (canResume != null) 'can_resume': canResume,
        });
        expect(p.pauseReason, DatingPauseReason.verification);
        expect(p.resumeOffered, offered, reason: 'can_resume $canResume');
      }
    });

    // Task 3 addition: the codes dating-verification and the session
    // table can send all have a name here, so none falls to the generic
    // failed / unknown answer and every one gets its own calm copy.
    test('every fixed code the server can send has a name here', () {
      final handler =
          File(
            'supabase/functions/dating-verification/handler.ts',
          ).readAsStringSync();
      // Fix round 1 (M-3): the newest Dating migration that (re)states the
      // session outcome CHECK, so a later batch's change is the one read.
      final checkOf = RegExp(r'outcome IS NULL OR outcome IN \(([^)]*)\)');
      final migration = (Directory('supabase/migrations')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('dating'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
          .map((f) => f.readAsStringSync())
          .lastWhere(checkOf.hasMatch);
      List<String> quoted(String text, String q) => [
        for (final m in RegExp('$q([a-z_]+)$q').allMatches(text)) m.group(1)!,
      ];
      final reasons = quoted(
        RegExp(
          r'const FIXED_REASONS = new Set\(\[([^\]]*)\]\)',
        ).firstMatch(handler)!.group(1)!,
        '"',
      );
      expect(reasons, containsAll(['busy', 'vendor_unavailable']));
      for (final r in reasons) {
        expect(DatingVerifyRefusal.of(r).wire, r, reason: r);
      }
      final outcomes = {
        ...quoted(
          RegExp(
            r'const VIDEO_OUTCOMES[^\n]*new Set\(\[([^\]]*)\]\)',
          ).firstMatch(handler)!.group(1)!,
          '"',
        ),
        // Fix round 1 (M-3): every literal an `outcome:` value can take
        // (a ternary's both branches included), and every comparison.
        for (final m in RegExp(r'outcome: ([^,}\n]+)').allMatches(handler))
          ...quoted(m.group(1)!, '"'),
        for (final m in RegExp(
          r'(?<!typeof \w+\.)outcome === "([a-z_]+)"',
        ).allMatches(handler))
          m.group(1)!,
        ...quoted(checkOf.allMatches(migration).last.group(1)!, "'"),
      };
      expect(outcomes, containsAll(['pending', 'id_pending', 'age_uncertain']));
      for (final o in outcomes) {
        expect(DatingVerifyOutcome.of(o).wire, o, reason: o);
      }
    });
  });

  group('the repository', () {
    late List<(String, Map<String, dynamic>?)> rpcs;
    late List<Map<String, Object?>> invokes;
    late List<String> uploads;
    Object? rpcAnswer;
    Object? rpcError;
    Object? invokeAnswer;
    Object? invokeError;
    var invokeHangs = false;

    DatingVerificationRepository repo() => DatingVerificationRepository(
      DatingRpc.withCall((fn, params) async {
        rpcs.add((fn, params));
        if (rpcError != null) throw rpcError!;
        return rpcAnswer;
      }),
      (body) async {
        invokes.add(body);
        if (invokeError != null) throw invokeError!;
        if (invokeHangs) return Completer<Object?>().future;
        return invokeAnswer;
      },
      (path, jpeg) async {
        if (path.contains('fail')) throw StateError('storage');
        // Fix round 1 (I-4): storage-api's answer to an object already there.
        if (path.contains('dup')) {
          throw const StorageException(
            'The resource already exists',
            statusCode: '409',
            error: 'Duplicate',
          );
        }
        if (path.contains('denied')) {
          throw const StorageException(
            'new row violates row-level security policy',
            statusCode: '403',
            error: 'Unauthorized',
          );
        }
        uploads.add(path);
      },
    );

    setUp(() {
      rpcs = [];
      invokes = [];
      uploads = [];
      rpcAnswer = null;
      rpcError = null;
      invokeAnswer = null;
      invokeError = null;
      invokeHangs = false;
    });

    test(
      'status: get_my_dating_verification; an error is unavailable',
      () async {
        rpcAnswer = {'ok': true, 'available': true};
        expect((await repo().status()).available, isTrue);
        expect(rpcs.single.$1, 'get_my_dating_verification');
        rpcError = StateError('network');
        expect((await repo().status()).available, isFalse);
      },
    );

    test(
      'consent: biometric_verification, granted; refusals by name',
      () async {
        expect((await repo().consent('k-1')).ok, isTrue);
        expect(rpcs.single.$1, 'record_dating_consent');
        expect(rpcs.single.$2, {
          'p_idempotency_key': 'k-1',
          'p_purpose': 'biometric_verification',
          'p_action': 'granted',
          'p_policy_version': datingBiometricPolicyVersion,
          'p_categories': ['face'],
        });
        rpcError = const PostgrestException(message: 'reverify_device');
        expect((await repo().consent('k-2')).reason, 'reverify_device');
        rpcError = const PostgrestException(message: 'invalid_consent_event');
        expect((await repo().consent('k-3')).reason, 'failed');
        rpcError = const PostgrestException(message: 'dating:busy');
        expect((await repo().consent('k-4')).reason, 'busy');
      },
    );

    test('act: the action and body to the edge function; any error is '
        'failed, never its text', () async {
      invokeAnswer = {
        'ok': true,
        'session_id': 's-1',
        'vendor': 'fake',
        'vendor_session': 'ref-1',
      };
      final a = await repo().act('start', {'scenario': 'pass'});
      expect(invokes.single, {'scenario': 'pass', 'action': 'start'});
      expect(
        [a.ok, a.sessionId, a.vendor, a.vendorRef],
        [true, 's-1', 'fake', 'ref-1'],
      );
      invokeAnswer = {'ok': false, 'reason': 'duplicate key value violates'};
      expect((await repo().act('start')).refusal, DatingVerifyRefusal.failed);
      invokeAnswer = {'ok': false, 'reason': 'rate_limited'};
      expect(
        (await repo().act('start')).refusal,
        DatingVerifyRefusal.rateLimited,
      );
      invokeError = StateError('FunctionException 500');
      expect(
        (await repo().act('complete')).refusal,
        DatingVerifyRefusal.failed,
      );
    });

    // Fix round 1 (I-1): an edge error's own fixed-code body is read (index.ts
    // answers a 500 with {ok:false, reason:'busy'}); anything else in it,
    // or a body that isn't an answer, is failed.
    test('an edge error answers its own fixed code, else failed', () async {
      invokeError = const FunctionException(
        status: 500,
        details: {'ok': false, 'reason': 'busy'},
      );
      expect((await repo().act('complete')).refusal, DatingVerifyRefusal.busy);
      for (final details in [
        {'ok': false, 'reason': 'unauthorized'},
        {'ok': true, 'outcome': 'verified'},
        'Internal Server Error',
        null,
      ]) {
        invokeError = FunctionException(status: 500, details: details);
        final a = await repo().act('complete');
        expect(
          [a.ok, a.refusal],
          [false, DatingVerifyRefusal.failed],
          reason: '$details',
        );
      }
    });

    // Fix round 1 (I-2): the edge may work until its 150 s wall clock
    // (vendor tries until 100 s, busy waits until 130 s); the app waits
    // past it, and a call that never answers is busy (its outcome is
    // unknown, so the status is read again), never failed.
    testWidgets('an edge call waits past the edge budget, then is busy', (
      t,
    ) async {
      expect(
        DatingVerificationRepository.actTimeout,
        greaterThan(const Duration(seconds: 150)),
      );
      // (testWidgets: the timers run on its fake clock.)
      invokeHangs = true;
      DatingVerifyAnswer? answer;
      unawaited(
        repo().act('complete', {'session_id': 's-1'}).then((a) => answer = a),
      );
      await t.pump(const Duration(seconds: 150));
      expect(answer, isNull);
      await t.pump(const Duration(seconds: 6));
      expect([answer?.ok, answer?.refusal], [false, DatingVerifyRefusal.busy]);
      expect(answer!.readStatusAgain, isTrue);
    });

    // Fix round 1 (I-3): every route's raw answer, through act.
    test('act reads every route answer from the wire', () async {
      invokeAnswer = {
        'ok': true,
        'session_id': 's-2',
        'vendor': 'fake',
        'vendor_job': 'job-1',
        'resumed': true,
      };
      final id = await repo().act('start_id', {'document': 'passport'});
      expect(
        [id.ok, id.sessionId, id.vendor, id.vendorRef, id.resumed],
        [true, 's-2', 'fake', 'job-1', true],
      );
      invokeAnswer = {
        'ok': true,
        'session_id': 's-3',
        'gestures': ['left_ear', 'thumbs_up', 7],
        'paths': ['s-3/1.jpg', 's-3/2.jpg'],
        'resumed': false,
      };
      final human = await repo().act('human_start');
      expect(human.gestures, ['left_ear', 'thumbs_up']);
      expect(human.paths, ['s-3/1.jpg', 's-3/2.jpg']);
      expect(human.resumed, isFalse);
      invokeAnswer = {'ok': true, 'outcome': 'photo_mismatch', 'position': 3};
      final mismatch = await repo().act('complete', {'session_id': 's-1'});
      expect(
        [mismatch.ok, mismatch.outcome, mismatch.position, mismatch.refusal],
        [true, DatingVerifyOutcome.photoMismatch, 3, null],
      );
      invokeAnswer = {'ok': true, 'outcome': 'retry', 'attempts': 1};
      final retry = await repo().act('complete', {'session_id': 's-1'});
      expect(
        [retry.outcome, retry.attempts, retry.position],
        [DatingVerifyOutcome.retry, 1, null],
      );
    });

    test('a review photo that did not land is false', () async {
      expect(
        await repo().uploadReviewPhoto('s/1.jpg', Uint8List.fromList([1])),
        isTrue,
      );
      expect(
        await repo().uploadReviewPhoto('fail/2.jpg', Uint8List.fromList([1])),
        isFalse,
      );
      expect(uploads, ['s/1.jpg']);
      // Fix round 1 (I-4): the same path already stored is the person's own
      // earlier upload (dating_review_upload_open keeps every path to the
      // caller's open session): landed, so a retry after a lost answer
      // goes on. Any other storage refusal did not land.
      expect(
        await repo().uploadReviewPhoto('dup/1.jpg', Uint8List.fromList([1])),
        isTrue,
      );
      expect(
        await repo().uploadReviewPhoto('denied/1.jpg', Uint8List.fromList([1])),
        isFalse,
      );
    });

    // Fix round 1 (I-2): when the app reads the status again.
    test('busy, failed and a closed session read the status again', () {
      const again = {
        DatingVerifyRefusal.busy,
        DatingVerifyRefusal.failed,
        DatingVerifyRefusal.sessionUnavailable,
      };
      for (final r in DatingVerifyRefusal.values) {
        expect(
          DatingVerifyAnswer(ok: false, refusal: r).readStatusAgain,
          again.contains(r),
          reason: r.name,
        );
      }
      expect(DatingVerifyAnswer.failed.readStatusAgain, isTrue);
      expect(const DatingVerifyAnswer(ok: true).readStatusAgain, isFalse);
    });

    // Fix round 1 (M-6): a settled reason never reads a failure as final.
    test('the reason to settle a key with: failed is never the empty code', () {
      expect(DatingVerifyAnswer.failed.settleReason, 'failed');
      expect(
        const DatingVerifyAnswer(ok: false).settleReason,
        'failed',
        reason: 'no refusal named',
      );
      expect(
        const DatingVerifyAnswer(
          ok: false,
          refusal: DatingVerifyRefusal.rateLimited,
        ).settleReason,
        'rate_limited',
      );
      expect(const DatingVerifyAnswer(ok: true).settleReason, isNull);
    });
  });

  test(
    'D8: the next account reads its own state, nothing of the last',
    () async {
      final gateway = FakeDatingVerificationGateway(
        state: const DatingVerification(available: true, age: DatingCheck.pass),
      );
      final account = StateProvider<String?>((ref) => 'ama');
      final c = ProviderContainer(
        overrides: [
          datingAccountProvider.overrideWith((ref) => ref.watch(account)),
          datingVerificationGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(
        datingVerificationProvider(c.read(datingAccountProvider)),
        (_, __) {},
      );
      expect(
        (await c.read(datingVerificationProvider('ama').future)).age,
        DatingCheck.pass,
      );
      gateway.hold = Completer<DatingVerification>();
      c.read(account.notifier).state = 'kofi';
      final next = c.read(datingVerificationProvider('kofi'));
      expect(next.hasValue, isFalse, reason: 'nothing of the last account');
      gateway.hold!.complete(const DatingVerification(available: true));
      expect(
        (await c.read(datingVerificationProvider('kofi').future)).age,
        DatingCheck.none,
      );
      sub.close();
      expect(
        await c.read(datingVerificationProvider(null).future),
        same(DatingVerification.unavailable),
      );
    },
  );

  // Fix round 1 (I-2): after a busy, failed or closed-session answer the
  // flow reads the person's own status again (the server may have moved
  // on while the answer was lost).
  testWidgets('the status is read again for this account on request', (
    t,
  ) async {
    final gateway = FakeDatingVerificationGateway(
      state: const DatingVerification(available: true),
    );
    late WidgetRef captured;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          datingAccountProvider.overrideWithValue('ama'),
          datingVerificationGatewayProvider.overrideWithValue(gateway),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            ref.watch(datingVerificationProvider('ama'));
            return const SizedBox();
          },
        ),
      ),
    );
    await t.pump();
    expect(gateway.reads, 1);
    gateway.state = const DatingVerification(
      available: true,
      age: DatingCheck.pass,
      identity: DatingCheck.pass,
    );
    final v = await captured.rereadDatingVerification('ama');
    expect(v.verified, isTrue);
    expect(gateway.reads, 2);
  });
}
