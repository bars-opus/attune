// Spec 2 W3b-W3c (§3.2, §4.4 Setup writers): every setup read and write,
// RPC-only. Each writer answers DatingWrite ({ok, next_step} or a reason);
// D4's three consents and the enrolment are one step. Keys come from the
// screen (one per action until it goes, Fable H3c).
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The consents' policy version (§3.2 D4).
const datingPolicyVersion = 'dating-2.0';

/// The raised codes a setup screen names (Task 1 review M-9). A raised
/// message is server text that can echo what the person typed, so only
/// these pass as the reason; anything else, the `idempotency_key_*` and
/// `invalid_consent_event` programmer errors included, is `failed`.
/// (`consent_required` comes back as a returned answer, not raised.)
const datingSetupRaisedReasons = {
  'reverify_device',
  'path_not_dating',
  'not_eligible',
  'rate_limited',
  'terms_consent_required',
  'dating_opt_in_required',
  'not_authenticated',
};

/// The enrolment states D4 can go on from (T5 fix round 1, M-6): any other
/// row (suspended, exited, or the empty row an exclusion-key mismatch
/// answers with) is not set up, so D4 reads not_eligible, never ok.
const _beginStates = {'profile_draft', 'active', 'paused'};

/// Lock timeout, deadlock, serialization: the write may not have run.
const _lockCodes = {'55P03', '40P01', '40001'};

/// A setup writer's answer to a raised error: busy for a busy server or a
/// lock error (the caller keeps its key and may retry), a known code as
/// itself, anything else `failed`. Never the message itself.
DatingWrite datingSetupRaised(Object error) {
  if (error is DatingBusy) return DatingWrite.busy;
  if (error is PostgrestException) {
    if (_lockCodes.contains(error.code) || error.message == 'dating:busy') {
      return DatingWrite.busy;
    }
    if (datingSetupRaisedReasons.contains(error.message)) {
      return DatingWrite(ok: false, reason: error.message);
    }
  }
  return DatingWrite.failed;
}

/// [datingWrite] for the setup writers: a raised error goes through
/// [datingSetupRaised].
Future<DatingWrite> _setupWrite(Future<dynamic> Function() write) async {
  try {
    return DatingWrite.fromJson(await write());
  } catch (e) {
    return datingSetupRaised(e);
  }
}

abstract class DatingSetupGateway {
  Future<DatingSetupLists> lists();
  Future<DatingMyProfile> myProfile();
  Future<DatingWrite> saveIntention(
    String key, {
    required String intention,
    String? timeline,
    required bool timelineVisible,
    String? marital,
    required bool maritalVisible,
  });
  Future<DatingWrite> saveLocation(
    String key, {
    required String country,
    required String region,
    String? side,
    required String scope,
  });
  Future<DatingWrite> agreeAndBegin(String key);
  Future<DatingWrite> saveIdentity(
    String key, {
    required String identity,
    String? specific,
    String? pronouns,
    List<String> extraPools = const [],
    required bool visible,
  });
  Future<DatingWrite> saveWhoToMeet(
    String key, {
    required List<String> seeking,
    required int minAge,
    required int maxAge,
  });
  Future<DatingWrite> saveChildren(
    String key, {
    required bool have,
    required String want,
    required bool mustMatch,
    required bool excludeParents,
  });
  Future<DatingWrite> saveFaith(
    String key, {
    required String faith,
    String? denomination,
    required String importance,
    required bool visible,
  });
  Future<DatingWrite> clearFaith(String key);
  Future<DatingWrite> savePrompts(String key, List<(String, String)> items);
  Future<DatingWrite> saveDisplayName(String key, String name);
  Future<DatingWrite> saveSettings(String key, Map<String, Object> values);
}

class DatingSetupRepository implements DatingSetupGateway {
  DatingSetupRepository(this._rpc);

  final DatingRpc _rpc;

  @override
  Future<DatingSetupLists> lists() async {
    final json = Map<String, dynamic>.from(
      await _rpc.call('get_dating_setup_lists') as Map,
    );
    if (json['ok'] != true) throw StateError('lists:${json['reason']}');
    return DatingSetupLists.fromJson(json);
  }

  @override
  Future<DatingMyProfile> myProfile() async {
    final json = Map<String, dynamic>.from(
      await _rpc.call('get_my_dating_profile') as Map,
    );
    if (json['ok'] != true) throw StateError('profile:${json['reason']}');
    final profile = json['profile'];
    return profile is Map
        ? DatingMyProfile.fromJson(Map<String, dynamic>.from(profile))
        : const DatingMyProfile(exists: false);
  }

  @override
  Future<DatingWrite> saveIntention(
    String key, {
    required String intention,
    String? timeline,
    required bool timelineVisible,
    String? marital,
    required bool maritalVisible,
  }) => _setupWrite(
    () => _rpc.call('save_dating_intention', {
      'p_idempotency_key': key,
      'p_intention': intention,
      'p_timeline': intention == 'marriage' ? timeline : null,
      'p_timeline_visible': timelineVisible,
      // The screen sends only after the box is ticked (§3.2 D2).
      'p_attested': true,
      'p_marital': marital,
      'p_marital_visible': maritalVisible,
    }),
  );

  @override
  Future<DatingWrite> saveLocation(
    String key, {
    required String country,
    required String region,
    String? side,
    required String scope,
  }) => _setupWrite(
    () => _rpc.call('save_dating_location', {
      'p_idempotency_key': key,
      'p_country': country,
      'p_region': region,
      'p_side': side,
      'p_scope': scope,
    }),
  );

  @override
  Future<DatingWrite> agreeAndBegin(String key) async {
    try {
      for (final purpose in const [
        'dating_terms',
        'dating_opt_in',
        'special_category_profile',
      ]) {
        await _rpc.call('record_dating_consent', {
          'p_idempotency_key': '$key:$purpose',
          'p_purpose': purpose,
          'p_action': 'granted',
          'p_policy_version': datingPolicyVersion,
          'p_categories':
              purpose == 'special_category_profile'
                  ? ['gender', 'who_to_meet']
                  : <String>[],
        });
      }
      final row = await _rpc.call('begin_dating_enrollment', {
        'p_terms_version': datingPolicyVersion,
        'p_idempotency_key': '$key:begin',
      });
      if (row is! Map || !_beginStates.contains(row['state'])) {
        return const DatingWrite(ok: false, reason: 'not_eligible');
      }
      return const DatingWrite(ok: true, nextStep: 'you');
    } catch (e) {
      return datingSetupRaised(e);
    }
  }

  @override
  Future<DatingWrite> saveIdentity(
    String key, {
    required String identity,
    String? specific,
    String? pronouns,
    List<String> extraPools = const [],
    required bool visible,
  }) => _setupWrite(
    () => _rpc.call('save_dating_identity', {
      'p_idempotency_key': key,
      'p_identity': identity,
      'p_specific': specific,
      'p_pronouns': pronouns,
      'p_extra_pools': extraPools,
      'p_visible': visible,
    }),
  );

  @override
  Future<DatingWrite> saveWhoToMeet(
    String key, {
    required List<String> seeking,
    required int minAge,
    required int maxAge,
  }) => _setupWrite(
    () => _rpc.call('save_dating_who_to_meet', {
      'p_idempotency_key': key,
      'p_seeking': seeking,
      'p_min_age': minAge,
      'p_max_age': maxAge,
    }),
  );

  @override
  Future<DatingWrite> saveChildren(
    String key, {
    required bool have,
    required String want,
    required bool mustMatch,
    required bool excludeParents,
  }) => _setupWrite(
    () => _rpc.call('save_dating_children', {
      'p_idempotency_key': key,
      'p_have': have,
      'p_want': want,
      'p_must_match': mustMatch,
      'p_exclude_parents': excludeParents,
    }),
  );

  @override
  Future<DatingWrite> saveFaith(
    String key, {
    required String faith,
    String? denomination,
    required String importance,
    required bool visible,
  }) async {
    try {
      await _rpc.call('record_dating_consent', {
        'p_idempotency_key': '$key:consent',
        'p_purpose': 'special_category_faith',
        'p_action': 'granted',
        'p_policy_version': datingPolicyVersion,
        'p_categories': ['faith'],
      });
    } catch (e) {
      return datingSetupRaised(e);
    }
    return _setupWrite(
      () => _rpc.call('save_dating_faith', {
        'p_idempotency_key': key,
        'p_faith': faith,
        'p_denomination': denomination,
        'p_importance': importance,
        'p_visible': visible,
      }),
    );
  }

  @override
  Future<DatingWrite> clearFaith(String key) => _setupWrite(
    () => _rpc.call('clear_dating_faith', {'p_idempotency_key': key}),
  );

  @override
  Future<DatingWrite> savePrompts(String key, List<(String, String)> items) =>
      _setupWrite(
        () => _rpc.call('save_dating_prompts', {
          'p_idempotency_key': key,
          'p_items': [
            for (final (id, answer) in items)
              {'prompt_id': id, 'answer': answer},
          ],
        }),
      );

  @override
  Future<DatingWrite> saveDisplayName(String key, String name) => _setupWrite(
    () => _rpc.call('save_dating_display_name', {
      'p_idempotency_key': key,
      'p_name': name,
    }),
  );

  @override
  Future<DatingWrite> saveSettings(String key, Map<String, Object> values) =>
      _setupWrite(
        () => _rpc.call('save_dating_settings', {
          'p_idempotency_key': key,
          'p_values': values,
        }),
      );
}
