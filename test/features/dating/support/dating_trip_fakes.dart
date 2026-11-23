// Spec 2 W8b: the device check and the trip choice faked for widget tests.
// Every call is recorded; a check can be held open (D8 tests).
import 'dart:async';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/device/dating_trip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FakeDatingTrip implements DatingTripGateway {
  FakeDatingTrip({
    this.answer = const DatingDeviceCheck(ok: true, trusted: true),
  });

  DatingDeviceCheck answer;
  DatingWrite choice = const DatingWrite(ok: true);
  final checks = <String?>[];
  final choices = <(String key, bool showHere)>[];
  Completer<void>? checkHold;

  @override
  Future<DatingDeviceCheck> check({String? networkCountry}) async {
    checks.add(networkCountry);
    final held = checkHold;
    if (held != null) await held.future;
    return answer;
  }

  @override
  Future<DatingWrite> choose(String key, {required bool showHere}) async {
    choices.add((key, showHere));
    return choice;
  }
}

/// The trip overrides: [fake] and the network country [network].
List<Override> datingTripOverrides(FakeDatingTrip fake, {String? network}) => [
  datingTripGatewayProvider.overrideWithValue(fake),
  datingNetworkCountryProvider.overrideWithValue(() async => network),
];
