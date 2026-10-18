// lib/features/conflict_translator/data/models/translator_request.dart

/// Spec 8 (plan review M5): gentle structure (NVC) or plain words.
enum TranslatorRegister { nvc, plain }

class TranslatorRequest {
  final String message;
  final String relationshipId;
  final TranslatorRegister register;

  const TranslatorRequest({
    required this.message,
    required this.relationshipId,
    this.register = TranslatorRegister.nvc,
  });

  /// Only the sender's own words (Spec 8, plan review I9): no profile and no
  /// partner tone summary ever leave the device for the translator.
  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'relationship_id': relationshipId,
      'register': register.name,
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
