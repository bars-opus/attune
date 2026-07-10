// lib/features/conflict_translator/data/models/translator_response.dart

class TranslatorResponse {
  final String rewrite;
  final String coreNeedIdentified;
  final String framingNote;
  final String rewriteConfidence; // 'high', 'medium', 'low'

  const TranslatorResponse({
    required this.rewrite,
    required this.coreNeedIdentified,
    required this.framingNote,
    required this.rewriteConfidence,
  });

  factory TranslatorResponse.fromJson(Map<String, dynamic> json) {
    return TranslatorResponse(
      rewrite: json['rewrite'] ?? '',
      coreNeedIdentified: json['core_need_identified'] ?? '',
      framingNote: json['framing_note'] ?? '',
      rewriteConfidence: json['rewrite_confidence'] ?? 'medium',
    );
  }

  bool get isHighConfidence => rewriteConfidence == 'high';
  bool get isMediumConfidence => rewriteConfidence == 'medium';
  bool get isLowConfidence => rewriteConfidence == 'low';
}
