// lib/features/verdict/data/models/verdict.dart

import 'package:equatable/equatable.dart';

class Verdict extends Equatable {
  final String id;
  final String relationshipId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime snapshotAt;
  final DateTime generatedAt;
  final String status; // 'published', 'withdrawn'
  final String dataConfidence; // 'low', 'medium', 'high'
  final String confidenceLabel;
  final String headline;
  final List<VerdictItem> strengths;
  final List<VerdictItem> watchAreas;
  final String oneAction;
  final List<String> oneActionEvidenceIds;
  final List<String> patternsReferenced;
  final String disclaimer;
  final String inputSchemaVersion;
  final String promptVersion;
  final String modelProvider;
  final String modelName;
  final DateTime? sourceUpdatedAtMax;

  const Verdict({
    required this.id,
    required this.relationshipId,
    required this.periodStart,
    required this.periodEnd,
    required this.snapshotAt,
    required this.generatedAt,
    required this.status,
    required this.dataConfidence,
    required this.confidenceLabel,
    required this.headline,
    required this.strengths,
    required this.watchAreas,
    required this.oneAction,
    required this.oneActionEvidenceIds,
    required this.patternsReferenced,
    required this.disclaimer,
    required this.inputSchemaVersion,
    required this.promptVersion,
    required this.modelProvider,
    required this.modelName,
    this.sourceUpdatedAtMax,
  });

  factory Verdict.fromJson(Map<String, dynamic> json) {
    return Verdict(
      id: json['id'],
      relationshipId: json['relationship_id'],
      periodStart: DateTime.parse(json['period_start']),
      periodEnd: DateTime.parse(json['period_end']),
      snapshotAt: DateTime.parse(json['snapshot_at']),
      generatedAt: DateTime.parse(json['generated_at']),
      status: json['status'],
      dataConfidence: json['data_confidence'],
      confidenceLabel: json['confidence_label'],
      headline: json['headline'],
      strengths:
          (json['strengths'] as List)
              .map((item) => VerdictItem.fromJson(item))
              .toList(),
      watchAreas:
          (json['watch_areas'] as List)
              .map((item) => VerdictItem.fromJson(item))
              .toList(),
      oneAction: json['one_action'],
      oneActionEvidenceIds: List<String>.from(json['one_action_evidence_ids']),
      patternsReferenced: List<String>.from(json['patterns_referenced']),
      disclaimer: json['disclaimer'],
      inputSchemaVersion: json['input_schema_version'],
      promptVersion: json['prompt_version'],
      modelProvider: json['model_provider'],
      modelName: json['model_name'],
      sourceUpdatedAtMax:
          json['source_updated_at_max'] != null
              ? DateTime.parse(json['source_updated_at_max'])
              : null,
    );
  }

  @override
  List<Object?> get props => [
    id,
    relationshipId,
    periodStart,
    periodEnd,
    status,
    dataConfidence,
    headline,
  ];
}

class VerdictItem extends Equatable {
  final String title;
  final String body;
  final List<String> evidenceIds;
  final String? source;

  const VerdictItem({
    required this.title,
    required this.body,
    required this.evidenceIds,
    this.source,
  });

  factory VerdictItem.fromJson(Map<String, dynamic> json) {
    return VerdictItem(
      title: json['title'],
      body: json['body'],
      evidenceIds: List<String>.from(json['evidence_ids'] ?? []),
      source: json['source'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'body': body,
      'evidence_ids': evidenceIds,
      if (source != null) 'source': source,
    };
  }

  @override
  List<Object?> get props => [title, body, evidenceIds, source];
}
