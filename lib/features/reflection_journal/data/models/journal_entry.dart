import 'package:equatable/equatable.dart';

class JournalEntry extends Equatable {
  final String id;
  final String userId;

  /// The entry's plain text (server-derived from its text blocks); what the
  /// reflection reads.
  final String content;
  final String? promptUsed;
  final String? tone;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? title;
  final DateTime? pinnedAt;

  const JournalEntry({
    required this.id,
    required this.userId,
    required this.content,
    this.promptUsed,
    this.tone,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.pinnedAt,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    return JournalEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String? ?? '',
      promptUsed: json['prompt_used'] as String?,
      tone: json['tone'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      title: json['title'] as String?,
      pinnedAt: json['pinned_at'] == null ? null : DateTime.parse(json['pinned_at'] as String),
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
      'title': title,
      'pinned_at': pinnedAt?.toIso8601String(),
    };
  }

  JournalEntry copyWith({
    String? content,
    String? title,
    bool clearTitle = false,
    DateTime? pinnedAt,
    bool clearPinned = false,
  }) => JournalEntry(
    id: id,
    userId: userId,
    content: content ?? this.content,
    promptUsed: promptUsed,
    tone: tone,
    createdAt: createdAt,
    updatedAt: updatedAt,
    title: clearTitle ? null : (title ?? this.title),
    pinnedAt: clearPinned ? null : (pinnedAt ?? this.pinnedAt),
  );

  @override
  List<Object?> get props => [id, userId, content, tone, createdAt, updatedAt, title, pinnedAt];
}

/// The first words of an entry, for lists and the cache: whitespace
/// collapsed, at most 80 characters (never the full text).
String journalSnippet(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = flat.runes.toList();
  return runes.length <= 80 ? flat : String.fromCharCodes(runes.take(80));
}

/// The Conversations "latest reflection" line.
String journalRowTitle(JournalEntry? latest) {
  if (latest == null) return 'Start your first reflection';
  final title = latest.title?.trim() ?? '';
  return title.isNotEmpty ? title : journalSnippet(latest.content);
}
