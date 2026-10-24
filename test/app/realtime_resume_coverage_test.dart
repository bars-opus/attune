// Stories Wave 3: the shell keeps the app mounted behind the privacy cover
// and the lock's return check, so an autoDispose provider holding a
// Realtime channel is no longer re-created (and re-fetched) on every
// return. These signal providers must keep their own resume emit: while
// backgrounded the socket is dropped, and a change made in that gap is
// never replayed. (Stories: story_read_repository_test pins its own.)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _provider(String path, String name) {
  final src = File(path).readAsStringSync();
  final start = src.indexOf('final $name =');
  expect(start, greaterThan(-1), reason: '$name in $path');
  final end = src.indexOf('\nfinal ', start + 1); // the next provider
  return src.substring(start, end < 0 ? src.length : end);
}

void main() {
  test('the Together signal emits on resume and on every (re)subscribe', () {
    final body = _provider(
      'lib/features/timeline/presentation/providers/timeline_providers.dart',
      'togetherChangeSignalProvider',
    );
    expect(body, matches(RegExp(r'AppLifecycleListener\(\s*onResume:\s*emit')));
    expect(
      body,
      matches(
        RegExp(
          r'status\s*==\s*RealtimeSubscribeStatus\.subscribed\s*\)\s*emit\(\)',
        ),
      ),
    );
  });

  test('the Planning signal emits on resume and on every (re)subscribe', () {
    final body = _provider(
      'lib/features/planning/presentation/planning_providers.dart',
      'planningChangeSignalProvider',
    );
    expect(body, matches(RegExp(r'AppLifecycleListener\(\s*onResume:')));
    expect(
      body,
      matches(RegExp(r'status\s*==\s*RealtimeSubscribeStatus\.subscribed')),
    );
  });
}
