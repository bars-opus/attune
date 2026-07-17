// lib/features/community/data/repositories/community_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/community_question.dart';

class CommunityRepository {
  final SupabaseClient _supabase;

  CommunityRepository(this._supabase);

  // ============================================================
  // Get Community Feed (paginated)
  // ============================================================

  Future<List<CommunityQuestion>> getCommunityFeed({
    required String userId,
    String? typeFilter, // 'this_or_that', 'truth', 'dare', or null for all
    String? toneFilter, // 'connecting', 'romantic', 'playful', 'spicy', 'intimate', or null for all
    String? searchQuery,
    int limit = 20,
    String? cursor,
  }) async {
    final List<CommunityQuestion> allQuestions = [];
    final normalizedType = _normalizeTypeFilter(typeFilter);
    final normalizedTone = _normalizeToneFilter(toneFilter);
    final normalizedQuery = searchQuery?.trim();

    // Fetch This or That community questions
    var totQuery = _supabase
        .from('custom_this_or_that_questions')
        .select('*');

    // Fetch Truth or Dare community questions
    var todQuery = _supabase
        .from('custom_truth_or_dare_questions')
        .select('*');

    totQuery = totQuery
        .eq('shared_to_community', true)
        .eq('hidden_for_review', false);

    todQuery = todQuery
        .eq('shared_to_community', true)
        .eq('hidden_for_review', false);

    // Apply filters
    if (normalizedType != null) {
      if (normalizedType == 'this_or_that') {
        // Only fetch This or That
        final totResponse = await totQuery
            .order('community_usage_count', ascending: false)
            .order('created_at', ascending: false)
            .limit(limit);
        for (final json in totResponse) {
          final isSaved = await _isThisOrThatQuestionSaved(userId, json);
          allQuestions.add(CommunityQuestion.fromThisOrThatJson(json, isSaved: isSaved));
        }
        return allQuestions;
      } else if (normalizedType == 'truth') {
        todQuery = todQuery.eq('question_type', 'truth');
      } else if (normalizedType == 'dare') {
        todQuery = todQuery.eq('question_type', 'dare');
      }
      // If filter is 'truth' or 'dare', we need to merge with This or That? No, filter excludes This or That.
      // Actually, if filter is 'truth' or 'dare', we only want Truth or Dare questions of that subtype.
      // But the UI may also want to show This or That with a separate filter.
      // For simplicity, the filter options are: All, This or That, Truth, Dare
      if (normalizedType == 'truth' || normalizedType == 'dare') {
        final todResponse = await todQuery
            .order('community_usage_count', ascending: false)
            .order('created_at', ascending: false)
            .limit(limit);
        for (final json in todResponse) {
          final isSaved = await _isTruthOrDareQuestionSaved(userId, json);
          allQuestions.add(CommunityQuestion.fromTruthOrDareJson(json, isSaved: isSaved));
        }
        return allQuestions;
      }
    }

    // Apply tone filter
    if (normalizedTone != null) {
      totQuery = totQuery.eq('tone', normalizedTone);
      todQuery = todQuery.eq('tone', normalizedTone);
    }

    // Apply search query
    if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
      totQuery = totQuery.ilike('question_text', '%$normalizedQuery%');
      todQuery = todQuery.ilike('content', '%$normalizedQuery%');
    }

    // Execute both queries and merge results
    final totResponse = await totQuery
        .order('community_usage_count', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    final todResponse = await todQuery
        .order('community_usage_count', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);

    // Get saved status for each question
    for (final json in totResponse) {
      final isSaved = await _isThisOrThatQuestionSaved(userId, json);
      allQuestions.add(CommunityQuestion.fromThisOrThatJson(json, isSaved: isSaved));
    }

    for (final json in todResponse) {
      final isSaved = await _isTruthOrDareQuestionSaved(userId, json);
      allQuestions.add(CommunityQuestion.fromTruthOrDareJson(json, isSaved: isSaved));
    }

    // Sort merged results by community_usage_count descending
    allQuestions.sort((a, b) => b.communityUsageCount.compareTo(a.communityUsageCount));

    // Apply cursor pagination
    if (cursor != null) {
      final cursorDate = DateTime.parse(cursor);
      allQuestions.removeWhere((q) => q.createdAt.isBefore(cursorDate) || q.createdAt == cursorDate);
    }

    return allQuestions.take(limit).toList();
  }

  // ============================================================
  // Check if question is saved by user
  // ============================================================

  Future<bool> _isThisOrThatQuestionSaved(
    String userId,
    Map<String, dynamic> sourceQuestion,
  ) async {
    final response = await _supabase
        .from('custom_this_or_that_questions')
        .select('id')
        .eq('user_id', userId)
        .eq('question_text', sourceQuestion['question_text'])
        .eq('option_a', sourceQuestion['option_a'])
        .eq('option_b', sourceQuestion['option_b'])
        .maybeSingle();

    return response != null;
  }

  Future<bool> _isTruthOrDareQuestionSaved(
    String userId,
    Map<String, dynamic> sourceQuestion,
  ) async {
    final response = await _supabase
        .from('custom_truth_or_dare_questions')
        .select('id')
        .eq('user_id', userId)
        .eq('question_type', sourceQuestion['question_type'])
        .eq('content', sourceQuestion['content'])
        .maybeSingle();

    return response != null;
  }

  // ============================================================
  // Save community question to personal bank
  // ============================================================

  Future<void> saveCommunityQuestion({
    required String userId,
    required CommunityQuestion question,
  }) async {
    if (question.type == 'this_or_that') {
      // Copy to This or That custom questions
      await _supabase.from('custom_this_or_that_questions').insert({
        'user_id': userId,
        'question_text': question.content,
        'option_a': question.optionA,
        'option_b': question.optionB,
        'emoji_a': question.emojiA,
        'emoji_b': question.emojiB,
        'tone': question.tone,
        'is_private': true,
        'shared_to_community': false,
      });

      // Increment community usage count on original
      await _supabase.rpc('increment_community_usage', params: {
        'p_question_id': question.id,
        'p_table': 'this_or_that',
      });
    } else {
      // Copy to Truth or Dare custom questions
      await _supabase.from('custom_truth_or_dare_questions').insert({
        'user_id': userId,
        'question_type': question.questionType,
        'content': question.content,
        'tone': question.tone,
        'is_private': true,
        'shared_to_community': false,
      });

      // Increment community usage count on original
      await _supabase.rpc('increment_community_usage', params: {
        'p_question_id': question.id,
        'p_table': 'truth_or_dare',
      });
    }
  }

  // ============================================================
  // Unsave community question (delete personal copy)
  // ============================================================

  Future<void> unsaveCommunityQuestion({
    required String userId,
    required CommunityQuestion question,
  }) async {
    if (question.type == 'this_or_that') {
      await _supabase
          .from('custom_this_or_that_questions')
          .delete()
          .eq('user_id', userId)
          .eq('question_text', question.content)
          .eq('option_a', question.optionA!)
          .eq('option_b', question.optionB!);
      return;
    }

    await _supabase
        .from('custom_truth_or_dare_questions')
        .delete()
        .eq('user_id', userId)
        .eq('question_type', question.questionType!)
        .eq('content', question.content);
  }

  // ============================================================
  // Share user's custom question with community
  // ============================================================

  Future<void> shareWithCommunity({
    required String questionId,
    required String table,
  }) async {
    final tableName = table == 'this_or_that'
        ? 'custom_this_or_that_questions'
        : 'custom_truth_or_dare_questions';

    await _supabase
        .from(tableName)
        .update({
          'shared_to_community': true,
          'community_usage_count': 0,
        })
        .eq('id', questionId);
  }

  // ============================================================
  // Unshare from community
  // ============================================================

  Future<void> unshareFromCommunity({
    required String questionId,
    required String table,
  }) async {
    final tableName = table == 'this_or_that'
        ? 'custom_this_or_that_questions'
        : 'custom_truth_or_dare_questions';

    await _supabase
        .from(tableName)
        .update({
          'shared_to_community': false,
        })
        .eq('id', questionId);
  }

  // ============================================================
  // Report community question
  // ============================================================

  Future<void> reportCommunityQuestion({
    required String questionId,
    required String table,
    required String reportedBy,
    required String reason,
  }) async {
    // Route through the shared moderation RPC (games-hardening migration). It
    // records ONE report per (question, reporter) and only hides the question
    // once >= 2 DISTINCT reporters flag it — so a lone actor cannot censor a
    // question. Doing the count/hide client-side (as before) both bypassed that
    // threshold (hid on a single report) and raced on report_count. The old
    // forum_reports insert also used non-existent community_question_* columns
    // and would have thrown.
    await _supabase.rpc(
      'report_custom_question',
      params: {'p_question_id': questionId, 'p_reason': reason},
    );
  }

  String? _normalizeTypeFilter(String? value) {
    if (value == null || value.isEmpty) return null;

    switch (value.trim().toLowerCase()) {
      case 'this or that':
      case 'this_or_that':
        return 'this_or_that';
      case 'truth':
        return 'truth';
      case 'dare':
        return 'dare';
      default:
        return null;
    }
  }

  String? _normalizeToneFilter(String? value) {
    if (value == null || value.isEmpty) return null;

    switch (value.trim().toLowerCase()) {
      case 'connecting':
      case 'romantic':
      case 'playful':
      case 'spicy':
      case 'intimate':
        return value.trim().toLowerCase();
      default:
        return null;
    }
  }
}
