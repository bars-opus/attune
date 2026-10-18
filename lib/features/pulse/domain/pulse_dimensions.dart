// lib/features/pulse/domain/pulse_dimensions.dart
import 'package:flutter/foundation.dart';

/// One shared Pulse dimension (PULSE.md §4.1 as amended by §11, Spec 1a).
@immutable
class PulseDimension {
  const PulseDimension({
    required this.label,
    required this.key,
    required this.shortLabel,
    required this.description,
    required this.weight,
  });

  /// Display label, also the map key the screen and charts use.
  final String label;

  /// The `pulse_scores` column / `delta_vs_previous` key.
  final String key;
  final String shortLabel;
  final String description;

  /// Raw weight (22/22/20/18); normalised against [sharedPulseWeightTotal].
  final int weight;
}

/// The four dimensions both partners see. Emotional safety is deliberately
/// absent: it is computed per partner and shown only to its author.
const sharedPulseDimensions = <PulseDimension>[
  PulseDimension(
    label: 'Communication',
    key: 'communication',
    shortLabel: 'Comm',
    description: 'How clearly and kindly you express yourselves',
    weight: 22,
  ),
  PulseDimension(
    label: 'Connection',
    key: 'connection',
    shortLabel: 'Conn',
    description: 'Emotional closeness and warmth',
    weight: 22,
  ),
  PulseDimension(
    label: 'Conflict Health',
    key: 'conflict_health',
    shortLabel: 'Conflict',
    description: 'How well you navigate disagreements',
    weight: 20,
  ),
  PulseDimension(
    label: 'Alignment',
    key: 'alignment',
    shortLabel: 'Align',
    description: 'Shared values and direction',
    weight: 18,
  ),
];

const sharedPulseWeightTotal = 82;

int sharedWeightPercent(PulseDimension d) =>
    (d.weight * 100 / sharedPulseWeightTotal).round();

String sharedWeightLine(PulseDimension d) =>
    'Counts for ${sharedWeightPercent(d)}% of the shared score.';

const emotionalSafetyPrivateNote =
    'Emotional safety is not part of the shared score. '
    'Each of you sees your own in Your week.';

PulseDimension? pulseDimensionByLabel(String label) {
  for (final d in sharedPulseDimensions) {
    if (d.label == label) return d;
  }
  return null;
}
