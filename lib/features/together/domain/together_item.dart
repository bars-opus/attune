/// One thing on the couple's calendar, from `list_together_items`:
/// a Together event, a moment, a reminder, or a Planning date or to-do.
/// One shape for every kind (plan ruling R8).
library;

enum TogetherItemKind { event, moment, reminder, planningDate, planningItem }

enum TogetherVisibility {
  shared('shared'),
  busyOnly('busy_only'),
  private('private');

  const TogetherVisibility(this.wire);
  final String wire;

  static TogetherVisibility fromWire(String? s) =>
      values.firstWhere((v) => v.wire == s, orElse: () => shared);
}

/// Whose an item is, seen from one partner: theirs, the other's, or both.
enum TogetherWho { me, partner, us }

const _kinds = {
  'event': TogetherItemKind.event,
  'moment': TogetherItemKind.moment,
  'reminder': TogetherItemKind.reminder,
  'planning_date': TogetherItemKind.planningDate,
  'planning_item': TogetherItemKind.planningItem,
};

class TogetherItem {
  const TogetherItem({
    required this.kind,
    required this.id,
    required this.date,
    this.startsAt,
    this.endsAt,
    required this.allDay,
    this.tz,
    required this.title,
    required this.participantIds,
    this.ownerId,
    this.createdBy,
    this.visibility = TogetherVisibility.shared,
    this.status = 'confirmed',
    this.sourceRef = const {},
  });

  factory TogetherItem.fromRow(Map<String, dynamic> r) {
    DateTime? local(Object? v) =>
        v == null ? null : DateTime.parse(v as String).toLocal();
    final day = DateTime.parse(r['item_date'] as String);
    return TogetherItem(
      kind: _kinds[r['item_kind']] ?? TogetherItemKind.event,
      id: r['item_id'] as String,
      date: DateTime(day.year, day.month, day.day),
      startsAt: local(r['starts_at']),
      endsAt: local(r['ends_at']),
      allDay: r['all_day'] as bool? ?? true,
      tz: r['tz'] as String?,
      title: r['title'] as String? ?? '',
      participantIds: [
        for (final p in (r['participant_ids'] as List? ?? const []))
          p as String,
      ],
      ownerId: r['owner_id'] as String?,
      createdBy: r['created_by'] as String?,
      visibility: TogetherVisibility.fromWire(r['visibility'] as String?),
      status: r['status'] as String? ?? 'confirmed',
      sourceRef: Map<String, dynamic>.from(r['source_ref'] as Map? ?? const {}),
    );
  }

  final TogetherItemKind kind;
  final String id;

  /// The calendar date the server placed it on (the event's own zone).
  final DateTime date;

  /// Local times; null for all-day items.
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool allDay;
  final String? tz;
  final String title;
  final List<String> participantIds;
  final String? ownerId;
  final String? createdBy;
  final TogetherVisibility visibility;
  final String status;
  final Map<String, dynamic> sourceRef;

  /// The local day to list it under: a timed item where it starts for the
  /// viewer, an all-day one (or a later day of a multi-day event) on its
  /// calendar date.
  DateTime get day {
    final s = startsAt;
    if (allDay || s == null || sourceRef['continuation'] == true) return date;
    return DateTime(s.year, s.month, s.day);
  }

  /// A busy block someone else made: the viewer sees only "Busy" and can't
  /// open it (spec §3.3). One rule for every surface that lists items.
  bool isMaskedFor(String? myId) =>
      visibility == TogetherVisibility.busyOnly && createdBy != myId;

  TogetherWho whoFor(String myId) {
    final mine = participantIds.contains(myId);
    if (mine && participantIds.length > 1) return TogetherWho.us;
    return mine ? TogetherWho.me : TogetherWho.partner;
  }
}
