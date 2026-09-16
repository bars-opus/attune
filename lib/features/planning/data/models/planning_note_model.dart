// lib/features/planning/data/models/planning_note_model.dart

class PlanningNoteModel {
  final String id;
  final String relationshipId;
  final String? createdBy;
  final String title;
  final String body;
  final DateTime updatedAt;

  const PlanningNoteModel({
    required this.id,
    required this.relationshipId,
    this.createdBy,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  factory PlanningNoteModel.fromRow(Map<String, dynamic> row) {
    return PlanningNoteModel(
      id: row['id'] as String,
      relationshipId: row['relationship_id'] as String,
      createdBy: row['created_by'] as String?,
      title: row['title'] as String,
      body: row['body'] as String? ?? '',
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
