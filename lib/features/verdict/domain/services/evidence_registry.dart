// lib/features/verdict/domain/services/evidence_registry.dart

class EvidenceRegistry {
  final List<Evidence> items = [];
  final Map<String, Evidence> _byId = {};
  DateTime _sourceUpdatedAtMax = DateTime.now();

  void addEvidence({
    required String sourceType,
    required String? sourceRecordId,
    required DateTime observedAt,
    required String metric,
    required num value,
    required num? delta,
    required int sampleSize,
    required String frameworkConfidence,
    required String displaySource,
  }) {
    final evidence = Evidence(
      id: '${sourceType}_${observedAt.toIso8601String()}_${metric.replaceAll(' ', '_')}',
      sourceType: sourceType,
      sourceRecordId: sourceRecordId,
      observedAt: observedAt,
      metric: metric,
      value: value,
      delta: delta,
      sampleSize: sampleSize,
      frameworkConfidence: frameworkConfidence,
      displaySource: displaySource,
    );

    items.add(evidence);
    _byId[evidence.id] = evidence;

    if (observedAt.isAfter(_sourceUpdatedAtMax)) {
      _sourceUpdatedAtMax = observedAt;
    }
  }

  Evidence? getById(String id) => _byId[id];

  List<Evidence> getByType(String sourceType) {
    return items.where((e) => e.sourceType == sourceType).toList();
  }

  List<Evidence> getHighConfidence() {
    return items.where((e) => e.frameworkConfidence == 'high').toList();
  }

  bool get hasStrengthEvidence {
    // Strength evidence: high confidence positive signals
    // Connection > 70, Communication > 70, or any high-confidence positive pattern
    return items.any((e) =>
        e.frameworkConfidence == 'high' &&
        ((e.metric == 'connection' && e.value >= 70) ||
            (e.metric == 'communication' && e.value >= 70) ||
            e.metric == 'milestone' ||
            e.metric == 'highlight'));
  }

  bool get hasWatchAreaEvidence {
    // Watch area evidence: medium/high confidence caution signals
    // Conflict count > 0, connection decline > 5, or active patterns
    return items.any((e) =>
        (e.frameworkConfidence == 'high' || e.frameworkConfidence == 'medium') &&
        ((e.metric == 'connection' && (e.delta ?? 0) < -5) ||
            (e.metric == 'conflict_count' && e.value > 0) ||
            e.metric == 'pattern_watch' ||
            e.metric == 'pattern_act'));
  }

  DateTime get sourceUpdatedAtMax => _sourceUpdatedAtMax;

  Map<String, dynamic> toJson() {
    return {
      'evidence': items.map((e) => e.toJson()).toList(),
      'source_updated_at_max': _sourceUpdatedAtMax.toIso8601String(),
    };
  }
}

class Evidence {
  final String id;
  final String sourceType;
  final String? sourceRecordId;
  final DateTime observedAt;
  final String metric;
  final num value;
  final num? delta;
  final int sampleSize;
  final String frameworkConfidence;
  final String displaySource;

  const Evidence({
    required this.id,
    required this.sourceType,
    this.sourceRecordId,
    required this.observedAt,
    required this.metric,
    required this.value,
    this.delta,
    required this.sampleSize,
    required this.frameworkConfidence,
    required this.displaySource,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source_type': sourceType,
      'source_record_id': sourceRecordId,
      'observed_at': observedAt.toIso8601String(),
      'metric': metric,
      'value': value,
      'delta': delta,
      'sample_size': sampleSize,
      'framework_confidence': frameworkConfidence,
      'display_source': displaySource,
    };
  }
}
