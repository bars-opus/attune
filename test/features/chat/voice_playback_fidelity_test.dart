import 'dart:math';

import 'package:attune/features/chat/presentation/widgets/voice_message_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// Speech-shaped stored waveform: syllables near -24 dBFS, pauses near -45,
/// through the recorder's own amplitude+gamma mapping.
List<int> _storedSpeech() {
  final rng = Random(11);
  double norm(double db) =>
      sqrt(pow(10, db.clamp(-60.0, 0.0) / 20).toDouble()) * 255;
  return List<int>.generate(100, (_) {
    final pause = rng.nextDouble() < 0.28;
    return norm(
      pause ? -45.0 + rng.nextDouble() * 8 : -24.0 + rng.nextDouble() * 16,
    ).round();
  });
}

/// Interquartile spread — what the eye reads as "how much this waveform
/// moves". Min/max flatter the result, since a single loud spike survives
/// any amount of flattening.
double _band(List<double> xs) {
  final s = [...xs]..sort();
  return s[(s.length * 3) ~/ 4] - s[s.length ~/ 4];
}

void main() {
  test('playback keeps the stored dynamics instead of flattening them', () {
    // The live recording waveform draws one bar per raw reading. The player
    // was collapsing ~3 stored samples per bar by PEAK, which discards most
    // of the detail and lifts quiet bars toward loud ones — playback read
    // as visibly less accurate than the same audio had looked live.
    final stored = _storedSpeech();
    final source = stored.map((v) => v / 255).toList();

    // 140px at the painter's own stride: the real bubble geometry.
    final drawn = voiceWaveformBars(stored, 140.0);

    expect(
      drawn.length,
      greaterThan(20),
      reason: 'a bubble-width waveform should still be a real waveform',
    );
    expect(
      _band(drawn),
      greaterThan(_band(source) * 0.75),
      reason:
          'drawn dynamics ${(_band(drawn) * 100).round()}% vs stored '
          '${(_band(source) * 100).round()}% — the painter is flattening it',
    );
  });

  test('a flat recording still draws flat', () {
    // Guards the inverse: the fidelity check must not be satisfiable by
    // inventing variation that is not in the data.
    final flat = List<int>.filled(100, 120);
    final drawn = voiceWaveformBars(flat, 140.0);
    expect(_band(drawn), lessThan(0.01));
  });
}
