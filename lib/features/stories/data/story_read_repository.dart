/// Everything that READS stories (Plan C, Task 2): the ring summary, the
/// active reel, the calendar's day counts and day items, a signed URL for
/// one story's media, and the refetch-signal stream from
/// `story_change_signals`.
///
/// Binding authority is `docs/superpowers/specs/2026-09-11-stories-design.md`
/// §5.5. Three of its rules shape every line of this file:
///
/// 1. **Keyset paging, never offset.** Both paginated RPCs
///    (`list_active_story_items`, `list_story_day_items`) take
///    `(p_after_created_at, p_after_id)` and are ordered
///    `(created_at, id) ASC`. The cursor this repository hands back is
///    always the LAST item's `(createdAt, id)` — never a page index or
///    row count — so an insert during viewing appends instead of shifting
///    already-fetched rows (spec §5.5, brief global constraints).
/// 2. **Realtime is a refetch signal, not data.** [watchChangeSignal] emits
///    `void` on every Postgres change to the caller's
///    `story_change_signals` row and on every (re)subscribe — it never
///    surfaces the row's `version`/`updated_at` payload. A subscriber's
///    only correct reaction is to re-read through the RPCs below, which
///    remain the sole authority (spec §5.5, "Realtime is a refetch signal,
///    not a second source of truth").
/// 3. **Signed URLs are minted per request and never cached.** Unlike
///    `supabase_chat_repository.dart`'s `createSignedMediaUrl`, which
///    deliberately caches within a safety margin, [signMediaUrl] here
///    calls `createSignedUrl` fresh every time and stores nothing. The
///    spec is explicit that a cached story URL can outlive the deletion
///    it is supposed to respect (§4.5's whole point is that the TTL is
///    the ONLY thing bounding an already-issued URL) — caching would
///    silently widen that bound. This is a deliberate divergence from the
///    brief's "reuse `createSignedMediaUrl`'s caching shape" instruction:
///    the design spec is binding authority above the brief (task
///    preamble), and the spec's global constraint ("mint per request,
///    NEVER store or cache") directly contradicts caching. Only the
///    bucket-name/TTL-constant SHAPE is reused, not the cache map.
///
/// Follows `story_repository.dart`'s conventions: an abstract gateway
/// interface (so tests can fake it instead of mocking the final,
/// heavily-generic `SupabaseClient` RPC/storage builders — see that
/// file's and `story_outbox_controller_test.dart`'s notes on why), a
/// 30-second timeout on every call, and `StoryApiError` for refusals —
/// the SAME error type and the SAME `_retryableCodes = {'RATE_LIMITED'}`
/// derived from the migrations, not re-guessed here.
library;

import 'dart:async';

import 'package:attune/features/stories/data/story_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row of `get_story_ring_summary` — spec §5.5 / the RPC's own
/// doc-comment (`20260938080000_stories_read_rpcs.sql`).
///
/// **ABSENCE OF A ROW FOR SOME AUTHOR IS NOT "DRAW NO RING."** The RPC
/// omits authors with zero active stories entirely (spec §5.1/§5.5). A
/// caller must derive "should I draw my own ring" from its OWN identity
/// (always yes — empty ring with a `+`), and use a
/// [StoryRingSummary] only to FILL a ring that already exists, keyed by
/// [authorId]. [storyRingSummaryProvider] returns a `Map<String,
/// StoryRingSummary>` rather than a single value for exactly this reason:
/// a map lookup that misses is an obviously different code path from a
/// null/empty single value that a caller might mistake for "no data yet."
@immutable
class StoryRingSummary {
  const StoryRingSummary({
    required this.authorId,
    required this.activeCount,
    required this.unviewedCount,
    required this.newestThumbnailKey,
    required this.newestCreatedAt,
  });

  factory StoryRingSummary.fromRow(Map<String, dynamic> row) {
    return StoryRingSummary(
      authorId: '${row['author_id']}',
      activeCount: (row['active_count'] as num).toInt(),
      unviewedCount: (row['unviewed_count'] as num).toInt(),
      newestThumbnailKey: '${row['newest_thumbnail_key']}',
      newestCreatedAt: DateTime.parse('${row['newest_created_at']}'),
    );
  }

  final String authorId;

  /// How many of this author's items are still in the reel
  /// (`expires_at > now()`). The ring's segment count, capped
  /// client-side at 12 arcs (spec §8) — that cap is a rendering concern
  /// for a later task, not applied here.
  final int activeCount;

  /// EXCLUDES the caller's own stories server-side (the RPC's `CASE`
  /// filters `author_id <> auth.uid()`). Always `0` for the caller's own
  /// row by construction — never derive "have I seen my own story" from
  /// this field.
  final int unviewedCount;

  final String newestThumbnailKey;
  final DateTime newestCreatedAt;
}

/// One row from `story_items` as returned by `list_active_story_items` /
/// `list_story_day_items` — same table, same columns, two different
/// filters (spec §5.5's "expires_at > now()" vs "occurred_on = date").
@immutable
class StoryItem {
  const StoryItem({
    required this.id,
    required this.clientStoryId,
    required this.relationshipId,
    required this.authorId,
    required this.mediaType,
    required this.mediaKey,
    required this.thumbnailKey,
    required this.mediaWidth,
    required this.mediaHeight,
    this.durationMs,
    required this.occurredOn,
    required this.createdAt,
    required this.expiresAt,
    required this.hasBeenViewed,
  });

  factory StoryItem.fromRow(Map<String, dynamic> row) {
    return StoryItem(
      id: '${row['id']}',
      clientStoryId: '${row['client_story_id']}',
      relationshipId: '${row['relationship_id']}',
      authorId: '${row['author_id']}',
      mediaType: '${row['media_type']}',
      mediaKey: '${row['media_key']}',
      thumbnailKey: '${row['thumbnail_key']}',
      mediaWidth: (row['media_width'] as num).toInt(),
      mediaHeight: (row['media_height'] as num).toInt(),
      durationMs: (row['duration_ms'] as num?)?.toInt(),
      occurredOn: DateTime.parse('${row['occurred_on']}'),
      createdAt: DateTime.parse('${row['created_at']}'),
      expiresAt: DateTime.parse('${row['expires_at']}'),
      hasBeenViewed: row['has_been_viewed'] == true,
    );
  }

  final String id;
  final String clientStoryId;
  final String relationshipId;
  final String authorId;

  /// `'image'` or `'video'`.
  final String mediaType;
  final String mediaKey;
  final String thumbnailKey;
  final int mediaWidth;
  final int mediaHeight;
  final int? durationMs;
  final DateTime occurredOn;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// On a partner's story: viewed by me. On the caller's own story:
  /// viewed by partner (spec §3.4). This repository does not disambiguate
  /// that — it is a rendering decision a later task makes by comparing
  /// [authorId] to the caller's own id.
  final bool hasBeenViewed;

  /// The cursor a caller pages from: the LAST item of the previous page,
  /// never an offset (spec §5.5, brief global constraints).
  StoryPageCursor get cursor => StoryPageCursor(createdAt: createdAt, id: id);
}

/// A keyset cursor: the `(created_at, id)` tuple of the last item already
/// fetched. Passed back as `p_after_created_at` / `p_after_id` on the next
/// page. There is deliberately no offset/page-number field anywhere in
/// this file — an offset-based pager is a defect here, not a style choice
/// (brief global constraints).
@immutable
class StoryPageCursor {
  const StoryPageCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final String id;
}

/// One page of keyset-paginated story items.
@immutable
class StoryItemPage {
  const StoryItemPage({required this.items, required this.nextCursor});

  final List<StoryItem> items;

  /// Null when this page was short of the server's cap — there is
  /// nothing more to fetch. The server caps at 50 regardless of what was
  /// asked (spec §5.5), so a full-length page does not itself guarantee
  /// more data exists, but a short page guarantees there is none; callers
  /// treat `items.length < requested limit` as "last page" the same way.
  final StoryPageCursor? nextCursor;
}

/// One row of `list_story_day_counts` — spec §5.5, backs the calendar
/// month view.
@immutable
class StoryDayCount {
  const StoryDayCount({required this.occurredOn, required this.itemCount});

  factory StoryDayCount.fromRow(Map<String, dynamic> row) {
    return StoryDayCount(
      occurredOn: DateTime.parse('${row['occurred_on']}'),
      itemCount: (row['item_count'] as num).toInt(),
    );
  }

  final DateTime occurredOn;
  final int itemCount;
}

/// Every server call the READ side of stories makes.
abstract class StoryReadGateway {
  /// `get_story_ring_summary`. Returns one entry per author WITH an
  /// active story — an author with zero is simply absent (spec §5.5).
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  });

  /// `list_active_story_items` — one author's reel, EXCLUDES expired
  /// items, oldest first for playback.
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  });

  /// `list_story_day_counts` — bounded by `[startOn, endOn]`, one row per
  /// date that has at least one item.
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  });

  /// `list_story_day_items` — one calendar day, INCLUDES expired items
  /// (the whole point of expiry hiding rather than deleting, spec §3.2),
  /// oldest first for playback.
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  });

  /// `mark_story_viewed`.
  Future<void> markViewed({required String storyItemId});

  /// `delete_story_item`.
  Future<void> deleteItem({required String storyItemId});

  /// Mints a FRESH 600-second signed URL for [storageKey] — never cached,
  /// never reused across calls. Returns null if signing fails (mirrors
  /// `supabase_chat_repository.dart`'s `createSignedMediaUrl`, which
  /// treats a signing failure as "no url" rather than throwing).
  Future<String?> signMediaUrl(String storageKey);

  /// Emits `void` — never the row's payload — whenever the caller's
  /// `story_change_signals` row changes AND on every successful
  /// (re)subscribe, so a socket drop-and-reconnect triggers a catch-up
  /// refetch the same way `supabase_chat_repository.dart`'s
  /// `_channelFor` does for chat. Callers must re-read through the RPCs
  /// above; the signal carries no data of its own (spec §5.5).
  Stream<void> watchChangeSignal({required String relationshipId});

  /// Releases realtime resources for [relationshipId]. A no-op if none
  /// were ever opened.
  void disposeChannel(String relationshipId);

  /// Releases every realtime channel this gateway ever opened.
  void disposeAllChannels();
}

class StoryReadRepository implements StoryReadGateway {
  StoryReadRepository(this._supabase);

  final SupabaseClient _supabase;

  static const _bucket = 'story-media';

  /// Same 600-second TTL as chat's `_signedUrlTtl`
  /// (`supabase_chat_repository.dart:31`) and the server's own
  /// `story_archive_ttl_seconds()` — but, per this file's header, never
  /// cached past it. There is deliberately no safety-margin constant and
  /// no cache map here, unlike chat's copy of this same shape.
  static const _signedUrlTtl = Duration(seconds: 600);

  /// Matches `story_repository.dart`'s checklist-1.2 bound: without one,
  /// a stalled connection leaves a reel/calendar screen spinning forever.
  static const _timeout = Duration(seconds: 30);

  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, StreamController<void>> _signalControllers = {};

  Map<String, dynamic> _unwrap(Object? response) {
    final data = Map<String, dynamic>.from(response! as Map);
    if (data['error'] == true) throw StoryApiError.fromJson(data);
    return data;
  }

  /// Same shape as `story_repository.dart`'s `_guard`: converts a timeout
  /// or any other transport failure into `StoryApiError.network` rather
  /// than letting a raw exception reach a screen.
  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op().timeout(_timeout);
    } on StoryApiError {
      rethrow;
    } catch (e) {
      throw StoryApiError.network(e);
    }
  }

  StoryPageCursor? _nextCursorFor(List<StoryItem> items, int limit) {
    // Server caps p_limit at 50 regardless of what was asked (spec §5.5).
    // A page shorter than what was requested means there is nothing more
    // — never derive "more pages" from a fixed count, since the caller
    // may have asked for fewer than 50 to begin with.
    if (items.isEmpty || items.length < limit) return null;
    return items.last.cursor;
  }

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) => _guard(() async {
    final rows = await _supabase.rpc(
      'get_story_ring_summary',
      params: {'p_relationship_id': relationshipId},
    );
    return (rows as List)
        .map((row) => StoryRingSummary.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  });

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) => _guard(() async {
    final rows = await _supabase.rpc(
      'list_active_story_items',
      params: {
        'p_relationship_id': relationshipId,
        'p_author_id': authorId,
        // Keyset cursor: the (created_at, id) tuple of the last item
        // fetched, or both null for the first page (spec §5.5). Never
        // an offset/row-count parameter.
        'p_after_created_at': after?.createdAt.toIso8601String(),
        'p_after_id': after?.id,
        'p_limit': limit,
      },
    );
    final items = (rows as List)
        .map((row) => StoryItem.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
    return StoryItemPage(
      items: items,
      nextCursor: _nextCursorFor(items, limit),
    );
  });

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) => _guard(() async {
    String dateOnly(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final rows = await _supabase.rpc(
      'list_story_day_counts',
      params: {
        'p_relationship_id': relationshipId,
        'p_start_on': dateOnly(startOn),
        'p_end_on': dateOnly(endOn),
      },
    );
    return (rows as List)
        .map((row) => StoryDayCount.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
  });

  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  }) => _guard(() async {
    String dateOnly(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final rows = await _supabase.rpc(
      'list_story_day_items',
      params: {
        'p_relationship_id': relationshipId,
        'p_occurred_on': dateOnly(occurredOn),
        'p_after_created_at': after?.createdAt.toIso8601String(),
        'p_after_id': after?.id,
        'p_limit': limit,
      },
    );
    final items = (rows as List)
        .map((row) => StoryItem.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
    return StoryItemPage(
      items: items,
      nextCursor: _nextCursorFor(items, limit),
    );
  });

  @override
  Future<void> markViewed({required String storyItemId}) => _guard(() async {
    _unwrap(
      await _supabase.rpc(
        'mark_story_viewed',
        params: {'p_story_item_id': storyItemId},
      ),
    );
  });

  @override
  Future<void> deleteItem({required String storyItemId}) => _guard(() async {
    _unwrap(
      await _supabase.rpc(
        'delete_story_item',
        params: {'p_story_item_id': storyItemId},
      ),
    );
  });

  @override
  Future<String?> signMediaUrl(String storageKey) => _guard(() async {
    try {
      // Deliberately no cache read/write here — see this file's header.
      // Every call reaches Storage and mints a brand-new URL.
      return await _supabase.storage
          .from(_bucket)
          .createSignedUrl(storageKey, _signedUrlTtl.inSeconds);
    } catch (_) {
      return null;
    }
  });

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) {
    final existing = _signalControllers[relationshipId];
    if (existing != null) return existing.stream;

    final controller = StreamController<void>.broadcast();
    _signalControllers[relationshipId] = controller;

    final channel =
        _supabase
            .channel('story-signals:$relationshipId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'story_change_signals',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'relationship_id',
                value: relationshipId,
              ),
              // The payload (version/updated_at) is intentionally
              // dropped. Only the fact that something changed is
              // forwarded — see this file's header, rule 2.
              callback: (_) {
                if (!controller.isClosed) controller.add(null);
              },
            )
            .subscribe((status, error) {
              // Same rationale as supabase_chat_repository.dart's
              // _channelFor: a websocket drop-and-reconnect otherwise
              // loses every signal that occurred while it was down, with
              // nothing telling the app to catch up. Emitting on every
              // successful (re)subscribe — including the first — closes
              // that gap; the first emission's refetch is harmless.
              if (status == RealtimeSubscribeStatus.subscribed) {
                if (!controller.isClosed) controller.add(null);
              }
            });

    _channels[relationshipId] = channel;
    return controller.stream;
  }

  @override
  void disposeChannel(String relationshipId) {
    final channel = _channels.remove(relationshipId);
    if (channel != null) {
      unawaited(_supabase.removeChannel(channel));
    }
    final controller = _signalControllers.remove(relationshipId);
    if (controller != null) {
      unawaited(controller.close());
    }
  }

  /// Releases every realtime channel this repository ever opened. Used by
  /// [storyReadGatewayProvider]'s own `ref.onDispose` so nothing is left
  /// subscribed once the last provider referencing this repository goes
  /// away — a plain loop over [disposeChannel] rather than requiring the
  /// caller to remember every relationship id it ever watched.
  @override
  void disposeAllChannels() {
    for (final relationshipId in _channels.keys.toList()) {
      disposeChannel(relationshipId);
    }
  }
}
