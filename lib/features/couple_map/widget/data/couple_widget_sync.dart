// lib/features/couple_map/widget/data/couple_widget_sync.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:attune/features/together/data/together_widget_sync.dart'
    show togetherWidgetAppGroup;
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This phone's opt-in (spec §2 ruling 1). Off unless set; every clearing
/// path resets it.
const coupleWidgetEnabledKey = 'couple_widget_enabled';
const coupleWidgetPayloadKey = 'couple_widget_v1';
const coupleWidgetMapKey = 'couple_widget_map';

sealed class MapUpdate {
  const MapUpdate();
}

class KeepMap extends MapUpdate {
  const KeepMap();
}

class ReplaceMap extends MapUpdate {
  const ReplaceMap(this.png);
  final Uint8List png;
}

class RemoveMap extends MapUpdate {
  const RemoveMap();
}

/// Where the native widgets read from (a seam for tests).
abstract class CoupleWidgetStore {
  Future<String?> readPayload();
  Future<void> writePayload(String json);
  Future<void> writeMap(Uint8List png);
  Future<void> removeMap();
  Future<void> notifyWidgets();
}

class HomeWidgetCoupleStore implements CoupleWidgetStore {
  const HomeWidgetCoupleStore();

  Future<void> _group() => HomeWidget.setAppGroupId(togetherWidgetAppGroup);

  @override
  Future<String?> readPayload() async {
    await _group();
    return HomeWidget.getWidgetData<String>(coupleWidgetPayloadKey);
  }

  @override
  Future<void> writePayload(String json) async {
    await _group();
    await HomeWidget.saveWidgetData<String>(coupleWidgetPayloadKey, json);
  }

  @override
  Future<void> writeMap(Uint8List png) async {
    await _group();
    await HomeWidget.saveFile(coupleWidgetMapKey, png, extension: 'png');
  }

  @override
  Future<void> removeMap() async {
    await _group();
    // A null value deletes the plugin-managed file too.
    await HomeWidget.saveWidgetData<String>(coupleWidgetMapKey, null);
  }

  @override
  Future<void> notifyWidgets() => HomeWidget.updateWidget(
    iOSName: 'CoupleWidget',
    qualifiedAndroidName: 'com.barsopus.attune.CoupleWidgetProvider',
  );
}

/// Fills, hides or empties the home-screen distance widget. Never throws: a
/// phone without the widget (or a test without the plugin) must not break
/// the caller. Writes are serialised, and a write that started under an
/// older [generation] is dropped (spec §4.1).
class CoupleWidgetSync {
  static CoupleWidgetStore store = const HomeWidgetCoupleStore();

  /// Bumped by every state-changing write (hide, clear). A read or render
  /// that began under an older value must not land.
  static int generation = 0;

  /// Tells in-memory holders (the publisher's preview and last read, the
  /// toggle) that a hide or clear happened, so nothing outlives it.
  static final changes = ValueNotifier<int>(0);

  static void _bump() {
    generation++;
    changes.value = generation;
  }

  static Future<void> _tail = Future.value();
  static int _pending = 0;

  /// Runs [body] after every earlier write. With nothing pending it starts
  /// from a fresh future, never chaining onto a finished one (which may
  /// belong to another zone, e.g. an earlier test's fake clock).
  static Future<T> _serial<T>(Future<T> Function() body) {
    final prev = _pending == 0 ? Future<void>.value() : _tail;
    _pending++;
    final next = prev.then((_) async {
      try {
        return await body();
      } finally {
        _pending--;
      }
    });
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  static Future<bool> isEnabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(
            coupleWidgetEnabledKey,
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> publish(
    CoupleWidgetPayload payload, {
    required MapUpdate map,
    required int generation,
  }) => _serial(() async {
    try {
      if (generation != CoupleWidgetSync.generation) return false;
      if (!await isEnabled()) return false;
      if (!payload.hasDistance) {
        await store.removeMap();
      } else if (map is ReplaceMap) {
        await store.writeMap(map.png);
      } else if (map is RemoveMap) {
        await store.removeMap();
      }
      if (generation != CoupleWidgetSync.generation) return false;
      await store.writePayload(payload.encode());
      // Written is written: before W2 ships the Android provider, this
      // throws (ClassNotFound → PlatformException) on every call.
      try {
        await store.notifyWidgets();
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  });

  /// Pause, stop, sharing off: the distance goes at once, the reunion stays.
  static Future<void> hideDistanceNow() {
    _bump();
    return _serial(() async {
      if (!await isEnabled()) return;
      try {
        final p = CoupleWidgetPayload.decode(await store.readPayload());
        await store.writePayload(p.withoutDistance().encode());
      } catch (_) {}
      try {
        await store.notifyWidgets();
      } catch (_) {}
      try {
        await store.removeMap();
      } catch (_) {}
    });
  }

  /// Quick exit, sign-out, account deletion, end relationship, toggle off,
  /// flag off: nothing readable is left (spec §6.4). The broadcast goes out
  /// before the image delete, so Android's 300 ms quick exit still repaints.
  static Future<void> clear({bool resetOptIn = true}) {
    _bump();
    return _serial(() async {
      if (resetOptIn) {
        try {
          await (await SharedPreferences.getInstance()).remove(
            coupleWidgetEnabledKey,
          );
        } catch (_) {}
      }
      try {
        await store.writePayload(CoupleWidgetPayload.empty.encode());
      } catch (_) {}
      try {
        await store.notifyWidgets();
      } catch (_) {}
      try {
        await store.removeMap();
      } catch (_) {}
    });
  }

  /// At app open: what has run out is deleted from storage, not just hidden.
  static Future<void> dropExpired(DateTime now) => _serial(() async {
    try {
      final raw = await store.readPayload();
      final stored = CoupleWidgetPayload.decode(raw);
      final current = stored.current(now);
      if (current == stored) return;
      await store.writePayload(current.encode());
      if (!current.hasDistance) await store.removeMap();
    } catch (_) {
      return;
    }
    try {
      await store.notifyWidgets();
    } catch (_) {}
  });
}
