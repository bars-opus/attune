/// Planning models. Plain immutable classes with fromJson, matching
/// the app's model style. JSON shapes: migrations 20261012200200..0400.
library;

enum PlanningBlockType { text, checklist, date, unsupported }

PlanningBlockType planningBlockTypeFromWire(String wire) => switch (wire) {
      'text' => PlanningBlockType.text,
      'checklist' => PlanningBlockType.checklist,
      'date' => PlanningBlockType.date,
      _ => PlanningBlockType.unsupported,
    };

String planningBlockTypeToWire(PlanningBlockType type) => switch (type) {
      PlanningBlockType.text => 'text',
      PlanningBlockType.checklist => 'checklist',
      PlanningBlockType.date => 'date',
      PlanningBlockType.unsupported => throw ArgumentError('unsupported has no wire form'),
    };

String planningYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
DateTime? _ts(Object? v) => v == null ? null : DateTime.parse(v as String);

class PlanningCategory {
  const PlanningCategory({
    required this.id,
    required this.seedKey,
    required this.name,
    required this.icon,
    required this.color,
    required this.sortKey,
    required this.hidden,
    required this.templateEntryId,
    required this.entryCount,
    required this.hasNew,
  });

  final String id;
  final String? seedKey;
  final String name;
  final String icon;
  final String color;
  final String sortKey;
  final bool hidden;
  final String? templateEntryId;
  final int entryCount;
  final bool hasNew;

  bool get isStarter => seedKey != null;

  /// Accepts both the home-read shape (`hidden`) and a raw row (`hidden_at`).
  factory PlanningCategory.fromJson(Map<String, dynamic> j) => PlanningCategory(
        id: j['id'] as String,
        seedKey: j['seed_key'] as String?,
        name: j['name'] as String,
        icon: j['icon'] as String,
        color: j['color'] as String,
        sortKey: j['sort_key'] as String,
        hidden: (j['hidden'] as bool?) ?? (j['hidden_at'] != null),
        templateEntryId: j['template_entry_id'] as String?,
        entryCount: (j['entry_count'] as num?)?.toInt() ?? 0,
        hasNew: (j['has_new'] as bool?) ?? false,
      );

  PlanningCategory copyWith({String? name, String? icon, String? color, bool? hidden, bool? hasNew}) =>
      PlanningCategory(
        id: id, seedKey: seedKey, name: name ?? this.name, icon: icon ?? this.icon,
        color: color ?? this.color, sortKey: sortKey, hidden: hidden ?? this.hidden,
        templateEntryId: templateEntryId, entryCount: entryCount, hasNew: hasNew ?? this.hasNew,
      );
}

class PlanningMember {
  const PlanningMember({required this.id, required this.displayName});
  final String id;
  final String displayName;

  factory PlanningMember.fromJson(Map<String, dynamic> j) =>
      PlanningMember(id: j['id'] as String, displayName: (j['display_name'] as String?) ?? '');

  String get initial => displayName.isEmpty ? '?' : displayName.characters0;
}

extension on String {
  /// First user-perceived character for avatars, without pulling in
  /// package:characters for one call: first rune is good enough for initials.
  String get characters0 => String.fromCharCode(runes.first).toUpperCase();
}

class PlanningItem {
  const PlanningItem({
    required this.id,
    required this.sortKey,
    required this.text,
    required this.section,
    required this.checkedAt,
    required this.checkedBy,
    required this.assignedTo,
    required this.dueDate,
    required this.version,
  });

  final String id;
  final String sortKey;
  final String text;
  final String? section;
  final DateTime? checkedAt;
  final String? checkedBy;
  final String? assignedTo;
  final DateTime? dueDate;
  final int version;

  bool get isChecked => checkedAt != null;

  factory PlanningItem.fromJson(Map<String, dynamic> j) => PlanningItem(
        id: j['id'] as String,
        sortKey: j['sort_key'] as String,
        text: (j['text'] as String?) ?? '',
        section: j['section'] as String?,
        checkedAt: _ts(j['checked_at']),
        checkedBy: j['checked_by'] as String?,
        assignedTo: j['assigned_to'] as String?,
        dueDate: _date(j['due_date']),
        version: (j['version'] as num).toInt(),
      );

  PlanningItem copyWith({
    String? text,
    String? section,
    DateTime? checkedAt,
    bool clearChecked = false,
    String? checkedBy,
    String? assignedTo,
    bool clearAssignee = false,
    int? version,
  }) =>
      PlanningItem(
        id: id,
        sortKey: sortKey,
        text: text ?? this.text,
        section: section ?? this.section,
        checkedAt: clearChecked ? null : (checkedAt ?? this.checkedAt),
        checkedBy: clearChecked ? null : (checkedBy ?? this.checkedBy),
        assignedTo: clearAssignee ? null : (assignedTo ?? this.assignedTo),
        dueDate: dueDate,
        version: version ?? this.version,
      );
}

class PlanningBlock {
  const PlanningBlock({
    required this.id,
    required this.type,
    required this.rawType,
    required this.sortKey,
    required this.payload,
    required this.plainText,
    required this.dateStart,
    required this.dateEnd,
    required this.version,
    required this.items,
  });

  final String id;
  final PlanningBlockType type;
  final String rawType;
  final String sortKey;
  final Map<String, dynamic> payload;
  final String? plainText;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final int version;
  final List<PlanningItem> items;

  String? get title => payload['title'] as String?;

  /// Quill Delta ops for a text block; a single newline when empty.
  List<Map<String, dynamic>> get delta {
    final raw = payload['delta'];
    if (raw is! List || raw.isEmpty) return const [{'insert': '\n'}];
    return [for (final op in raw) Map<String, dynamic>.from(op as Map)];
  }

  factory PlanningBlock.fromJson(Map<String, dynamic> j) => PlanningBlock(
        id: j['id'] as String,
        type: planningBlockTypeFromWire(j['block_type'] as String),
        rawType: j['block_type'] as String,
        sortKey: j['sort_key'] as String,
        payload: Map<String, dynamic>.from((j['payload'] as Map?) ?? const {}),
        plainText: j['plain_text'] as String?,
        dateStart: _date(j['date_start']),
        dateEnd: _date(j['date_end']),
        version: (j['version'] as num).toInt(),
        items: [
          for (final i in (j['items'] as List? ?? const []))
            PlanningItem.fromJson(Map<String, dynamic>.from(i as Map))
        ],
      );

  PlanningBlock copyWith({List<PlanningItem>? items, int? version}) => PlanningBlock(
        id: id, type: type, rawType: rawType, sortKey: sortKey, payload: payload,
        plainText: plainText, dateStart: dateStart, dateEnd: dateEnd,
        version: version ?? this.version, items: items ?? this.items,
      );
}

class PlanningEntry {
  const PlanningEntry({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.categorySeedKey,
    required this.isTemplate,
    required this.title,
    required this.status,
    required this.currency,
    required this.lastActivityAt,
    this.pinnedAt,
  });

  final String id;
  final String categoryId;
  final String categoryName;
  final String? categorySeedKey;
  final bool isTemplate;
  final String title;
  final String status;
  final String currency;
  final DateTime lastActivityAt;
  final DateTime? pinnedAt;

  bool get isPinned => pinnedAt != null;

  factory PlanningEntry.fromJson(Map<String, dynamic> j) => PlanningEntry(
        id: j['id'] as String,
        categoryId: j['category_id'] as String,
        categoryName: j['category_name'] as String,
        categorySeedKey: j['category_seed_key'] as String?,
        isTemplate: j['is_template'] as bool,
        title: j['title'] as String,
        status: j['status'] as String,
        currency: j['currency'] as String,
        lastActivityAt: DateTime.parse(j['last_activity_at'] as String),
        pinnedAt: _ts(j['pinned_at']),
      );
}

class PlanningEntryDetail {
  const PlanningEntryDetail({required this.entry, required this.members, required this.blocks});

  final PlanningEntry entry;
  final List<PlanningMember> members;
  final List<PlanningBlock> blocks;

  factory PlanningEntryDetail.fromJson(Map<String, dynamic> j) => PlanningEntryDetail(
        entry: PlanningEntry.fromJson(Map<String, dynamic>.from(j['entry'] as Map)),
        members: [
          for (final m in (j['members'] as List? ?? const []))
            PlanningMember.fromJson(Map<String, dynamic>.from(m as Map))
        ],
        blocks: [
          for (final b in (j['blocks'] as List? ?? const []))
            PlanningBlock.fromJson(Map<String, dynamic>.from(b as Map))
        ],
      );

  PlanningEntryDetail copyWith({PlanningEntry? entry, List<PlanningBlock>? blocks}) =>
      PlanningEntryDetail(entry: entry ?? this.entry, members: members, blocks: blocks ?? this.blocks);

  PlanningMember? member(String? id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }
}

class PlanningEntrySummary {
  const PlanningEntrySummary({
    required this.id,
    required this.title,
    required this.status,
    required this.lastActivityAt,
    required this.dateStart,
    required this.dateEnd,
    required this.checklistDone,
    required this.checklistTotal,
    this.pinned = false,
  });

  final String id;
  final String title;
  final String status;
  final DateTime lastActivityAt;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final int checklistDone;
  final int checklistTotal;
  final bool pinned;

  PlanningEntrySummary copyWith({required bool pinned}) => PlanningEntrySummary(
        id: id, title: title, status: status, lastActivityAt: lastActivityAt, dateStart: dateStart,
        dateEnd: dateEnd, checklistDone: checklistDone, checklistTotal: checklistTotal, pinned: pinned,
      );

  factory PlanningEntrySummary.fromJson(Map<String, dynamic> j) => PlanningEntrySummary(
        id: j['id'] as String,
        title: j['title'] as String,
        status: j['status'] as String,
        lastActivityAt: DateTime.parse(j['last_activity_at'] as String),
        dateStart: _date(j['date_start']),
        dateEnd: _date(j['date_end']),
        checklistDone: (j['checklist_done'] as num).toInt(),
        checklistTotal: (j['checklist_total'] as num).toInt(),
        pinned: (j['pinned'] as bool?) ?? false,
      );
}

class PlanningEntriesPage {
  const PlanningEntriesPage({
    required this.entries,
    required this.nextCursorAt,
    required this.nextCursorId,
    this.pinned = const [],
  });

  final List<PlanningEntrySummary> entries;

  /// Pinned plans: on the first page only, never repeated in [entries].
  final List<PlanningEntrySummary> pinned;
  final DateTime? nextCursorAt;
  final String? nextCursorId;

  bool get hasMore => nextCursorId != null;

  factory PlanningEntriesPage.fromJson(Map<String, dynamic> j) {
    final cursor = j['next_cursor'];
    return PlanningEntriesPage(
      entries: [
        for (final e in (j['entries'] as List? ?? const []))
          PlanningEntrySummary.fromJson(Map<String, dynamic>.from(e as Map))
      ],
      nextCursorAt: cursor is Map ? DateTime.parse(cursor['at'] as String) : null,
      nextCursorId: cursor is Map ? cursor['id'] as String : null,
      pinned: [
        for (final e in (j['pinned'] as List? ?? const []))
          PlanningEntrySummary.fromJson(Map<String, dynamic>.from(e as Map))
      ],
    );
  }
}

/// One row of the shared calendar: a plan's date (on each day of its
/// range) or a dated to-do. [entryId] is the plan to open on tap.
enum PlanningCalendarKind { date, item }

class PlanningCalendarEntry {
  const PlanningCalendarEntry({
    required this.kind,
    required this.entryId,
    required this.itemId,
    required this.date,
    required this.title,
    required this.isComplete,
  });

  final PlanningCalendarKind kind;
  final String entryId;
  final String? itemId;
  final DateTime date;
  final String title;
  final bool isComplete;

  factory PlanningCalendarEntry.fromJson(Map<String, dynamic> j) => PlanningCalendarEntry(
        kind: j['entry_kind'] == 'date' ? PlanningCalendarKind.date : PlanningCalendarKind.item,
        entryId: j['entry_id'] as String,
        itemId: j['item_id'] as String?,
        date: DateTime.parse(j['entry_date'] as String),
        title: j['title'] as String,
        isComplete: (j['is_complete'] as bool?) ?? false,
      );
}

/// The one line the Conversations card shows about Planning.
enum PlanningSummaryKind { overdue, upcoming, recent }

class PlanningSummary {
  const PlanningSummary({required this.kind, required this.entryId, required this.title, required this.contextDate});

  final PlanningSummaryKind kind;
  final String entryId;
  final String title;
  final DateTime? contextDate;

  factory PlanningSummary.fromJson(Map<String, dynamic> j) => PlanningSummary(
        kind: switch (j['kind']) {
          'overdue' => PlanningSummaryKind.overdue,
          'upcoming' => PlanningSummaryKind.upcoming,
          _ => PlanningSummaryKind.recent,
        },
        entryId: j['entry_id'] as String,
        title: j['title'] as String,
        contextDate: _date(j['context_date']),
      );
}

