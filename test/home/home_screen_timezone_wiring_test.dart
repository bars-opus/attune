// test/home/home_screen_timezone_wiring_test.dart
// Spec 1b: quiet hours follow the phone's zone, reported at the three
// moments HomeScreen already re-syncs (first frame, sign-in, resume). A
// source scan, the repo's pattern for wiring that a widget test cannot
// reach without the whole auth stack (see together_routes_test.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'HomeScreen reports the time zone at first frame, sign-in and resume',
    () {
      final src = File('lib/home/home_screen.dart').readAsStringSync();
      expect(
        src,
        contains(
          "import 'package:attune/core/services/user_timezone_reporter.dart';",
        ),
      );
      expect(src, contains('void _reportTimezone()'));
      expect(RegExp(r'_reportTimezone\(\);').allMatches(src).length, 3);
      final resume = src.substring(
        src.indexOf('void didChangeAppLifecycleState'),
      );
      expect(
        resume.substring(0, resume.indexOf('\n  }')),
        contains('_reportTimezone();'),
      );
    },
  );
}
