// test/features/couple_map/widget/support/memory_widget_store.dart
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';

class MemoryCoupleWidgetStore implements CoupleWidgetStore {
  String? payload;
  Uint8List? map;
  int notified = 0;
  final log = <String>[];

  @override
  Future<String?> readPayload() async => payload;

  @override
  Future<void> writePayload(String json) async {
    log.add('payload');
    payload = json;
  }

  @override
  Future<void> writeMap(Uint8List png) async {
    log.add('map');
    map = png;
  }

  @override
  Future<void> removeMap() async {
    log.add('removeMap');
    map = null;
  }

  @override
  Future<void> notifyWidgets() async {
    log.add('notify');
    notified++;
  }
}

/// Android before W2: the provider class doesn't exist, so updateWidget
/// throws a PlatformException after the data is written.
class NotifyFailsStore extends MemoryCoupleWidgetStore {
  @override
  Future<void> notifyWidgets() => throw Exception('-3 no provider class');
}

class ThrowingCoupleWidgetStore implements CoupleWidgetStore {
  @override
  Future<String?> readPayload() => throw Exception('no plugin');
  @override
  Future<void> writePayload(String json) => throw Exception('no plugin');
  @override
  Future<void> writeMap(Uint8List png) => throw Exception('no plugin');
  @override
  Future<void> removeMap() => throw Exception('no plugin');
  @override
  Future<void> notifyWidgets() => throw Exception('no plugin');
}
