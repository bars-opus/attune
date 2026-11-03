import 'dart:async';
import 'dart:io';

import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where an About us answer goes: one relationship's shared profile, or
/// this account's own draft before linking (spec §4.2; the draft is per
/// account, so nobody's answers reach another account on a shared phone).
@immutable
class AboutUsTarget {
  const AboutUsTarget.shared(String this.relationshipId);

  const AboutUsTarget.draft() : relationshipId = null;

  final String? relationshipId;

  bool get isDraft => relationshipId == null;

  /// The outbox key part: the relationship id, or `draft`.
  String get wire => relationshipId ?? 'draft';

  static AboutUsTarget fromWire(String wire) =>
      wire == 'draft'
          ? const AboutUsTarget.draft()
          : AboutUsTarget.shared(wire);

  @override
  bool operator ==(Object other) =>
      other is AboutUsTarget && other.relationshipId == relationshipId;

  @override
  int get hashCode => relationshipId.hashCode;
}

/// The server's `couple_profile:*` refusals (spec §4.3 W5), each answered
/// in the app's own words.
enum AboutUsRefusal {
  notFound,
  readOnly,
  notRelationship,
  futureDate,
  tooManyCeremonies,
  ceremoniesNeedMarried,
  bandsNeedYes,
  anniversaryNeedsDay,
  invalid,
}

class AboutUsRefused implements Exception {
  const AboutUsRefused(this.reason);

  final AboutUsRefusal reason;

  static AboutUsRefusal reasonOf(String message) => switch (message) {
    'couple_profile:not_found' => AboutUsRefusal.notFound,
    'couple_profile:read_only' => AboutUsRefusal.readOnly,
    'couple_profile:not_relationship' => AboutUsRefusal.notRelationship,
    'couple_profile:future_date' => AboutUsRefusal.futureDate,
    'couple_profile:too_many_ceremonies' => AboutUsRefusal.tooManyCeremonies,
    'couple_profile:ceremonies_need_married' =>
      AboutUsRefusal.ceremoniesNeedMarried,
    'couple_profile:bands_need_yes' => AboutUsRefusal.bandsNeedYes,
    'couple_profile:anniversary_needs_day' =>
      AboutUsRefusal.anniversaryNeedsDay,
    _ => AboutUsRefusal.invalid,
  };
}

/// No answer from the server (offline, a timeout, a server error): the
/// write is queued and replayed (spec §3.14).
class AboutUsOffline implements Exception {
  const AboutUsOffline({this.reachedServer = false});

  /// Batch-3 fix round 1 (I-2): true when the server answered with an
  /// error that isn't a refusal; false when nothing got through (offline,
  /// a timeout) or the server is down or busy (fix round 2, NM-2: a 5xx,
  /// a 429). Only the first counts toward a queued answer's tries.
  final bool reachedServer;
}

/// True when nothing got through to the server: a timeout, no network, a
/// dropped connection, a token refresh that couldn't reach it.
bool isAboutUsTransportFailure(Object error) =>
    error is TimeoutException ||
    error is IOException ||
    error is http.ClientException ||
    error is AuthRetryableFetchException;

final _gatewayDown = RegExp(r'^5\d\d$');

/// B3 fix round 2 (NM-2): the server is down or busy, not refusing: a
/// gateway 5xx or a 429 (postgrest gives the status as the code when the
/// body isn't its JSON), PostgREST's own "can't reach the database"
/// (PGRST000-PGRST003), or the database's connection (08), resource (53)
/// and operator (57: a cancelled or timed-out statement, a restart)
/// classes. Like being offline, it never uses up a queued answer's tries.
bool isAboutUsServerOutage(PostgrestException error) {
  final code = error.code ?? '';
  return code == '429' ||
      _gatewayDown.hasMatch(code) ||
      const {'PGRST000', 'PGRST001', 'PGRST002', 'PGRST003'}.contains(code) ||
      (code.length == 5 &&
          (code.startsWith('08') ||
              code.startsWith('53') ||
              code.startsWith('57')));
}

/// Nothing got through, or the server is down or busy.
bool isAboutUsOutage(Object error) =>
    isAboutUsTransportFailure(error) ||
    (error is PostgrestException && isAboutUsServerOutage(error));

typedef CoupleProfileRpc =
    Future<Object?> Function(String fn, Map<String, dynamic>? params);

final coupleProfileRpcProvider = Provider<CoupleProfileRpc>(
  (ref) => (fn, params) => Supabase.instance.client.rpc(fn, params: params),
);

/// The four About us calls (spec §4.3 W5) behind one seam.
class CoupleProfileService {
  CoupleProfileService(this._rpc);

  final CoupleProfileRpc _rpc;

  static const timeout = Duration(seconds: 15);

  Future<CoupleProfile> fetch(AboutUsTarget target) async => _profile(
    target.isDraft
        ? await _call('get_my_couple_profile_draft', null)
        : await _call('get_couple_profile', {
          'p_relationship_id': target.relationshipId,
        }),
  );

  Future<CoupleProfile> update(
    AboutUsTarget target,
    AboutUsPatch patch,
  ) async => _profile(
    target.isDraft
        ? await _call('update_my_couple_profile_draft', {
          'p_patch': patch.values,
        })
        : await _call('update_couple_profile', {
          'p_relationship_id': target.relationshipId,
          'p_patch': patch.values,
        }),
  );

  CoupleProfile _profile(Object? data) {
    if (data is! Map) throw const AboutUsOffline(reachedServer: true);
    return CoupleProfile.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Object?> _call(String fn, Map<String, dynamic>? params) async {
    try {
      return await _rpc(fn, params).timeout(timeout);
    } on PostgrestException catch (error) {
      if (error.message.startsWith('couple_profile:')) {
        throw AboutUsRefused(AboutUsRefused.reasonOf(error.message));
      }
      throw AboutUsOffline(reachedServer: !isAboutUsServerOutage(error));
    } catch (error) {
      if (isAboutUsTransportFailure(error)) throw const AboutUsOffline();
      rethrow;
    }
  }
}

final coupleProfileServiceProvider = Provider<CoupleProfileService>(
  (ref) => CoupleProfileService(ref.watch(coupleProfileRpcProvider)),
);
