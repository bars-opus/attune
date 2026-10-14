import 'package:flutter/material.dart' show IconData, Icons;

enum RitualCadence { weekly, fortnightly }

enum RitualStatus { proposed, active, paused }

const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _hm(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

/// A ritual of connection the couple agreed on (Phase 3). No counters:
/// only what it is, when, and the next time.
class TogetherRitual {
  const TogetherRitual({
    required this.id,
    required this.template,
    required this.title,
    required this.cadence,
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.durationMin,
    required this.tz,
    required this.status,
    this.createdBy,
    this.proposedTo,
    this.nextEventId,
    this.nextStartsAt,
  });

  factory TogetherRitual.fromRow(Map<String, dynamic> r) {
    final parts = (r['local_time'] as String? ?? '00:00').split(':');
    return TogetherRitual(
      id: r['ritual_id'] as String,
      template: r['template'] as String? ?? 'custom',
      title: r['title'] as String? ?? '',
      cadence:
          r['cadence'] == 'fortnightly'
              ? RitualCadence.fortnightly
              : RitualCadence.weekly,
      weekday: (r['weekday'] as num).toInt(),
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
      durationMin: (r['duration_min'] as num).toInt(),
      tz: r['tz'] as String? ?? 'UTC',
      status: switch (r['status']) {
        'proposed' => RitualStatus.proposed,
        'paused' => RitualStatus.paused,
        _ => RitualStatus.active,
      },
      createdBy: r['created_by'] as String?,
      proposedTo: r['proposed_to'] as String?,
      nextEventId: r['next_event_id'] as String?,
      nextStartsAt:
          r['next_starts_at'] == null
              ? null
              : DateTime.parse(r['next_starts_at'] as String).toLocal(),
    );
  }

  final String id;
  final String template;
  final String title;
  final RitualCadence cadence;
  final int weekday;
  final int hour;
  final int minute;
  final int durationMin;
  final String tz;
  final RitualStatus status;
  final String? createdBy;
  final String? proposedTo;
  final String? nextEventId;
  final DateTime? nextStartsAt;

  /// "Fridays at 19:00" / "Every other Sunday at 18:00" (in its own zone).
  String get when =>
      cadence == RitualCadence.weekly
          ? '${_days[weekday - 1]}s at ${_hm(hour, minute)}'
          : 'Every other ${_days[weekday - 1]} at ${_hm(hour, minute)}';

  /// [when], naming the ritual's zone when it isn't the viewer's own, so a
  /// long-distance partner knows whose 19:00 it is.
  String whenFor(String? deviceTz) {
    if (deviceTz == null || deviceTz == tz) return when;
    final city = tz.split('/').last.replaceAll('_', ' ');
    return '$when ($city time)';
  }
}

/// A starting point for a ritual (plan R6): a plain name, why, and defaults.
class RitualTemplate {
  const RitualTemplate({
    required this.id,
    required this.title,
    required this.blurb,
    required this.weekday,
    required this.hour,
    required this.durationMin,
    required this.icon,
    this.minute = 0,
    this.cadence = RitualCadence.weekly,
  });
  final String id;
  final String title;
  final String blurb;
  final RitualCadence cadence;
  final int weekday;
  final int hour;
  final int minute;
  final int durationMin;
  final IconData icon;
}

const ritualTemplates = [
  RitualTemplate(
    id: 'date_night',
    title: 'Date night',
    blurb: 'Time for just the two of you',
    weekday: DateTime.friday,
    hour: 19,
    durationMin: 120,
    icon: Icons.local_bar_outlined,
  ),
  RitualTemplate(
    id: 'state_of_union',
    title: 'State of the Union',
    blurb: "An hour to check in on how you're both doing",
    weekday: DateTime.sunday,
    hour: 18,
    durationMin: 60,
    icon: Icons.forum_outlined,
  ),
  RitualTemplate(
    id: 'weekly_call',
    title: 'Weekly call',
    blurb: "A longer call when you're apart",
    weekday: DateTime.sunday,
    hour: 19,
    durationMin: 60,
    icon: Icons.call_outlined,
  ),
  RitualTemplate(
    id: 'bedtime_check_in',
    title: 'After-bedtime check-in',
    blurb: 'Twenty minutes once the kids are down',
    weekday: DateTime.wednesday,
    hour: 21,
    durationMin: 20,
    icon: Icons.nightlight_outlined,
  ),
  RitualTemplate(
    id: 'custom',
    title: 'Something of our own',
    blurb: 'Name it and choose a time',
    weekday: DateTime.saturday,
    hour: 10,
    durationMin: 60,
    icon: Icons.favorite_border_rounded,
  ),
];

/// What the ritual editor collects.
class RitualDraft {
  const RitualDraft({
    required this.template,
    required this.title,
    required this.cadence,
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.durationMin,
    required this.tz,
  });
  final String template;
  final String title;
  final RitualCadence cadence;
  final int weekday;
  final int hour;
  final int minute;
  final int durationMin;
  final String tz;

  Map<String, dynamic> toPayload() => {
    'template': template,
    'title': title.trim(),
    'cadence': cadence.name,
    'weekday': weekday,
    'local_time': _hm(hour, minute),
    'duration_min': durationMin,
    'tz': tz,
  };
}
