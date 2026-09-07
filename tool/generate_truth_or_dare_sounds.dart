// Generates Truth or Dare's sounds from scratch, the same way
// tool/generate_this_or_that_sounds.dart does.
//
// Synthesised rather than sourced: nothing to licence, nothing to
// attribute, tiny files, and the pitches are tunable by editing a number
// and re-running. The committed .wav files are build artifacts of this.
//
// The two card sounds are the point. A flip landing on TRUTH and one
// landing on DARE must not sound the same -- the player should know which
// they got before the text resolves. Truth settles DOWN a perfect fifth
// (open, inviting, at rest); dare climbs UP a minor third and sharpens
// (unresolved, leaning forward). Same instrument, opposite motion.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 44100;

void main() {
  Directory('assets/sounds').createSync(recursive: true);

  // TRUTH: G5 falling to C5 -- a descending fifth, the most restful
  // interval there is. It sounds like someone sitting down to talk.
  _write('game_truth.wav', 0.42, (t, duration) {
    final first = _note(t, 0, 0.22, 783.99);
    final second = _note(t, 0.13, 0.28, 523.25);
    return 0.23 * (first + second) * _envelope(t, duration, 0.006, 0.17);
  });

  // DARE: C5 climbing to E5 then G5, quicker and brighter, with a touch
  // of shimmer on top. It leans forward rather than resolving.
  _write('game_dare.wav', 0.40, (t, duration) {
    final first = _note(t, 0, 0.16, 523.25);
    final second = _note(t, 0.08, 0.16, 659.25);
    final third = _note(t, 0.16, 0.22, 783.99);
    final shimmer = 0.16 * _note(t, 0.16, 0.20, 1567.98);
    return 0.21 *
        (first + second + third + shimmer) *
        _envelope(t, duration, 0.004, 0.14);
  });

  // The answer landing. Softer than either card sound, because it marks
  // something received rather than something dealt.
  _write('game_answer.wav', 0.30, (t, duration) {
    final body = _note(t, 0, 0.20, 440);
    final lift = 0.5 * _note(t, 0.06, 0.20, 659.25);
    return 0.20 * (body + lift) * _envelope(t, duration, 0.008, 0.15);
  });
}

void _write(String filename, double duration, _Sample sample) {
  final count = (_sampleRate * duration).round();
  final pcm = Int16List(count);
  for (var i = 0; i < count; i++) {
    final value = sample(i / _sampleRate, duration).clamp(-0.68, 0.68);
    pcm[i] = (value * 32767).round();
  }

  final dataSize = pcm.lengthInBytes;
  final bytes =
      ByteData(44 + dataSize)
        ..setUint32(0, 0x52494646, Endian.big)
        ..setUint32(4, 36 + dataSize, Endian.little)
        ..setUint32(8, 0x57415645, Endian.big)
        ..setUint32(12, 0x666D7420, Endian.big)
        ..setUint32(16, 16, Endian.little)
        ..setUint16(20, 1, Endian.little)
        ..setUint16(22, 1, Endian.little)
        ..setUint32(24, _sampleRate, Endian.little)
        ..setUint32(28, _sampleRate * 2, Endian.little)
        ..setUint16(32, 2, Endian.little)
        ..setUint16(34, 16, Endian.little)
        ..setUint32(36, 0x64617461, Endian.big)
        ..setUint32(40, dataSize, Endian.little);

  bytes.buffer.asInt16List(44).setAll(0, pcm);
  File('assets/sounds/$filename').writeAsBytesSync(bytes.buffer.asUint8List());
  stdout.writeln('wrote assets/sounds/$filename');
}

typedef _Sample = double Function(double t, double duration);

double _sine(double t, double frequency) =>
    math.sin(2 * math.pi * frequency * t);

double _note(double t, double delay, double length, double frequency) {
  final local = t - delay;
  if (local < 0 || local > length) return 0;
  final envelope = _envelope(local, length, 0.008, math.min(0.18, length / 2));
  return (_sine(local, frequency) + (0.22 * _sine(local, frequency * 2))) *
      envelope;
}

double _envelope(double t, double duration, double attack, double release) {
  final attackGain = math.min(1.0, t / attack);
  final releaseGain = math.min(1.0, (duration - t) / release);
  return math.max(0.0, math.min(attackGain, releaseGain));
}
