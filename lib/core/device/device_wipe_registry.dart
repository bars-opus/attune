import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When something is removed from this phone (Spec 1 §5.8, D19).
enum WipeMoment { signOut, quickExit }

/// One thing to remove from this phone at one or both moments.
@immutable
class DeviceWipeEntry {
  const DeviceWipeEntry({
    required this.id,
    required this.moments,
    required this.run,
    this.order = 0,
    this.bound = const Duration(seconds: 1),
    this.protective = false,
    this.keys = const {},
  });

  /// Unique, e.g. `spec1.home_state_cache`.
  final String id;

  /// Lower runs first; one order's entries run side by side.
  final int order;
  final Set<WipeMoment> moments;

  /// The wipe. On quick exit it starts before the decoy's first frame, so
  /// it should do no synchronous work before its first await (batch-1
  /// review, info).
  final Future<void> Function() run;

  /// At most [DeviceWipeRegistry.maxBound].
  final Duration bound;

  /// A protective setting (the Dating lock, the Safety PIN, the discreet
  /// icon): it may never be removed by quick exit, only by sign-out.
  final bool protective;

  /// The device keys (or key patterns, `<uid>` for an account id) this entry
  /// removes, so a test can prove no quick-exit entry touches a protective
  /// one.
  final Set<String> keys;
}

/// One ordered list of "things to remove from this phone", run on sign-out
/// and on quick exit. Spec 1 owns it and its two call sites
/// (quick_exit_service.dart, auth_provider.dart and safety_sign_out.dart's
/// fallback); features only register entries, through
/// lib/app/device_wipes.dart.
class DeviceWipeRegistry {
  DeviceWipeRegistry({this.totalBound = const Duration(seconds: 3)});

  static final instance = DeviceWipeRegistry();

  /// No entry may hold a moment longer than this.
  static const maxBound = Duration(seconds: 2);

  /// The whole run, every entry included.
  final Duration totalBound;

  final _entries = <String, DeviceWipeEntry>{};

  List<DeviceWipeEntry> get entries => List.unmodifiable(_entries.values);

  /// Adds [entry]. A duplicate id, no moment, a bound outside (0, 2 s], or a
  /// protective entry that would run on quick exit is refused: an assert in
  /// debug, ignored (false) in release.
  bool register(DeviceWipeEntry entry) {
    final problem = _problem(entry);
    if (problem != null) {
      assert(false, 'DeviceWipeRegistry: $problem');
      return false;
    }
    _entries[entry.id] = entry;
    return true;
  }

  String? _problem(DeviceWipeEntry entry) {
    if (_entries.containsKey(entry.id)) return 'duplicate id ${entry.id}';
    if (entry.moments.isEmpty) return '${entry.id} names no moment';
    if (entry.bound <= Duration.zero || entry.bound > maxBound) {
      return '${entry.id} bound ${entry.bound} is outside (0, $maxBound]';
    }
    if (entry.protective && entry.moments.contains(WipeMoment.quickExit)) {
      return '${entry.id} is protective and may not run on quick exit';
    }
    return null;
  }

  /// Runs every entry for [moment]: one order after another, each order's
  /// entries side by side, each in its own try and bound, so one failing
  /// or hanging entry never skips another. Bounded by [totalBound]; never
  /// throws.
  Future<void> run(WipeMoment moment) async {
    try {
      await _runAll(moment).timeout(totalBound);
    } catch (error) {
      debugPrint(
        '[device-wipe] ${moment.name} cut short: ${error.runtimeType}',
      );
    }
  }

  Future<void> _runAll(WipeMoment moment) async {
    final due = [
      for (final entry in _entries.values)
        if (entry.moments.contains(moment)) entry,
    ];
    final orders = {for (final entry in due) entry.order}.toList()..sort();
    for (final order in orders) {
      await Future.wait([
        for (final entry in due)
          if (entry.order == order) _runOne(entry),
      ]);
    }
  }

  Future<void> _runOne(DeviceWipeEntry entry) async {
    try {
      await Future<void>.sync(entry.run).timeout(entry.bound);
    } catch (error) {
      debugPrint('[device-wipe] ${entry.id}: ${error.runtimeType}');
    }
  }

  /// Empties the list (tests only).
  @visibleForTesting
  void clear() => _entries.clear();
}

/// [DeviceWipeRegistry.instance], replaceable in tests (spec §5.3).
final deviceWipeRegistryProvider = Provider<DeviceWipeRegistry>(
  (ref) => DeviceWipeRegistry.instance,
);
