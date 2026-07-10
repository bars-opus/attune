import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

/// Application-layer encryption for the local chat read cache and outgoing
/// queue (Spec 4.4: "Drift database files use platform-appropriate encryption
/// where supported by the approved storage package").
///
/// Message content, media metadata, drafts, and queued sends are encrypted with
/// AES-256-GCM before they are written to SQLite, so raw content never rests on
/// the device filesystem in plaintext. The 256-bit data key is generated once
/// per install and stored in the platform keystore (iOS Keychain / Android
/// Keystore) via [FlutterSecureStorage], never in the database itself.
///
/// Index columns (user_id, relationship_id, client_message_id, created_at) are
/// intentionally left plaintext so the backend can key and order rows; they
/// contain no message content, per the local-diagnostics rule in Spec 4.4.
class ChatCacheCipher {
  ChatCacheCipher._(this._key);

  static const _keyStorageKey = 'attune_chat_cache_key_v1';
  static const _magic = 'acc1'; // versioned envelope prefix
  static const _nonceLength = 12;
  static const _macLength = 16;

  final Uint8List _key;

  /// A cipher with a fixed in-memory key, avoiding the platform keystore. Used
  /// by [ChatCacheService.forTesting] so cache encryption round-trips can be
  /// exercised in unit tests.
  factory ChatCacheCipher.forTesting() {
    final key = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      key[i] = i;
    }
    return ChatCacheCipher._(key);
  }

  /// Loads the persisted data key or generates and stores a new one.
  static Future<ChatCacheCipher> create({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  }) async {
    final existing = await storage.read(key: _keyStorageKey);
    if (existing != null) {
      final decoded = base64Decode(existing);
      if (decoded.length == 32) {
        return ChatCacheCipher._(Uint8List.fromList(decoded));
      }
    }
    final key = _randomBytes(32);
    await storage.write(key: _keyStorageKey, value: base64Encode(key));
    return ChatCacheCipher._(key);
  }

  /// Encrypts a UTF-8 plaintext payload into a base64 envelope:
  /// `magic || nonce(12) || ciphertext+tag`.
  String encryptString(String plaintext) {
    final nonce = _randomBytes(_nonceLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(_key),
          _macLength * 8,
          nonce,
          Uint8List(0),
        ),
      );
    final input = Uint8List.fromList(utf8.encode(plaintext));
    final output = cipher.process(input);
    final envelope = BytesBuilder()
      ..add(utf8.encode(_magic))
      ..add(nonce)
      ..add(output);
    return base64Encode(envelope.toBytes());
  }

  /// Decrypts an envelope produced by [encryptString]. Returns null when the
  /// blob is not a recognized envelope or fails authentication (tampered,
  /// corrupted, or written under a rotated/absent key) so callers treat it as a
  /// cache miss and rebuild from the server.
  String? decryptString(String? envelope) {
    if (envelope == null || envelope.isEmpty) return null;
    try {
      final bytes = base64Decode(envelope);
      final magicBytes = utf8.encode(_magic);
      if (bytes.length < magicBytes.length + _nonceLength + _macLength) {
        return null;
      }
      for (var i = 0; i < magicBytes.length; i++) {
        if (bytes[i] != magicBytes[i]) return null;
      }
      final nonce = Uint8List.sublistView(
        bytes,
        magicBytes.length,
        magicBytes.length + _nonceLength,
      );
      final ciphertext = Uint8List.sublistView(
        bytes,
        magicBytes.length + _nonceLength,
      );
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(_key),
            _macLength * 8,
            nonce,
            Uint8List(0),
          ),
        );
      final plain = cipher.process(ciphertext);
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}
