class ReminderModel {
  final String id;
  final String relationshipId;
  final String createdBy;
  final String reminderType; // anniversary | birthday | checkin | ai_generated
  final String title;
  final String? note;
  final DateTime remindAt;
  final String recurrence; // none | weekly | monthly | yearly
  final bool sent;
  final String? familyMemberId;
  final String? linkedTimelineEventId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReminderModel({
    required this.id,
    required this.relationshipId,
    required this.createdBy,
    required this.reminderType,
    required this.title,
    this.note,
    required this.remindAt,
    required this.recurrence,
    required this.sent,
    this.familyMemberId,
    this.linkedTimelineEventId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    return ReminderModel(
      id: json['id'] as String,
      relationshipId: json['relationship_id'] as String,
      createdBy: json['created_by'] as String,
      reminderType: json['reminder_type'] as String,
      title: json['title'] as String,
      note: json['note'] as String?,
      remindAt: DateTime.parse(json['remind_at'] as String),
      recurrence: json['recurrence'] as String,
      sent: json['sent'] as bool,
      familyMemberId: json['family_member_id'] as String?,
      linkedTimelineEventId: json['linked_timeline_event_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'relationship_id': relationshipId,
      'created_by': createdBy,
      'reminder_type': reminderType,
      'title': title,
      'note': note,
      'remind_at': remindAt.toIso8601String(),
      'recurrence': recurrence,
      'sent': sent,
      'family_member_id': familyMemberId,
      'linked_timeline_event_id': linkedTimelineEventId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isRecurring => recurrence == 'yearly';
  bool get isBirthday => reminderType == 'birthday';
  bool get isAnniversary => reminderType == 'anniversary';
}
