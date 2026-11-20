// Spec 2 W5b (§3.4: the other person's photos are "cleared when Dating is
// left"; Task 6 fix round 1, I-1): every Dating page is counted while it
// is open, and when the last one closes the photos leave memory. A go()
// from one Dating page to another never reaches zero: the new page mounts
// in the build phase, the old one is disposed after it (finalizeTree), so
// a page that replaces another keeps the photos (tested). Quick exit and
// sign-out clear them too (the device wipe registry).
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:flutter/widgets.dart';

class DatingPageWatch extends StatefulWidget {
  const DatingPageWatch({super.key, required this.child});

  final Widget child;

  static int _open = 0;

  /// The Dating pages open now (tests).
  @visibleForTesting
  static int get open => _open;

  @override
  State<DatingPageWatch> createState() => _DatingPageWatchState();
}

class _DatingPageWatchState extends State<DatingPageWatch> {
  @override
  void initState() {
    super.initState();
    DatingPageWatch._open++;
  }

  @override
  void dispose() {
    DatingPageWatch._open--;
    if (DatingPageWatch._open <= 0) {
      DatingPageWatch._open = 0;
      DatingPhotoMemory.clearForLeave();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
