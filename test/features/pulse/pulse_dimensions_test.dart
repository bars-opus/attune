// test/features/pulse/pulse_dimensions_test.dart
import 'package:attune/features/pulse/domain/pulse_dimensions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('four shared dimensions, in the server order, no Emotional safety', () {
    expect(sharedPulseDimensions.map((d) => d.label), [
      'Communication',
      'Connection',
      'Conflict Health',
      'Alignment',
    ]);
    expect(sharedPulseDimensions.map((d) => d.key), [
      'communication',
      'connection',
      'conflict_health',
      'alignment',
    ]);
    expect(
      sharedPulseDimensions.any((d) => d.label.contains('Safety')),
      isFalse,
    );
  });

  test('weights are 22/22/20/18, disclosed as 27/27/24/22 and sum to 100', () {
    expect(sharedPulseDimensions.map((d) => d.weight), [22, 22, 20, 18]);
    expect(sharedPulseWeightTotal, 82);
    final pct = sharedPulseDimensions.map(sharedWeightPercent).toList();
    expect(pct, [27, 27, 24, 22]);
    expect(pct.fold<int>(0, (a, b) => a + b), 100);
    expect(
      sharedWeightLine(sharedPulseDimensions.first),
      'Counts for 27% of the shared score.',
    );
  });

  test('lookup by label, and the private note', () {
    expect(pulseDimensionByLabel('Alignment')?.key, 'alignment');
    expect(pulseDimensionByLabel('Emotional Safety'), isNull);
    expect(
      emotionalSafetyPrivateNote,
      'Emotional safety is not part of the shared score. Each of you sees your own in Your week.',
    );
  });
}
