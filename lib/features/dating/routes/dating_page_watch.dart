// Spec 2 W5b (§3.4: the other person's photos are "cleared when Dating is
// left"; Task 6 fix round 1, I-1): every Dating page is counted while it
// is open, and when the last one closes the photos leave memory. A go()
// from one Dating page to another never reaches zero: the new page mounts
// in the build phase, the old one is disposed after it (finalizeTree), so
// a page that replaces another keeps the photos (tested). Quick exit and
// sign-out clear them too (the device wipe registry).
//
// Spec 2 W8a (§6.7; W6 final carry: the quick-exit decoy's transition
// showed about 300 ms of Dating): every page shows nothing once quick exit
// or sign-out has run (DatingSurface), until every Dating page is gone.
// W8a Task 2 (§6.7; F-4): while any Dating page is open the screen is
// protected (FLAG_SECURE on Android) and pages blur while iOS says the
// screen is captured (DatingDiscretion). A stricter reading of "a Dating
// route on top": a page pushed over a Dating page (the PIN setup) is
// protected too.
// Spec 2 W8 final client fix (I-1): the first page opened says so
// ([DatingPageWatch.firstOpened]): the device check starts there.
import 'dart:async';

import 'package:attune/features/dating/device/dating_discretion.dart';
import 'package:attune/features/dating/device/dating_surface.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:flutter/widgets.dart';

class DatingPageWatch extends StatefulWidget {
  const DatingPageWatch({super.key, required this.child});

  final Widget child;

  static int _open = 0;

  /// The Dating pages open now (tests).
  @visibleForTesting
  static int get open => _open;

  /// W8a fix round 1: whether any Dating page is open (DatingSurfaceGuard).
  static bool get anyOpen => _open > 0;

  /// Final client fix (I-1): moves each time a Dating page opens with none
  /// open before (the device check listens).
  static final firstOpened = ValueNotifier<int>(0);

  @override
  State<DatingPageWatch> createState() => _DatingPageWatchState();
}

class _DatingPageWatchState extends State<DatingPageWatch> {
  @override
  void initState() {
    super.initState();
    // W8a: a page opened after every Dating page is gone shows again.
    if (DatingPageWatch._open <= 0) {
      DatingSurface.reset();
      // W8a Task 2: the first page turns the protection on.
      unawaited(DatingDiscretion.setSecure(true));
      // Final client fix (I-1): and starts the device check.
      DatingPageWatch.firstOpened.value++;
    }
    DatingPageWatch._open++;
  }

  @override
  void dispose() {
    DatingPageWatch._open--;
    if (DatingPageWatch._open <= 0) {
      DatingPageWatch._open = 0;
      DatingPhotoMemory.clearForLeave();
      DatingSurface.reset();
      // W8a Task 2: the last page turns it off.
      unawaited(DatingDiscretion.setSecure(false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: DatingSurface.hidden,
    child: widget.child,
    builder:
        (context, hidden, child) =>
            hidden
                ? const DatingBlankPage()
                : DatingCaptureCover(child: child!),
  );
}
