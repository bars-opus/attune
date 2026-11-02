import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/domain/sign_up_draft.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The server calls behind the home, the catch-up steps and switching
/// (Spec 1 §3.7, §3.12, §3.15, §4.3 W1b), behind one seam so they can be
/// tested without a backend.
abstract class HomeStateGateway {
  Future<Object?> rpc(String fn, {Map<String, dynamic>? params});

  /// A1's catch-up for an account without a name: the users row (granted
  /// column) and profiles.display_name (games read it), as today's
  /// onboarding writes them.
  Future<void> saveDisplayName(String userId, String name);
}

class SupabaseHomeStateGateway implements HomeStateGateway {
  SupabaseHomeStateGateway([SupabaseClient? client]) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  @override
  Future<Object?> rpc(String fn, {Map<String, dynamic>? params}) =>
      _db.rpc(fn, params: params);

  @override
  Future<void> saveDisplayName(String userId, String name) async {
    await _db.from('users').update({'display_name': name}).eq('id', userId);
    await _db.from('profiles').upsert({
      'id': userId,
      'display_name': name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }
}

/// set_my_path's refusals (spec §4.3 W1b), each answered by a screen.
enum PathRefusal {
  /// `path:relationship_open`: a shared space is open or paused.
  relationshipOpen,

  /// `path:confirm_withdraw`: own pending invites would be withdrawn.
  confirmWithdraw,

  /// `path:confirm_pause_dating`: Dating would be paused.
  confirmPauseDating,

  /// `path:needs_signup`: no account, no date of birth or an older EULA.
  needsSignUp,

  /// Any other `path:*` refusal.
  invalid,
}

class PathRefused implements Exception {
  const PathRefused(this.reason);

  final PathRefusal reason;
}

/// set_my_birth_date's answer (spec §3.15 A2).
enum BirthDateOutcome { ok, notEligible, alreadySet }

/// The server couldn't be reached or answered with a transient error.
class HomeOffline implements Exception {
  const HomeOffline();
}

class HomeStateService {
  HomeStateService(this._gateway);

  final HomeStateGateway _gateway;

  static const timeout = Duration(seconds: 15);

  /// get_my_home_state().
  Future<HomeState> fetch() async => _state(await _call('get_my_home_state'));

  /// set_my_path (A6, switching); returns the new home state.
  Future<HomeState> setPath(AppPath path, {bool confirmed = false}) async =>
      _state(
        await _call(
          'set_my_path',
          params: {'p_path': path.wire, 'p_confirmed': confirmed},
        ),
      );

  /// A2's catch-up for a legacy account (spec §3.15).
  Future<BirthDateOutcome> setBirthDate(DateTime birthDate) async {
    final Object? data;
    try {
      data = await _call(
        'set_my_birth_date',
        params: {'p_birth_date': SignUpDraft.dateOnly(birthDate)},
      );
    } on _Refused catch (refused) {
      if (refused.message.startsWith('birth_date:already_set')) {
        return BirthDateOutcome.alreadySet;
      }
      throw const HomeOffline();
    }
    final status = data is Map ? data['status'] : null;
    return status == 'not_eligible'
        ? BirthDateOutcome.notEligible
        : BirthDateOutcome.ok;
  }

  /// A5c for an account on an older EULA (spec §3.15); W2's version, so a
  /// later EULA changes one constant.
  Future<void> acceptUpdatedTerms() async {
    await _call(
      'record_eula_acceptance',
      params: {'p_version': AccountService.eulaVersion},
    );
  }

  /// A1's catch-up (spec §3.15).
  Future<void> saveDisplayName(String userId, String name) async {
    try {
      await _gateway.saveDisplayName(userId, name).timeout(timeout);
    } on PostgrestException {
      throw const HomeOffline();
    } on TimeoutException {
      throw const HomeOffline();
    } on IOException {
      throw const HomeOffline();
    } on http.ClientException {
      throw const HomeOffline();
    }
  }

  /// R3's "Cancel this invite" (spec §3.8): withdraws this person's pending
  /// invites and, with [returnToPreviousPath], restores the path they came
  /// from. Returns how many were withdrawn.
  Future<int> withdrawPendingInvites({
    required bool returnToPreviousPath,
  }) async {
    final data = await _call(
      'withdraw_my_pending_invites',
      params: {'p_return_to_previous_path': returnToPreviousPath},
    );
    return data is int ? data : 0;
  }

  HomeState _state(Object? data) {
    if (data is! Map) throw const HomeOffline();
    return HomeState.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Object?> _call(String fn, {Map<String, dynamic>? params}) async {
    try {
      return await _gateway.rpc(fn, params: params).timeout(timeout);
    } on PostgrestException catch (error) {
      final message = error.message;
      if (message.startsWith('path:')) throw PathRefused(_pathRefusal(message));
      if (message.startsWith('birth_date:')) throw _Refused(message);
      throw const HomeOffline();
    } on TimeoutException {
      throw const HomeOffline();
    } on IOException {
      throw const HomeOffline();
    } on http.ClientException {
      throw const HomeOffline();
    } on AuthRetryableFetchException {
      throw const HomeOffline();
    }
  }

  static PathRefusal _pathRefusal(String message) {
    if (message.startsWith('path:relationship_open')) {
      return PathRefusal.relationshipOpen;
    }
    if (message.startsWith('path:confirm_withdraw')) {
      return PathRefusal.confirmWithdraw;
    }
    if (message.startsWith('path:confirm_pause_dating')) {
      return PathRefusal.confirmPauseDating;
    }
    if (message.startsWith('path:needs_signup')) return PathRefusal.needsSignUp;
    return PathRefusal.invalid;
  }
}

class _Refused implements Exception {
  const _Refused(this.message);

  final String message;
}

final homeStateServiceProvider = Provider<HomeStateService>(
  (ref) => HomeStateService(SupabaseHomeStateGateway()),
);
