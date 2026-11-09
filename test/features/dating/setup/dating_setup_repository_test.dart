import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/dating_fakes.dart';

void main() {
  test('the lists parse; a region knows whether it is open', () async {
    final s = ScriptedRpc([
      (_, __) => {
        'ok': true,
        'countries': [
          {
            'code': 'GH',
            'same_gender': false,
            'regions': [
              {
                'code': 'AA',
                'name_key': 'dating_region_gh_aa',
                'open': true,
                'sides': [
                  {'code': 'accra', 'name_key': 'dating_side_gh_accra'},
                ],
              },
              {
                'code': 'TV',
                'name_key': 'dating_region_gh_tv',
                'open': false,
                'sides': [],
              },
            ],
            'faiths': [
              {
                'code': 'christian',
                'name_key': 'dating_faith_christian',
                'denominations': [
                  {
                    'code': 'catholic',
                    'name_key': 'dating_denomination_catholic',
                  },
                ],
              },
            ],
          },
        ],
        'phone_country': 'GH',
        'note_country': 'GH',
        'default_ages': [25, 35],
      },
    ]);
    final lists = await DatingSetupRepository(s.rpc).lists();
    final gh = lists.country('GH')!;
    expect(gh.sameGender, isFalse);
    expect(gh.regions.map((r) => (r.code, r.open)), [
      ('AA', true),
      ('TV', false),
    ]);
    expect(gh.regions.first.sides.single.code, 'accra');
    expect(gh.faiths.single.denominations.single.code, 'catholic');
    expect(lists.noteCountry, 'GH');
    expect(lists.defaultAges, (25, 35));
    expect(s.calls.single.$1, 'get_dating_setup_lists');
  });

  test('D2 sends exactly the writer\'s parameters', () async {
    final s = ScriptedRpc([
      (_, __) => {'ok': true, 'next_step': 'where'},
    ]);
    final w = await DatingSetupRepository(s.rpc).saveIntention(
      'k-d2-000001',
      intention: 'marriage',
      timeline: 'few_years',
      timelineVisible: true,
      marital: 'divorced',
      maritalVisible: false,
    );
    expect(w.nextStep, 'where');
    // A record holding a Map compares the Map by identity: check each part.
    expect(s.calls.single.$1, 'save_dating_intention');
    expect(s.calls.single.$2, {
      'p_idempotency_key': 'k-d2-000001',
      'p_intention': 'marriage',
      'p_timeline': 'few_years',
      'p_timeline_visible': true,
      'p_attested': true,
      'p_marital': 'divorced',
      'p_marital_visible': false,
    });
  });

  test(
    'D4: three consents, then the enrolment, all under one key family',
    () async {
      final s = ScriptedRpc([
        (_, __) => null,
        (_, __) => null,
        (_, __) => null,
        (_, __) => {'state': 'profile_draft'},
      ]);
      final w = await DatingSetupRepository(s.rpc).agreeAndBegin('k-d4-000001');
      expect(w.ok, isTrue);
      expect(w.nextStep, 'you');
      expect(s.calls.map((c) => c.$1), [
        'record_dating_consent',
        'record_dating_consent',
        'record_dating_consent',
        'begin_dating_enrollment',
      ]);
      expect(s.calls.take(3).map((c) => c.$2!['p_purpose']), [
        'dating_terms',
        'dating_opt_in',
        'special_category_profile',
      ]);
      expect(
        s.calls.take(3).map((c) => c.$2!['p_idempotency_key']).toSet().length,
        3,
      );
      expect(s.calls.last.$2, {
        'p_terms_version': 'dating-2.0',
        'p_idempotency_key': 'k-d4-000001:begin',
      });
    },
  );

  test('D4 refused: its message is the reason', () async {
    final s = ScriptedRpc([
      (_, __) => PostgrestException(message: 'reverify_device', code: '22023'),
    ]);
    final w = await DatingSetupRepository(s.rpc).agreeAndBegin('k-d4-000002');
    expect(w.ok, isFalse);
    expect(w.reason, 'reverify_device');
  });

  test('D8: the faith consent, then the faith; Skip is the clear', () async {
    final s = ScriptedRpc([
      (_, __) => null,
      (_, __) => {'ok': true, 'next_step': 'photos'},
      (_, __) => {'ok': true, 'next_step': 'photos'},
    ]);
    final repo = DatingSetupRepository(s.rpc);
    await repo.saveFaith(
      'k-d8-000001',
      faith: 'christian',
      denomination: null,
      importance: 'must_share',
      visible: false,
    );
    await repo.clearFaith('k-d8-000002');
    expect(s.calls.map((c) => c.$1), [
      'record_dating_consent',
      'save_dating_faith',
      'clear_dating_faith',
    ]);
    expect(s.calls.first.$2!['p_purpose'], 'special_category_faith');
  });

  test('a busy server is busy, never ok', () async {
    final s = ScriptedRpc([
      (_, __) => PostgrestException(message: 'dating:busy', code: '55P03'),
      (_, __) => PostgrestException(message: 'dating:busy', code: '55P03'),
    ]);
    final w = await DatingSetupRepository(s.rpc).saveChildren(
      'k-d7-000001',
      have: true,
      want: 'open',
      mustMatch: false,
      excludeParents: false,
    );
    expect(w.reason, 'busy');
  });

  test(
    'my profile: a missing profile is empty, never another account\'s',
    () async {
      final s = ScriptedRpc([
        (_, __) => {'ok': true, 'profile': null},
      ]);
      expect(
        await DatingSetupRepository(s.rpc).myProfile(),
        const DatingMyProfile(),
      );
    },
  );

  // Task 1 review carry M-9: a raised message is server text and may carry
  // what the person typed, so a setup writer's reason is only ever a known
  // code; a lock error is busy; anything else is `failed`.
  group('a raised refusal never carries server text', () {
    const leaky =
        'new row violates check "dating_profiles_check": phone '
        '+233558703991 in Greater Accra';

    void expectNoInput(DatingWrite w) {
      expect(w.ok, isFalse);
      expect(w.reason, 'failed');
      expect(w.reason, isNot(contains('233558703991')));
      expect(w.reason, isNot(contains('Greater Accra')));
      expect(w.field, isNull);
    }

    test('D4: the consent or the enrolment', () async {
      final consent = ScriptedRpc([
        (_, __) => PostgrestException(message: leaky, code: '23514'),
      ]);
      expectNoInput(
        await DatingSetupRepository(consent.rpc).agreeAndBegin('k-d4-000003'),
      );
      final begin = ScriptedRpc([
        (_, __) => null,
        (_, __) => null,
        (_, __) => null,
        (_, __) => PostgrestException(message: leaky, code: '22023'),
      ]);
      expectNoInput(
        await DatingSetupRepository(begin.rpc).agreeAndBegin('k-d4-000004'),
      );
    });

    test('D8: the faith consent', () async {
      final s = ScriptedRpc([
        (_, __) => PostgrestException(message: leaky, code: '23514'),
      ]);
      expectNoInput(
        await DatingSetupRepository(s.rpc).saveFaith(
          'k-d8-000003',
          faith: 'christian',
          importance: 'must_share',
          visible: false,
        ),
      );
      expect(s.calls.single.$1, 'record_dating_consent');
    });

    test('D3: a writer that raises', () async {
      final s = ScriptedRpc([
        (_, __) => PostgrestException(message: leaky, code: '23514'),
      ]);
      expectNoInput(
        await DatingSetupRepository(s.rpc).saveLocation(
          'k-d3-000001',
          country: 'GH',
          region: 'AA',
          scope: 'region',
        ),
      );
    });

    test('a known code passes; an unknown one is failed', () async {
      final s = ScriptedRpc([
        (_, __) =>
            PostgrestException(message: 'path_not_dating', code: '22023'),
        (_, __) => PostgrestException(message: 'rate_limited', code: '22023'),
        (_, __) => PostgrestException(message: 'some_new_code', code: '22023'),
      ]);
      final repo = DatingSetupRepository(s.rpc);
      expect(
        (await repo.agreeAndBegin('k-d4-000005')).reason,
        'path_not_dating',
      );
      expect((await repo.agreeAndBegin('k-d4-000006')).reason, 'rate_limited');
      expect((await repo.agreeAndBegin('k-d4-000007')).reason, 'failed');
    });

    test('a lock error is busy, never ok and never its message', () async {
      for (final code in ['55P03', '40P01', '40001']) {
        final s = ScriptedRpc([
          (_, __) => PostgrestException(
            message: 'canceling statement due to lock timeout',
            code: code,
          ),
          (_, __) =>
              PostgrestException(message: 'deadlock detected', code: code),
          (_, __) => PostgrestException(
            message: 'could not serialize access',
            code: code,
          ),
        ]);
        final repo = DatingSetupRepository(s.rpc);
        expect((await repo.agreeAndBegin('k-d4-1$code')).reason, 'busy');
        expect(
          (await repo.saveFaith(
            'k-d8-1$code',
            faith: 'none',
            importance: 'nice_to_share',
            visible: false,
          )).reason,
          'busy',
        );
        expect((await repo.clearFaith('k-d8-2$code')).reason, 'busy');
      }
    });
  });

  // T5 fix round 1 (M-6): D4 goes on only with an enrolment it can set up.
  test('D4: a suspended, exited or empty enrolment is not ok', () async {
    for (final row in <Object?>[
      {'state': 'suspended'},
      {'state': 'exited'},
      {'state': null},
      null,
      'profile_draft',
    ]) {
      final s = ScriptedRpc([
        (_, __) => null,
        (_, __) => null,
        (_, __) => null,
        (_, __) => row,
      ]);
      final w = await DatingSetupRepository(s.rpc).agreeAndBegin('k-d4-0001');
      expect(w.ok, isFalse, reason: '$row');
      expect(w.reason, 'not_eligible', reason: '$row');
    }
    for (final state in ['active', 'paused']) {
      final s = ScriptedRpc([
        (_, __) => null,
        (_, __) => null,
        (_, __) => null,
        (_, __) => {'state': state},
      ]);
      final w = await DatingSetupRepository(s.rpc).agreeAndBegin('k-d4-0002');
      expect((w.ok, w.nextStep), (true, 'you'), reason: state);
    }
  });

  // T5 fix round 1 (M-4): every gateway write maps a raised error the same
  // way (a lock error is busy; a leaky message is failed, without it).
  test(
    'every setup write: a lock error is busy, a leaky raise failed',
    () async {
      const leaky = 'violates check: phone +233558703991 in Greater Accra';
      final writes = <
        String,
        (int, Future<DatingWrite> Function(DatingSetupRepository))
      >{
        'saveIntention': (
          0,
          (r) => r.saveIntention(
            'k',
            intention: 'marriage',
            timelineVisible: true,
            maritalVisible: false,
          ),
        ),
        'saveLocation': (
          0,
          (r) =>
              r.saveLocation('k', country: 'GH', region: 'AA', scope: 'region'),
        ),
        'agreeAndBegin consent': (0, (r) => r.agreeAndBegin('k')),
        'agreeAndBegin begin': (3, (r) => r.agreeAndBegin('k')),
        'saveIdentity': (
          0,
          (r) => r.saveIdentity('k', identity: 'woman', visible: false),
        ),
        'saveWhoToMeet': (
          0,
          (r) => r.saveWhoToMeet('k', seeking: ['man'], minAge: 25, maxAge: 35),
        ),
        'saveChildren': (
          0,
          (r) => r.saveChildren(
            'k',
            have: false,
            want: 'yes',
            mustMatch: false,
            excludeParents: false,
          ),
        ),
        'saveFaith consent': (
          0,
          (r) => r.saveFaith(
            'k',
            faith: 'none',
            importance: 'nice_to_share',
            visible: false,
          ),
        ),
        'saveFaith write': (
          1,
          (r) => r.saveFaith(
            'k',
            faith: 'none',
            importance: 'nice_to_share',
            visible: false,
          ),
        ),
        'clearFaith': (0, (r) => r.clearFaith('k')),
        'savePrompts': (0, (r) => r.savePrompts('k', [('p1', 'an answer')])),
        'saveDisplayName': (0, (r) => r.saveDisplayName('k', 'Ama')),
        'saveSettings': (0, (r) => r.saveSettings('k', {'data_saver': true})),
      };
      for (final MapEntry(key: name, value: (okCalls, write))
          in writes.entries) {
        for (final (error, want) in [
          (
            PostgrestException(
              message: 'canceling statement due to lock timeout',
              code: '55P03',
            ),
            'busy',
          ),
          (PostgrestException(message: leaky, code: '23514'), 'failed'),
        ]) {
          final s = ScriptedRpc([
            for (var i = 0; i < okCalls; i++) (_, __) => null,
            (_, __) => error,
          ]);
          final w = await write(DatingSetupRepository(s.rpc));
          expect(w.ok, isFalse, reason: name);
          expect(w.reason, want, reason: name);
          expect(s.calls.length, okCalls + 1, reason: name);
        }
      }
    },
  );
}
