import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A Together event alarm opens Together, never the generic home fallback.
void main() {
  test("a 'together_event' tap is routed, not left to the default", () {
    final source =
        File(
          'lib/core/notifications/config/notification_config.dart',
        ).readAsStringSync();
    final at = source.indexOf("case 'together_event':");
    expect(at, isNot(-1));
    expect(
      source.substring(at, source.indexOf('return;', at)),
      contains('RouteNames.together'),
    );
  });

  for (final type in [
    'together_proposal',
    'together_proposal_reply',
    'together_handoff',
    'together_handoff_reply',
    'together_daily',
    'together_ritual',
    'together_ritual_reply',
  ]) {
    test("a '$type' tap opens Together", () {
      final source =
          File(
            'lib/core/notifications/config/notification_config.dart',
          ).readAsStringSync();
      final at = source.indexOf("case '$type':");
      expect(at, isNot(-1), reason: type);
      expect(
        source.substring(at, source.indexOf('return;', at)),
        contains('RouteNames.together'),
      );
    });
  }
}
