/// How the Conversations ring summary stays current without wasting calls
/// (03 M2, M3, L6; 04 #15): one fetch in flight per relationship with at
/// most one follow-up, a backoff after failures, a re-read when the newest
/// story expires, and which thumbnails a re-read shows were deleted.
library;

import 'dart:async';
import 'dart:convert';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Automatic re-reads after a failed load before waiting for a signal,
/// a resume or Retry.
const int kStoryRingMaxAutoRetries = 6;

/// 2, 4, 8, 16, 32, then 60 s.
Duration storyRingRetryDelay(int failures) {
  final seconds = 2 << (failures - 1).clamp(0, 5);
  return Duration(seconds: seconds > 60 ? 60 : seconds);
}

const Duration kStoryRingExpirySlack = Duration(seconds: 1);

/// How soon after a return's re-read starts a call still counts as the
/// same return's resume signal (final review M-4). The realtime socket is
/// still reconnecting then; its own re-subscribe signal lands later and
/// re-reads as usual.
const Duration kStoryRingReturnJoinWindow = Duration(milliseconds: 250);
const Duration kStoryRingSkewRecheck = Duration(minutes: 1);
const Duration kStoryRingSkewWindow = Duration(minutes: 10);

/// When to re-read so a story leaves the ring once it expires (03 M2):
/// a second after the soonest end still ahead (the server's
/// `next_expires_at`, else the newest story's 24 h end). A row already past
/// that end by the phone's clock but still listed by the server means the
/// clock runs ahead: look again each minute for ten minutes, then leave that
/// row to the next signal or resume (Review Focus 1). A row past the window
/// never hides another row's end (review #2). Null when nothing is due.
Duration? storyRingExpiryDelay(Iterable<StoryRingSummary> rows, DateTime now) {
  Duration? ahead;
  var skewed = false;
  for (final row in rows) {
    if (row.activeCount <= 0) continue;
    final at = row.nextExpiresAt ?? row.newestCreatedAt.add(kStoryLifetime);
    final wait = at.difference(now) + kStoryRingExpirySlack;
    if (wait > Duration.zero) {
      if (ahead == null || wait < ahead) ahead = wait;
    } else if (-wait <= kStoryRingSkewWindow) {
      skewed = true;
    }
  }
  if (skewed && (ahead == null || kStoryRingSkewRecheck < ahead)) {
    return kStoryRingSkewRecheck;
  }
  return ahead;
}

/// How far the server's clock runs ahead of this phone's (negative: behind),
/// from one ring read: `server_now` against the middle of the request
/// (Wave 5, Wave 4 M-6). Capped at a day either way, so one bad value cannot
/// park the expiry timer for ever.
Duration storyServerClockOffset({
  required DateTime serverNow,
  required DateTime startedAt,
  required DateTime receivedAt,
}) {
  final middle = startedAt.add(receivedAt.difference(startedAt) ~/ 2);
  final offset = serverNow.difference(middle);
  const cap = Duration(days: 1);
  if (offset > cap) return cap;
  if (offset < -cap) return -cap;
  return offset;
}

/// Thumbnail keys a re-read shows were deleted (05 #6): an author's newest
/// key that changed to an older story's, or an author gone before their
/// newest story's 24 h ran out. A key replaced by a newer post, or gone
/// because it expired (it is still a calendar memory), is kept.
Set<String> storyRingDroppedThumbnailKeys(
  Map<String, StoryRingSummary> previous,
  Map<String, StoryRingSummary> next,
  DateTime now,
) {
  final dropped = <String>{};
  previous.forEach((author, before) {
    final after = next[author];
    if (after != null) {
      if (after.newestThumbnailKey == before.newestThumbnailKey) return;
      if (after.newestCreatedAt.isAfter(before.newestCreatedAt)) return;
    } else if (!before.newestCreatedAt.add(kStoryLifetime).isAfter(now)) {
      return;
    }
    dropped.add(before.newestThumbnailKey);
  });
  return dropped;
}

/// Whether two ring maps differ in anything the snapshot stores.
bool storyRingRowsDiffer(
  Map<String, StoryRingSummary> a,
  Map<String, StoryRingSummary> b,
) {
  String encode(Map<String, StoryRingSummary> m) =>
      jsonEncode([for (final key in m.keys.toList()..sort()) m[key]!.toRow()]);
  return encode(a) != encode(b);
}

@immutable
class StoryRingFetch {
  const StoryRingFetch({required this.rows, required this.startedAt});
  final List<StoryRingSummary> rows;

  /// When the RPC was issued: a hold set before this is answered by it.
  final DateTime startedAt;
}

/// Per relationship: the fetch in flight, the one follow-up queued behind
/// it, the failure count and the last good map. Outlives the autoDispose
/// summary provider; a new one per account.
class StoryRingFetchCoalescer {
  final Map<String, Future<StoryRingFetch>> _inFlight = {};
  final Map<String, Future<StoryRingFetch>> _followUp = {};
  final Map<String, int> _failures = {};
  final Map<String, Map<String, StoryRingSummary>> _last = {};
  final Map<String, int> _savedEpoch = {};

  /// Relationships whose next fetch is a return's re-read (M-4).
  final Set<String> _returning = {};

  /// When the return's re-read in flight started, by relationship.
  final Map<String, DateTime> _returnFetchStartedAt = {};

  /// Runs [fetch], or joins work already queued: a call while a fetch is in
  /// flight waits for exactly one more fetch that starts after it, shared
  /// by every caller that arrives meanwhile (the pager's F3 scheme; no
  /// timers, so a lone signal still re-reads at once).
  ///
  /// Final review M-4: a call within [kStoryRingReturnJoinWindow] of a
  /// return's re-read starting joins that read. It is the resume signal
  /// for the same return, so coming back costs one fetch whichever of the
  /// two lands first.
  Future<StoryRingFetch> run(
    String relationshipId,
    Future<List<StoryRingSummary>> Function() fetch,
  ) {
    final queued = _followUp[relationshipId];
    if (queued != null) return queued;
    final running = _inFlight[relationshipId];
    if (running == null) return _start(relationshipId, fetch);
    final returnedAt = _returnFetchStartedAt[relationshipId];
    if (returnedAt != null) {
      final age = clock.now().difference(returnedAt);
      if (!age.isNegative && age < kStoryRingReturnJoinWindow) return running;
    }
    return _followUp[relationshipId] = running
        .then<void>((_) {}, onError: (Object _) {})
        .then((_) {
          _followUp.remove(relationshipId);
          return _start(relationshipId, fetch);
        });
  }

  Future<StoryRingFetch> _start(
    String relationshipId,
    Future<List<StoryRingSummary>> Function() fetch,
  ) {
    final startedAt = clock.now();
    if (_returning.remove(relationshipId)) {
      _returnFetchStartedAt[relationshipId] = startedAt;
    } else {
      _returnFetchStartedAt.remove(relationshipId);
    }
    final future = Future.sync(
      fetch,
    ).then((rows) => StoryRingFetch(rows: rows, startedAt: startedAt));
    _inFlight[relationshipId] = future;
    void settle() {
      if (identical(_inFlight[relationshipId], future)) {
        _inFlight.remove(relationshipId);
        _returnFetchStartedAt.remove(relationshipId);
      }
    }

    unawaited(
      future.then<void>((_) => settle(), onError: (Object _) => settle()),
    );
    return future;
  }

  /// The next fetch for [relationshipId] is a return's re-read: a retry or
  /// expiry fell due while Attune was hidden (M-4).
  void markReturn(String relationshipId) => _returning.add(relationshipId);

  int recordFailure(String relationshipId) =>
      _failures[relationshipId] = (_failures[relationshipId] ?? 0) + 1;

  void resetFailures(String relationshipId) => _failures.remove(relationshipId);

  Map<String, StoryRingSummary>? previous(String relationshipId) =>
      _last[relationshipId];

  void remember(String relationshipId, Map<String, StoryRingSummary> map) =>
      _last[relationshipId] = map;

  /// The last-known store's epoch when this relationship's snapshot was
  /// last written: a different one means a wipe since, so the next good
  /// read saves again even if the rows are unchanged.
  int? savedEpoch(String relationshipId) => _savedEpoch[relationshipId];

  void markSaved(String relationshipId, int epoch) =>
      _savedEpoch[relationshipId] = epoch;

  /// A story wipe (05 #6): the last good maps go, so the next read diffs
  /// and saves as a first read. Fetches in flight and failure counts stay.
  void forgetRings() {
    _last.clear();
    _savedEpoch.clear();
  }
}

final storyRingFetchCoalescerProvider = Provider<StoryRingFetchCoalescer>((
  ref,
) {
  ref.watch(currentUserProvider.select((u) => u?.id));
  return StoryRingFetchCoalescer();
});
