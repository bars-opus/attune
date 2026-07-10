// lib/features/opinions/presentation/providers/profile_providers.dart

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// User's profile status (relationship status)
final userProfileStatusProvider = FutureProvider.family<String?, String>((
  ref,
  userId,
) async {
  final supabase = ref.read(supabaseClientProvider);
  final response =
      await supabase
          .from('profiles')
          .select('relationship_status')
          .eq('id', userId)
          .maybeSingle();
  return response?['relationship_status'] as String?;
});

// Follower count for a user
final profileFollowerCountProvider = FutureProvider.family<int, String>((
  ref,
  userId,
) async {
  final supabase = ref.read(supabaseClientProvider);
  final response =
      await supabase
          .from('opinion_follower_counts')
          .select('follower_count')
          .eq('user_id', userId)
          .maybeSingle();
  return response?['follower_count'] as int? ?? 0;
});

// User's opinions (for profile page)
final profileOpinionsProvider =
    FutureProvider.family<List<OpinionModel>, String>((ref, userId) async {
      final supabase = ref.read(supabaseClientProvider);
      final currentUserId = ref.read(currentUserIdProvider);

      // Get user's opinions
      final opinionsRes = await supabase
          .from('opinions')
          .select('*')
          .eq('user_id', userId)
          .isFilter('removed_at', null)
          .eq('hidden_pending_review', false)
          .order('created_at', ascending: false);

      final List<OpinionModel> opinions = [];
      for (final json in opinionsRes) {
        // Get user's reaction (if current user)
        String? userReaction;
        if (currentUserId != null) {
          final reactionRes =
              await supabase
                  .from('opinion_reactions')
                  .select('reaction_type')
                  .eq('opinion_id', json['id'])
                  .eq('user_id', currentUserId)
                  .maybeSingle();
          userReaction = reactionRes?['reaction_type'] as String?;
        }

        opinions.add(
          OpinionModel(
            id: json['id'],
            userId: json['user_id'],
            content: json['content'],
            relationshipStatus: json['relationship_status_at_post'],
            likeCount: json['like_count'] ?? 0,
            dislikeCount: json['dislike_count'] ?? 0,
            commentCount: json['comment_count'] ?? 0,
            userReaction: userReaction,
            createdAt: DateTime.parse(json['created_at']),
          ),
        );
      }

      return opinions;
    });
