// lib/features/safety/presentation/widgets/triple_tap_detector.dart

import 'dart:async';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:flutter/material.dart';

class TripleTapDetector extends StatefulWidget {
  final Widget child;

  const TripleTapDetector({super.key, required this.child});

  @override
  State<TripleTapDetector> createState() => _TripleTapDetectorState();
}

class _TripleTapDetectorState extends State<TripleTapDetector> {
  int _tapCount = 0;
  Timer? _tapTimer;

  void _handleTap(BuildContext context) {
    _tapCount++;

    // Reset after 2 seconds of inactivity
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(seconds: 2), () {
      _tapCount = 0;
    });

    if (_tapCount >= 3) {
      _tapCount = 0;
      _tapTimer?.cancel();
      QuickExitService.execute(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: topInset + 8,
          left: 0,
          right: 0,
          child: Center(
            child: Semantics(
              label: 'Quick exit gesture area',
              button: true,
              // Listener, NOT GestureDetector. A GestureDetector here — even
              // with HitTestBehavior.translucent — enters the tap-gesture
              // ARENA (not just the hit test), and real, unrelated
              // GestureDetectors underneath it (e.g. a header logo opening a
              // bottom sheet) can lose that arena to it, or get
              // double-counted on every tap. That produced two real bugs:
              // taps on the Chat tab's logo either did nothing, or silently
              // fed this counter and fired quick-exit on what looked like a
              // single tap. Listener only OBSERVES raw pointer-down events —
              // it never joins the arena and never consumes the gesture —
              // so it can coexist with any GestureDetector underneath
              // without blocking or double-counting its taps.
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _handleTap(context),
                child: const SizedBox(width: 72, height: 72),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }
}
