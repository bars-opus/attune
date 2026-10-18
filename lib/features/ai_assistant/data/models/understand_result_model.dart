// lib/features/ai_assistant/data/models/understand_result_model.dart

/// `ok`'s confidence, matching spec §6.2 exactly. `high` deliberately
/// does not exist as a value anywhere in this enum or the wire
/// contract: "text alone cannot establish another person's internal
/// state" (spec §6.2) — there is no code path, client or server, that
/// can ever produce it.
enum UnderstandConfidence { low, medium }

UnderstandConfidence _parseConfidence(Object? value) {
  switch (value) {
    case 'low':
      return UnderstandConfidence.low;
    case 'medium':
      return UnderstandConfidence.medium;
    default:
      throw FormatException(
        'UnderstandResultModel.fromJson: unrecognized confidence "$value"',
      );
  }
}

List<String> _parseStringList(Object? value, String fieldName) {
  if (value is! List) {
    throw FormatException(
      'UnderstandResultModel.fromJson: missing/invalid $fieldName',
    );
  }
  return value.map((e) {
    if (e is! String) {
      throw FormatException(
        'UnderstandResultModel.fromJson: non-string entry in $fieldName',
      );
    }
    return e;
  }).toList(growable: false);
}

/// An Understand result, as `ai-understand` returns it (spec §6.2).
/// Sealed on `status` so the two branches are mutually exclusive at
/// the type level: [UnderstandResultOk] has no `reason` field, and
/// [UnderstandResultCannotHelp] has no `possibleReadings`/
/// `responseOptions`/`confidence` fields — there is no shared nullable
/// field either branch could populate for the other.
///
/// This model is never persisted (Drift, SharedPreferences, secure
/// storage) per spec §6.3 — that constraint is enforced by how the
/// provider holding this model is built (`.autoDispose`, per the
/// brief), not by anything in this class itself.
sealed class UnderstandResultModel {
  const UnderstandResultModel();

  /// Throws on any missing/mistyped field rather than defaulting —
  /// this is the boundary where raw server JSON becomes a trusted
  /// model.
  factory UnderstandResultModel.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    switch (status) {
      case 'ok':
        final possibleReadings = _parseStringList(
          json['possible_readings'],
          'possible_readings',
        );
        final responseOptions = _parseStringList(
          json['response_options'],
          'response_options',
        );
        final confidence = _parseConfidence(json['confidence']);
        return UnderstandResultOk(
          possibleReadings: possibleReadings,
          responseOptions: responseOptions,
          confidence: confidence,
        );
      case 'cannot_help':
        final reason = json['reason'];
        if (reason is! String || reason.isEmpty) {
          throw FormatException(
            'UnderstandResultModel.fromJson: missing/invalid reason',
          );
        }
        return UnderstandResultCannotHelp(reason: reason);
      // Spec 8 (F15 (2); plan review C3): fixed outcomes of the
      // deterministic pre-check — no readings, nothing derived.
      case 'boundary':
        return const UnderstandResultBoundary();
      case 'supporter':
        return const UnderstandResultSupporter();
      default:
        throw FormatException(
          'UnderstandResultModel.fromJson: unrecognized status "$status"',
        );
    }
  }
}

/// `ok` branch: one or more plausible readings of the target message
/// plus optional reply phrasings — never a verdict, diagnosis, or
/// claim about intent (spec §6.2).
class UnderstandResultOk extends UnderstandResultModel {
  final List<String> possibleReadings;
  final List<String> responseOptions;
  final UnderstandConfidence confidence;

  const UnderstandResultOk({
    required this.possibleReadings,
    required this.responseOptions,
    required this.confidence,
  });
}

/// `cannot_help` branch: the model declined to interpret (insufficient
/// context, unsafe to infer, or an unsupported request). `reason` is
/// one of `'insufficient_context' | 'unsafe_to_infer' | 'unsupported'`
/// per spec §6.2; kept as a raw String here (rather than a Dart enum)
/// since the UI's only obligation with it today is to route to the
/// same generic "can't help with this" copy regardless of which one it
/// is (spec §6.1) — promote to an enum if per-reason copy is ever
/// needed.
/// The partner's message is a "no" (Spec 8): it is not read for meaning.
class UnderstandResultBoundary extends UnderstandResultModel {
  const UnderstandResultBoundary();
}

/// The partner's message speaks of self-harm (Spec 8): the supporter card.
class UnderstandResultSupporter extends UnderstandResultModel {
  const UnderstandResultSupporter();
}

class UnderstandResultCannotHelp extends UnderstandResultModel {
  final String reason;

  const UnderstandResultCannotHelp({required this.reason});
}
