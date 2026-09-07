import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PendingThisOrThatAnswer {
  const PendingThisOrThatAnswer({
    required this.roundId,
    required this.choice,
    required this.savedAt,
  });

  final String roundId;
  final String choice;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
    'round_id': roundId,
    'choice': choice,
    'saved_at': savedAt.toUtc().toIso8601String(),
  };

  static PendingThisOrThatAnswer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final roundId = json['round_id'];
    final choice = json['choice'];
    final savedAt = DateTime.tryParse(json['saved_at'] as String? ?? '');
    if (roundId is! String ||
        (choice != 'a' && choice != 'b') ||
        savedAt == null) {
      return null;
    }
    return PendingThisOrThatAnswer(
      roundId: roundId,
      choice: choice as String,
      savedAt: savedAt,
    );
  }
}

abstract interface class ThisOrThatAnswerOutbox {
  Future<PendingThisOrThatAnswer?> read({
    required String userId,
    required String roundId,
  });

  Future<void> save({
    required String userId,
    required String roundId,
    required String choice,
  });

  Future<void> remove({required String userId, required String roundId});
}

class SecureThisOrThatAnswerOutbox implements ThisOrThatAnswerOutbox {
  const SecureThisOrThatAnswerOutbox({
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  });

  static const _prefix = 'attune_this_or_that_answer_v1';
  final FlutterSecureStorage storage;

  String _key(String userId, String roundId) => '$_prefix:$userId:$roundId';

  @override
  Future<PendingThisOrThatAnswer?> read({
    required String userId,
    required String roundId,
  }) async {
    final value = await storage.read(key: _key(userId, roundId));
    if (value == null) return null;
    try {
      return PendingThisOrThatAnswer.fromJson(jsonDecode(value));
    } on FormatException {
      await remove(userId: userId, roundId: roundId);
      return null;
    }
  }

  @override
  Future<void> save({
    required String userId,
    required String roundId,
    required String choice,
  }) async {
    if (choice != 'a' && choice != 'b') {
      throw ArgumentError.value(choice, 'choice', 'Must be a or b');
    }
    final pending = PendingThisOrThatAnswer(
      roundId: roundId,
      choice: choice,
      savedAt: DateTime.now(),
    );
    await storage.write(
      key: _key(userId, roundId),
      value: jsonEncode(pending.toJson()),
    );
  }

  @override
  Future<void> remove({required String userId, required String roundId}) {
    return storage.delete(key: _key(userId, roundId));
  }
}
