import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/planning_v2_error.dart';

/// Offline queue for checklist ticks and item adds (spec §10). Bounded
/// (200), persisted, replayed in order with exponential backoff + full
/// jitter (checklist 3.9: base 500ms, cap 30s, 6 attempts). Permanent
/// errors drop the op and are reported, never retried (3.10). Each op
/// carries a stable id so a replay after a lost response cannot apply
/// twice (server dedupes on it: planning_applied_ops / client item ids).
sealed class OutboxOp {
  const OutboxOp({required this.opId, required this.relationshipId, required this.entryId});

  final String opId;
  final String relationshipId;
  final String entryId;

  Map<String, dynamic> toJson();

  static OutboxOp? fromJson(Map<String, dynamic> j) {
    try {
      return switch (j['kind']) {
        'check' => CheckItemOp(
            opId: j['op_id'] as String, relationshipId: j['relationship_id'] as String,
            entryId: j['entry_id'] as String, itemId: j['item_id'] as String,
            checked: j['checked'] as bool),
        'add' => AddItemOp(
            opId: j['op_id'] as String, relationshipId: j['relationship_id'] as String,
            entryId: j['entry_id'] as String, itemId: j['item_id'] as String,
            blockId: j['block_id'] as String, text: j['text'] as String,
            section: j['section'] as String?, afterId: j['after_id'] as String?),
        _ => null,
      };
    } on TypeError {
      return null;
    }
  }
}

class CheckItemOp extends OutboxOp {
  const CheckItemOp({
    required super.opId,
    required super.relationshipId,
    required super.entryId,
    required this.itemId,
    required this.checked,
  });

  final String itemId;
  final bool checked;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'check', 'op_id': opId, 'relationship_id': relationshipId,
        'entry_id': entryId, 'item_id': itemId, 'checked': checked,
      };
}

/// The item's own client-generated id is its op id: add is idempotent
/// by item id on the server.
class AddItemOp extends OutboxOp {
  const AddItemOp({
    required super.opId,
    required super.relationshipId,
    required super.entryId,
    required this.itemId,
    required this.blockId,
    required this.text,
    required this.section,
    required this.afterId,
  });

  final String itemId;
  final String blockId;
  final String text;
  final String? section;
  final String? afterId;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'add', 'op_id': opId, 'relationship_id': relationshipId,
        'entry_id': entryId, 'item_id': itemId, 'block_id': blockId,
        'text': text, 'section': section, 'after_id': afterId,
      };
}

abstract class OutboxStore {
  Future<List<Map<String, dynamic>>> read();
  Future<void> write(List<Map<String, dynamic>> ops);
}

class MemoryOutboxStore implements OutboxStore {
  List<Map<String, dynamic>> raw = [];

  @override
  Future<List<Map<String, dynamic>>> read() async => [...raw];

  @override
  Future<void> write(List<Map<String, dynamic>> ops) async => raw = [...ops];
}

class SharedPreferencesOutboxStore implements OutboxStore {
  static const _key = 'planning_v2_outbox_v1';

  @override
  Future<List<Map<String, dynamic>>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_key);
      if (s == null) return [];
      return [for (final o in jsonDecode(s) as List) Map<String, dynamic>.from(o as Map)];
    } catch (_) {
      return []; // corrupt or unavailable storage must never block planning
    }
  }

  @override
  Future<void> write(List<Map<String, dynamic>> ops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(ops));
  }
}

class OutboxFullException implements Exception {
  const OutboxFullException();
}

class OutboxReplayResult {
  const OutboxReplayResult({required this.sent, required this.dropped, required this.remaining});
  final int sent;
  final List<OutboxOp> dropped;
  final int remaining;
}

typedef OutboxSender = Future<void> Function(OutboxOp op);

class PlanningOutbox {
  PlanningOutbox({
    required OutboxStore store,
    required OutboxSender send,
    Random? random,
    Future<void> Function(Duration)? sleep,
    this.capacity = 200,
    this.maxAttempts = 6,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
  })  : _store = store,
        _send = send,
        _random = random ?? Random(),
        _sleep = sleep ?? Future<void>.delayed {
    unawaited(pending());
  }

  final OutboxStore _store;
  final OutboxSender _send;
  final Random _random;
  final Future<void> Function(Duration) _sleep;
  final int capacity;
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);
  Future<OutboxReplayResult>? _inFlight;

  Future<List<OutboxOp>> pending() async {
    final ops = [
      for (final j in await _store.read())
        if (OutboxOp.fromJson(j) case final op?) op
    ];
    pendingCount.value = ops.length;
    return ops;
  }

  Future<void> _save(List<OutboxOp> ops) async {
    await _store.write([for (final o in ops) o.toJson()]);
    pendingCount.value = ops.length;
  }

  Future<void> enqueue(OutboxOp op) async {
    final ops = await pending();
    if (ops.any((o) => o.opId == op.opId)) return;
    if (ops.length >= capacity) throw const OutboxFullException();
    await _save([...ops, op]);
  }

  Duration _backoff(int attempt) {
    final capMs = min(maxDelay.inMilliseconds, baseDelay.inMilliseconds * (1 << attempt));
    return Duration(milliseconds: (_random.nextDouble() * capMs).round());
  }

  /// One replay at a time; concurrent callers share the in-flight run.
  Future<OutboxReplayResult> replay() => _inFlight ??= _replay().whenComplete(() => _inFlight = null);

  Future<OutboxReplayResult> _replay() async {
    var ops = await pending();
    var sent = 0;
    final dropped = <OutboxOp>[];
    while (ops.isNotEmpty) {
      final op = ops.first;
      var delivered = false;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          await _send(op);
          delivered = true;
          sent++;
          break;
        } catch (e) {
          final error = mapPlanningV2Error(e);
          if (error.isPermanent) {
            dropped.add(op);
            delivered = true; // resolved: never retry a permanent failure
            break;
          }
          if (attempt < maxAttempts - 1) await _sleep(_backoff(attempt));
        }
      }
      if (!delivered) {
        return OutboxReplayResult(sent: sent, dropped: dropped, remaining: ops.length);
      }
      ops = ops.sublist(1);
      await _save(ops);
    }
    return OutboxReplayResult(sent: sent, dropped: dropped, remaining: 0);
  }
}
