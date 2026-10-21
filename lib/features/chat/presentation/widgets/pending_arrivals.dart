import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:flutter/foundation.dart';

/// Arrivals waiting for their row to be built, each stamped with when it
/// arrived. The arrival animation is a "just now" gesture: past
/// [window] the id is dropped and the row renders settled.
class PendingArrivals {
  PendingArrivals({this.window = kArrivalAnimationWindow});

  final Duration window;
  final Map<String, DateTime> _since = {};

  /// Records [ids] as arrived at [now]. An id already pending keeps its
  /// original stamp. Entries past [window] are dropped first: a row never
  /// built in time will never animate, so holding it only grows the map,
  /// and an id that arrives again after that is a new arrival.
  void add(Iterable<String> ids, DateTime now) {
    _since.removeWhere((_, since) => now.difference(since) > window);
    for (final id in ids) {
      _since.putIfAbsent(id, () => now);
    }
  }

  /// Consumes [id]. True only if it was pending and still inside [window].
  bool take(String id, DateTime now) {
    final since = _since.remove(id);
    if (since == null) return false;
    return now.difference(since) <= window;
  }

  bool get isEmpty => _since.isEmpty;

  @visibleForTesting
  Set<String> get debugPendingIds => {..._since.keys};
}
