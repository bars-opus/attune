import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Spec 7 (research 06 B9, A9): a private quiet state. While it lasts the app
/// stops celebrating at this person. Nobody else can see it.
enum QuietKind {
  hardTime('hard_time', 'Having a hard time'),
  loss('loss', 'Going through a loss');

  const QuietKind(this.key, this.label);
  final String key;
  final String label;

  static QuietKind? fromKey(Object? key) {
    for (final k in values) {
      if (k.key == key) return k;
    }
    return null;
  }
}

class QuietState {
  const QuietState({
    required this.kind,
    required this.until,
    required this.lineOffered,
  });

  final QuietKind kind;
  final DateTime until;

  /// The once-only line has been offered in this activation.
  final bool lineOffered;

  static QuietState? fromRow(Map<String, dynamic> row) {
    final kind = QuietKind.fromKey(row['kind']);
    final until = DateTime.tryParse(row['until'] as String? ?? '');
    if (kind == null || until == null) return null;
    return QuietState(
      kind: kind,
      until: until,
      lineOffered: row['line_offered'] == true,
    );
  }
}

typedef QuietRpc =
    Future<dynamic> Function(String fn, [Map<String, dynamic>? params]);

class QuietStateService {
  QuietStateService({QuietRpc? rpc}) : _rpc = rpc;

  final QuietRpc? _rpc;

  Future<dynamic> _call(String fn, [Map<String, dynamic>? params]) {
    final rpc = _rpc;
    if (rpc != null) return rpc(fn, params);
    return Supabase.instance.client.rpc(fn, params: params);
  }

  Future<QuietState?> mine() async {
    final rows = await _call('get_my_quiet_state') as List<dynamic>?;
    if (rows == null || rows.isEmpty) return null;
    return QuietState.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<void> start(QuietKind kind) =>
      _call('set_my_quiet_state', {'p_kind': kind.key});

  Future<void> end() => _call('end_my_quiet_state');

  Future<void> markLineOffered() => _call('mark_quiet_line_offered');
}

final quietStateServiceProvider = Provider<QuietStateService>(
  (_) => QuietStateService(),
);
