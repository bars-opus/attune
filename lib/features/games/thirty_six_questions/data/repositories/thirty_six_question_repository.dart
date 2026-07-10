// lib/features/games/thirty_six_questions/data/repositories/thirty_six_question_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/thirty_six_question_answer.dart';
import '../models/thirty_six_question_chapter.dart';
import '../models/thirty_six_question_journey.dart';

class ThirtySixQuestionRepository {
  final SupabaseClient _supabase;

  ThirtySixQuestionRepository(this._supabase);

  Future<ThirtySixQuestionJourney> createJourney({
    required String relationshipId,
  }) async {
    final existing = await getActiveJourney(relationshipId);
    if (existing != null) return existing;

    final response =
        await _supabase
            .from('thirty_six_question_journeys')
            .insert({
              'relationship_id': relationshipId,
              'status': 'in_progress',
            })
            .select()
            .single();

    return ThirtySixQuestionJourney.fromJson(response);
  }

  Future<ThirtySixQuestionJourney?> getActiveJourney(
    String relationshipId,
  ) async {
    final response =
        await _supabase
            .from('thirty_six_question_journeys')
            .select('*')
            .eq('relationship_id', relationshipId)
            .eq('status', 'in_progress')
            .maybeSingle();

    return response == null
        ? null
        : ThirtySixQuestionJourney.fromJson(response);
  }

  Future<ThirtySixQuestionJourney?> getJourney(String journeyId) async {
    final response =
        await _supabase
            .from('thirty_six_question_journeys')
            .select('*')
            .eq('id', journeyId)
            .maybeSingle();

    return response == null
        ? null
        : ThirtySixQuestionJourney.fromJson(response);
  }

  Future<void> updateJourneyStatus({
    required String journeyId,
    required String status,
  }) async {
    await _supabase
        .from('thirty_six_question_journeys')
        .update({
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', journeyId);
  }

  Future<ThirtySixQuestionChapter> createChapterSession({
    required String journeyId,
    required String relationshipId,
    required String initiatorId,
    required int chapter,
    required List<Map<String, dynamic>> questions,
  }) async {
    if (questions.length < 12) {
      throw Exception('Not enough questions available for Chapter $chapter.');
    }

    final sessionResponse =
        await _supabase
            .from('game_sessions')
            .insert({
              'relationship_id': relationshipId,
              'initiator_id': initiatorId,
              'game_type': '36_questions',
              'tone': 'connecting',
              'status': 'invited',
              'total_rounds': 12,
              'current_round': 1,
              'journey_id': journeyId,
              'chapter': chapter,
              'skips_used': 0,
            })
            .select()
            .single();

    final sessionId = sessionResponse['id'] as String;
    for (var i = 0; i < 12; i++) {
      final question = questions[i];
      await _supabase.from('game_session_rounds').insert({
        'session_id': sessionId,
        'round_number': i + 1,
        'canonical_question_id': question['canonical_id'],
        'question_text_snapshot': question['question_text'],
        'level': chapter,
      });
    }

    return ThirtySixQuestionChapter.fromJson(sessionResponse);
  }

  Future<ThirtySixQuestionChapter?> getChapterSession(String sessionId) async {
    final response =
        await _supabase
            .from('game_sessions')
            .select('*')
            .eq('id', sessionId)
            .maybeSingle();

    return response == null
        ? null
        : ThirtySixQuestionChapter.fromJson(response);
  }

  Future<List<ThirtySixQuestionChapter>> getJourneyChapters(
    String journeyId,
  ) async {
    final response = await _supabase
        .from('game_sessions')
        .select('*')
        .eq('journey_id', journeyId)
        .eq('game_type', '36_questions')
        .order('chapter', ascending: true)
        .order('created_at', ascending: false);

    final byChapter = <int, ThirtySixQuestionChapter>{};
    for (final row in response) {
      final chapter = ThirtySixQuestionChapter.fromJson(row);
      byChapter.putIfAbsent(chapter.chapterNumber, () => chapter);
    }
    return byChapter.values.toList()
      ..sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
  }

  Future<ThirtySixQuestionChapter?> getActiveChapterForJourney({
    required String journeyId,
    required int chapter,
  }) async {
    final response =
        await _supabase
            .from('game_sessions')
            .select('*')
            .eq('journey_id', journeyId)
            .eq('chapter', chapter)
            .eq('game_type', '36_questions')
            .inFilter('status', ['invited', 'active'])
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

    return response == null
        ? null
        : ThirtySixQuestionChapter.fromJson(response);
  }

  Future<ThirtySixQuestionChapter> acceptChapterInvitation({
    required String sessionId,
  }) async {
    final response =
        await _supabase
            .from('game_sessions')
            .update({
              'status': 'active',
              'started_at': DateTime.now().toIso8601String(),
            })
            .eq('id', sessionId)
            .eq('status', 'invited')
            .select()
            .single();

    return ThirtySixQuestionChapter.fromJson(response);
  }

  Future<void> updateChapterStatus({
    required String sessionId,
    required String status,
    String? abandonReason,
  }) async {
    final updateData = <String, dynamic>{'status': status};
    if (abandonReason != null) updateData['abandon_reason'] = abandonReason;
    if (status == 'completed') {
      updateData['completed_at'] = DateTime.now().toIso8601String();
    }
    if (status == 'abandoned') {
      updateData['abandoned_at'] = DateTime.now().toIso8601String();
    }

    await _supabase
        .from('game_sessions')
        .update(updateData)
        .eq('id', sessionId);
  }

  Future<({String journeyId, int chapter, bool journeyCompleted})>
  completeChapter(String sessionId) async {
    final response = await _supabase.rpc(
      'complete_thirty_six_chapter',
      params: {'p_session_id': sessionId},
    );

    final row =
        response is List && response.isNotEmpty
            ? Map<String, dynamic>.from(response.first as Map)
            : <String, dynamic>{};

    return (
      journeyId: row['journey_id'] as String,
      chapter: row['chapter'] as int,
      journeyCompleted: row['journey_completed'] as bool? ?? false,
    );
  }

  Future<ThirtySixQuestionAnswer> submitAnswer({
    required String roundId,
    required String userId,
    required String answerText,
  }) async {
    final trimmed = answerText.trim();
    if (trimmed.isEmpty) throw Exception('Answer cannot be empty.');
    if (trimmed.length > 400) {
      throw Exception('Answer must be 400 characters or fewer.');
    }

    final round =
        await _supabase
            .from('game_session_rounds')
            .select('both_answered')
            .eq('id', roundId)
            .single();
    if (round['both_answered'] == true) {
      throw Exception('This question has already been revealed.');
    }

    final response =
        await _supabase
            .from('thirty_six_question_answers')
            .upsert({
              'round_id': roundId,
              'user_id': userId,
              'answer_text': trimmed,
              'is_removed': false,
              'is_safety_triggered': false,
              'is_excluded_from_ai': false,
              'submitted_at': DateTime.now().toIso8601String(),
              'removed_at': null,
            }, onConflict: 'round_id,user_id')
            .select()
            .single();

    await _supabase.rpc(
      'mark_thirty_six_round_complete',
      params: {'p_round_id': roundId},
    );

    return ThirtySixQuestionAnswer.fromJson(response);
  }

  Future<ThirtySixQuestionAnswer?> getAnswer({
    required String roundId,
    required String userId,
  }) async {
    final response =
        await _supabase
            .from('thirty_six_question_answers')
            .select('*')
            .eq('round_id', roundId)
            .eq('user_id', userId)
            .maybeSingle();

    return response == null ? null : ThirtySixQuestionAnswer.fromJson(response);
  }

  Future<List<ThirtySixQuestionAnswer>> getRoundAnswers(String roundId) async {
    final response = await _supabase
        .from('thirty_six_question_answers')
        .select('*')
        .eq('round_id', roundId);

    return response
        .map((json) => ThirtySixQuestionAnswer.fromJson(json))
        .toList();
  }

  Future<void> removeAnswer({
    required String answerId,
    required String userId,
  }) async {
    await _supabase
        .from('thirty_six_question_answers')
        .update({
          'is_removed': true,
          'removed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', answerId)
        .eq('user_id', userId);

    await _invalidateReflectionsForAnswer(answerId);
  }

  Future<void> flagSafetyTriggered(String answerId) async {
    await _supabase
        .from('thirty_six_question_answers')
        .update({'is_safety_triggered': true, 'is_excluded_from_ai': true})
        .eq('id', answerId);
  }

  Future<Map<String, dynamic>?> getChapterReflection({
    required String journeyId,
    required int chapter,
  }) async {
    final response =
        await _supabase
            .from('chapter_reflections')
            .select('*')
            .eq('journey_id', journeyId)
            .eq('chapter', chapter)
            .eq('is_hidden', false)
            .maybeSingle();

    return response;
  }

  Future<Map<String, dynamic>> getJourneyReflection({
    required String journeyId,
  }) async {
    final response =
        await _supabase
            .from('thirty_six_question_journeys')
            .select(
              'final_observation, final_observation_confidence, final_observation_hidden',
            )
            .eq('id', journeyId)
            .single();

    return {
      'observation': response['final_observation'],
      'confidence': response['final_observation_confidence'],
      'is_hidden': response['final_observation_hidden'] ?? false,
    };
  }

  Future<Map<String, dynamic>> generateChapterReflection({
    required String journeyId,
    required int chapter,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'generate-thirty-six-reflection',
        body: {'journey_id': journeyId, 'chapter': chapter, 'type': 'chapter'},
      );
      return Map<String, dynamic>.from(response.data as Map? ?? const {});
    } catch (_) {
      return {'observation': null, 'confidence': 'low'};
    }
  }

  Future<Map<String, dynamic>> generateJourneyReflection({
    required String journeyId,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'generate-thirty-six-reflection',
        body: {'journey_id': journeyId, 'type': 'journey'},
      );
      return Map<String, dynamic>.from(response.data as Map? ?? const {});
    } catch (_) {
      return {'observation': null, 'confidence': 'low'};
    }
  }

  Future<Map<String, dynamic>> useSkip({
    required String sessionId,
    required String roundId,
    String locale = 'en',
  }) async {
    final response = await _supabase.rpc(
      'replace_thirty_six_question',
      params: {
        'p_session_id': sessionId,
        'p_round_id': roundId,
        'p_locale': locale,
      },
    );

    final row =
        response is List && response.isNotEmpty
            ? Map<String, dynamic>.from(response.first as Map)
            : <String, dynamic>{};
    if (row.isEmpty) throw Exception('Could not replace question.');
    return row;
  }

  Future<List<Map<String, dynamic>>> selectChapterQuestions({
    required String relationshipId,
    required int chapter,
    String locale = 'en',
  }) async {
    final canonicalResponse = await _supabase
        .from('thirty_six_questions_canonical')
        .select('id, chapter, intensity_order, requires_review')
        .eq('chapter', chapter)
        .eq('active', true)
        .order('intensity_order', ascending: true);

    final canonicalIds =
        canonicalResponse.map((q) => q['id'] as String).toList();
    if (canonicalIds.isEmpty) return [];

    final translations = await _loadTranslations(
      canonicalIds: canonicalIds,
      locale: locale,
      chapter: chapter,
    );

    final seenMap = await getSeenMap(relationshipId);
    final questions = <Map<String, dynamic>>[];

    for (final canonical in canonicalResponse) {
      final canonicalId = canonical['id'] as String;
      final translation = translations[canonicalId];
      if (translation == null) continue;

      questions.add({
        'canonical_id': canonicalId,
        'question_text': translation,
        'intensity_order': canonical['intensity_order'] as int,
        'seen_at': seenMap[canonicalId],
      });
    }

    final unseen =
        questions.where((q) => q['seen_at'] == null).toList()..sort(
          (a, b) => (a['intensity_order'] as int).compareTo(
            b['intensity_order'] as int,
          ),
        );
    final seen =
        questions.where((q) => q['seen_at'] != null).toList()..sort(
          (a, b) =>
              (a['seen_at'] as DateTime).compareTo(b['seen_at'] as DateTime),
        );

    return [...unseen, ...seen].take(12).toList();
  }

  Future<Map<String, DateTime>> getSeenMap(String relationshipId) async {
    final response = await _supabase.rpc(
      'get_thirty_six_seen_map',
      params: {'p_relationship_id': relationshipId},
    );

    final result = <String, DateTime>{};
    if (response is List) {
      for (final row in response) {
        final map = Map<String, dynamic>.from(row as Map);
        result[map['canonical_question_id'] as String] = DateTime.parse(
          map['seen_at'] as String,
        );
      }
    }
    return result;
  }

  Future<ThirtySixQuestionChapter> sendContinuationInvite({
    required String journeyId,
    required String relationshipId,
    required String initiatorId,
    required int chapter,
    String locale = 'en',
  }) async {
    final journey = await getJourney(journeyId);
    if (journey == null) throw Exception('Journey not found.');
    if (journey.status != 'in_progress') {
      throw Exception('This journey is not active.');
    }
    if (chapter < 1 || chapter > 3) throw Exception('Invalid chapter.');
    if (chapter == 2 && journey.chapter1CompletedAt == null) {
      throw Exception('Chapter 1 must be completed before Chapter 2.');
    }
    if (chapter == 3 && journey.chapter2CompletedAt == null) {
      throw Exception('Chapter 2 must be completed before Chapter 3.');
    }

    final existing = await getActiveChapterForJourney(
      journeyId: journeyId,
      chapter: chapter,
    );
    if (existing != null) return existing;

    final questions = await selectChapterQuestions(
      relationshipId: relationshipId,
      chapter: chapter,
      locale: locale,
    );

    final chapterSession = await createChapterSession(
      journeyId: journeyId,
      relationshipId: relationshipId,
      initiatorId: initiatorId,
      chapter: chapter,
      questions: questions,
    );

    await _sendChapterInvitation(
      relationshipId: relationshipId,
      sessionId: chapterSession.sessionId,
      journeyId: journeyId,
      chapter: chapter,
      initiatorId: initiatorId,
    );

    return chapterSession;
  }

  Future<void> expireInvitations() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));
    final response = await _supabase
        .from('game_sessions')
        .select('id')
        .eq('game_type', '36_questions')
        .eq('status', 'invited')
        .lt('created_at', cutoff.toIso8601String());

    for (final session in response) {
      await updateChapterStatus(
        sessionId: session['id'] as String,
        status: 'abandoned',
        abandonReason: 'invite_expired',
      );
    }
  }

  Future<void> expireInactiveChapters() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final response = await _supabase
        .from('game_sessions')
        .select('id')
        .eq('game_type', '36_questions')
        .eq('status', 'active')
        .lt('started_at', cutoff.toIso8601String());

    for (final session in response) {
      await updateChapterStatus(
        sessionId: session['id'] as String,
        status: 'abandoned',
        abandonReason: 'inactivity',
      );
    }
  }

  Future<void> abandonChapter({required String sessionId}) async {
    await updateChapterStatus(
      sessionId: sessionId,
      status: 'abandoned',
      abandonReason: 'user_initiated',
    );
  }

  Future<void> abandonJourney({required String journeyId}) async {
    final chapters = await getJourneyChapters(journeyId);
    for (final chapter in chapters) {
      if (chapter.isActive || chapter.isInvited) {
        await updateChapterStatus(
          sessionId: chapter.sessionId,
          status: 'abandoned',
          abandonReason: 'user_initiated',
        );
      }
    }
    await updateJourneyStatus(journeyId: journeyId, status: 'abandoned');
  }

  Future<String> getPartnerId(String relationshipId, String userId) async {
    final relationship =
        await _supabase
            .from('relationships')
            .select('user_a, user_b')
            .eq('id', relationshipId)
            .single();

    final userA = relationship['user_a'] as String;
    final userB = relationship['user_b'] as String;
    return userA == userId ? userB : userA;
  }

  Future<String> getPartnerName(String relationshipId, String userId) async {
    final partnerId = await getPartnerId(relationshipId, userId);
    final profile =
        await _supabase
            .from('profiles')
            .select('display_name')
            .eq('id', partnerId)
            .maybeSingle();
    return profile?['display_name'] as String? ?? 'Partner';
  }

  Future<Map<String, String>> getRelationshipMembers(
    String relationshipId,
  ) async {
    final relationship =
        await _supabase
            .from('relationships')
            .select('user_a, user_b')
            .eq('id', relationshipId)
            .single();

    return {
      'user_a': relationship['user_a'] as String,
      'user_b': relationship['user_b'] as String,
    };
  }

  Future<Map<String, String>> _loadTranslations({
    required List<String> canonicalIds,
    required String locale,
    required int chapter,
  }) async {
    final localeRows = await _supabase
        .from('thirty_six_questions_translations')
        .select('canonical_id, question_text, is_reviewed')
        .inFilter('canonical_id', canonicalIds)
        .eq('locale', locale);

    final enRows = await _supabase
        .from('thirty_six_questions_translations')
        .select('canonical_id, question_text, is_reviewed')
        .inFilter('canonical_id', canonicalIds)
        .eq('locale', 'en');

    final result = <String, String>{};
    for (final row in [...enRows, ...localeRows]) {
      final isReviewed = row['is_reviewed'] as bool? ?? false;
      if (chapter == 3 && !isReviewed) continue;
      result[row['canonical_id'] as String] = row['question_text'] as String;
    }
    return result;
  }

  Future<void> _sendChapterInvitation({
    required String relationshipId,
    required String sessionId,
    required String journeyId,
    required int chapter,
    required String initiatorId,
  }) async {
    final partnerId = await getPartnerId(relationshipId, initiatorId);
    final profile =
        await _supabase
            .from('profiles')
            .select('display_name')
            .eq('id', initiatorId)
            .maybeSingle();
    final initiatorName = profile?['display_name'] as String? ?? 'Your partner';

    await _supabase.functions.invoke(
      'send-notification',
      body: {
        'userId': partnerId,
        'type': 'thirty_six_question_invite',
        'partnerName': initiatorName,
        'chapter': chapter,
        'journeyId': journeyId,
        'sessionId': sessionId,
      },
    );
  }

  Future<void> _invalidateReflectionsForAnswer(String answerId) async {
    await _supabase
        .from('chapter_reflections')
        .update({'is_hidden': true})
        .contains('source_answer_ids', [answerId]);

    await _supabase
        .from('thirty_six_question_journeys')
        .update({
          'final_observation_hidden': true,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .contains('final_source_answer_ids', [answerId]);
  }
}
