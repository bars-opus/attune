import 'package:flutter/widgets.dart';

/// How long each step before the first frame took (Spec 1 §3.14, W10b).
///
/// main() marks each awaited step; once the first frame is drawn one line
/// is printed, `[startup] supabase 41 ms, chat cache 12 ms, ... first frame
/// 380 ms`, so a slow cold start (airplane mode, an expired session) shows
/// which step held the splash. Device-side, the owner reads it next to
/// `flutter run --profile --trace-startup`. Nothing is stored or sent.
class BootTimeline {
  BootTimeline({Stopwatch? clock}) : _clock = clock ?? Stopwatch();

  final Stopwatch _clock;
  final _marks = <(String, int)>[];

  /// Starts the clock (first thing in main()).
  void start() =>
      _clock
        ..reset()
        ..start();

  /// Records that [step] has finished.
  void mark(String step) => _marks.add((step, _clock.elapsedMilliseconds));

  /// Each step's own duration, then the total to the first frame.
  String summary() {
    final parts = <String>[];
    var previous = 0;
    for (final (step, at) in _marks) {
      parts.add(
        step == 'first frame' ? '$step $at ms' : '$step ${at - previous} ms',
      );
      previous = at;
    }
    return '[startup] ${parts.join(', ')}';
  }

  /// Prints [summary] once the first frame has been drawn ([firstFrame]:
  /// the binding's, unless a test passes its own).
  Future<void> reportFirstFrame({
    Future<void>? firstFrame,
    void Function(String line)? log,
  }) async {
    await (firstFrame ?? WidgetsBinding.instance.waitUntilFirstFrameRasterized);
    mark('first frame');
    (log ?? debugPrint)(summary());
  }
}

/// The app's one timeline.
final bootTimeline = BootTimeline();
