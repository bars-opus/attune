/// Something on Together waiting on me (or my proposal waiting on my
/// partner), from `list_together_needs_you`.
library;

enum TogetherNeedKind {
  proposal,
  ritualProposal,
  sentProposal,
  handoff,
  unownedTodo,
  poll,
}

const _kinds = {
  'proposal': TogetherNeedKind.proposal,
  'ritual_proposal': TogetherNeedKind.ritualProposal,
  'sent_proposal': TogetherNeedKind.sentProposal,
  'handoff': TogetherNeedKind.handoff,
  'unowned_todo': TogetherNeedKind.unownedTodo,
  'poll': TogetherNeedKind.poll,
};

DateTime? _local(Object? v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

DateTime? _day(Object? v) {
  if (v == null) return null;
  final p = DateTime.parse(v as String);
  return DateTime(p.year, p.month, p.day);
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// One time a proposal offers.
class TogetherOption {
  const TogetherOption({
    required this.id,
    required this.position,
    required this.allDay,
    required this.start,
    this.end,
  });

  factory TogetherOption.fromJson(
    Map<String, dynamic> j, {
    required bool allDay,
  }) => TogetherOption(
    id: j['id'] as String,
    position: (j['position'] as num).toInt(),
    allDay: allDay,
    start: allDay ? _day(j['start_date'])! : _local(j['starts_at'])!,
    end: allDay ? _day(j['end_date']) : _local(j['ends_at']),
  );

  /// An option in the proposal's own mode, or null for one that isn't
  /// (skipped rather than crashing the whole "Needs you" list).
  static TogetherOption? tryParse(
    Map<String, dynamic> j, {
    required bool allDay,
  }) {
    final hasStart = allDay ? j['start_date'] != null : j['starts_at'] != null;
    return hasStart ? TogetherOption.fromJson(j, allDay: allDay) : null;
  }

  final String id;
  final int position;
  final bool allDay;
  final DateTime start;
  final DateTime? end;
}

/// A time to offer when proposing.
class ProposalTime {
  const ProposalTime({required this.start, this.end});
  final DateTime start;
  final DateTime? end;

  Map<String, dynamic> toJson({required bool allDay}) =>
      allDay
          ? {'start_date': _ymd(start), if (end != null) 'end_date': _ymd(end!)}
          : {
            'starts_at': start.toUtc().toIso8601String(),
            if (end != null) 'ends_at': end!.toUtc().toIso8601String(),
          };
}

class TogetherNeed {
  const TogetherNeed({
    required this.kind,
    required this.itemId,
    required this.title,
    this.dueDate,
    this.createdBy,
    this.options = const [],
    this.expiresAt,
    this.entryId,
    this.proposedTo,
    this.allDay = false,
    this.detail = const {},
  });

  factory TogetherNeed.fromRow(Map<String, dynamic> r) {
    final d = Map<String, dynamic>.from(r['detail'] as Map? ?? const {});
    final allDay = d['all_day'] as bool? ?? false;
    return TogetherNeed(
      kind: _kinds[r['need_kind']] ?? TogetherNeedKind.poll,
      itemId: r['item_id'] as String,
      title: r['title'] as String? ?? '',
      dueDate: _day(r['due_date']),
      createdBy: r['created_by'] as String?,
      options: [
        for (final o in (d['options'] as List? ?? const []))
          if (TogetherOption.tryParse(
                Map<String, dynamic>.from(o as Map),
                allDay: allDay,
              )
              case final option?)
            option,
      ],
      expiresAt: _local(d['expires_at']),
      entryId: d['entry_id'] as String?,
      proposedTo: d['proposed_to'] as String?,
      allDay: allDay,
      detail: d,
    );
  }

  final TogetherNeedKind kind;
  final String itemId;
  final String title;
  final DateTime? dueDate;
  final String? createdBy;
  final List<TogetherOption> options;
  final DateTime? expiresAt;
  final String? entryId;
  final String? proposedTo;
  final bool allDay;

  /// The row's raw detail (e.g. a ritual suggestion's cadence and time).
  final Map<String, dynamic> detail;
}
