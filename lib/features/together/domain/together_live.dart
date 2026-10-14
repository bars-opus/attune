/// The lock-screen plan (Together Phase 8c): one shared plan close at hand,
/// as a countdown. Titles as written; no names, no app wording (R2).
library;

import 'together_item.dart';

class LivePlan {
  const LivePlan({required this.title, required this.start, required this.end});

  final String title;
  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is LivePlan &&
      other.title == title &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(title, start, end);
}

/// How long before a plan starts it appears. iOS keeps a Live Activity up
/// for at most 8 hours, so the lead leaves room for the plan itself (R3).
const liveLead = Duration(hours: 4);

LivePlan? livePlanFor({
  required List<TogetherItem> items,
  required String? me,
  required DateTime now,
}) {
  if (me == null) return null;
  LivePlan? best;
  for (final i in items) {
    final start = i.startsAt;
    if (i.kind != TogetherItemKind.event || i.allDay || start == null) continue;
    if (i.status != 'confirmed') continue;
    // A surprise or a busy block never reaches the lock screen (spec §3).
    if (i.visibility != TogetherVisibility.shared) continue;
    if (i.whoFor(me) != TogetherWho.us) continue;
    final end = i.endsAt ?? start.add(const Duration(hours: 1));
    if (!end.isAfter(now) || start.difference(now) > liveLead) continue;
    if (best == null || start.isBefore(best.start)) {
      best = LivePlan(title: i.title, start: start, end: end);
    }
  }
  return best;
}
