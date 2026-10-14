import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/together_ai.dart';

/// The seam to the `ai-together` function and its status RPC.
abstract class TogetherAiGateway {
  Future<dynamic> invoke(String fn, Map<String, dynamic> body);
  Future<dynamic> rpc(String fn, Map<String, dynamic> params);
}

class SupabaseTogetherAiGateway implements TogetherAiGateway {
  const SupabaseTogetherAiGateway(this._supabase);
  final SupabaseClient _supabase;

  @override
  Future<dynamic> invoke(String fn, Map<String, dynamic> body) async {
    try {
      final res = await _supabase.functions.invoke(fn, body: body);
      return res.data;
    } on FunctionException catch (e) {
      final d = e.details;
      throw TogetherAiException(
        d is Map && d['code'] is String
            ? d['code'] as String
            : 'INTERNAL_ERROR',
        retryAfterSeconds:
            d is Map && d['retry_after_seconds'] is num
                ? (d['retry_after_seconds'] as num).toInt()
                : null,
      );
    }
  }

  @override
  Future<dynamic> rpc(String fn, Map<String, dynamic> params) =>
      _supabase.rpc(fn, params: params);
}

String _two(int n) => n.toString().padLeft(2, '0');
String _localStamp(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}T${_two(d.hour)}:${_two(d.minute)}';

class TogetherAiRepository {
  const TogetherAiRepository(this._gateway);
  final TogetherAiGateway _gateway;
  static const _fn = 'ai-together';

  /// Fails closed: anything but a clear yes is "not available".
  Future<({bool available, String partnerName})> status(
    String relationshipId,
  ) async {
    try {
      final r = await _gateway.rpc('get_together_ai_status', {
        'p_relationship_id': relationshipId,
      });
      final m = Map<String, dynamic>.from(r as Map);
      return (
        available: m['available'] == true,
        partnerName: m['partner_name'] as String? ?? '',
      );
    } catch (_) {
      return (available: false, partnerName: '');
    }
  }

  Future<CaptureDraft> capture(
    String relationshipId,
    String text,
    DateTime now,
  ) async {
    final r = await _gateway.invoke(_fn, {
      'action': 'capture',
      'relationship_id': relationshipId,
      'request_id': const Uuid().v4(),
      'text': text,
      'now_local': _localStamp(now),
    });
    return CaptureDraft.fromJson(
      Map<String, dynamic>.from((r as Map)['draft'] as Map),
    );
  }

  Future<List<DateIdea>> ideas(
    String relationshipId,
    DateTime start,
    DateTime end,
  ) async {
    final r = await _gateway.invoke(_fn, {
      'action': 'ideas',
      'relationship_id': relationshipId,
      'request_id': const Uuid().v4(),
      'window_start_local': _localStamp(start),
      'window_end_local': _localStamp(end),
    });
    return [
      for (final i in (r as Map)['ideas'] as List)
        DateIdea(
          title: (i as Map)['title'] as String,
          blurb: i['blurb'] as String,
        ),
    ];
  }
}
