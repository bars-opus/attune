// lib/features/couple_map/widget/presentation/couple_widget_publisher.dart
import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:attune/features/couple_map/widget/data/world_outline.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_config.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:attune/features/couple_map/widget/domain/region_frame.dart';
import 'package:attune/features/couple_map/widget/presentation/region_map_painter.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart'
    show currentRelationshipIdProvider;
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    show remindersListProvider;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class CoupleWidgetPreview {
  const CoupleWidgetPreview(this.view, this.map);
  final CoupleWidgetView view;
  final Uint8List? map;
}

/// Writes the home-screen widget from presence READS only (spec §4.1): the
/// map tab's own refresh (via presenceReadsProvider) and one read on app
/// resume. It never records, never samples, and never watches the
/// couple-map provider (that would keep it alive and sampling). Reminder
/// changes re-publish the last read from memory, with its original read
/// time, so they cost no network and never extend the 3 h validity.
class CoupleWidgetPublisher {
  CoupleWidgetPublisher(this._ref) {
    CoupleWidgetSync.changes.addListener(_forget);
  }

  final Ref _ref;
  DateTime Function() clock = DateTime.now;
  Future<Uint8List> Function(RegionFrame, WorldOutline) render =
      (f, o) => renderRegionMap(f, o);
  Duration renderBudget = CoupleWidgetConfig.renderBudget;

  final preview = ValueNotifier<CoupleWidgetPreview?>(null);

  bool _started = false;
  bool _disposed = false;
  DateTime? _lastRead;
  CoupleMapPresence? _lastPresence;
  DateTime? _lastPresenceAt;
  int? _lastPresenceGen;
  String? _mapKey;
  Uint8List? _mapBytes;
  int _seenGeneration = -1;
  StreamSubscription<(String, CoupleMapPresence)>? _reads;
  AppLifecycleListener? _life;
  ProviderSubscription<AsyncValue<List<ReminderModel>>>? _reminders;

  bool get started => _started;

  /// At launch: costs nothing unless this phone opted in.
  Future<void> startIfEnabled() async {
    if (await CoupleWidgetSync.isEnabled()) start();
  }

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _reads = _ref
        .read(presenceReadsProvider)
        .stream
        .listen(
          (e) => unawaited(
            _publish(e.$2, CoupleWidgetSync.generation, readAt: clock()),
          ),
        );
    _life = AppLifecycleListener(
      onResume: () => unawaited(refreshFromServer()),
    );
    _reminders = _ref.listen<AsyncValue<List<ReminderModel>>>(
      remindersListProvider,
      (_, next) {
        if (next.isLoading) return; // wait for the settled value
        final last = _lastPresence;
        final at = _lastPresenceAt;
        // Only a read taken since the last hide or clear may come back.
        if (last != null &&
            at != null &&
            _lastPresenceGen == CoupleWidgetSync.generation) {
          unawaited(_publish(last, CoupleWidgetSync.generation, readAt: at));
        }
      },
    );
    unawaited(_startup());
  }

  Future<void> _startup() async {
    await CoupleWidgetSync.dropExpired(clock());
    await refreshFromServer(force: true);
  }

  Future<bool> _flagOn() async {
    try {
      return await _ref.read(coupleMapEnabledProvider.future);
    } catch (_) {
      return false;
    }
  }

  /// One read-only fetch, at most every 5 minutes unless [force]. A failed
  /// read leaves what's stored: it expires by itself (spec §4.2).
  Future<void> refreshFromServer({bool force = false}) async {
    if (_disposed) return;
    final t = clock();
    if (!force &&
        _lastRead != null &&
        t.difference(_lastRead!) < CoupleWidgetConfig.readDebounce) {
      return;
    }
    if (!await CoupleWidgetSync.isEnabled() || _disposed) return;
    _lastRead = t;
    final g = CoupleWidgetSync.generation;
    final CoupleMapPresence p;
    try {
      final rel = await _ref.read(currentRelationshipIdProvider.future);
      if (rel == null || _disposed) return;
      p = await _ref.read(presenceRepositoryProvider).fetchMapPresence(rel);
    } catch (_) {
      dev.log('widget_read_failed', name: 'couple_widget');
      return;
    }
    if (_disposed) return;
    // The flag provider caches a safe "false" when the server couldn't be
    // reached (ChatFeatureFlags). The read just succeeded, so ask again
    // before clearing on flag-off.
    if (!await _flagOn()) {
      if (_disposed) return;
      _ref.invalidate(coupleMapEnabledProvider);
      if (await _flagOn() || _disposed) {
        if (!_disposed) await _publish(p, g, readAt: t);
        return;
      }
      await CoupleWidgetSync.clear(resetOptIn: false);
      return;
    }
    await _publish(p, g, readAt: t);
  }

  Future<List<(String, DateTime)>?> _events() async {
    try {
      final list = await _ref
          .read(remindersListProvider.future)
          .timeout(const Duration(seconds: 5));
      return [for (final r in list) (r.title, r.remindAt)];
    } catch (_) {
      return null;
    }
  }

  Future<void> _publish(
    CoupleMapPresence presence,
    int g, {
    required DateTime readAt,
  }) async {
    if (_disposed) return;
    if (_lastRead == null || readAt.isAfter(_lastRead!)) _lastRead = readAt;
    if (g != CoupleWidgetSync.generation) return;
    if (_lastPresenceAt == null || !readAt.isBefore(_lastPresenceAt!)) {
      _lastPresence = presence;
      _lastPresenceAt = readAt;
      _lastPresenceGen = g;
    }
    if (!await CoupleWidgetSync.isEnabled() || !await _flagOn()) return;
    // Reminders unknown (still loading past 5 s, or failed): don't write a
    // payload that would drop a kept countdown. The listener publishes
    // again when they settle.
    final events = await _events();
    if (events == null || _disposed) return;
    if (_seenGeneration != CoupleWidgetSync.generation) {
      _seenGeneration = CoupleWidgetSync.generation;
      _mapKey = null;
      _mapBytes = null;
    }
    String? kept;
    try {
      kept =
          CoupleWidgetPayload.decode(
            await CoupleWidgetSync.store.readPayload(),
          ).reunionDate;
    } catch (_) {}
    if (_disposed) return;
    final now = clock();
    final b = buildCoupleWidget(
      presence: presence,
      events: events,
      now: now,
      readAt: readAt,
      keptReunionDate: kept,
    );
    MapUpdate map = const RemoveMap();
    String? key;
    Uint8List? bytes;
    if (b.hasMap) {
      final frame = regionFrame(b.mapSelf!, b.mapPartner!);
      key = '${WorldOutline.version}|${frame.cacheKey}';
      if (key == _mapKey && _mapBytes != null) {
        map = const KeepMap();
        bytes = _mapBytes;
      } else {
        try {
          final outline = await _ref.read(worldOutlineProvider.future);
          bytes = await render(frame, outline).timeout(renderBudget);
          map = ReplaceMap(bytes);
        } catch (_) {
          dev.log('widget_render_failed', name: 'couple_widget');
          bytes = null;
          key = null;
        }
      }
    }
    if (_disposed) return;
    final ok = await CoupleWidgetSync.publish(
      b.payload,
      map: map,
      generation: g,
    );
    if (!ok || _disposed) return;
    _mapKey = map is RemoveMap ? null : key;
    _mapBytes = map is RemoveMap ? null : bytes;
    preview.value = CoupleWidgetPreview(
      resolveCoupleWidget(b.payload, now),
      b.payload.hasDistance ? _mapBytes : null,
    );
  }

  /// A hide or clear: nothing read before it may be shown or re-published
  /// (final review C1/I1: the next account must not inherit it).
  void _forget() {
    _lastPresence = null;
    _lastPresenceAt = null;
    _lastPresenceGen = null;
    _mapKey = null;
    _mapBytes = null;
    if (!_disposed) preview.value = null;
  }

  void dispose() {
    _disposed = true;
    CoupleWidgetSync.changes.removeListener(_forget);
    unawaited(_reads?.cancel());
    _life?.dispose();
    _reminders?.close();
    preview.dispose();
  }
}

final coupleWidgetPublisherProvider = Provider<CoupleWidgetPublisher>((ref) {
  final p = CoupleWidgetPublisher(ref);
  ref.onDispose(p.dispose);
  return p;
});
