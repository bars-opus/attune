// lib/features/planning/data/models/planning_event_model.dart

class PlanningEventModel {
  final String id;
  final String relationshipId;
  final String? createdBy;
  final String title;
  final String? note;
  final DateTime eventDate;
  final DateTime updatedAt;

  const PlanningEventModel({
    required this.id,
    required this.relationshipId,
    this.createdBy,
    required this.title,
    this.note,
    required this.eventDate,
    required this.updatedAt,
  });

  bool get isPast => eventDate.isBefore(DateTime.now());

  factory PlanningEventModel.fromRow(Map<String, dynamic> row) {
    return PlanningEventModel(
      id: row['id'] as String,
      relationshipId: row['relationship_id'] as String,
      createdBy: row['created_by'] as String?,
      title: row['title'] as String,
      note: row['note'] as String?,
      // event_date is a Postgres `date` column with no time zone of
      // its own; a bare "YYYY-MM-DD" string must be parsed as UTC
      // midnight, not local midnight, or the date silently shifts by
      // a day for any client not in UTC.
      eventDate: _parseDateOnlyUtc(row['event_date'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}

DateTime _parseDateOnlyUtc(String value) =>
    DateTime.parse(value.contains('T') ? value : '${value}T00:00:00Z');
