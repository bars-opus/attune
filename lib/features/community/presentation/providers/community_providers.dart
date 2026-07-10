// lib/features/community/presentation/providers/community_providers.dart

import 'package:attune/features/community/data/models/community_question.dart';
import 'package:attune/features/community/data/repositories/community_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return CommunityRepository(supabase);
});

final currentUserIdProvider = Provider<String?>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  return supabase.auth.currentUser?.id;
});

// Community feed
final communityFeedProvider = FutureProvider.family<List<CommunityQuestion>, ({
  String? typeFilter,
  String? toneFilter,
  String? searchQuery,
  int limit,
  String? cursor,
})>((ref, params) async {
  final repository = ref.read(communityRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) return [];

  return await repository.getCommunityFeed(
    userId: userId,
    typeFilter: params.typeFilter,
    toneFilter: params.toneFilter,
    searchQuery: params.searchQuery,
    limit: params.limit,
    cursor: params.cursor,
  );
});

// Save community question
final saveCommunityQuestionProvider = FutureProvider.family<void, CommunityQuestion>((ref, question) async {
  final repository = ref.read(communityRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');

  await repository.saveCommunityQuestion(
    userId: userId,
    question: question,
  );
  ref.invalidate(communityFeedProvider);
});

// Unsave community question
final unsaveCommunityQuestionProvider = FutureProvider.family<void, ({
  CommunityQuestion question,
})>((ref, params) async {
  final repository = ref.read(communityRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');

  await repository.unsaveCommunityQuestion(
    userId: userId,
    question: params.question,
  );
  ref.invalidate(communityFeedProvider);
});

// Share with community
final shareWithCommunityProvider = FutureProvider.family<void, ({
  String questionId,
  String table,
})>((ref, params) async {
  final repository = ref.read(communityRepositoryProvider);
  await repository.shareWithCommunity(
    questionId: params.questionId,
    table: params.table,
  );
});

// Unshare from community
final unshareFromCommunityProvider = FutureProvider.family<void, ({
  String questionId,
  String table,
})>((ref, params) async {
  final repository = ref.read(communityRepositoryProvider);
  await repository.unshareFromCommunity(
    questionId: params.questionId,
    table: params.table,
  );
});

// Report community question
final reportCommunityQuestionProvider = FutureProvider.family<void, ({
  String questionId,
  String table,
  String reason,
})>((ref, params) async {
  final repository = ref.read(communityRepositoryProvider);
  final userId = ref.read(currentUserIdProvider);
  if (userId == null) throw Exception('Not authenticated');

  await repository.reportCommunityQuestion(
    questionId: params.questionId,
    table: params.table,
    reportedBy: userId,
    reason: params.reason,
  );
  ref.invalidate(communityFeedProvider);
});
