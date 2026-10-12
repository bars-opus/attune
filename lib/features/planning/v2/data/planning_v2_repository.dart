import 'package:attune/features/planning/data/repositories/planning_repository.dart'
    show PlanningRpcGateway;

import 'planning_v2_error.dart';
import 'planning_v2_models.dart';

/// One method per v2 RPC. Every failure surfaces as [PlanningV2Error].
class PlanningV2Repository {
  const PlanningV2Repository(this._gateway);

  final PlanningRpcGateway _gateway;

  /// Every RPC this repository calls; a test asserts none collides with v1.
  static const rpcNames = {
    'get_planning_home', 'create_planning_category', 'update_planning_category',
    'set_planning_category_hidden', 'delete_planning_category', 'move_planning_category',
    'mark_planning_category_seen', 'list_planning_entries', 'create_planning_entry',
    'duplicate_planning_entry', 'update_planning_entry', 'delete_planning_entry',
    'get_planning_entry', 'reset_planning_template', 'add_planning_block',
    'update_planning_block', 'delete_planning_block', 'restore_planning_block',
    'move_planning_block', 'add_planning_block_item', 'update_planning_block_item',
    'set_planning_block_item_checked', 'delete_planning_block_item',
    'restore_planning_block_item', 'move_planning_block_item', 'pin_planning_entry',
    'restore_planning_entry', 'list_planning_calendar_entries', 'get_planning_summary',
  };

  Future<Map<String, dynamic>> _call(String fn, Map<String, dynamic> params) async {
    assert(rpcNames.contains(fn), '$fn missing from rpcNames');
    try {
      final result = await _gateway.rpc(fn, params: params);
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      throw mapPlanningV2Error(e);
    }
  }

  /// For RPCs that return a set of rows (`RETURNS TABLE`).
  Future<List<Map<String, dynamic>>> _callRows(String fn, Map<String, dynamic> params) async {
    assert(rpcNames.contains(fn), '$fn missing from rpcNames');
    try {
      final result = await _gateway.rpc(fn, params: params);
      return [for (final r in (result as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    } catch (e) {
      throw mapPlanningV2Error(e);
    }
  }

  // ---- feeds ----

  /// The shared calendar for [start]..[end] (at most 42 days).
  Future<List<PlanningCalendarEntry>> listCalendarEntries(String relationshipId,
      {required DateTime start, required DateTime end}) async => [
        for (final r in await _callRows('list_planning_calendar_entries', {
          'p_relationship_id': relationshipId,
          'p_start_date': planningYmd(start),
          'p_end_date': planningYmd(end),
        }))
          PlanningCalendarEntry.fromJson(r)
      ];

  /// The Conversations card's line, or null when nothing is planned yet.
  Future<PlanningSummary?> getSummary(String relationshipId, {required DateTime today}) async {
    final rows = await _callRows(
        'get_planning_summary', {'p_relationship_id': relationshipId, 'p_today': planningYmd(today)});
    return rows.isEmpty ? null : PlanningSummary.fromJson(rows.first);
  }

  // ---- categories ----

  Future<List<PlanningCategory>> getHome(String relationshipId) async {
    final r = await _call('get_planning_home', {'p_relationship_id': relationshipId});
    return [
      for (final c in (r['categories'] as List? ?? const []))
        PlanningCategory.fromJson(Map<String, dynamic>.from(c as Map))
    ];
  }

  Future<PlanningCategory> createCategory({
    required String id,
    required String relationshipId,
    required String name,
    required String icon,
    required String color,
  }) async =>
      PlanningCategory.fromJson(await _call('create_planning_category', {
        'p_id': id, 'p_relationship_id': relationshipId, 'p_name': name,
        'p_icon': icon, 'p_color': color,
      }));

  Future<PlanningCategory> updateCategory({
    required String id,
    required String name,
    required String icon,
    required String color,
  }) async =>
      PlanningCategory.fromJson(await _call('update_planning_category',
          {'p_id': id, 'p_name': name, 'p_icon': icon, 'p_color': color}));

  Future<void> setCategoryHidden(String id, {required bool hidden}) =>
      _call('set_planning_category_hidden', {'p_id': id, 'p_hidden': hidden});

  Future<int> deleteCategory(String id) async =>
      ((await _call('delete_planning_category', {'p_id': id}))['deleted_entries'] as num).toInt();

  Future<void> moveCategory(String id, {required String? afterId}) =>
      _call('move_planning_category', {'p_id': id, 'p_after_id': afterId});

  Future<void> markCategorySeen(String id) => _call('mark_planning_category_seen', {'p_id': id});

  // ---- entries ----

  Future<PlanningEntriesPage> listEntries(
    String categoryId, {
    String group = 'open',
    DateTime? cursorAt,
    String? cursorId,
    int limit = 30,
  }) async =>
      PlanningEntriesPage.fromJson(await _call('list_planning_entries', {
        'p_category_id': categoryId, 'p_group': group,
        'p_cursor_at': cursorAt?.toUtc().toIso8601String(), 'p_cursor_id': cursorId,
        'p_limit': limit,
      }));

  Future<PlanningEntryDetail> createEntry({
    required String id,
    required String categoryId,
    required String title,
    required bool useTemplate,
    required String currency,
  }) async =>
      PlanningEntryDetail.fromJson(await _call('create_planning_entry', {
        'p_id': id, 'p_category_id': categoryId, 'p_title': title,
        'p_use_template': useTemplate, 'p_currency': currency,
      }));

  Future<PlanningEntryDetail> duplicateEntry({
    required String sourceId,
    required String newId,
    required String title,
  }) async =>
      PlanningEntryDetail.fromJson(await _call('duplicate_planning_entry',
          {'p_source_id': sourceId, 'p_new_id': newId, 'p_title': title}));

  Future<PlanningEntry> updateEntry({required String id, required String title, required String status}) async {
    final r = await _call('update_planning_entry', {'p_id': id, 'p_title': title, 'p_status': status});
    return PlanningEntry.fromJson(Map<String, dynamic>.from(r['entry'] as Map));
  }

  Future<void> deleteEntry(String id) => _call('delete_planning_entry', {'p_id': id});

  /// Shared by both partners; at most 20 pinned plans per category.
  Future<PlanningEntry> pinEntry(String id, {required bool pinned}) async {
    final r = await _call('pin_planning_entry', {'p_id': id, 'p_pinned': pinned});
    return PlanningEntry.fromJson(Map<String, dynamic>.from(r['entry'] as Map));
  }

  /// Undo for a delete: restores the plan and exactly what that delete removed.
  Future<PlanningEntry> restoreEntry(String id) async {
    final r = await _call('restore_planning_entry', {'p_id': id});
    return PlanningEntry.fromJson(Map<String, dynamic>.from(r['entry'] as Map));
  }

  Future<PlanningEntryDetail> getEntry(String id) async =>
      PlanningEntryDetail.fromJson(await _call('get_planning_entry', {'p_id': id}));

  Future<PlanningEntryDetail> resetTemplate(String categoryId) async =>
      PlanningEntryDetail.fromJson(await _call('reset_planning_template', {'p_category_id': categoryId}));

  // ---- blocks ----

  Future<PlanningBlock> addBlock({
    required String id,
    required String entryId,
    required PlanningBlockType type,
    required Map<String, dynamic> payload,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? afterId,
  }) async =>
      PlanningBlock.fromJson(await _call('add_planning_block', {
        'p_id': id, 'p_entry_id': entryId, 'p_block_type': planningBlockTypeToWire(type),
        'p_payload': payload,
        'p_date_start': dateStart == null ? null : planningYmd(dateStart),
        'p_date_end': dateEnd == null ? null : planningYmd(dateEnd),
        'p_after_id': afterId,
      }));

  Future<PlanningBlock> updateBlock({
    required String id,
    required int version,
    required Map<String, dynamic> payload,
    DateTime? dateStart,
    DateTime? dateEnd,
  }) async =>
      PlanningBlock.fromJson(await _call('update_planning_block', {
        'p_id': id, 'p_version': version, 'p_payload': payload,
        'p_date_start': dateStart == null ? null : planningYmd(dateStart),
        'p_date_end': dateEnd == null ? null : planningYmd(dateEnd),
      }));

  Future<void> deleteBlock(String id) => _call('delete_planning_block', {'p_id': id});

  Future<PlanningBlock> restoreBlock(String id) async =>
      PlanningBlock.fromJson(await _call('restore_planning_block', {'p_id': id}));

  Future<PlanningBlock> moveBlock(String id, {required String? afterId}) async =>
      PlanningBlock.fromJson(await _call('move_planning_block', {'p_id': id, 'p_after_id': afterId}));

  // ---- items ----

  Future<PlanningItem> addItem({
    required String id,
    required String blockId,
    required String text,
    String? section,
    String? assignedTo,
    DateTime? dueDate,
    String? afterId,
  }) async =>
      PlanningItem.fromJson(await _call('add_planning_block_item', {
        'p_id': id, 'p_block_id': blockId, 'p_text': text, 'p_section': section,
        'p_assigned_to': assignedTo,
        'p_due_date': dueDate == null ? null : planningYmd(dueDate),
        'p_after_id': afterId,
      }));

  Future<PlanningItem> updateItem({
    required String id,
    required int version,
    required String text,
    String? section,
    String? assignedTo,
    DateTime? dueDate,
  }) async =>
      PlanningItem.fromJson(await _call('update_planning_block_item', {
        'p_id': id, 'p_version': version, 'p_text': text, 'p_section': section,
        'p_assigned_to': assignedTo,
        'p_due_date': dueDate == null ? null : planningYmd(dueDate),
      }));

  Future<PlanningItem> setItemChecked({required String id, required bool checked, required String opId}) async =>
      PlanningItem.fromJson(await _call('set_planning_block_item_checked',
          {'p_id': id, 'p_checked': checked, 'p_op_id': opId}));

  Future<void> deleteItem(String id) => _call('delete_planning_block_item', {'p_id': id});

  Future<PlanningItem> restoreItem(String id) async =>
      PlanningItem.fromJson(await _call('restore_planning_block_item', {'p_id': id}));

  Future<PlanningItem> moveItem(String id, {required String? afterId}) async =>
      PlanningItem.fromJson(await _call('move_planning_block_item', {'p_id': id, 'p_after_id': afterId}));
}
