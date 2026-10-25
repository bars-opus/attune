// Spec 1 W2: a scripted AccountGateway for the sign-up tests.
import 'dart:async';

import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAccountGateway implements AccountGateway {
  FakeAccountGateway({this.homeState, this.name});

  /// get_my_home_state's answer.
  Map<String, dynamic>? homeState;
  String? name;

  /// complete_sign_up / record_eula_acceptance throw this, if set.
  Object? failWith;

  /// While set and not completed, get_my_home_state waits for it.
  Completer<void>? holdHomeState;

  final calls = <(String, Map<String, dynamic>?)>[];

  int count(String fn) => calls.where((c) => c.$1 == fn).length;

  @override
  Future<Object?> rpc(String fn, {Map<String, dynamic>? params}) async {
    calls.add((fn, params));
    if (fn == 'get_my_home_state') {
      final hold = holdHomeState;
      if (hold != null) await hold.future;
      return homeState;
    }
    if (failWith != null) throw failWith!;
    if (fn == 'complete_sign_up') return {'age': 30, 'created': true};
    return null;
  }

  @override
  Future<String?> displayName(String userId) async => name;

  static Map<String, dynamic> account({
    bool hasAccount = true,
    List<String> needs = const [],
  }) => {
    'has_account': hasAccount,
    'path': null,
    'tab': 'me',
    'path_previous': null,
    'needs': needs,
    'hold': false,
    'eula_version': hasAccount ? '2' : null,
    'dating': {'enabled': false, 'enrolled': false},
    'link': {'state': 'none'},
  };

  static PostgrestException refusal(String message) =>
      PostgrestException(message: message, code: 'P0001');
}
