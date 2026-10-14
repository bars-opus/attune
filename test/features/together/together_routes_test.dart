import 'dart:io';

import 'package:attune/app/routing/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

/// /together is the hub's home; /timeline stays as an alias for old links
/// and notifications, building the same screen (plan ruling R7).
void main() {
  test('route names', () {
    expect(RouteNames.together, '/together');
    expect(RouteNames.timeline, '/timeline');
  });

  test('both paths build the Together screen', () {
    final src = File('lib/app/routing/app_router.dart').readAsStringSync();
    for (final name in ["name: 'together'", "name: 'timeline'"]) {
      final at = src.indexOf(name);
      expect(at, isNot(-1), reason: name);
      expect(
        src.substring(at, src.indexOf('),', at)),
        contains('const TogetherScreen('),
        reason: name,
      );
    }
  });
}
