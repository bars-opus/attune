import 'package:equatable/equatable.dart';

class JournalEntry extends Equatable {
  final String id;
  final String userId;
  final String content;
  final String? promptUsed;
  final String? tone;
  final DateTime createdAt;
  final DateTime updatedAt;

  const JournalEntry({
    required this.id,
    required this.userId,
    required this.content,
    this.promptUsed,
    this.tone,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    return JournalEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String,
      promptUsed: json['prompt_used'] as String?,
      tone: json['tone'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'content': content,
      'prompt_used': promptUsed,
      'tone': tone,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, userId, content, tone, createdAt, updatedAt];
}
