import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:attune/features/dating/data/models/dating_enrollment.dart';
import 'package:attune/features/dating/data/models/dating_introduction.dart';
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatingRepository {
  DatingRepository(this._supabase);

  final SupabaseClient _supabase;

  /// Every RPC and PostgREST call in this repository is bounded by this.
  ///
  /// Checklist 1.2: without it a stalled connection leaves the caller
  /// awaiting forever, which in practice is a dating or healing screen
  /// spinning with no error and no way back. Matches the 30s used by
  /// RelationshipLifecycleService.
  static const _timeout = Duration(seconds: 30);
  final Map<String, String> _pendingIdempotencyKeys = <String, String>{};

  Future<Map<String, dynamic>> getEligibility() async {
    final response = await _supabase
        .rpc('get_dating_eligibility')
        .timeout(_timeout);
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

    final response = await _supabase
        .from('dating_enrollments')
        .select('*')
        .eq('user_id', userId)
        .maybeSingle()
        .timeout(_timeout);

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

    final profile = await _supabase
        .from('dating_profiles')
        .select('display_name, city_region_code, relationship_intention, bio')
        .eq('user_id', userId)
        .maybeSingle()
        .timeout(_timeout);
    final preferences = await _supabase
        .from('dating_preferences')
        .select('min_age, max_age')
        .eq('user_id', userId)
        .maybeSingle()
        .timeout(_timeout);

    if (profile == null && preferences == null) {
      return null;
    }

    return <String, dynamic>{...?profile, ...?preferences};
  }

  Future<List<DatingIntroduction>> getIntroductions() async {
    final response = await _supabase
        .rpc('get_my_dating_introductions', params: {'p_limit': 20})
        .timeout(_timeout);

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
    final response = await _supabase
        .rpc('get_my_dating_matches', params: {'p_limit': 50})
        .timeout(_timeout);

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

  Future<List<DatingProfilePhoto>> listPhotos() async {
    final response = await _supabase
        .rpc('list_dating_profile_photos')
        .timeout(_timeout);
    if (response is! List) {
      return const <DatingProfilePhoto>[];
    }
    return response
        .whereType<Map>()
        .map(
          (row) => DatingProfilePhoto.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _createPhotoUploadIntent(String mimeType) async {
    final response = await _supabase
        .rpc(
          'create_dating_photo_upload_intent',
          params: {'p_mime_type': mimeType},
        )
        .timeout(_timeout);
    final row =
        response is List && response.isNotEmpty
            ? Map<String, dynamic>.from(response.first as Map)
            : Map<String, dynamic>.from(response as Map);
    return row;
  }

  Future<String> uploadPhoto({
    required String localPath,
    required int position,
  }) async {
    const preparer = DatingImagePreparer();
    final prepared = await preparer.prepare(localPath);

    final intent = await _createPhotoUploadIntent(prepared.mimeType);
    final storageKey = intent['storage_key'] as String;
    final bucket = intent['bucket'] as String;
    final intentId = intent['intent_id'] as String;

    await _supabase.storage
        .from(bucket)
        .upload(
          storageKey,
          prepared.file,
          fileOptions: FileOptions(
            upsert: false,
            contentType: prepared.mimeType,
          ),
        )
        .timeout(_timeout);

    final response = await _supabase
        .rpc(
          'insert_dating_profile_photo',
          params: {'p_intent_id': intentId, 'p_position': position},
        )
        .timeout(_timeout);
    return response as String;
  }

  Future<void> deletePhoto(String photoId) async {
    await _runIdempotent(
      'delete_photo_$photoId',
      (key) => _supabase.rpc(
        'delete_dating_profile_photo',
        params: {'p_photo_id': photoId},
      ),
    );
  }

  /// Returns the resulting `verification_state` ('verified' | 'needs_review'
  /// | 'pending'). A 'pending' result means the Rekognition call itself
  /// failed (not a low-confidence match) — per spec §4 step 6, the caller
  /// should offer the user a retry rather than treating this as either
  /// success or failure.
  Future<String> submitVerificationSelfie({required String localPath}) async {
    const preparer = DatingImagePreparer();
    final prepared = await preparer.prepare(localPath);
    final bytes = await File(prepared.file.path).readAsBytes();

    final response = await _supabase.functions
        .invoke(
          'verify-dating-profile',
          body: {
            'selfie_base64': base64Encode(bytes),
            'mime_type': prepared.mimeType,
          },
        )
        .timeout(_timeout);
    if (response.status != 200) {
      throw Exception('Verification request failed');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['verification_state'] as String? ?? 'pending';
  }

  Future<String> getVerificationState() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return 'unverified';
    final response = await _supabase
        .from('dating_profiles')
        .select('verification_state')
        .eq('user_id', userId)
        .maybeSingle()
        .timeout(_timeout);
    return response?['verification_state'] as String? ?? 'unverified';
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
