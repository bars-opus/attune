// lib/features/quiz/data/repositories/quiz_repository.dart

import 'package:attune/features/quiz/domain/models/attachment_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QuizRepository {
  final SupabaseClient _supabase;

  QuizRepository(this._supabase);

  Future<void> saveAttachmentResult({
    required String userId,
    required Map<int, int?> answers,
    required AttachmentResult result,
    required String quizType,
  }) async {
    // Step 1: Insert into quiz_responses
    final Map<String, dynamic> formattedAnswers = {};
    answers.forEach((key, value) {
      formattedAnswers['Q${key + 1}'] = value;
    });

    // Get current version (for retake handling)
    final existing = await _supabase
        .from('quiz_responses')
        .select('version')
        .eq('user_id', userId)
        .eq('quiz_type', quizType)
        .order('version', ascending: false)
        .limit(1)
        .maybeSingle();

    final nextVersion = (existing != null ? (existing['version'] as int) + 1 : 1);

    // If this is a retake, move current result to history
    if (existing != null) {
      final currentResponse = await _supabase
          .from('quiz_responses')
          .select('*')
          .eq('user_id', userId)
          .eq('quiz_type', quizType)
          .eq('version', existing['version'])
          .single();

      await _supabase.from('psych_profile_history').insert({
        'user_id': userId,
        'quiz_type': quizType,
        'result_type': currentResponse['result_type'],
        'anxiety_score': currentResponse['anxiety_score'],
        'avoidance_score': currentResponse['avoidance_score'],
        'version': currentResponse['version'],
        'recorded_at': currentResponse['completed_at'],
      });
    }

    // Insert new response
    await _supabase.from('quiz_responses').insert({
      'user_id': userId,
      'quiz_type': quizType,
      'responses': formattedAnswers,
      'anxiety_score': result.anxietyScore,
      'avoidance_score': result.avoidanceScore,
      'result_type': result.resultType,
      'version': nextVersion,
    });

    // Step 2: Update psych_profiles
    final existingProfile = await _supabase
        .from('psych_profiles')
        .select('attachment_style, completed_quizzes')
        .eq('user_id', userId)
        .maybeSingle();

    final attachmentStyle = {
      'type': result.resultType,
      'display_name': result.displayName,
      'anxiety_score': result.anxietyScore,
      'avoidance_score': result.avoidanceScore,
      'version': nextVersion,
      'completed_at': DateTime.now().toIso8601String(),
    };

    if (existingProfile == null) {
      // Create new profile
      await _supabase.from('psych_profiles').insert({
        'user_id': userId,
        'attachment_style': attachmentStyle,
        'completed_quizzes': [quizType],
        'last_updated': DateTime.now().toIso8601String(),
      });
    } else {
      // Update existing profile
      final currentQuizzes = existingProfile['completed_quizzes'] as List? ?? [];
      if (!currentQuizzes.contains(quizType)) {
        currentQuizzes.add(quizType);
      }

      await _supabase.from('psych_profiles').update({
        'attachment_style': attachmentStyle,
        'completed_quizzes': currentQuizzes,
        'last_updated': DateTime.now().toIso8601String(),
      }).eq('user_id', userId);
    }

    // Step 3: If user is in couples mode and has previously shared, notify partner
    // (Will be implemented in Phase 5 - Sharing System)
  }
}
