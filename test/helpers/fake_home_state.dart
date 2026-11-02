// Spec 1 W3: scripted home-state and flag gateways for the W3 tests.
import 'dart:async';

import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// get_my_home_state()'s shape (spec §4.3 W1b), with every field settable.
Map<String, dynamic> homeJson({
  bool hasAccount = true,
  String? path = 'just_me',
  String? tab,
  String? pathPrevious,
  List<String> needs = const [],
  bool hold = false,
  bool datingEnabled = false,
  bool datingEnrolled = false,
  String link = 'none',
  String? relationshipId,
  String? partnerFirstName,
  String? inviteExpiresAt,
  String? windowEndsAt,
}) => {
  'has_account': hasAccount,
  'path': path,
  'tab': tab ?? (path == 'relationship' ? 'chat' : 'me'),
  'path_previous': pathPrevious,
  'needs': needs,
  'hold': hold,
  'eula_version': hasAccount ? '2' : null,
  'dating': {'enabled': datingEnabled, 'enrolled': datingEnrolled},
  'link': {
    'state': link,
    'relationship_id': relationshipId,
    'partner_first_name': partnerFirstName,
    'invite_expires_at': inviteExpiresAt,
    'window_ends_at': windowEndsAt,
  },
};

class FakeHomeStateGateway implements HomeStateGateway {
  FakeHomeStateGateway({Map<String, dynamic>? state})
    : state = state ?? homeJson();

  /// What get_my_home_state (and set_my_path) answer.
  Map<String, dynamic> state;

  /// Thrown by the next call, if set (once).
  Object? failNext;

  /// Thrown by every call while set.
  Object? failAlways;

  /// While set and not completed, every call waits for it.
  Completer<void>? hold;

  /// set_my_birth_date's answer.
  String birthDateStatus = 'ok';

  /// set_my_path: what the call does to [state] before it answers.
  void Function(Map<String, dynamic> params)? onSetPath;

  final calls = <(String, Map<String, dynamic>?)>[];
  final savedNames = <(String, String)>[];

  int count(String fn) => calls.where((c) => c.$1 == fn).length;

  @override
  Future<Object?> rpc(String fn, {Map<String, dynamic>? params}) async {
    calls.add((fn, params));
    final wait = hold;
    if (wait != null) await wait.future;
    final once = failNext;
    if (once != null) {
      failNext = null;
      throw once;
    }
    if (failAlways != null) throw failAlways!;
    switch (fn) {
      case 'get_my_home_state':
        return state;
      case 'set_my_path':
        onSetPath?.call(params ?? const {});
        return state;
      case 'set_my_birth_date':
        return {'status': birthDateStatus, 'age': 30};
      case 'withdraw_my_pending_invites':
        return 1;
      default:
        return null;
    }
  }

  @override
  Future<void> saveDisplayName(String userId, String name) async {
    if (failAlways != null) throw failAlways!;
    savedNames.add((userId, name));
  }

  static PostgrestException refusal(String message) =>
      PostgrestException(message: message, code: 'P0001');
}

class FakeFlowFlagsGateway implements FlowFlagsGateway {
  FakeFlowFlagsGateway({this.pathsV2 = true, this.couplesV2 = false});

  bool pathsV2;
  bool couplesV2;
  Object? failWith;
  int fetches = 0;

  @override
  Future<SignedInFlowFlags> fetch() async {
    fetches++;
    if (failWith != null) throw failWith!;
    return SignedInFlowFlags(pathsV2: pathsV2, couplesV2: couplesV2);
  }
}
