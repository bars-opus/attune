/// Signed URLs for story media, by storage key, held in memory only
/// (STORIES.md §4.1 as amended in Wave 4). The rings and the calendar share
/// one URL per key while it is under [kStoryUrlReuseWindow] old, so a
/// rebuild, a month swipe or a second ring does not sign again. Never
/// written to disk; forgotten on sign-out and account change (a new
/// instance per account), quick exit and a relationship's pause or end
/// ([clearEveryLiveCache]), and when a story is deleted ([evict]).
library;

import 'package:clock/clock.dart';

/// Under the 600 s TTL with a minute to spare, the same window the reel
/// uses for its own screen-local reuse.
const Duration kStoryUrlReuseWindow = Duration(seconds: 540);

/// Automatic re-signs after a failure, before waiting for a rebuild.
const int kStorySignMaxAutoRetries = 4;

/// 2, 4, 8, 16 s (capped at 32 s).
Duration storySignRetryDelay(int failures) =>
    Duration(seconds: 2 << (failures - 1).clamp(0, 4));

/// A key that could not be signed (refused, offline or timed out). Carries
/// the key for callers; never logged.
/// How much longer a URL whose request started at [mintedAt] may be
/// reused, or null when it is stale. A negative age (the phone's clock was
/// set back) is stale: the server's TTL ran on its own clock.
Duration? storyUrlFreshFor(DateTime mintedAt) {
  final age = clock.now().difference(mintedAt);
  if (age.isNegative || age >= kStoryUrlReuseWindow) return null;
  return kStoryUrlReuseWindow - age;
}

class StorySignFailure implements Exception {
  const StorySignFailure(this.storageKey);
  final String storageKey;

  @override
  String toString() => 'StorySignFailure';
}

class StorySignedUrlCache {
  StorySignedUrlCache() {
    _live.add(this);
  }

  static final Set<StorySignedUrlCache> _live = {};

  final Map<String, ({String url, DateTime mintedAt})> _urls = {};
  final Map<String, int> _failures = {};

  /// Keys signed since the last [clear] or their [evict]: a URL for any
  /// other key that a holder still shows is from before a wipe, a delete
  /// or another account (final review M-2).
  final Set<String> _known = {};

  /// Signing requests in flight, by key (final review I-1).
  final Map<String, int> _signing = {};

  /// The reusable URL for [storageKey] and how much longer it may be
  /// reused, from ONE clock read (final review M-3), or null (and the URL
  /// forgotten) when there is none or it is stale.
  ({String url, Duration left})? reusable(String storageKey) {
    final entry = _urls[storageKey];
    if (entry == null) return null;
    final left = storyUrlFreshFor(entry.mintedAt);
    if (left == null) {
      _urls.remove(storageKey);
      return null;
    }
    return (url: entry.url, left: left);
  }

  /// The URL minted for [storageKey] under [kStoryUrlReuseWindow] ago.
  String? fresh(String storageKey) => reusable(storageKey)?.url;

  /// How much longer [storageKey]'s URL may be reused, or null (and the
  /// URL forgotten) when there is none or it is stale.
  Duration? freshFor(String storageKey) => reusable(storageKey)?.left;

  /// [mintedAt] is when the signing request STARTED, so a slow reply does
  /// not eat into the margin under the TTL.
  void put(String storageKey, String url, {DateTime? mintedAt}) {
    _urls[storageKey] = (url: url, mintedAt: mintedAt ?? clock.now());
    _failures.remove(storageKey);
    _known.add(storageKey);
  }

  /// Whether [storageKey] was signed since the last [clear] or its
  /// [evict] (final review M-2).
  bool knows(String storageKey) => _known.contains(storageKey);

  /// One more failed signing for [storageKey]; returns the total so far.
  int recordFailure(String storageKey) =>
      _failures[storageKey] = (_failures[storageKey] ?? 0) + 1;

  /// Whether [storageKey]'s last signing failed, and none is in flight.
  bool hasFailed(String storageKey) =>
      _failures.containsKey(storageKey) && !_signing.containsKey(storageKey);

  /// A fresh run of automatic retries for [storageKey] (final review I-1).
  void resetFailures(String storageKey) => _failures.remove(storageKey);

  void beginSigning(String storageKey) =>
      _signing[storageKey] = (_signing[storageKey] ?? 0) + 1;

  void endSigning(String storageKey) {
    final left = (_signing[storageKey] ?? 1) - 1;
    if (left <= 0) {
      _signing.remove(storageKey);
    } else {
      _signing[storageKey] = left;
    }
  }

  void evict(Iterable<String> storageKeys) {
    for (final key in storageKeys) {
      _urls.remove(key);
      _failures.remove(key);
      _known.remove(key);
    }
  }

  void clear() {
    _urls.clear();
    _failures.clear();
    _known.clear();
  }

  void dispose() {
    clear();
    _live.remove(this);
  }

  /// Quick exit and a relationship's pause or end run with no provider
  /// container in hand: every cache still alive forgets everything.
  static void clearEveryLiveCache() {
    for (final cache in _live) {
      cache.clear();
    }
  }
}
