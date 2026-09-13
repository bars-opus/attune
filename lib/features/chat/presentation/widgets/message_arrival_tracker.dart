/// Tracks messages that were inserted after the chat's initial snapshot.
///
/// Message timestamps are deliberately irrelevant: a realtime row can carry
/// an old server timestamp because of clock skew or delayed delivery. Stable
/// client IDs are the reliable signal that a row has entered this screen.
///
/// [sync] expects IDs in the same newest-first order used by the chat list.
class MessageArrivalTracker {
  final Set<String> _seenIds = <String>{};
  bool _hasBaseline = false;
  bool _wasLoadingMore = false;
  String? _paginationBoundaryId;

  /// Returns IDs that should receive their one-time arrival animation.
  Set<String> sync(
    Iterable<String> orderedIds, {
    required bool initialLoading,
    required bool loadingMore,
  }) {
    final ids = orderedIds.toList(growable: false);

    // An empty loading frame contains no history to baseline. Waiting for its
    // first settled snapshot also makes a genuinely empty conversation work:
    // the empty snapshot becomes the baseline, so its first later message is
    // correctly treated as an arrival.
    if (!_hasBaseline) {
      if (initialLoading && ids.isEmpty) return const <String>{};
      _hasBaseline = true;
      _seenIds.addAll(ids);
      _wasLoadingMore = loadingMore;
      if (loadingMore) _paginationBoundaryId = _lastSeenId(ids);
      return const <String>{};
    }

    if (loadingMore && !_wasLoadingMore) {
      // Everything appended after this oldest already-visible row belongs to
      // the requested history page. Insertions before it can still be genuine
      // realtime arrivals that happened while pagination was in flight.
      _paginationBoundaryId = _lastSeenId(ids);
    }

    final additions = ids.where((id) => !_seenIds.contains(id)).toSet();
    final paginationActive = loadingMore || _wasLoadingMore;
    final boundary = _paginationBoundaryId;
    if (paginationActive && boundary != null) {
      final boundaryIndex = ids.indexOf(boundary);
      if (boundaryIndex >= 0) {
        for (var index = boundaryIndex + 1; index < ids.length; index++) {
          additions.remove(ids[index]);
        }
      }
    }

    // Keep a screen-lifetime ledger. A deleted/replaced row retaining the
    // same client ID must not replay when it reappears.
    _seenIds.addAll(ids);
    _wasLoadingMore = loadingMore;
    if (!loadingMore) _paginationBoundaryId = null;
    return additions;
  }

  String? _lastSeenId(List<String> ids) {
    for (var index = ids.length - 1; index >= 0; index--) {
      if (_seenIds.contains(ids[index])) return ids[index];
    }
    return null;
  }
}
