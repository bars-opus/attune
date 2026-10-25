import 'package:equatable/equatable.dart';

class JournalAnalysis extends Equatable {
  // 'pending' | 'completed' | 'insufficient_evidence' | 'failed' | 'paused'
  final String status;
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

  /// Spec 1 W1c (D12): insights are paused (journal_ai_insights off). The
  /// entry screen shows a reflection only when [isComplete], so a paused
  /// answer shows nothing.
  bool get isPaused => status == 'paused';

  @override
  List<Object?> get props => [status, tone, observation, confidence];
}
