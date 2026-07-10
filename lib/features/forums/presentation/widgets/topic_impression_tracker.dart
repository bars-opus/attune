// lib/features/forums/presentation/widgets/topic_impression_tracker.dart

import 'dart:async';

import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A widget that tracks when a topic card becomes visible on screen
/// for >= 2 seconds and records an impression.
class TopicImpressionTracker extends ConsumerStatefulWidget {
  final String topicId;
  final Widget child;

  const TopicImpressionTracker({
    super.key,
    required this.topicId,
    required this.child,
  });

  @override
  ConsumerState<TopicImpressionTracker> createState() => _TopicImpressionTrackerState();
}

class _TopicImpressionTrackerState extends ConsumerState<TopicImpressionTracker> {
  final GlobalKey _key = GlobalKey();
  bool _hasRecorded = false;
  Timer? _visibilityTimer;

  @override
  void dispose() {
    _visibilityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WidgetsBindingListener(
      onWidgetsBinding: () {
        _checkVisibility();
      },
      child: Container(
        key: _key,
        child: widget.child,
      ),
    );
  }

  void _checkVisibility() {
    if (_hasRecorded) return;

    final RenderBox? renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenHeight = MediaQuery.of(context).size.height;

    // Check if widget is visible on screen
    final isVisible = position.dy < screenHeight && position.dy + size.height > 0;

    if (isVisible) {
      _visibilityTimer ??= Timer(const Duration(seconds: 2), () {
        if (!_hasRecorded && mounted) {
          _recordImpression();
        }
      });
    } else {
      _visibilityTimer?.cancel();
      _visibilityTimer = null;
    }
  }

  void _recordImpression() async {
    if (_hasRecorded) return;
    _hasRecorded = true;
    _visibilityTimer?.cancel();

    try {
      await ref.read(recordTopicImpressionProvider(widget.topicId).future);
    } catch (e) {
      // Silent fail - impression recording is not critical
      debugPrint('Failed to record impression: $e');
    }
  }
}

// Helper widget to listen to WidgetsBinding
class WidgetsBindingListener extends StatefulWidget {
  final VoidCallback onWidgetsBinding;
  final Widget child;

  const WidgetsBindingListener({
    super.key,
    required this.onWidgetsBinding,
    required this.child,
  });

  @override
  State<WidgetsBindingListener> createState() => _WidgetsBindingListenerState();
}

class _WidgetsBindingListenerState extends State<WidgetsBindingListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    widget.onWidgetsBinding();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.onWidgetsBinding();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
