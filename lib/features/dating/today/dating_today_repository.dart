// Spec 2 W5b (§3.4, §3.5, §4.4, §4.7): Today's calls. The reads, act and
// the marks go through the Dating RPC client (its device header); the
// photo URLs come from dating-photo-urls through the same Dating-scoped
// client. Every call is bounded; a failure answers failed or busy, never
// the error's text.
import 'dart:async';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/device/trip_phone.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef DatingPhotoUrlsInvoke =
    Future<Object?> Function(Map<String, Object?> body);

abstract class DatingTodayGateway {
  Future<DatingToday> today();

  /// 'interested' or 'passed' on introduction [id], under [key].
  Future<DatingActAnswer> act(String key, String id, String action);

  /// Task 7b (§3.6): blocks the other person on introduction [id], under
  /// [key].
  Future<DatingBlockAnswer> block(String key, String id);

  /// The match moment was shown on this side (best effort).
  Future<void> momentSeen(String matchId);

  /// 'family' or 'quiet': the Today note is not shown again.
  Future<DatingWrite> dismissNote(String note);

  /// The family question's answer (§3.4); null clears it.
  Future<DatingWrite> saveFamily(String key, String? value);

  /// 60-second URLs for the other person's photos on an introduction or
  /// a match; null when refused, busy or failed (the card shows its slots).
  Future<List<DatingPhotoUrl>?> photoUrls(String kind, String id);
}

class DatingTodayRepository implements DatingTodayGateway {
  DatingTodayRepository(
    this._rpc,
    this._invoke, {
    Future<bool> Function()? showSameGender,
  }) : _showSameGender = showSameGender;

  /// Through the Dating-scoped client (its edge calls carry the device
  /// header, as its RPCs do).
  factory DatingTodayRepository.of(
    DatingRpc rpc,
    SupabaseClient c, {
    Future<bool> Function()? showSameGender,
  }) => DatingTodayRepository(
    rpc,
    (body) async =>
        (await c.functions.invoke('dating-photo-urls', body: body)).data,
    showSameGender: showSameGender,
  );

  final DatingRpc _rpc;
  final DatingPhotoUrlsInvoke _invoke;

  /// Spec 2 W8b (R-T5-1): this phone's "Show it on this phone anyway" for
  /// the signed-in account, sent with Today and act.
  final Future<bool> Function()? _showSameGender;

  static const timeout = Duration(seconds: 30);

  @override
  Future<DatingToday> today() async {
    try {
      return DatingToday.fromJson(
        await _rpc.call(
          'get_my_dating_today',
          await datingShowSameGender(_showSameGender),
        ),
      );
    } on DatingBusy {
      return DatingToday.busy;
    } catch (_) {
      return DatingToday.failed;
    }
  }

  @override
  Future<DatingActAnswer> act(String key, String id, String action) async {
    try {
      return DatingActAnswer.fromJson(
        await _rpc.call(
          'act_on_dating_introduction',
          await datingShowSameGender(_showSameGender, {
            'p_idempotency_key': key,
            'p_introduction_id': id,
            'p_action': action,
          }),
        ),
      );
    } on DatingBusy {
      return DatingActAnswer.busy;
    } catch (_) {
      return DatingActAnswer.failed;
    }
  }

  @override
  Future<DatingBlockAnswer> block(String key, String id) async {
    try {
      return DatingBlockAnswer.fromJson(
        await _rpc.call('block_dating_introduction', {
          'p_idempotency_key': key,
          'p_introduction_id': id,
        }),
      );
    } on DatingBusy {
      return DatingBlockAnswer.busy;
    } catch (_) {
      return DatingBlockAnswer.failed;
    }
  }

  @override
  Future<void> momentSeen(String matchId) async {
    try {
      await _rpc.call('mark_dating_match_moment_seen', {'p_match_id': matchId});
    } catch (_) {
      // Shown again next time: never worse than once more.
    }
  }

  @override
  Future<DatingWrite> dismissNote(String note) => datingWrite(
    () => _rpc.call('dismiss_dating_today_note', {'p_note': note}),
  );

  @override
  Future<DatingWrite> saveFamily(String key, String? value) => datingWrite(
    () => _rpc.call('save_dating_family_involvement', {
      'p_idempotency_key': key,
      'p_value': value,
    }),
  );

  @override
  Future<List<DatingPhotoUrl>?> photoUrls(String kind, String id) async {
    try {
      final raw = await _invoke({'kind': kind, 'id': id}).timeout(timeout);
      if (raw is! Map || raw['ok'] != true || raw['photos'] is! List) {
        return null;
      }
      return [
        for (final p in (raw['photos'] as List).whereType<Map>())
          if (p['position'] is int && p['url'] is String)
            DatingPhotoUrl(p['position'] as int, p['url'] as String),
      ];
    } catch (_) {
      return null;
    }
  }
}
