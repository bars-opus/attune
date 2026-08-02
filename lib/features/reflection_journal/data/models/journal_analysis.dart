import 'package:equatable/equatable.dart';

class JournalAnalysis extends Equatable {
  final String status; // 'pending' | 'completed' | 'insufficient_evidence' | 'failed'
  final String? tone;
  final String? observation;
  final String? confidence; // 'high' | 'medium' | 'low' | 'none'

  const JournalAnalysis({
    required this.status,
    this.tone,
    this.observation,
    this.confidence,
  });

  factory JournalAnalysis.fromJson(Map<String, dynamic> json) {
    return JournalAnalysis(
      status: json['status'] as String,
      tone: json['tone'] as String?,
      observation: json['observation'] as String?,
      confidence: json['confidence'] as String?,
    );
  }

  bool get isComplete => status == 'completed';
  bool get isPending => status == 'pending';
  bool get isInsufficientEvidence => status == 'insufficient_evidence';

  @override
  List<Object?> get props => [status, tone, observation, confidence];
}
