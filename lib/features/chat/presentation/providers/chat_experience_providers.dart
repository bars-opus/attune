import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final chatConnectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  final initial = await connectivity.checkConnectivity();
  yield initial != ConnectivityResult.none;

  await for (final result in connectivity.onConnectivityChanged) {
    yield result != ConnectivityResult.none;
  }
});

final chatTranslatorEntryEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.translatorEntry,
  );
});

final chatExpandedHeaderDrawerEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.expandedHeaderDrawer,
  );
});

final chatHistoricalImportEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.historicalImport,
  );
});

final chatContextRepositoryProvider = Provider<ChatContextRepository>((ref) {
  return ChatContextRepository(ref.read(supabaseClientProvider));
});

final chatHeaderSnapshotProvider =
    FutureProvider.family<ChatHeaderSnapshot, String>((
      ref,
      relationshipId,
    ) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return const ChatHeaderSnapshot();
      return ref
          .read(chatContextRepositoryProvider)
          .loadHeaderSnapshot(userId: user.id, relationshipId: relationshipId);
    });

final chatInsightsProvider =
    FutureProvider.family<List<ChatInsightItem>, String>((
      ref,
      relationshipId,
    ) async {
      final user = ref.watch(currentUserProvider);
      if (user == null) return const [];
      return ref
          .read(chatContextRepositoryProvider)
          .loadInsights(userId: user.id, relationshipId: relationshipId);
    });

class ChatContextRepository {
  ChatContextRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<ChatHeaderSnapshot> loadHeaderSnapshot({
    required String userId,
    required String relationshipId,
  }) async {
    final pulseRows = await _supabase
        .from('pulse_scores')
        .select('overall_score,week_ending')
        .eq('relationship_id', relationshipId)
        .order('week_ending', ascending: false)
        .limit(2);

    PulseSummary? pulse;
    if (pulseRows.isNotEmpty) {
      final latest = Map<String, dynamic>.from(pulseRows.first);
      final previous =
          pulseRows.length > 1 ? Map<String, dynamic>.from(pulseRows[1]) : null;
      final latestScore = (latest['overall_score'] as num?)?.toInt();
      final previousScore = (previous?['overall_score'] as num?)?.toInt();
      if (latestScore != null) {
        pulse = PulseSummary(
          score: latestScore,
          delta: previousScore == null ? null : latestScore - previousScore,
        );
      }
    }

    final insightRows = await _supabase
        .from('personal_insights')
        .select('id,insight_type,insight_body,created_at,viewed_at')
        .eq('user_id', userId)
        .eq('relationship_id', relationshipId)
        .isFilter('viewed_at', null)
        .order('created_at', ascending: false)
        .limit(1);

    final latestUnreadInsight =
        insightRows.isEmpty
            ? null
            : ChatInsightItem.fromRow(
              Map<String, dynamic>.from(insightRows.first),
            );

    final reminderRows = await _supabase
        .from('scheduled_notifications')
        .select('id,notification_type,scheduled_for,status,metadata')
        .eq('user_id', userId)
        .eq('status', 'pending')
        .gte('scheduled_for', DateTime.now().toUtc().toIso8601String())
        .order('scheduled_for', ascending: true)
        .limit(1);

    final nextReminder =
        reminderRows.isEmpty
            ? null
            : ChatReminderSummary.fromRow(
              Map<String, dynamic>.from(reminderRows.first),
            );

    return ChatHeaderSnapshot(
      pulse: pulse,
      latestUnreadInsight: latestUnreadInsight,
      nextReminder: nextReminder,
    );
  }

  Future<List<ChatInsightItem>> loadInsights({
    required String userId,
    required String relationshipId,
  }) async {
    final rows = await _supabase
        .from('personal_insights')
        .select('id,insight_type,insight_body,created_at,viewed_at')
        .eq('user_id', userId)
        .eq('relationship_id', relationshipId)
        .order('created_at', ascending: false)
        .limit(20);

    return rows
        .map((row) => ChatInsightItem.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> markInsightsViewed(List<String> insightIds) async {
    if (insightIds.isEmpty) return;
    await _supabase
        .from('personal_insights')
        .update({'viewed_at': DateTime.now().toUtc().toIso8601String()})
        .inFilter('id', insightIds)
        .isFilter('viewed_at', null);
  }
}

class ChatHeaderSnapshot {
  final PulseSummary? pulse;
  final ChatInsightItem? latestUnreadInsight;
  final ChatReminderSummary? nextReminder;

  const ChatHeaderSnapshot({
    this.pulse,
    this.latestUnreadInsight,
    this.nextReminder,
  });
}

class PulseSummary {
  final int score;
  final int? delta;

  const PulseSummary({required this.score, this.delta});
}

class ChatInsightItem {
  final String id;
  final String type;
  final String body;
  final DateTime createdAt;
  final DateTime? viewedAt;

  const ChatInsightItem({
    required this.id,
    required this.type,
    required this.body,
    required this.createdAt,
    required this.viewedAt,
  });

  factory ChatInsightItem.fromRow(Map<String, dynamic> row) {
    return ChatInsightItem(
      id: row['id'] as String,
      type: row['insight_type'] as String? ?? 'insight',
      body: row['insight_body'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      viewedAt:
          row['viewed_at'] == null
              ? null
              : DateTime.parse(row['viewed_at'] as String).toLocal(),
    );
  }

  bool get isUnread => viewedAt == null;
}

class ChatReminderSummary {
  final String id;
  final String type;
  final DateTime scheduledFor;

  const ChatReminderSummary({
    required this.id,
    required this.type,
    required this.scheduledFor,
  });

  factory ChatReminderSummary.fromRow(Map<String, dynamic> row) {
    return ChatReminderSummary(
      id: row['id'] as String,
      type: row['notification_type'] as String? ?? 'reminder',
      scheduledFor: DateTime.parse(row['scheduled_for'] as String).toLocal(),
    );
  }
}
