// Spec 1 W5: a scripted About us server for the W5 tests. It keeps one
// profile per target and applies a patch the way update_couple_profile
// does for the keys the tests use (no attribution maths: each changed
// field is marked "by me" now).
import 'dart:async';

import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// get_couple_profile()'s shape (spec §4.3 W5), with every field settable.
Map<String, dynamic> aboutUsJson({
  bool draft = false,
  bool readOnly = false,
  String? readUntil,
  String? togetherSince,
  String? precision,
  String? stage,
  String? stageWords,
  List<Map<String, Object?>> ceremonies = const [],
  String? living,
  String? children,
  List<String> bands = const [],
  String anniversary = 'off',
  String? reminderId,
  Map<String, Object?> changes = const {},
}) => {
  'draft': draft,
  'read_only': readOnly,
  'read_until': readUntil,
  'together_since': togetherSince,
  'together_since_precision': precision,
  'stage': stage,
  'stage_words': stageWords,
  'ceremonies': ceremonies,
  'living': living,
  'children': children,
  'child_age_bands': bands,
  'anniversary_source': anniversary,
  'anniversary_reminder_id': reminderId,
  'changes': changes,
};

class FakeCoupleProfileServer {
  FakeCoupleProfileServer({Map<String, Map<String, dynamic>>? profiles})
    : profiles = profiles ?? {};

  /// By target wire: a relationship id, or `draft`.
  final Map<String, Map<String, dynamic>> profiles;

  /// Every call, in order: (function, params).
  final calls = <(String, Map<String, dynamic>?)>[];

  /// Thrown by the next call, if set (once).
  Object? failNext;

  /// Thrown by every call while set.
  Object? failAlways;

  /// Thrown by every update while set (reads still answer).
  Object? failUpdates;

  /// While set and not completed, every call waits for it.
  Completer<void>? hold;

  /// Preflight F-2 (the server's rule since Task 1): while true the caller
  /// is in an active or paused relationship, so both draft RPCs refuse with
  /// `couple_profile:not_found` and no draft row is written.
  bool linked = false;

  /// Preflight F-1: who the server sees as the caller (auth.uid()), read
  /// when each call leaves the phone. While set, each account has its own
  /// draft (`draft:<uid>`), as `couple_profile_drafts.user_id` keeps it.
  String? Function()? caller;

  /// Each call's caller, in order, beside [calls] (null when [caller] is
  /// unset).
  final callers = <String?>[];

  /// B3 fix round 2: while true, an update is checked against the row it
  /// would leave, as update_couple_profile checks it: ceremonies need
  /// Married (`couple_profile:ceremonies_need_married`).
  bool enforcesStageRules = false;

  /// B3 fix round 4 (NM-3): while true, an update whose together_since is
  /// later than UTC today + 1 is refused, as update_couple_profile refuses
  /// it (`couple_profile:future_date`).
  bool refusesFutureDates = false;

  /// B3 fix round 2: one entry per coming update, in order; a non-null
  /// entry is thrown by that update (after [failUpdates]).
  final failUpdatesInOrder = <Object?>[];

  int count(String fn) => calls.where((c) => c.$1 == fn).length;

  /// The callers [fn] was called as.
  List<String?> callersOf(String fn) => [
    for (var i = 0; i < calls.length; i++)
      if (calls[i].$1 == fn) callers[i],
  ];

  CoupleProfileRpc get rpc => call;

  Map<String, dynamic> _profile(String wire) => profiles.putIfAbsent(
    wire,
    () => aboutUsJson(draft: wire.startsWith('draft')),
  );

  Future<Object?> call(String fn, Map<String, dynamic>? params) async {
    calls.add((fn, params));
    final who = caller?.call();
    callers.add(who);
    final draftWire = caller == null ? 'draft' : 'draft:$who';
    final wait = hold;
    if (wait != null) await wait.future;
    final once = failNext;
    if (once != null) {
      failNext = null;
      throw once;
    }
    if (failAlways != null) throw failAlways!;
    if (linked &&
        (fn == 'get_my_couple_profile_draft' ||
            fn == 'update_my_couple_profile_draft')) {
      throw refusal('couple_profile:not_found');
    }
    switch (fn) {
      case 'get_couple_profile':
        return Map<String, dynamic>.from(
          _profile(params!['p_relationship_id'] as String),
        );
      case 'get_my_couple_profile_draft':
        return Map<String, dynamic>.from(_profile(draftWire));
      case 'update_couple_profile':
      case 'update_my_couple_profile_draft':
        if (failUpdates != null) throw failUpdates!;
        if (failUpdatesInOrder.isNotEmpty) {
          final scripted = failUpdatesInOrder.removeAt(0);
          if (scripted != null) throw scripted;
        }
        final wire =
            fn == 'update_my_couple_profile_draft'
                ? draftWire
                : params!['p_relationship_id'] as String;
        final profile = _profile(wire);
        final patch = Map<String, dynamic>.from(params!['p_patch'] as Map);
        if (refusesFutureDates && patch['together_since'] is String) {
          final since = DateTime.parse(patch['together_since'] as String);
          final today = DateTime.now().toUtc();
          final limit = DateTime.utc(today.year, today.month, today.day + 1);
          if (DateTime.utc(since.year, since.month, since.day).isAfter(limit)) {
            throw refusal('couple_profile:future_date');
          }
        }
        if (enforcesStageRules) {
          final stage =
              patch.containsKey('stage') ? patch['stage'] : profile['stage'];
          final ceremonies = patch['ceremonies'];
          if (ceremonies is List &&
              ceremonies.isNotEmpty &&
              stage != 'married') {
            throw refusal('couple_profile:ceremonies_need_married');
          }
        }
        final changes = Map<String, Object?>.from(
          profile['changes'] as Map? ?? const {},
        );
        final now = DateTime.now().toUtc().toIso8601String();
        void mark(String field) {
          if (!wire.startsWith('draft')) {
            changes[field] = {'changed_by_me': true, 'changed_at': now};
          }
        }

        if (patch.containsKey('together_since')) {
          profile['together_since'] = patch['together_since'];
          profile['together_since_precision'] =
              patch['together_since_precision'];
          mark('together_since');
        }
        if (patch.containsKey('stage')) {
          profile['stage'] = patch['stage'];
          profile['stage_words'] = patch['stage_words'];
          if (patch['stage'] != 'married' && !patch.containsKey('ceremonies')) {
            profile['ceremonies'] = <Object?>[];
          }
          mark('stage');
        }
        if (patch.containsKey('ceremonies')) {
          profile['ceremonies'] = patch['ceremonies'];
          mark('ceremonies');
        }
        if (patch.containsKey('living')) {
          profile['living'] = patch['living'];
          mark('living');
        }
        if (patch.containsKey('children')) {
          profile['children'] = patch['children'];
          profile['child_age_bands'] = patch['child_age_bands'] ?? <String>[];
          mark('children');
        }
        if (patch.containsKey('anniversary_source')) {
          profile['anniversary_source'] = patch['anniversary_source'];
          mark('anniversary');
        }
        profile['changes'] = changes;
        return Map<String, dynamic>.from(profile);
      default:
        return null;
    }
  }

  static PostgrestException refusal(String message) =>
      PostgrestException(message: message, code: 'P0001');
}
