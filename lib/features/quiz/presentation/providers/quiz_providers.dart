// lib/features/quiz/providers/quiz_providers.dart

import 'package:attune/features/quiz/domain/models/attachment_compatibility.dart';
import 'package:attune/features/quiz/domain/models/attachment_result.dart';
import 'package:attune/features/quiz/data/repositories/quiz_repository.dart';
import 'package:attune/features/quiz/domain/models/communication_style_result.dart';
import 'package:attune/features/quiz/domain/models/conflict_style_result.dart';
import 'package:attune/features/quiz/domain/models/love_language_result.dart';
import 'package:attune/features/quiz/domain/models/shared_quiz_result.dart';
import 'package:attune/features/quiz/domain/services/attachment_scoring_service.dart';
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
    case 'attachment':
      final quizRes =
          await supabase
              .from('quiz_responses')
              .select('anxiety_score, avoidance_score, result_type')
              .eq('id', shareRes['quiz_response_id'])
              .single();

      return SharedQuizResult.attachment(
        AttachmentResult(
          anxietyScore: quizRes['anxiety_score'],
          avoidanceScore: quizRes['avoidance_score'],
          resultType: quizRes['result_type'],
          displayName: AttachmentScoringService.getDisplayNameFromType(
            quizRes['result_type'],
          ),
          poeticDescription:
              AttachmentScoringService.getPoeticDescriptionFromType(
                quizRes['result_type'],
              ),
          practiceBullets: AttachmentScoringService.getPracticeBulletsFromType(
            quizRes['result_type'],
          ),
          securePercentage: 0,
          anxiousPercentage: 0,
          avoidantPercentage: 0,
          fearfulPercentage: 0,
        ),
      );
    case 'love_language':
      final profileRes =
          await supabase
              .from('psych_profiles')
              .select('love_languages')
              .eq('user_id', partnerId)
              .maybeSingle();

      final loveLanguages = profileRes?['love_languages'];
      if (loveLanguages is! Map) return null;

      return SharedQuizResult.loveLanguage(
        LoveLanguageResult.fromJson(Map<String, dynamic>.from(loveLanguages)),
      );
    case 'communication':
      final profileRes =
          await supabase
              .from('psych_profiles')
              .select('communication_style')
              .eq('user_id', partnerId)
              .maybeSingle();

      final communicationStyle = profileRes?['communication_style'];
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
    displayName: loveLanguageData?.getPrimaryDisplay(),
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

// Check if both partners have shared their attachment results
final bothPartnersSharedProvider = FutureProvider<bool>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return false;

  final relationshipRes =
      await supabase
          .from('relationships')
          .select('user_a, user_b')
          .or('user_a.eq.$userId,user_b.eq.$userId')
          .eq('status', 'active')
          .maybeSingle();

  if (relationshipRes == null) return false;

  final partnerId =
      relationshipRes['user_a'] == userId
          ? relationshipRes['user_b']
          : relationshipRes['user_a'];

  if (partnerId == null) return false;

  final userShare =
      await supabase
          .from('quiz_shares')
          .select('id')
          .eq('sharer_user_id', userId)
          .eq('recipient_user_id', partnerId)
          .eq('quiz_type', 'attachment')
          .maybeSingle();

  final partnerShare =
      await supabase
          .from('quiz_shares')
          .select('id')
          .eq('sharer_user_id', partnerId)
          .eq('recipient_user_id', userId)
          .eq('quiz_type', 'attachment')
          .maybeSingle();

  return userShare != null && partnerShare != null;
});

// Get attachment compatibility (with Claude API)
final attachmentCompatibilityProvider = FutureProvider<
  AttachmentCompatibility?
>((ref) async {
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

  final cachedRes =
      await supabase
          .from('attachment_compatibility_cache')
          .select('*')
          .eq('relationship_id', relationshipRes['id'])
          .maybeSingle();

  if (cachedRes != null) {
    final partnerProfile =
        await supabase
            .from('profiles')
            .select('display_name')
            .eq('id', partnerId)
            .single();

    return AttachmentCompatibility(
      userType: cachedRes['type_a'] as String? ?? 'Secure',
      partnerType: cachedRes['type_b'] as String? ?? 'Secure',
      partnerName: partnerProfile['display_name'] as String? ?? 'Partner',
      partnerId: partnerId,
      pairingName: cachedRes['pairing_name'] as String? ?? 'A balanced dynamic',
      pairingDescription:
          cachedRes['pairing_description'] as String? ??
          'These two styles bring different but workable rhythms.',
      naturalStrength:
          cachedRes['natural_strength'] as String? ??
          'You can learn from each other over time',
      watchArea:
          cachedRes['watch_area'] as String? ??
          'Notice how you handle distance and closeness',
    );
  }

  final userShare =
      await supabase
          .from('quiz_shares')
          .select('quiz_response_id')
          .eq('sharer_user_id', userId)
          .eq('recipient_user_id', partnerId)
          .eq('quiz_type', 'attachment')
          .single();

  final partnerShare =
      await supabase
          .from('quiz_shares')
          .select('quiz_response_id')
          .eq('sharer_user_id', partnerId)
          .eq('recipient_user_id', userId)
          .eq('quiz_type', 'attachment')
          .single();

  final userQuiz =
      await supabase
          .from('quiz_responses')
          .select('result_type')
          .eq('id', userShare['quiz_response_id'])
          .single();

  final partnerQuiz =
      await supabase
          .from('quiz_responses')
          .select('result_type')
          .eq('id', partnerShare['quiz_response_id'])
          .single();

  final userType = userQuiz['result_type'] as String;
  final partnerType = partnerQuiz['result_type'] as String;

  final partnerProfile =
      await supabase
          .from('profiles')
          .select('display_name')
          .eq('id', partnerId)
          .single();

  final compatibility = await _generateCompatibilityNote(userType, partnerType);

  await supabase.rpc(
    'upsert_attachment_compatibility_cache',
    params: {
      'p_relationship_id': relationshipRes['id'],
      'p_type_a': userType,
      'p_type_b': partnerType,
      'p_pairing_name': compatibility['pairing_name'],
      'p_pairing_description': compatibility['pairing_description'],
      'p_natural_strength': compatibility['natural_strength'],
      'p_watch_area': compatibility['watch_area'],
    },
  );

  return AttachmentCompatibility(
    userType: AttachmentScoringService.getDisplayNameFromType(userType),
    partnerType: AttachmentScoringService.getDisplayNameFromType(partnerType),
    partnerName: partnerProfile['display_name'] as String? ?? 'Partner',
    partnerId: partnerId,
    pairingName: compatibility['pairing_name'] ?? 'A balanced dynamic',
    pairingDescription:
        compatibility['pairing_description'] ??
        'These two styles bring different but workable rhythms.',
    naturalStrength:
        compatibility['natural_strength'] ??
        'You can learn from each other over time',
    watchArea:
        compatibility['watch_area'] ??
        'Notice how you handle distance and closeness',
  );
});

// Provider to check if compatibility needs refresh
final needsCompatibilityRefreshProvider = FutureProvider<bool>((ref) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return false;

  // Get relationship
  final relationshipRes =
      await supabase
          .from('relationships')
          .select('id, user_a, user_b')
          .or('user_a.eq.$userId,user_b.eq.$userId')
          .eq('status', 'active')
          .maybeSingle();

  if (relationshipRes == null) return false;

  final partnerId =
      relationshipRes['user_a'] == userId
          ? relationshipRes['user_b']
          : relationshipRes['user_a'];

  // Get the most recent shared quiz response for both users
  final userShare =
      await supabase
          .from('quiz_shares')
          .select('quiz_response_id, shared_at')
          .eq('sharer_user_id', userId)
          .eq('recipient_user_id', partnerId)
          .eq('quiz_type', 'attachment')
          .order('shared_at', ascending: false)
          .limit(1)
          .maybeSingle();

  final partnerShare =
      await supabase
          .from('quiz_shares')
          .select('quiz_response_id, shared_at')
          .eq('sharer_user_id', partnerId)
          .eq('recipient_user_id', userId)
          .eq('quiz_type', 'attachment')
          .order('shared_at', ascending: false)
          .limit(1)
          .maybeSingle();

  if (userShare == null || partnerShare == null) return false;

  // Get cached compatibility
  final cachedRes =
      await supabase
          .from('attachment_compatibility_cache')
          .select('generated_at')
          .eq('relationship_id', relationshipRes['id'])
          .maybeSingle();

  if (cachedRes == null) return true;

  final cachedDate = DateTime.parse(cachedRes['generated_at']);
  final userShareDate = DateTime.parse(userShare['shared_at']);
  final partnerShareDate = DateTime.parse(partnerShare['shared_at']);

  // If either share is newer than the cached compatibility, refresh needed
  return userShareDate.isAfter(cachedDate) ||
      partnerShareDate.isAfter(cachedDate);
});

// Provider that refreshes compatibility when needed
final refreshedAttachmentCompatibilityProvider =
    FutureProvider<AttachmentCompatibility?>((ref) async {
      // First check if refresh is needed
      final needsRefresh = await ref.read(
        needsCompatibilityRefreshProvider.future,
      );

      if (needsRefresh) {
        // Invalidate the cached compatibility to force refresh
        ref.invalidate(attachmentCompatibilityProvider);
      }

      return ref.watch(attachmentCompatibilityProvider.future);
    });

// Claude API call for compatibility note
Future<Map<String, String>> _generateCompatibilityNote(
  String typeA,
  String typeB,
) async {
  final displayA = AttachmentScoringService.getDisplayNameFromType(typeA);
  final displayB = AttachmentScoringService.getDisplayNameFromType(typeB);

  const systemPrompt = '''
ABSOLUTE CONSTRAINTS — these override all other instructions:

1. Never attribute a negative behaviour to a named or implied partner.
2. Never use these words: toxic, narcissist, codependent, disorder, broken.
3. The watch_area describes the dynamic — never blames either person.
4. Return ONLY valid JSON. No preamble. No markdown fences.
''';

  final userPrompt = '''
Generate a short attachment compatibility note for two people.

Person A attachment type: $displayA
Person B attachment type: $displayB

Return ONLY valid JSON:
{
  "pairing_name": string (3-5 words, poetic, warm — not clinical),
  "pairing_description": string (max 30 words, specific to this combination),
  "natural_strength": string (max 20 words),
  "watch_area": string (max 20 words, about the dynamic not about either person individually)
}

Rules:
- pairing_name must feel like a name for this dynamic not a clinical description
- Never use: anxious, avoidant, fearful, disorder, broken
- watch_area describes the dynamic — never blames either person
''';

  final response = await _callClaudeApi(systemPrompt, userPrompt);

  return {
    'pairing_name': response['pairing_name'] ?? 'A balanced dynamic',
    'pairing_description':
        response['pairing_description'] ??
        'These two attachment styles complement each other in meaningful ways.',
    'natural_strength':
        response['natural_strength'] ??
        'You bring different perspectives that can deepen understanding',
    'watch_area':
        response['watch_area'] ??
        'Notice how you handle distance and closeness',
  };
}

// Placeholder for Claude API call - implement with your actual HTTP client
Future<Map<String, dynamic>> _callClaudeApi(
  String systemPrompt,
  String userPrompt,
) async {
  // TODO: Implement actual Claude API call
  return {
    'pairing_name': 'The anchor and the tide',
    'pairing_description':
        'One brings steady presence, the other brings depth of feeling — together you create emotional richness.',
    'natural_strength': 'You balance stability with emotional awareness',
    'watch_area': 'Notice how you react when one person needs space',
  };
}

// Save love language result
final saveLoveLanguageResultProvider = FutureProvider.family<
  void,
  ({Map<int, int?> answers, LoveLanguageResult result})
>((ref, params) async {
  final supabase = ref.read(supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;

  if (userId == null) throw Exception('Not authenticated');

  // Format answers for storage
  final formattedAnswers = <String, int?>{};
  params.answers.forEach((key, value) {
    formattedAnswers['Q${key + 1}'] = value;
  });

  // Get current version (for retake handling)
  final existing =
      await supabase
          .from('quiz_responses')
          .select('version')
          .eq('user_id', userId)
          .eq('quiz_type', 'love_language')
          .order('version', ascending: false)
          .limit(1)
          .maybeSingle();

  final nextVersion = (existing != null ? (existing['version'] as int) + 1 : 1);

  // If this is a retake, move current result to history
  if (existing != null) {
    final currentResponse =
        await supabase
            .from('quiz_responses')
            .select('*')
            .eq('user_id', userId)
            .eq('quiz_type', 'love_language')
            .eq('version', existing['version'])
            .single();

    await supabase.from('psych_profile_history').insert({
      'user_id': userId,
      'quiz_type': 'love_language',
      'result_type': currentResponse['result_type'] ?? '',
      'version': currentResponse['version'],
      'recorded_at': currentResponse['completed_at'],
    });
  }

  // Insert new response
  await supabase.from('quiz_responses').insert({
    'user_id': userId,
    'quiz_type': 'love_language',
    'responses': formattedAnswers,
    'result_type': params.result.primary,
    'version': nextVersion,
  });

  // Update psych_profiles
  final existingProfile =
      await supabase
          .from('psych_profiles')
          .select('love_languages, completed_quizzes')
          .eq('user_id', userId)
          .maybeSingle();

  if (existingProfile == null) {
    // Create new profile
    await supabase.from('psych_profiles').insert({
      'user_id': userId,
      'love_languages': params.result.toJson(),
      'completed_quizzes': ['love_language'],
      'last_updated': DateTime.now().toIso8601String(),
    });
  } else {
    // Update existing profile
    final currentQuizzes = existingProfile['completed_quizzes'] as List? ?? [];
    if (!currentQuizzes.contains('love_language')) {
      currentQuizzes.add('love_language');
    }

    await supabase
        .from('psych_profiles')
        .update({
          'love_languages': params.result.toJson(),
          'completed_quizzes': currentQuizzes,
          'last_updated': DateTime.now().toIso8601String(),
        })
        .eq('user_id', userId);
  }
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

  await supabase.from('quiz_responses').insert({
    'user_id': userId,
    'quiz_type': 'communication',
    'responses': formattedAnswers,
    'result_type': params.result.primary,
    'version': nextVersion,
  });

  final completedAt = DateTime.now().toUtc();
  final resultJson = params.result.copyWith(completedAt: completedAt).toJson();

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
