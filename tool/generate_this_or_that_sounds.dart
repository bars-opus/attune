import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 44100;

void main() {
  Directory('assets/sounds').createSync(recursive: true);

  _write('game_tap.wav', 0.09, (t, duration) {
    final tone = _sine(t, 560) + (0.45 * _sine(t, 1120));
    return 0.28 * tone * _envelope(t, duration, 0.002, 0.07);
  });

  _write('game_reveal.wav', 0.32, (t, duration) {
    final first = _note(t, 0, 0.18, 392);
    final second = _note(t, 0.105, 0.21, 523.25);
    return 0.24 * (first + second) * _envelope(t, duration, 0.006, 0.13);
  });

  _write('game_match.wav', 0.48, (t, duration) {
    final root = _note(t, 0, 0.34, 523.25);
    final third = _note(t, 0.07, 0.34, 659.25);
    final fifth = _note(t, 0.14, 0.34, 783.99);
    return 0.21 * (root + third + fifth) * _envelope(t, duration, 0.006, 0.22);
  });

  _write('game_complete.wav', 0.72, (t, duration) {
    final a = _note(t, 0, 0.26, 392);
    final b = _note(t, 0.12, 0.28, 523.25);
    final c = _note(t, 0.24, 0.30, 659.25);
    final d = _note(t, 0.38, 0.32, 783.99);
    return 0.18 * (a + b + c + d) * _envelope(t, duration, 0.008, 0.26);
  });
}

typedef _Sample = double Function(double t, double duration);

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
}

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
