// lib/features/opinions/presentation/providers/profile_providers.dart

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Anonymous author profile, keyed by the opaque author handle (never a real
/// user_id — FORUM.md §3). All three providers below take a handle.

class AuthorProfileSummary {
  final String? relationshipStatus;
  final int followerCount;
  final bool isMine;
  final bool isFollowing;

  const AuthorProfileSummary({
    this.relationshipStatus,
    this.followerCount = 0,
    this.isMine = false,
    this.isFollowing = false,
  });
}

// Author profile summary (status, follower count, own/following flags).
final authorProfileProvider =
    FutureProvider.family<AuthorProfileSummary, String>((ref, handle) async {
  final supabase = ref.read(supabaseClientProvider);
  final rows = await supabase
      .rpc('get_author_profile', params: {'p_author_handle': handle});
  final list = rows as List;
  if (list.isEmpty) return const AuthorProfileSummary();
  final row = Map<String, dynamic>.from(list.first);
  return AuthorProfileSummary(
    relationshipStatus: row['relationship_status'] as String?,
    followerCount: row['follower_count'] as int? ?? 0,
    isMine: row['is_mine'] as bool? ?? false,
    isFollowing: row['is_following'] as bool? ?? false,
  );
});

// An author's opinions for the profile page (by handle).
final profileOpinionsProvider =
    FutureProvider.family<List<OpinionModel>, String>((ref, handle) async {
  final supabase = ref.read(supabaseClientProvider);
  final rows = await supabase
      .rpc('get_author_opinions', params: {'p_author_handle': handle});
  return (rows as List)
      .map((r) => OpinionModel.fromFeedRow(Map<String, dynamic>.from(r)))
      .toList();
});
