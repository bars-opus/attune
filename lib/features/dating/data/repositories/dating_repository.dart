import 'dart:math';

import 'package:attune/features/dating/data/models/dating_enrollment.dart';
import 'package:attune/features/dating/data/models/dating_introduction.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatingRepository {
  DatingRepository(this._supabase);

  final SupabaseClient _supabase;
  final Map<String, String> _pendingIdempotencyKeys = <String, String>{};

  Future<Map<String, dynamic>> getEligibility() async {
    final response = await _supabase.rpc('get_dating_eligibility');
    if (response is! Map) {
      return const <String, dynamic>{'is_eligible': false, 'reason': 'unknown'};
    }
    return Map<String, dynamic>.from(response);
  }

  Future<DatingEnrollment?> getEnrollment() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }

    final response =
        await _supabase
            .from('dating_enrollments')
            .select('*')
            .eq('user_id', userId)
            .maybeSingle();

    if (response == null) {
      return null;
    }

    return DatingEnrollment.fromJson(response);
  }

  Future<void> recordConsent({
    required String purpose,
    required bool granted,
    required String policyVersion,
    required List<String> categories,
  }) async {
    await _runIdempotent(
      'consent_${purpose}_${granted}_$policyVersion',
      (key) => _supabase.rpc(
        'record_dating_consent',
        params: {
          'p_idempotency_key': key,
          'p_purpose': purpose,
          'p_action': granted ? 'granted' : 'withdrawn',
          'p_policy_version': policyVersion,
          'p_categories': categories,
        },
      ),
    );
  }

  Future<DatingEnrollment> optIn({required String termsVersion}) async {
    final response = await _runIdempotent(
      'begin_enrollment_$termsVersion',
      (key) => _supabase.rpc(
        'begin_dating_enrollment',
        params: {'p_terms_version': termsVersion, 'p_idempotency_key': key},
      ),
    );

    return DatingEnrollment.fromJson(_mapResponse(response));
  }

  Future<Map<String, dynamic>> saveProfile({
    required String displayName,
    required String cityRegionCode,
    required String relationshipIntention,
    required int minAge,
    required int maxAge,
    String? bio,
  }) async {
    final response = await _runIdempotent(
      'save_profile',
      (key) => _supabase.rpc(
        'save_dating_profile_draft',
        params: {
          'p_idempotency_key': key,
          'p_display_name': displayName,
          'p_city_region_code': cityRegionCode,
          'p_relationship_intention': relationshipIntention,
          'p_bio': bio,
          'p_min_age': minAge,
          'p_max_age': maxAge,
        },
      ),
    );

    return _mapResponse(response);
  }

  Future<DatingEnrollment> activateProfile() async {
    final response = await _runIdempotent(
      'activate_profile',
      (key) => _supabase.rpc(
        'activate_dating_profile',
        params: {'p_idempotency_key': key},
      ),
    );

    return DatingEnrollment.fromJson(_mapResponse(response));
  }

  Future<DatingEnrollment> pause() async {
    final response = await _runIdempotent(
      'pause_mode',
      (key) => _supabase.rpc(
        'pause_dating_mode',
        params: {'p_idempotency_key': key},
      ),
    );

    return DatingEnrollment.fromJson(_mapResponse(response));
  }

  Future<DatingEnrollment> resume() async {
    final response = await _runIdempotent(
      'resume_mode',
      (key) => _supabase.rpc(
        'activate_dating_profile',
        params: {'p_idempotency_key': key},
      ),
    );

    return DatingEnrollment.fromJson(_mapResponse(response));
  }

  Future<DatingEnrollment> exit() async {
    final response = await _runIdempotent(
      'exit_mode',
      (key) =>
          _supabase.rpc('exit_dating_mode', params: {'p_idempotency_key': key}),
    );

    return DatingEnrollment.fromJson(_mapResponse(response));
  }

  Future<Map<String, dynamic>?> getProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }

    final profile =
        await _supabase
            .from('dating_profiles')
            .select(
              'display_name, city_region_code, relationship_intention, bio',
            )
            .eq('user_id', userId)
            .maybeSingle();
    final preferences =
        await _supabase
            .from('dating_preferences')
            .select('min_age, max_age')
            .eq('user_id', userId)
            .maybeSingle();

    if (profile == null && preferences == null) {
      return null;
    }

    return <String, dynamic>{...?profile, ...?preferences};
  }

  Future<List<DatingIntroduction>> getIntroductions() async {
    final response = await _supabase.rpc(
      'get_my_dating_introductions',
      params: {'p_limit': 20},
    );

    if (response is! List) {
      return const <DatingIntroduction>[];
    }

    return response
        .whereType<Map>()
        .map(
          (row) => DatingIntroduction.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<void> expressInterest({
    required String introductionId,
    required String action,
  }) async {
    await _runIdempotent(
      'intro_${introductionId}_$action',
      (key) => _supabase.rpc(
        'act_on_dating_introduction',
        params: {
          'p_idempotency_key': key,
          'p_introduction_id': introductionId,
          'p_action': action,
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getMatches() async {
    final response = await _supabase.rpc(
      'get_my_dating_matches',
      params: {'p_limit': 50},
    );

    if (response is! List) {
      return const <Map<String, dynamic>>[];
    }

    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<void> unmatch(String matchId) async {
    await _runIdempotent(
      'unmatch_$matchId',
      (key) => _supabase.rpc(
        'unmatch_dating_match',
        params: {'p_idempotency_key': key, 'p_match_id': matchId},
      ),
    );
  }

  Future<void> blockIntroduction(String introductionId) async {
    await _runIdempotent(
      'block_introduction_$introductionId',
      (key) => _supabase.rpc(
        'block_dating_introduction',
        params: {'p_idempotency_key': key, 'p_introduction_id': introductionId},
      ),
    );
  }

  Future<void> blockMatch(String matchId) async {
    await _runIdempotent(
      'block_match_$matchId',
      (key) => _supabase.rpc(
        'block_dating_match',
        params: {'p_idempotency_key': key, 'p_match_id': matchId},
      ),
    );
  }

  Future<void> reportIntroduction({
    required String introductionId,
    required String category,
    String? details,
  }) async {
    await _runIdempotent(
      'report_introduction_${introductionId}_$category',
      (key) => _supabase.rpc(
        'report_dating_introduction',
        params: {
          'p_idempotency_key': key,
          'p_introduction_id': introductionId,
          'p_category': category,
          'p_details': details,
        },
      ),
    );
  }

  Future<void> reportMatch({
    required String matchId,
    required String category,
    String? details,
  }) async {
    await _runIdempotent(
      'report_match_${matchId}_$category',
      (key) => _supabase.rpc(
        'report_dating_match',
        params: {
          'p_idempotency_key': key,
          'p_match_id': matchId,
          'p_category': category,
          'p_details': details,
        },
      ),
    );
  }

  Future<void> saveDateReflection({
    required String matchId,
    required String response,
    String? note,
  }) async {
    await _runIdempotent(
      'reflection_${matchId}_$response',
      (key) => _supabase.rpc(
        'save_private_date_reflection',
        params: {
          'p_idempotency_key': key,
          'p_match_id': matchId,
          'p_response': response,
          'p_note': note,
        },
      ),
    );
  }

  Future<void> deleteDateReflection({required String matchId}) async {
    await _runIdempotent(
      'delete_reflection_$matchId',
      (key) => _supabase.rpc(
        'delete_private_date_reflection',
        params: {'p_idempotency_key': key, 'p_match_id': matchId},
      ),
    );
  }

  Future<void> deleteProfile() async {
    await _runIdempotent(
      'delete_profile',
      (key) => _supabase.rpc(
        'delete_dating_profile',
        params: {'p_idempotency_key': key},
      ),
    );
  }

  Map<String, dynamic> _mapResponse(dynamic response) {
    if (response is! Map) {
      throw Exception('Unexpected response from Dating backend');
    }

    return Map<String, dynamic>.from(response);
  }

  String _idempotencyKey(String scope) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final entropy = Random().nextInt(1 << 32);
    return '$scope-$timestamp-$entropy';
  }

  Future<T> _runIdempotent<T>(
    String scope,
    Future<T> Function(String key) operation,
  ) async {
    final key = _pendingIdempotencyKeys.putIfAbsent(
      scope,
      () => _idempotencyKey(scope),
    );
    final result = await operation(key);
    _pendingIdempotencyKeys.remove(scope);
    return result;
  }
}
