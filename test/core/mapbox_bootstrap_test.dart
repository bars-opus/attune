// test/core/mapbox_bootstrap_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Mapbox is configured at bootstrap from Environment, never hard-coded',
    () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(
        main.contains(
          'MapboxOptions.setAccessToken(Environment.mapboxAccessToken)',
        ),
        isTrue,
      );
      expect(
        RegExp(r"setAccessToken\('pk\.").hasMatch(main),
        isFalse,
        reason: 'no hard-coded token (checklist 2.7)',
      );
    },
  );
}
