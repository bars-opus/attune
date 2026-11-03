import 'dart:async';

import 'package:attune/core/flags/public_app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the platform says about the person's age (Spec 1 §3.3 A2, §5.1,
/// W6b). Never stored, never sent: A2 reads it once and forgets it.
enum AgeSignalStatus { adult, minor, supervised, unknown, unavailable }

@immutable
class AgeSignal {
  const AgeSignal(this.source, this.status);

  static const none = AgeSignal('none', AgeSignalStatus.unavailable);

  /// `apple_declared_age_range`, `play_age_signals` or `none`.
  final String source;
  final AgeSignalStatus status;

  /// A minor or supervised result opens X1 (the stricter of the signal and
  /// the typed date wins); unknown and unavailable leave it to the date.
  bool get stopsSignUp =>
      status == AgeSignalStatus.minor || status == AgeSignalStatus.supervised;

  static AgeSignalStatus statusFrom(Object? answer) {
    final value = answer is Map ? answer['status'] : null;
    for (final status in AgeSignalStatus.values) {
      if (status.name == value) return status;
    }
    return AgeSignalStatus.unknown;
  }
}

/// iOS: Apple's Declared Age Range (iOS 26; weak-linked, `unavailable`
/// below it and outside [storefronts]), through AppDelegate's
/// `attune/age_signals` channel. Android: Play Age Signals through
/// MainActivity's. Anything else, or any failure: `unavailable`.
class AgeSignals {
  const AgeSignals._();

  static const channel = MethodChannel('attune/age_signals');

  /// Apple's sheet waits for the person; Play answers on its own.
  static const iosWait = Duration(seconds: 60);
  static const androidWait = Duration(seconds: 10);

  static Future<AgeSignal> read(
    List<String> storefronts, {
    TargetPlatform? platform,
  }) async {
    final os = platform ?? defaultTargetPlatform;
    final source = switch (os) {
      TargetPlatform.iOS => 'apple_declared_age_range',
      TargetPlatform.android => 'play_age_signals',
      _ => null,
    };
    if (source == null) return AgeSignal.none;
    try {
      final answer = await channel
          .invokeMethod<Object?>('read', {'storefronts': storefronts})
          .timeout(os == TargetPlatform.iOS ? iosWait : androidWait);
      return AgeSignal(source, AgeSignal.statusFrom(answer));
    } catch (_) {
      // Never logged (Play Age Signals' terms): unavailable, the date decides.
      return AgeSignal(source, AgeSignalStatus.unavailable);
    }
  }
}

/// platform_age_signals (effective) and the App Store storefronts, from the
/// anon config: live, else the cached copy; off until either is known.
final ageSignalSettingsProvider =
    Provider<({bool on, List<String> storefronts})>((ref) {
      final config =
          ref.watch(
            publicAppConfigProvider.select((config) => config.valueOrNull),
          ) ??
          ref.watch(cachedPublicAppConfigProvider);
      return (
        on: config?.platformAgeSignals ?? false,
        storefronts: config?.ageSignalStorefronts ?? const [],
      );
    });

/// The read itself, replaceable in tests.
final ageSignalReaderProvider =
    Provider<Future<AgeSignal> Function(List<String> storefronts)>(
      (ref) => AgeSignals.read,
    );
