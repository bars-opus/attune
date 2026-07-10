// lib/features/conflict_translator/data/models/translator_request.dart

class TranslatorRequest {
  final String message;
  final TranslatorContext? context;
  final String relationshipId;

  const TranslatorRequest({
    required this.message,
    this.context,
    required this.relationshipId,
  });

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'context': context?.toJson(),
      'relationship_id': relationshipId,
    };
  }
}

class TranslatorContext {
  final String? attachmentStyle;
  final String? communicationStyle;
  final Map<String, int>? conflictTendencies;
  final int? daysTogether;
  final String? last3MessagesToneSummary;

  const TranslatorContext({
    this.attachmentStyle,
    this.communicationStyle,
    this.conflictTendencies,
    this.daysTogether,
    this.last3MessagesToneSummary,
  });

  Map<String, dynamic> toJson() {
    return {
      'attachment_style': attachmentStyle,
      'communication_style': communicationStyle,
      'conflict_tendencies': conflictTendencies,
      'days_together': daysTogether,
      'last_3_messages_tone_summary': last3MessagesToneSummary,
    };
  }
}
