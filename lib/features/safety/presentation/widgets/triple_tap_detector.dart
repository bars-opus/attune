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
              child: GestureDetector(
                onTap: () => _handleTap(context),
                behavior: HitTestBehavior.opaque,
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
