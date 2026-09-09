import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 44100;

void main() {
  Directory('assets/sounds').createSync(recursive: true);

  // A compact, warm resolve. Kept softer than chat_send because stopping the
  // recorder already has a firm haptic beat.
  _write('voice_send.wav', 0.20, (t, duration) {
    final first = _tone(t, 392) * math.exp(-14 * t);
    final shifted = math.max(0.0, t - 0.055);
    final second = _tone(shifted, 523.25) * math.exp(-13 * shifted);
    return _envelope(t, duration, attack: 0.006, release: 0.10) *
        (0.17 * first + 0.15 * second);
  });

  // A soft papery tuck. The noise is heavily smoothed so it reads as a gentle
  // rustle rather than a sharp impact, with only a faint descending body to
  // keep the action legible as a discard.
  var noiseState = 0x4A3C2D1E;
  var smoothedNoise = 0.0;
  _write('voice_delete.wav', 0.28, (t, duration) {
    noiseState = (1664525 * noiseState + 1013904223) & 0x7fffffff;
    final noise = (noiseState / 0x3fffffff) - 1.0;
    smoothedNoise = (0.94 * smoothedNoise) + (0.06 * noise);
    final rustle = smoothedNoise * math.exp(-10 * t);
    final body = _tone(t, 225 - (65 * t / duration)) * math.exp(-13 * t);
    return _envelope(t, duration, attack: 0.012, release: 0.13) *
        (0.085 * rustle + 0.045 * body);
  });
}

typedef _Sample = double Function(double t, double duration);

void _write(String filename, double duration, _Sample sample) {
  final count = (_sampleRate * duration).round();
  final pcm = Int16List(count);
  for (var i = 0; i < count; i++) {
    final value = sample(i / _sampleRate, duration).clamp(-0.7, 0.7);
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

double _tone(double t, double frequency) {
  if (t <= 0) return 0;
  final fundamental = math.sin(2 * math.pi * frequency * t);
  final overtone = math.sin(2 * math.pi * frequency * 2 * t);
  return fundamental + 0.14 * overtone;
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
