// Spec 2 W8a (§6.7; W6 final carry: quick exit's decoy slid in over about
// 300 ms of Dating): once quick exit or sign-out runs, every Dating page
// shows a blank page of the theme's background, in the same frame the
// decoy starts. A Dating page opened after every one of them is gone shows
// again (DatingPageWatch). Memory only.
//
// Fix round 1 (I-1, M-3): every Dating sheet, dialog and picker
// (DatingSheetTracker) and Me's Dating section are blank in that frame too
// (DatingSurfaceGuard), the sheets with what was typed in them.
//
// Task 2 fix round 1 (I-2): a sheet, dialog or picker also blurs while iOS
// says the screen is captured (DatingCaptureCover), keeping its state.
import 'package:attune/features/dating/device/dating_discretion.dart';
import 'package:attune/features/dating/routes/dating_page_watch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

abstract final class DatingSurface {
  /// True from quick exit or sign-out until every Dating page is gone.
  static final hidden = ValueNotifier<bool>(false);

  static int _hides = 0;
  static Stopwatch? _since;

  /// Round 2 (Re-1-M1): how long after a hide the Dating unlock does
  /// nothing. Quick exit's decoy comes in over about 300 ms and Attune
  /// leaves after it; 2 s is the device wipe's own longest entry.
  static const quiet = Duration(seconds: 2);

  /// Round 4 (Re-2-M1): the quiet window's stopwatch (tests: the fake
  /// clock's).
  @visibleForTesting
  static Stopwatch Function() stopwatch = Stopwatch.new;

  /// The device wipe entry: synchronous before its first await, so the
  /// pages are blank before the decoy's first frame.
  static Future<void> hide() async {
    _hides++;
    _since = stopwatch()..start();
    hidden.value = true;
  }

  /// Round 2 (Re-1-M1): quick exit or sign-out is under way (hidden, and
  /// less than [quiet] ago). A Safety PIN check that finishes now (Me's
  /// slot) unlocks nothing; one entered later unlocks as before. Round 4
  /// (Re-2-M1): measured on a monotonic stopwatch, so the phone's clock
  /// set back never keeps the unlock off.
  static bool get leaving {
    final since = _since;
    return hidden.value && since != null && since.elapsed < quiet;
  }

  /// Fix round 1: a reset asked for inside a frame (a page or surface
  /// mounting, going, or on top again) lands just after that frame, so no
  /// other widget is marked while the tree is building or locked; a hide
  /// since then wins.
  static void reset() {
    if (!hidden.value) return;
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      final hides = _hides;
      binding.addPostFrameCallback((_) {
        if (hides == _hides) hidden.value = false;
      });
      return;
    }
    hidden.value = false;
  }
}

/// What a Dating page shows once [DatingSurface] is hidden: nothing.
class DatingBlankPage extends StatelessWidget {
  const DatingBlankPage({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const ValueKey('dating_blank_page'),
    color: Theme.of(context).scaffoldBackgroundColor,
    child: const SizedBox.expand(),
  );
}

/// Fix round 1 (I-1, M-3): a Dating surface that isn't a page shows
/// nothing once [DatingSurface] is hidden. A sheet, dialog or picker shows
/// [DatingBlankPage] in place of its content (what was typed goes with
/// it); Me's section ([DatingSurfaceGuard.section]) keeps its place, so
/// nothing under the decoy moves. One opened, or on top again, once every
/// Dating page is gone shows again (quick exit from Me, a sign-out that
/// didn't finish: M-2). One that opens while a Dating page is still open
/// under the decoy (an answer that lands during its transition) stays
/// blank until it goes, even once every page has gone.
class DatingSurfaceGuard extends StatefulWidget {
  const DatingSurfaceGuard({super.key, required this.child}) : keepSize = false;

  const DatingSurfaceGuard.section({super.key, required this.child})
    : keepSize = true;

  final Widget child;
  final bool keepSize;

  @override
  State<DatingSurfaceGuard> createState() => _DatingSurfaceGuardState();
}

class _DatingSurfaceGuardState extends State<DatingSurfaceGuard> {
  bool? _current;

  /// A sheet that opened under the decoy's transition: blank until it goes.
  bool _held = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    final was = _current;
    _current = current;
    // Only a change to on top counts: quick exit pressed here keeps it on
    // top until the decoy's route replaces it, and nothing resets then.
    if (current && was != true && !DatingPageWatch.anyOpen) {
      DatingSurface.reset();
    } else if (was == null && !widget.keepSize && DatingSurface.hidden.value) {
      _held = true;
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: DatingSurface.hidden,
    child: widget.child,
    builder: (context, hidden, child) {
      // Me's section always sits in the Visibility, so its state is kept.
      if (widget.keepSize) {
        return Visibility(
          key: const ValueKey('dating_section_surface'),
          visible: !hidden,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: child!,
        );
      }
      return hidden || _held
          ? const DatingBlankPage()
          : DatingCaptureCover(child: child!);
    },
  );
}
