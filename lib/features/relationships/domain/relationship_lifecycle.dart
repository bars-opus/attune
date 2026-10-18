/// Where a shared space is after it stops being active (Spec 3a; research
/// 05 D.1). Read from get_my_relationship_lifecycle; never says whether the
/// other person sealed their side.
enum LifecycleStatus { paused, ended, archived }

class RelationshipLifecycle {
  const RelationshipLifecycle({
    required this.relationshipId,
    required this.status,
    required this.partnerFirstName,
    required this.endedByMe,
    required this.endedByPartner,
    required this.pausedByMe,
    required this.endedAt,
    required this.windowEndsAt,
    required this.pausedAt,
    required this.decideBy,
    required this.sealedByMe,
    required this.chatReadable,
  });

  factory RelationshipLifecycle.fromRow(Map<String, dynamic> row) {
    DateTime? at(String key) {
      final raw = row[key] as String?;
      return raw == null ? null : DateTime.parse(raw);
    }

    final status = switch (row['status']) {
      'paused' => LifecycleStatus.paused,
      'ended' => LifecycleStatus.ended,
      'archived' => LifecycleStatus.archived,
      final other => throw FormatException('not a lifecycle status: $other'),
    };
    return RelationshipLifecycle(
      relationshipId: row['relationship_id'] as String,
      status: status,
      partnerFirstName: row['partner_first_name'] as String?,
      endedByMe: row['ended_by_me'] as bool? ?? false,
      endedByPartner: row['ended_by_partner'] as bool? ?? false,
      pausedByMe: row['paused_by_me'] as bool? ?? false,
      endedAt: at('ended_at'),
      windowEndsAt: at('window_ends_at'),
      pausedAt: at('paused_at'),
      decideBy: at('decide_by'),
      sealedByMe: row['sealed_by_me'] as bool? ?? false,
      chatReadable: row['chat_readable'] as bool? ?? false,
    );
  }

  final String relationshipId;
  final LifecycleStatus status;
  final String? partnerFirstName;
  final bool endedByMe;

  /// The partner ended it (not this person, and not the 30-day pause expiry
  /// or a new relationship): only then does the ending sheet name them.
  final bool endedByPartner;
  final bool pausedByMe;
  final DateTime? endedAt;
  final DateTime? windowEndsAt;
  final DateTime? pausedAt;
  final DateTime? decideBy;
  final bool sealedByMe;
  final bool chatReadable;
}

/// Whole days from [now] until [until]; 0 when under a day or past.
int daysLeft(DateTime? until, DateTime now) {
  if (until == null || !until.isAfter(now)) return 0;
  return until.difference(now).inDays;
}
