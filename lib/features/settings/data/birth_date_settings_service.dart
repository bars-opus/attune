import 'dart:async';

import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Settings -> Date of birth (Spec 1 §3.15, W6b): the age, and whether the
/// one correction is still open. Never the date itself.
@immutable
class BirthDateStatus {
  const BirthDateStatus({
    required this.age,
    required this.canCorrect,
    this.correctUntil,
  });

  /// Null when the account has no date of birth yet.
  final int? age;
  final bool canCorrect;
  final DateTime? correctUntil;

  factory BirthDateStatus.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final until = map['correct_until'];
    return BirthDateStatus(
      age: (map['age'] as num?)?.toInt(),
      canCorrect: map['can_correct'] == true,
      correctUntil:
          until is String ? DateTime.tryParse(until)?.toLocal() : null,
    );
  }
}

/// Under 18 (§3.15): only ever an account on hold; the phone stops at X1.
bool ageIsUnder18(int? age) => age != null && age < 18;

/// correct_my_birth_date's answer.
enum BirthDateCorrection {
  /// Saved (or the same date again: nothing changed).
  saved,

  /// Under 18: the account is on hold; the phone stops at X1.
  notEligible,

  /// `birth_date:correction_closed`: used, too late, or Dating is active.
  closed,

  /// Offline, a timeout or a refusal that can't be acted on.
  failed,
}

typedef SettingsRpc =
    Future<Object?> Function(String fn, Map<String, dynamic>? params);

class BirthDateSettingsService {
  BirthDateSettingsService(this._rpc);

  final SettingsRpc _rpc;

  static const timeout = Duration(seconds: 15);

  Future<BirthDateStatus> status() async => BirthDateStatus.fromJson(
    await _rpc('get_my_birth_date_status', null).timeout(timeout),
  );

  Future<BirthDateCorrection> correct(DateTime birthDate) async {
    try {
      final data = await _rpc('correct_my_birth_date', {
        'p_birth_date': SignUpDraft.dateOnly(birthDate),
      }).timeout(timeout);
      final status = data is Map ? data['status'] : null;
      final age = data is Map ? data['age'] : null;
      return switch (status) {
        'not_eligible' => BirthDateCorrection.notEligible,
        // Review B7 I-1: an older server answers a retried under-18 date
        // (its not_eligible lost) 'ok' with the age: still not eligible.
        'ok' when age is num && ageIsUnder18(age.toInt()) =>
          BirthDateCorrection.notEligible,
        'ok' => BirthDateCorrection.saved,
        _ => BirthDateCorrection.failed,
      };
    } on PostgrestException catch (error) {
      return error.message.startsWith('birth_date:correction_closed')
          ? BirthDateCorrection.closed
          : BirthDateCorrection.failed;
    } catch (error) {
      debugPrint('[dob-settings] correction failed: ${error.runtimeType}');
      return BirthDateCorrection.failed;
    }
  }
}

final birthDateSettingsServiceProvider = Provider<BirthDateSettingsService>(
  (ref) => BirthDateSettingsService(
    (fn, params) => Supabase.instance.client.rpc(fn, params: params),
  ),
);

final birthDateStatusProvider = FutureProvider.autoDispose<BirthDateStatus>(
  (ref) => ref.watch(birthDateSettingsServiceProvider).status(),
);
