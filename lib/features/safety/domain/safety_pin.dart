/// The Safety PIN (Spec 2; research 06 §3 F2): a salted PBKDF2-HMAC-SHA256
/// hash, a 4–8 digit PIN, and an escalating delay after five misses. No wipe.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

final _digits = RegExp(r'^[0-9]{4,8}$');
final _random = Random.secure();

/// 4 to 8 ASCII digits.
bool isValidPin(String pin) => _digits.hasMatch(pin);

/// Iterations for new hashes. The PIN space (10^4–10^8) is what the keystore
/// and the delay protect; the KDF only slows an offline copy, so this stays
/// low enough not to jank a low-end phone. The version prefix carries the
/// count, so it can change without breaking stored hashes.
const safetyPinIterations = 20000;

Uint8List _derive(String pin, List<int> salt, int iterations) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, 32));
  return kdf.process(Uint8List.fromList(utf8.encode(pin)));
}

String hashPin(
  String pin, {
  List<int>? salt,
  int iterations = safetyPinIterations,
}) {
  final s = salt ?? List<int>.generate(16, (_) => _random.nextInt(256));
  final h = _derive(pin, s, iterations);
  return 'v1\$$iterations\$${base64Encode(s)}\$${base64Encode(h)}';
}

bool verifyPinHash(String pin, String encoded) {
  final parts = encoded.split(r'$');
  if (parts.length != 4 || parts[0] != 'v1') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1) return false;
  final List<int> salt;
  final List<int> want;
  try {
    salt = base64Decode(parts[2]);
    want = base64Decode(parts[3]);
  } on FormatException {
    return false;
  }
  final got = _derive(pin, salt, iterations);
  if (got.length != want.length) return false;
  var diff = 0;
  for (var i = 0; i < got.length; i++) {
    diff |= got[i] ^ want[i];
  }
  return diff == 0;
}

/// No delay for the first four misses, then 30 s and escalating to a day
/// (review I4: a flat cap made a 4-digit PIN cheap to walk through).
Duration safetyPinDelayAfter(int failures) {
  if (failures < 5) return Duration.zero;
  return switch (failures) {
    5 => const Duration(seconds: 30),
    6 => const Duration(minutes: 1),
    7 => const Duration(minutes: 5),
    8 => const Duration(minutes: 15),
    9 => const Duration(hours: 1),
    10 => const Duration(hours: 2),
    11 => const Duration(hours: 4),
    12 => const Duration(hours: 8),
    _ => const Duration(hours: 24),
  };
}

enum PinCheck { ok, wrong, waiting }
