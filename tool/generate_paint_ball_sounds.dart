import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 44100;

void main() {
  Directory('assets/sounds').createSync(recursive: true);

  _write('game_fire.wav', 0.16, (t, duration, noise) {
    final chirp = _chirp(t, duration, 900, 210);
    return _envelope(t, duration, attack: 0.004, release: 0.12) *
        (0.32 * chirp + 0.22 * noise * math.exp(-18 * t));
  });
  _write('game_hit.wav', 0.21, (t, duration, noise) {
    final body = math.sin(2 * math.pi * (125 * t - 70 * t * t));
    return _envelope(t, duration, attack: 0.002, release: 0.18) *
        (0.48 * body + 0.16 * noise * math.exp(-28 * t));
  });
  _write('game_miss.wav', 0.22, (t, duration, noise) {
    return _envelope(t, duration, attack: 0.008, release: 0.17) *
        (0.30 * _chirp(t, duration, 480, 235) +
            0.10 * noise * math.exp(-9 * t));
  });
  _write('game_knockout.wav', 0.42, (t, duration, noise) {
    final first = math.sin(2 * math.pi * 92 * t) * math.exp(-13 * t);
    final shifted = math.max(0.0, t - 0.13);
    final second =
        math.sin(2 * math.pi * 72 * shifted) * math.exp(-15 * shifted);
    final color = math.sin(2 * math.pi * 184 * t) * math.exp(-8 * t);
    return _envelope(t, duration, attack: 0.002, release: 0.30) *
        (0.38 * first + 0.31 * second + 0.10 * color + 0.05 * noise);
  });
  _write('game_penalty_reveal.wav', 0.34, (t, duration, noise) {
    final first = math.sin(2 * math.pi * 520 * t) * math.exp(-7 * t);
    final shifted = math.max(0.0, t - 0.09);
    final second =
        math.sin(2 * math.pi * 660 * shifted) * math.exp(-8 * shifted);
    return _envelope(t, duration, attack: 0.006, release: 0.24) *
        (0.22 * first + 0.20 * second);
  });
}

typedef _Sample = double Function(double t, double duration, double noise);

void _write(String filename, double duration, _Sample sample) {
  final count = (_sampleRate * duration).round();
  final pcm = Int16List(count);
  var random = 0x5A17;

  for (var i = 0; i < count; i++) {
    random = (1664525 * random + 1013904223) & 0xFFFFFFFF;
    final noise = ((random / 0xFFFFFFFF) * 2) - 1;
    final value = sample(i / _sampleRate, duration, noise).clamp(-0.72, 0.72);
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

double _chirp(double t, double duration, double startHz, double endHz) {
  final slope = (endHz - startHz) / duration;
  return math.sin(2 * math.pi * (startHz * t + 0.5 * slope * t * t));
}

double _envelope(
  double t,
  double duration, {
  required double attack,
  required double release,
}) {
  final attackGain = math.min(1.0, t / attack);
  final releaseGain = math.min(1.0, (duration - t) / release);
  return math.max(0.0, math.min(attackGain, releaseGain));
}
