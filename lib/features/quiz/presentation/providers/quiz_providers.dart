// lib/features/quiz/providers/quiz_providers.dart

import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/quiz/domain/models/attachment_result.dart';
import 'package:attune/features/quiz/data/repositories/quiz_repository.dart';
import 'package:attune/features/quiz/domain/models/communication_style_result.dart';
import 'package:attune/features/quiz/domain/models/conflict_style_result.dart';
import 'package:attune/features/quiz/domain/models/love_language_result.dart';
import 'package:attune/features/quiz/domain/models/shared_quiz_result.dart';
import 'package:attune/features/quiz/domain/services/quiz_notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final quizRepositoryProvider = Provider<QuizRepository>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return QuizRepository(supabase);
});

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return const [];
}

// Current user ID provider
final currentUserIdProvider = Provider<String?>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return supabase.auth.currentUser?.id;
});

// Save quiz result to database
final saveQuizResultProvider = FutureProvider.family<
  void,
  ({String quizType, Map<int, int?> answers, AttachmentResult result})
>((ref, params) async {
  final repository = ref.read(quizRepositoryProvider);
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;

  if (userId == null) throw Exception('Not authenticated');

  await repository.saveAttachmentResult(
    userId: userId,
    answers: params.answers,
    result: params.result,
    quizType: params.quizType,
  );
});

// Current user's relationship mode
final userRelationshipModeProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final response =
      await supabase
          .from('relationships')
          .select('status')
          .or('user_a.eq.$userId,user_b.eq.$userId')
          .eq('status', 'active')
          .maybeSingle();

  return response != null ? 'couples' : 'personal';
});

// Partner's display name (for sharing dialog)
final partnerNameProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final relationshipRes =
      await supabase
          .from('relationships')
          .select('user_a, user_b')
          .or('user_a.eq.$userId,user_b.eq.$userId')
          .eq('status', 'active')
          .maybeSingle();

  if (relationshipRes == null) return null;

  final partnerId =
      relationshipRes['user_a'] == userId
          ? relationshipRes['user_b']
          : relationshipRes['user_a'];

  if (partnerId == null) return null;

  final profileRes =
      await supabase
          .from('profiles')
          .select('display_name')
          .eq('id', partnerId)
          .single();

  return profileRes['display_name'] as String? ?? 'your partner';
});

// Check if user has already shared this quiz with partner
final hasSharedQuizProvider = FutureProvider.family<bool, (String, String)>((
  ref,
  params,
) async {
  final (quizType, _) = params;
  final supabase = ref.read(supabaseClientProvider);
  final currentUserId = supabase.auth.currentUser?.id;
  if (currentUserId == null) return false;

  final relationshipRes =
      await supabase
          .from('relationships')
          .select('user_a, user_b')
          .or('user_a.eq.$currentUserId,user_b.eq.$currentUserId')
          .eq('status', 'active')
          .maybeSingle();

  if (relationshipRes == null) return false;

  final partnerId =
      relationshipRes['user_a'] == currentUserId
          ? relationshipRes['user_b']
          : relationshipRes['user_a'];

  if (partnerId == null) return false;

  final shareRes =
      await supabase
          .from('quiz_shares')
          .select('id')
          .eq('sharer_user_id', currentUserId)
          .eq('recipient_user_id', partnerId)
          .eq('quiz_type', quizType)
          .maybeSingle();

  return shareRes != null;
});

// Share quiz result with partner (with notification)
final shareQuizResultProvider =
    FutureProvider.family<void, ({String quizType})>((ref, params) async {
      // Spec 5 (F9 (3)): an attachment result is about you; it is never
      // shared (the server refuses it too).
      if (params.quizType == 'attachment') {
        throw UnsupportedError('Attachment results are not shared');
      }
      final supabase = ref.read(supabaseClientProvider);
      final notificationService = QuizNotificationService(supabase);
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      final profileRes =
          await supabase
              .from('profiles')
              .select('display_name')
              .eq('id', userId)
              .single();
      final sharerName =
          profileRes['display_name'] as String? ?? 'Your partner';

      final quizRes =
          await supabase
              .from('quiz_responses')
              .select('id')
              .eq('user_id', userId)
              .eq('quiz_type', params.quizType)
              .order('version', ascending: false)
              .limit(1)
              .single();

      final relationshipRes =
          await supabase
              .from('relationships')
              .select('user_a, user_b')
              .or('user_a.eq.$userId,user_b.eq.$userId')
              .eq('status', 'active')
              .single();

      final partnerId =
          relationshipRes['user_a'] == userId
              ? relationshipRes['user_b']
              : relationshipRes['user_a'];

      final existingShare =
          await supabase
              .from('quiz_shares')
              .select('id')
              .eq('sharer_user_id', userId)
              .eq('recipient_user_id', partnerId)
              .eq('quiz_type', params.quizType)
              .maybeSingle();

      await supabase.from('quiz_shares').upsert({
        'sharer_user_id': userId,
        'recipient_user_id': partnerId,
        'quiz_type': params.quizType,
        'quiz_response_id': quizRes['id'],
      }, onConflict: 'sharer_user_id,recipient_user_id,quiz_type');

      if (existingShare == null) {
        await notificationService.notifyPartnerQuizShared(
          partnerId: partnerId,
          sharerName: sharerName,
          quizType: params.quizType,
        );
      }
    });

final stopSharingQuizProvider = FutureProvider.family<void, String>((
  ref,
  quizType,
) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) throw Exception('Not authenticated');

  await supabase
      .from('quiz_shares')
      .delete()
      .eq('sharer_user_id', userId)
      .eq('quiz_type', quizType);
});

// Get partner's shared quiz result
final partnerQuizResultProvider = FutureProvider.family<
  SharedQuizResult?,
  (String, String)
>((ref, params) async {
  final (quizType, partnerId) = params;
  final supabase = ref.read(supabaseClientProvider);

  final shareRes =
      await supabase
          .from('quiz_shares')
          .select('quiz_response_id')
          .eq('sharer_user_id', partnerId)
          .eq('quiz_type', quizType)
          .order('shared_at', ascending: false)
          .limit(1)
          .maybeSingle();

  if (shareRes == null) return null;

  switch (quizType) {
    // No 'attachment' case: an attachment result is about the person who
    // took it and is never shared (Spec 5, F9 (3); final review M-2).
    case 'love_language':
      // The shared response itself (a partner cannot read psych_profiles);
      // save_loving_now keeps the share on the newest answers.
      final quizRes =
          await supabase
              .from('quiz_responses')
              .select('result_data')
              .eq('id', shareRes['quiz_response_id'])
              .maybeSingle();
      final resultData = quizRes?['result_data'];
      if (resultData is! Map) return null;
      return SharedQuizResult.loveLanguage(
        LoveLanguageResult.fromJson(Map<String, dynamic>.from(resultData)),
      );
    case 'communication':
      // The shared response itself: a partner cannot read psych_profiles
      // (owner-only RLS); the "shared aggregate read" policy allows exactly
      // this row (Spec 5 final review).
      final quizRes =
          await supabase
              .from('quiz_responses')
              .select('result_data')
              .eq('id', shareRes['quiz_response_id'])
              .maybeSingle();
      final communicationStyle = quizRes?['result_data'];
      if (communicationStyle is! Map) return null;

      return SharedQuizResult.communication(
        CommunicationStyleResult.fromJson(
          Map<String, dynamic>.from(communicationStyle),
        ),
      );
    case 'conflict':
      final quizRes =
          await supabase
              .from('quiz_responses')
              .select('result_data')
              .eq('id', shareRes['quiz_response_id'])
              .single();

      final resultData = quizRes['result_data'];
      if (resultData is! Map) return null;
      return SharedQuizResult.conflict(
        ConflictStyleResult.fromJson(Map<String, dynamic>.from(resultData)),
      );
    default:
      return null;
  }
});

// Quiz completion status model
class QuizCompletionStatus {
  final bool completed;
  final String? displayName;
  final AttachmentResult? result;
  final LoveLanguageResult? loveLanguageResult;
  final CommunicationStyleResult? communicationStyleResult;
  final ConflictStyleResult? conflictStyleResult;

  QuizCompletionStatus({
    required this.completed,
    this.displayName,
    this.result,
    this.loveLanguageResult,
    this.communicationStyleResult,
    this.conflictStyleResult,
  });
}

// Get all quizzes status for the current user
final userQuizzesStatusProvider = FutureProvider<
  Map<String, QuizCompletionStatus>
>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return {};

  final profileRes =
      await supabase
          .from('psych_profiles')
          .select(
            'attachment_style, love_languages, communication_style, conflict_style, completed_quizzes',
          )
          .eq('user_id', userId)
          .maybeSingle();

  final completedQuizzes = profileRes?['completed_quizzes'] as List? ?? [];
  final result = <String, QuizCompletionStatus>{};

  if (completedQuizzes.contains('attachment') &&
      profileRes?['attachment_style'] != null) {
    final attachmentData =
        profileRes!['attachment_style'] as Map<String, dynamic>;
    final attachmentResult = AttachmentResult(
      anxietyScore: attachmentData['anxiety_score'] ?? 0,
      avoidanceScore: attachmentData['avoidance_score'] ?? 0,
      resultType: attachmentData['type'] ?? 'secure',
      displayName: attachmentData['display_name'] ?? 'Secure',
      poeticDescription: '',
      practiceBullets: [],
      securePercentage: 0,
      anxiousPercentage: 0,
      avoidantPercentage: 0,
      fearfulPercentage: 0,
    );
    result['attachment'] = QuizCompletionStatus(
      completed: true,
      displayName: attachmentData['display_name'],
      result: attachmentResult,
    );
  } else {
    result['attachment'] = QuizCompletionStatus(completed: false);
  }

  final loveLanguageData =
      profileRes?['love_languages'] != null
          ? LoveLanguageResult.fromJson(
            Map<String, dynamic>.from(profileRes!['love_languages'] as Map),
          )
          : null;

  result['love_language'] = QuizCompletionStatus(
    completed:
        completedQuizzes.contains('love_language') && loveLanguageData != null,
    displayName: loveLanguageData?.summary,
    loveLanguageResult: loveLanguageData,
  );

  final communicationData =
      profileRes?['communication_style'] != null
          ? CommunicationStyleResult.fromJson(
            Map<String, dynamic>.from(
              profileRes!['communication_style'] as Map,
            ),
          )
          : null;

  result['communication'] = QuizCompletionStatus(
    completed:
        completedQuizzes.contains('communication') && communicationData != null,
    displayName: communicationData?.getPrimaryDisplay(),
    communicationStyleResult: communicationData,
  );
  final conflictData =
      profileRes?['conflict_style'] is Map
          ? ConflictStyleResult.fromJson(
            Map<String, dynamic>.from(profileRes!['conflict_style'] as Map),
          )
          : null;

  result['conflict'] = QuizCompletionStatus(
    completed: completedQuizzes.contains('conflict') && conflictData != null,
    displayName:
        conflictData == null
            ? null
            : conflictData.isTied || conflictData.isMixed
            ? conflictData.getMixedDisplay()
            : conflictData.getPrimaryDisplay(),
    conflictStyleResult: conflictData,
  );

  return result;
});


// Spec 5 (research 06 §3 F9): no pairing or compatibility statement about the
// couple is ever computed or shown; the compatibility providers are gone.

// Save "what feels loving to me right now" (Spec 5, R5-5). The server
// checks the shape, stores the next version and moves any existing share
// to it (save_loving_now).
final saveLoveLanguageResultProvider =
    FutureProvider.family<void, LoveLanguageResult>((ref, result) async {
      final supabase = ref.read(supabaseClientProvider);
      await supabase.rpc(
        'save_loving_now',
        params: {'p_result': result.toJson()},
      );
    });

// Spec 5 (R5-6): the communication and conflict quizzes wait for clinical
// sign-off; off unless the flag says otherwise.
final quizClinicalSignoffProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.quizClinicalSignoff,
  );
});

// Save communication quiz result
final saveCommunicationQuizResultProvider = FutureProvider.family<
  CommunicationStyleResult,
  ({String quizType, Map<int, int?> answers, CommunicationStyleResult result})
>((ref, params) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;

  if (userId == null) throw Exception('Not authenticated');

  // Format answers
  final formattedAnswers = <String, int?>{};
  params.answers.forEach((key, value) {
    formattedAnswers['Q${key + 1}'] = value;
  });

  final existing =
      await supabase
          .from('quiz_responses')
          .select('version, result_type, completed_at')
          .eq('user_id', userId)
          .eq('quiz_type', 'communication')
          .order('version', ascending: false)
          .limit(1)
          .maybeSingle();

  final nextVersion = (existing != null ? (existing['version'] as int) + 1 : 1);

  if (existing != null) {
    await supabase.from('psych_profile_history').insert({
      'user_id': userId,
      'quiz_type': 'communication',
      'result_type': existing['result_type'] ?? '',
      'version': existing['version'],
      'recorded_at': existing['completed_at'],
    });
  }

  final completedAt = DateTime.now().toUtc();
  final resultJson = params.result.copyWith(completedAt: completedAt).toJson();

  await supabase.from('quiz_responses').insert({
    'user_id': userId,
    'quiz_type': 'communication',
    'responses': formattedAnswers,
    'result_type': params.result.primary,
    // What a partner reads once it is shared (they cannot read psych_profiles).
    'result_data': resultJson,
    'version': nextVersion,
  });

  final existingProfile =
      await supabase
          .from('psych_profiles')
          .select('completed_quizzes')
          .eq('user_id', userId)
          .maybeSingle();

  final currentQuizzes = _stringList(existingProfile?['completed_quizzes']);
  if (!currentQuizzes.contains('communication')) {
    currentQuizzes.add('communication');
  }

  if (existingProfile == null) {
    await supabase.from('psych_profiles').insert({
      'user_id': userId,
      'communication_style': resultJson,
      'completed_quizzes': currentQuizzes,
      'last_updated': completedAt.toIso8601String(),
    });
  } else {
    await supabase
        .from('psych_profiles')
        .update({
          'communication_style': resultJson,
          'completed_quizzes': currentQuizzes,
          'last_updated': completedAt.toIso8601String(),
        })
        .eq('user_id', userId);
  }

  // Invalidate caches
  ref.invalidate(userQuizzesStatusProvider);

  return params.result.copyWith(completedAt: completedAt);
});

// Save conflict quiz result
final saveConflictQuizResultProvider = FutureProvider.family<
  ConflictStyleResult,
  ({
    String quizType,
    Map<int, int?> answers,
    ConflictStyleResult result,
    String idempotencyKey,
  })
>((ref, params) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;

  if (userId == null) throw Exception('Not authenticated');

  // Format answers for validation (not stored)
  final formattedAnswers = <String, int?>{};
  params.answers.forEach((key, value) {
    formattedAnswers['Q${key + 1}'] = value;
  });

  // Call atomic completion RPC
  final response = await supabase.rpc(
    'save_conflict_quiz_result',
    params: {
      'p_responses': formattedAnswers,
      'p_idempotency_key': params.idempotencyKey,
    },
  );

  if (response is! Map || response['success'] != true) {
    throw Exception('Failed to save quiz result');
  }

  // Invalidate caches
  ref.invalidate(userQuizzesStatusProvider);

  final resultData = response['result_data'];
  if (resultData is! Map) throw Exception('Invalid saved quiz result');
  return ConflictStyleResult.fromJson(Map<String, dynamic>.from(resultData));
});
