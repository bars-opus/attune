import 'dart:typed_data';

import 'package:attune/features/planning/data/planning_media.dart';
import 'package:attune/features/planning/data/planning_repository.dart';

typedef RpcHandler = dynamic Function(Map<String, dynamic> params);

/// Fakes the RPC seam (planning_repository.dart) so tests exercise the
/// real PlanningRepository mapping without Supabase.
class FakePlanningGateway implements PlanningRpcGateway {
  FakePlanningGateway([Map<String, RpcHandler>? handlers]) : handlers = handlers ?? {};

  final Map<String, RpcHandler> handlers;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    final p = params ?? const <String, dynamic>{};
    calls.add((function, p));
    final handler = handlers[function];
    if (handler == null) {
      throw StateError('FakePlanningGateway: no handler for $function');
    }
    return handler(p);
  }

  List<Map<String, dynamic>> callsTo(String function) =>
      [for (final c in calls) if (c.$1 == function) c.$2];
}

Map<String, dynamic> fakeItemJson({
  required String id,
  String text = 'Milk',
  String sortKey = 'V',
  String? section,
  String? checkedAt,
  String? assignedTo,
  int version = 1,
}) =>
    {
      'id': id, 'sort_key': sortKey, 'text': text, 'section': section,
      'checked_at': checkedAt, 'checked_by': checkedAt == null ? null : 'u-a',
      'assigned_to': assignedTo, 'due_date': null, 'version': version,
    };

Map<String, dynamic> fakeBlockJson({
  required String id,
  String type = 'checklist',
  Map<String, dynamic>? payload,
  String? plainText,
  String sortKey = 'V',
  String? dateStart,
  String? dateEnd,
  int version = 1,
  List<Map<String, dynamic>> items = const [],
}) =>
    {
      'id': id, 'block_type': type, 'sort_key': sortKey,
      'payload': payload ?? <String, dynamic>{}, 'plain_text': plainText,
      'date_start': dateStart, 'date_end': dateEnd, 'version': version,
      'updated_at': '2026-10-12T09:00:00Z', 'items': items,
    };

Map<String, dynamic> fakeEntryDetailJson({
  String id = 'e1',
  String title = 'Saturday shop',
  bool isTemplate = false,
  List<Map<String, dynamic>> blocks = const [],
  String seedKey = 'groceries',
  String categoryName = 'Groceries',
  String? pinnedAt,
}) =>
    {
      'entry': {
        'id': id, 'category_id': 'c1', 'category_name': categoryName,
        'category_seed_key': seedKey, 'is_template': isTemplate, 'title': title, 'pinned_at': pinnedAt,
        'status': 'active', 'currency': 'GHS', 'cover_path': null,
        'last_activity_at': '2026-10-12T09:00:00Z',
        'created_at': '2026-10-12T09:00:00Z', 'updated_at': '2026-10-12T09:00:00Z',
      },
      'members': [
        {'id': 'u-a', 'display_name': 'Ama'},
        {'id': 'u-b', 'display_name': 'Kofi'},
      ],
      'blocks': blocks,
    };

Map<String, dynamic> fakeCategoryJson({
  required String id,
  String? seedKey,
  String name = 'Groceries',
  String icon = 'cart',
  String color = 'green',
  bool hidden = false,
  int entryCount = 0,
  bool hasNew = false,
}) =>
    {
      'id': id, 'seed_key': seedKey, 'name': name, 'icon': icon, 'color': color,
      'sort_key': 'V', 'hidden': hidden, 'template_entry_id': 't-$id',
      'entry_count': entryCount, 'has_new': hasNew,
    };

/// Records uploads and preview requests instead of touching Storage.
class FakePlanningMediaGateway implements PlanningMediaGateway {
  final List<(String, Uint8List)> uploads = [];
  final List<String> previewRequests = [];

  @override
  Future<void> uploadJpeg(String path, Uint8List bytes) async => uploads.add((path, bytes));

  @override
  Future<String> signedUrl(String path) async => 'https://storage.test/$path';

  @override
  Future<void> requestLinkPreview(String blockId) async => previewRequests.add(blockId);
}
