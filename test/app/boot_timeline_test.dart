// Spec 1 W10b (§3.14): the startup line names each step's own time and the
// total to the first frame, and main() marks every awaited step before
// runApp.
import 'dart:async';
import 'dart:io';

import 'package:attune/app/boot_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stopwatch the test moves by hand.
class _HandStopwatch implements Stopwatch {
  int ms = 0;

  @override
  int get elapsedMilliseconds => ms;

  @override
  void start() {}

  @override
  void reset() => ms = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('each step is its own duration; the first frame is the total', () {
    final clock = _HandStopwatch();
    final timeline = BootTimeline(clock: clock)..start();
    clock.ms = 40;
    timeline.mark('supabase');
    clock.ms = 52;
    timeline.mark('chat cache');
    clock.ms = 352;
    timeline.mark('first frame');
    expect(
      timeline.summary(),
      '[startup] supabase 40 ms, chat cache 12 ms, first frame 352 ms',
    );
  });

  test('the line is printed once the first frame is drawn', () async {
    final lines = <String>[];
    final frame = Completer<void>();
    final timeline = BootTimeline(clock: _HandStopwatch())..start();
    final done = timeline.reportFirstFrame(
      firstFrame: frame.future,
      log: lines.add,
    );
    await Future<void>.delayed(Duration.zero);
    expect(lines, isEmpty, reason: 'not before the frame');
    frame.complete();
    await done;
    expect(lines, ['[startup] first frame 0 ms']);
  });

  test('main() marks every awaited step before runApp', () {
    final main = File('lib/main.dart').readAsStringSync();
    final body = main.substring(
      main.indexOf('Future<void> main() async {'),
      main.indexOf('  runApp('),
    );
    expect(body, contains('bootTimeline.start();'));
    for (final step in [
      "bootTimeline.mark('supabase');",
      "bootTimeline.mark('chat cache');",
      "bootTimeline.mark('prefs');",
      "bootTimeline.mark('age block');",
      "bootTimeline.mark('lock seed');",
    ]) {
      expect(body, contains(step));
    }
    expect(main, contains('unawaited(bootTimeline.reportFirstFrame());'));
  });
}
