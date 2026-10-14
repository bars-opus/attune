/// What a share from another app becomes (Together Phase 8b R1, R2).
library;

/// A shared item without the plugin's types (text, url, image, …).
class SharedItem {
  const SharedItem(this.kind, this.value);
  final String kind;
  final String value;
}

String _clip(String s, int max) {
  final r = s.runes;
  return r.length <= max ? s : String.fromCharCodes(r.take(max));
}

/// Text and links only, joined, trimmed, clipped to capture's 300.
String? sharedCaptureText(List<SharedItem> items) {
  final parts = [
    for (final i in items)
      if ((i.kind == 'text' || i.kind == 'url') && i.value.trim().isNotEmpty)
        i.value.trim(),
  ];
  if (parts.isEmpty) return null;
  return _clip(parts.join('\n'), 300);
}

/// Without AI: the first line is the title, the rest the note.
({String title, String? note}) sharedCaptureFallback(String text) {
  final lines =
      text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return (title: '', note: null);
  final title = _clip(lines.first, 120);
  final rest = lines.skip(1).join('\n').trim();
  return (title: title, note: rest.isEmpty ? null : _clip(rest, 500));
}
