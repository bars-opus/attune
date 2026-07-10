import 'package:attune/features/verdict/data/models/verdict.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum VerdictLoadStatus {
  available,
  ineligible,
  queued,
  processing,
  unavailable,
}

class VerdictLoadState {
  final VerdictLoadStatus status;
  final Verdict? verdict;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String? reason;
  final String? message;

  const VerdictLoadState({
    required this.status,
    required this.periodStart,
    required this.periodEnd,
    this.verdict,
    this.reason,
    this.message,
  });

  bool get hasVerdict => verdict != null;
}

class VerdictService {
  static const String _disclaimer =
      'This reflects patterns in your data. It is not a diagnosis or a decision.';

  final SupabaseClient _supabase;

  VerdictService(this._supabase);

  static ({DateTime start, DateTime end}) previousCompletedPeriodUtc([
    DateTime? now,
  ]) {
    final reference = (now ?? DateTime.now()).toUtc();
    final currentMonthStart = DateTime.utc(reference.year, reference.month, 1);
    final previousMonthStart = DateTime.utc(
      currentMonthStart.year,
      currentMonthStart.month - 1,
      1,
    );
    return (start: previousMonthStart, end: currentMonthStart);
  }

  Future<VerdictLoadState> loadForRelationship(String relationshipId) async {
    final period = previousCompletedPeriodUtc();
    final verdict = await _getVerdictForPeriod(
      relationshipId: relationshipId,
      periodStart: period.start,
    );

    if (verdict != null) {
      return VerdictLoadState(
        status: VerdictLoadStatus.available,
        verdict: verdict,
        periodStart: period.start,
        periodEnd: period.end,
      );
    }

    final response = await _supabase.rpc(
      'request_verdict_generation',
      params: {'p_relationship_id': relationshipId},
    );
    final payload = Map<String, dynamic>.from(response as Map);
    final status = payload['status'] as String? ?? 'unavailable';

    if (status == 'queued') {
      await _triggerGeneration(relationshipId);
      final refreshed = await _getVerdictForPeriod(
        relationshipId: relationshipId,
        periodStart: period.start,
      );
      if (refreshed != null) {
        return VerdictLoadState(
          status: VerdictLoadStatus.available,
          verdict: refreshed,
          periodStart: period.start,
          periodEnd: period.end,
        );
      }
    }

    return VerdictLoadState(
      status: switch (status) {
        'queued' => VerdictLoadStatus.queued,
        'processing' => VerdictLoadStatus.processing,
        'ineligible' => VerdictLoadStatus.ineligible,
        _ => VerdictLoadStatus.unavailable,
      },
      periodStart: period.start,
      periodEnd: period.end,
      reason: payload['reason'] as String?,
      message: payload['message'] as String?,
    );
  }

  Future<void> markViewed(String verdictId) async {
    await _supabase.rpc(
      'mark_verdict_viewed',
      params: {'p_verdict_id': verdictId},
    );
  }

  Future<void> markDismissed(String verdictId) async {
    await _supabase.rpc(
      'mark_verdict_dismissed',
      params: {'p_verdict_id': verdictId},
    );
  }

  Future<Verdict?> _getVerdictForPeriod({
    required String relationshipId,
    required DateTime periodStart,
  }) async {
    final verdictRow =
        await _supabase
            .from('verdicts')
            .select('*')
            .eq('relationship_id', relationshipId)
            .eq('period_start', _toDate(periodStart))
            .eq('status', 'published')
            .maybeSingle();

    if (verdictRow == null) {
      return null;
    }

    final evidenceRows = await _supabase
        .from('verdict_evidence')
        .select('evidence_id, display_source')
        .eq('verdict_id', verdictRow['id']);

    final evidenceById = <String, String>{
      for (final row in evidenceRows)
        row['evidence_id'] as String: row['display_source'] as String,
    };

    final enriched = Map<String, dynamic>.from(verdictRow);
    enriched['strengths'] = _attachSources(
      List<Map<String, dynamic>>.from(
        (verdictRow['strengths'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      ),
      evidenceById,
    );
    enriched['watch_areas'] = _attachSources(
      List<Map<String, dynamic>>.from(
        (verdictRow['watch_areas'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      ),
      evidenceById,
    );
    enriched['disclaimer'] = enriched['disclaimer'] ?? _disclaimer;
    return Verdict.fromJson(enriched);
  }

  List<Map<String, dynamic>> _attachSources(
    List<Map<String, dynamic>> items,
    Map<String, String> evidenceById,
  ) {
    return items.map((item) {
      final evidenceIds = List<String>.from(item['evidence_ids'] ?? const []);
      final source = evidenceIds
          .map((id) => evidenceById[id])
          .whereType<String>()
          .toSet()
          .join(' • ');
      return {
        ...item,
        'source': source.isEmpty ? 'Based on your shared data' : source,
      };
    }).toList();
  }

  Future<void> _triggerGeneration(String relationshipId) async {
    try {
      await _supabase.functions.invoke(
        'generate-verdict',
        body: {'relationship_id': relationshipId},
      );
    } catch (_) {
      // The persisted job remains available for the scheduled worker.
    }
  }

  String _toDate(DateTime value) =>
      value.toUtc().toIso8601String().split('T')[0];
}
