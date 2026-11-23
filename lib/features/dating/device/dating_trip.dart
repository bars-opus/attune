// Spec 2 W8b (§2.3, §2.5, §3.11; R-75..R-79): where the phone is, and the
// person's choice on a trip. The check goes to dating-device-check through
// the Dating-scoped client (its device header), with the network country
// on Android; the choice is set_dating_trip_choice, for the away kind only
// (a same-gender trip's choice stays on this phone: trip_phone.dart, never
// the server, R-T4-9). Every call is bounded; a failure answers failed or
// busy, never the error's text. The place's country is held in memory for
// the note's words, one entry per account.
import 'dart:async';

import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/device/dating_device_check.dart';
import 'package:attune/features/dating/device/network_country.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// §2.3: at most one check per 15 minutes per account (final client fix
/// I-1: while a Dating page or Me's section shows; dating_device_check).
const kDatingDeviceCheckEvery = Duration(minutes: 15);

/// dating-device-check's answer.
class DatingDeviceCheck {
  const DatingDeviceCheck({
    required this.ok,
    this.trusted = false,
    this.away = false,
    this.noteCountry,
  });

  static const failed = DatingDeviceCheck(ok: false);

  final bool ok;
  final bool trusted;

  /// Dating isn't allowed where the phone is (the flag on).
  final bool away;

  /// While the place restricts: its country, for the note's words. Null
  /// also while away when the place isn't resolved (Task 6).
  final String? noteCountry;

  factory DatingDeviceCheck.fromJson(Object? raw) {
    if (raw is! Map || raw['ok'] != true) return failed;
    final note = raw['note'];
    final country = note is Map ? note['country'] : null;
    return DatingDeviceCheck(
      ok: true,
      trusted: raw['trusted'] == true,
      away: raw['away'] == true,
      noteCountry:
          country is String && RegExp(r'^[A-Z]{2}$').hasMatch(country)
              ? country
              : null,
    );
  }

  /// The home shown is from before a trip began or ended. Away with no
  /// place resolved (note null) is still away: only a check that names no
  /// restriction at all disagrees with a trip shown.
  bool disagreesWith(DatingHome home) =>
      away != (home.state == DatingHomeState.away) ||
      (away && home.trip == null) ||
      (!away && noteCountry == null && home.trip != null);
}

abstract class DatingTripGateway {
  /// Where the phone is now; [networkCountry] on Android.
  Future<DatingDeviceCheck> check({String? networkCountry});

  /// §3.11, the away kind only: "Show it on this phone anyway"
  /// ([showHere]) or "Keep it hidden", under [key]; either marks the note
  /// seen for the trip. Never called for a same-gender trip.
  Future<DatingWrite> choose(String key, {required bool showHere});
}

typedef DatingDeviceCheckInvoke =
    Future<Object?> Function(Map<String, Object?> body);

class DatingTripRepository implements DatingTripGateway {
  DatingTripRepository(this._rpc, this._invoke);

  factory DatingTripRepository.of(DatingRpc rpc, SupabaseClient c) =>
      DatingTripRepository(
        rpc,
        (body) async =>
            (await c.functions.invoke('dating-device-check', body: body)).data,
      );

  final DatingRpc _rpc;
  final DatingDeviceCheckInvoke _invoke;

  static const timeout = Duration(seconds: 15);

  @override
  Future<DatingDeviceCheck> check({String? networkCountry}) async {
    try {
      return DatingDeviceCheck.fromJson(
        await _invoke({
          if (networkCountry != null) 'network_country': networkCountry,
        }).timeout(timeout),
      );
    } catch (_) {
      return DatingDeviceCheck.failed;
    }
  }

  @override
  Future<DatingWrite> choose(String key, {required bool showHere}) =>
      datingWrite(
        () => _rpc.call('set_dating_trip_choice', {
          'p_idempotency_key': key,
          'p_show_here': showHere,
        }),
      );
}

final datingTripGatewayProvider = Provider<DatingTripGateway>(
  (ref) => DatingTripRepository.of(
    ref.watch(datingRpcProvider),
    ref.watch(datingSupabaseClientProvider),
  ),
);

/// The network country's read (tests replace it).
final datingNetworkCountryProvider = Provider<Future<String?> Function()>(
  (ref) => NetworkCountry.read,
);

/// The place of [account]'s trip, from the last check (memory only, gone
/// with the checker: final client fix I-1, dating_device_check.dart).
final datingTripPlaceProvider = Provider.autoDispose.family<String?, String?>(
  (ref, account) => ref.watch(
    datingDeviceCheckerProvider.select((s) => s.answers[account]?.noteCountry),
  ),
);

/// One device check through [read] (a ref's); never throws (no gateway
/// in a build without a backend, no channel: a failed check changes
/// nothing).
Future<DatingDeviceCheck> checkDatingDevice(
  T Function<T>(ProviderListenable<T> provider) read,
) async {
  try {
    final network = await read(datingNetworkCountryProvider)();
    return await read(datingTripGatewayProvider).check(networkCountry: network);
  } catch (_) {
    return DatingDeviceCheck.failed;
  }
}
