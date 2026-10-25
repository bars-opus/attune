import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The server calls behind sign-up (Spec 1 §3.3, §3.4, §4.3 W1b), so the
/// flow can be tested without a backend.
abstract class AccountGateway {
  Future<Object?> rpc(String fn, {Map<String, dynamic>? params});

  /// The account's own `users.display_name` (own-row SELECT), or null.
  Future<String?> displayName(String userId);
}

class SupabaseAccountGateway implements AccountGateway {
  SupabaseAccountGateway([SupabaseClient? client]) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  @override
  Future<Object?> rpc(String fn, {Map<String, dynamic>? params}) =>
      _db.rpc(fn, params: params);

  @override
  Future<String?> displayName(String userId) async {
    final row =
        await _db
            .from('users')
            .select('display_name')
            .eq('id', userId)
            .maybeSingle();
    return row?['display_name'] as String?;
  }
}

/// complete_sign_up's refusals (spec §3.3 A5).
enum SignUpRefusal {
  /// `signup:not_eligible`: under 18 on the server's UTC date. X1.
  notEligible,

  /// `signup:phone_required`: no verified phone on the Auth user.
  phoneRequired,

  /// Any other `signup:*` refusal: retrying can't help.
  invalid,
}

class SignUpRefused implements Exception {
  const SignUpRefused(this.reason);

  final SignUpRefusal reason;
}

/// The server couldn't be reached (or answered with a transient error):
/// the call can be queued and replayed.
class AccountOffline implements Exception {
  const AccountOffline();
}

class AccountService {
  AccountService(this._gateway);

  final AccountGateway _gateway;

  static const timeout = Duration(seconds: 15);

  /// The EULA version A5 and A5c record (spec §3.3, §3.15).
  static const eulaVersion = '2';

  Future<HomeState> homeState() async {
    final data = await _call('get_my_home_state');
    if (data is! Map) throw const AccountOffline();
    return HomeState.fromJson(Map<String, dynamic>.from(data));
  }

  /// A5: the account in one transaction, phone from Auth (D8). Idempotent,
  /// so a queued call can be replayed.
  Future<void> completeSignUp({
    required String displayName,
    required DateTime birthDate,
  }) async {
    await _call(
      'complete_sign_up',
      params: {
        'p_display_name': displayName,
        'p_birth_date': SignUpDraft.dateOnly(birthDate),
        'p_eula_version': eulaVersion,
      },
    );
  }

  /// A5c for an account that accepted an older EULA (spec §3.15).
  Future<void> acceptUpdatedTerms() async {
    await _call('record_eula_acceptance', params: {'p_version': eulaVersion});
  }

  /// For "Welcome back, {name}." Null when unreadable.
  Future<String?> storedDisplayName(String userId) async {
    try {
      return await _gateway.displayName(userId).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  Future<Object?> _call(String fn, {Map<String, dynamic>? params}) async {
    try {
      return await _gateway.rpc(fn, params: params).timeout(timeout);
    } on PostgrestException catch (error) {
      final message = error.message;
      if (message.startsWith('signup:not_eligible')) {
        throw const SignUpRefused(SignUpRefusal.notEligible);
      }
      if (message.startsWith('signup:phone_required')) {
        throw const SignUpRefused(SignUpRefusal.phoneRequired);
      }
      if (message.startsWith('signup:')) {
        throw const SignUpRefused(SignUpRefusal.invalid);
      }
      throw const AccountOffline();
    } on TimeoutException {
      throw const AccountOffline();
    } on IOException {
      // Socket, TLS (a captive portal's handshake) and HTTP (review M-7).
      throw const AccountOffline();
    } on http.ClientException {
      throw const AccountOffline();
    } on AuthRetryableFetchException {
      // An expired session refreshed offline (review M-7).
      throw const AccountOffline();
    }
  }
}

final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(SupabaseAccountGateway()),
);
