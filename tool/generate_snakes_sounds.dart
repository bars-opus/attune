// Generates Snakes and Ladders' sounds, the same way the other games'
// were: synthesised from sine waves, nothing licensed, tiny files,
// reproducible byte-for-byte from this source.
//
// The ladder and the snake are the two that matter. They must be
// distinguishable without looking at the board, because a player watching
// their partner's replay should know what happened from the sound alone.
// So they are literal opposites: the ladder climbs a major arpeggio, the
// snake falls down a chromatic slide.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 44100;

void main() {
  Directory('assets/sounds').createSync(recursive: true);

  // A die landing: a short knock, no pitch to speak of.
  _write('game_dice.wav', 0.16, (t, duration) {
    final knock = _sine(t, 180) + (0.6 * _sine(t, 320));
    final noise = (math.Random(1).nextDouble() - 0.5) * 0.3;
    return 0.30 * (knock + noise) * _envelope(t, duration, 0.002, 0.11);
  });

  // One cell of the walk. Deliberately tiny -- it plays up to six times
  // in a second and must not become a drumbeat.
  _write('game_step.wav', 0.05, (t, duration) {
    return 0.16 * _sine(t, 880) * _envelope(t, duration, 0.001, 0.04);
  });

  // Climbing: C5 E5 G5 C6, quick and rising.
  _write('game_ladder.wav', 0.44, (t, duration) {
    final a = _note(t, 0, 0.14, 523.25);
    final b = _note(t, 0.08, 0.14, 659.25);
    final c = _note(t, 0.16, 0.14, 783.99);
    final d = _note(t, 0.24, 0.18, 1046.50);
    return 0.20 * (a + b + c + d) * _envelope(t, duration, 0.004, 0.16);
  });

  // Falling: the same shape inverted, and flattened, so it reads as a
  // slide rather than a tune.
  _write('game_snake.wav', 0.46, (t, duration) {
    final a = _note(t, 0, 0.16, 622.25);
    final b = _note(t, 0.09, 0.16, 466.16);
    final c = _note(t, 0.18, 0.16, 349.23);
    final d = _note(t, 0.27, 0.19, 261.63);
    return 0.21 * (a + b + c + d) * _envelope(t, duration, 0.004, 0.17);
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
  final envelope = _envelope(local, length, 0.006, math.min(0.14, length / 2));
  return (_sine(local, frequency) + (0.22 * _sine(local, frequency * 2))) *
      envelope;
}

double _envelope(double t, double duration, double attack, double release) {
  final attackGain = math.min(1.0, t / attack);
  final releaseGain = math.min(1.0, (duration - t) / release);
  return math.max(0.0, math.min(attackGain, releaseGain));
}
