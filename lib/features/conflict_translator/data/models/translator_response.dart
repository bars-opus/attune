// lib/features/conflict_translator/data/models/translator_response.dart

class TranslatorResponse {
  final String rewrite;
  final String coreNeedIdentified;
  final String framingNote;
  final String rewriteConfidence; // 'high', 'medium', 'low'

  /// Spec 8 (F15 (2)): the sender's own words disclosed harm; the server
  /// returned the writer-facing card instead of a rewrite.
  final bool writerResources;

  const TranslatorResponse({
    required this.rewrite,
    required this.coreNeedIdentified,
    required this.framingNote,
    required this.rewriteConfidence,
    this.writerResources = false,
  });

  factory TranslatorResponse.fromJson(Map<String, dynamic> json) {
    if (json['status'] == 'writer_resources') {
      return const TranslatorResponse(
        rewrite: '',
        coreNeedIdentified: '',
        framingNote: '',
        rewriteConfidence: 'low',
        writerResources: true,
      );
    }
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
