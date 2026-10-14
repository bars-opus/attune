import 'package:intl/intl.dart';

import 'journal_analysis.dart';
import 'journal_entry.dart';

/// One part of an entry: formatted text, or a private photo.
class JournalBlock {
  const JournalBlock({
    required this.id,
    required this.entryId,
    required this.position,
    required this.kind,
    required this.payload,
    this.plainText,
    required this.version,
  });

  factory JournalBlock.fromJson(Map<String, dynamic> j) => JournalBlock(
    id: j['id'] as String,
    entryId: j['entry_id'] as String,
    position: (j['position'] as num).toInt(),
    kind: j['kind'] as String,
    payload: Map<String, dynamic>.from(j['payload'] as Map),
    plainText: j['plain_text'] as String?,
    version: (j['version'] as num).toInt(),
  );

  final String id;
  final String entryId;
  final int position;
  final String kind;
  final Map<String, dynamic> payload;
  final String? plainText;
  final int version;

  bool get isText => kind == 'text';
  bool get isPhoto => kind == 'photo';
  String? get photoPath => payload['path'] as String?;
  List<Map<String, dynamic>> get delta => [
    for (final op in (payload['delta'] as List? ?? const [])) Map<String, dynamic>.from(op as Map),
  ];

  JournalBlock withPosition(int p) => JournalBlock(
    id: id, entryId: entryId, position: p, kind: kind, payload: payload, plainText: plainText, version: version);
}

class JournalEntryDetail {
  const JournalEntryDetail({required this.entry, required this.blocks, this.analysis});

  factory JournalEntryDetail.fromJson(Map<String, dynamic> j) => JournalEntryDetail(
    entry: JournalEntry.fromJson(Map<String, dynamic>.from(j['entry'] as Map)),
    blocks: [for (final b in (j['blocks'] as List? ?? const [])) JournalBlock.fromJson(Map<String, dynamic>.from(b as Map))],
    analysis: j['analysis'] == null ? null : JournalAnalysis.fromJson(Map<String, dynamic>.from(j['analysis'] as Map)),
  );

  final JournalEntry entry;
  final List<JournalBlock> blocks;
  final JournalAnalysis? analysis;

  JournalEntryDetail copyWith({JournalEntry? entry, List<JournalBlock>? blocks}) =>
      JournalEntryDetail(entry: entry ?? this.entry, blocks: blocks ?? this.blocks, analysis: analysis);

  /// Nothing written, titled or added (a new entry like this is discarded).
  bool get isUntouched =>
      (entry.title ?? '').trim().isEmpty && blocks.every((b) => b.isText && (b.plainText ?? '').trim().isEmpty);
}

/// A row in the Entries list.
class JournalEntrySummary {
  const JournalEntrySummary({
    required this.id,
    this.title,
    required this.snippet,
    required this.hasPhoto,
    required this.pinned,
    this.tone,
    required this.createdAt,
    required this.updatedAt,
  });

  factory JournalEntrySummary.fromJson(Map<String, dynamic> j) => JournalEntrySummary(
    id: j['id'] as String,
    title: j['title'] as String?,
    snippet: j['snippet'] as String? ?? '',
    hasPhoto: j['has_photo'] as bool? ?? false,
    pinned: j['pinned'] as bool? ?? false,
    tone: j['tone'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
    updatedAt: DateTime.parse(j['updated_at'] as String),
  );

  final String id;
  final String? title;
  final String snippet;
  final bool hasPhoto;
  final bool pinned;
  final String? tone;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// An untitled entry is called by the day it was written.
  String displayTitle([DateFormat? format]) {
    final t = title?.trim() ?? '';
    return t.isNotEmpty ? t : (format ?? DateFormat('EEEE, d MMMM')).format(createdAt.toLocal());
  }

  JournalEntrySummary withPinned(bool p) => JournalEntrySummary(
    id: id, title: title, snippet: snippet, hasPhoto: hasPhoto, pinned: p, tone: tone,
    createdAt: createdAt, updatedAt: updatedAt);
}

class JournalListPage {
  const JournalListPage({required this.pinned, required this.entries, required this.hasMore});

  factory JournalListPage.fromJson(Map<String, dynamic> j) => JournalListPage(
    pinned: [for (final x in (j['pinned'] as List? ?? const [])) JournalEntrySummary.fromJson(Map<String, dynamic>.from(x as Map))],
    entries: [for (final x in (j['entries'] as List? ?? const [])) JournalEntrySummary.fromJson(Map<String, dynamic>.from(x as Map))],
    hasMore: j['has_more'] as bool? ?? false,
  );

  final List<JournalEntrySummary> pinned;
  final List<JournalEntrySummary> entries;
  final bool hasMore;
}
