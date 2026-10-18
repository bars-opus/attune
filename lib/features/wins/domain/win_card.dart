/// Spec 7 (research 06 B2): a partner's win, asked about from an in-app
/// card (never a push). The draft is fixed copy; no AI writes it.
class WinCard {
  const WinCard({
    required this.eventId,
    required this.title,
    required this.createdAt,
  });

  final String eventId;
  final String title;
  final DateTime createdAt;

  static WinCard fromRow(Map<String, dynamic> row) => WinCard(
    eventId: row['event_id'] as String,
    title: row['title'] as String? ?? '',
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

/// "{title}! What was the best part?" — the title's own end punctuation is
/// dropped so the question reads once (plan review M6).
String winDraft(String title) {
  final t = title.trim().replaceFirst(RegExp(r'[.!?\s]+$'), '');
  return '$t! What was the best part?';
}
