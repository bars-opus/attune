class FamilyMemberModel {
  final String id;
  final String relationshipId;
  final String name;
  final DateTime? birthday;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FamilyMemberModel({
    required this.id,
    required this.relationshipId,
    required this.name,
    this.birthday,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FamilyMemberModel.fromJson(Map<String, dynamic> json) {
    return FamilyMemberModel(
      id: json['id'] as String,
      relationshipId: json['relationship_id'] as String,
      name: json['name'] as String,
      birthday: json['birthday'] != null
          ? DateTime.parse(json['birthday'] as String)
          : null,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
