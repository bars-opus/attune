import 'dart:async';

import 'package:flutter/widgets.dart';

/// One submit at a time on a sign-in step (Spec 1 §2.2). A busy flag only
/// disables a step's buttons on the next frame, and a double tap, or the
/// keyboard's Done and the button together, can both land before then. So
/// a step runs its submit through [submitOnce], which turns any other away
/// until the flow's own work (saving, sending, checking) has finished.
mixin SubmitOnce<T extends StatefulWidget> on State<T> {
  bool _submitting = false;
  Object? _runningTag;

  /// A submit started on this step is still running.
  bool get submitting => _submitting;

  /// The `tag` the running submit was started with, so progress shows on
  /// the button that was pressed (review B4 I-3); null when none runs.
  Object? get runningTag => _runningTag;

  /// Runs [submit] unless one is already running, and stays [submitting]
  /// until it has finished. A throw is reported to [FlutterError] (never
  /// lost as an uncaught error) and the step is free again.
  void submitOnce(FutureOr<void> Function() submit, {Object? tag}) {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _runningTag = tag;
    });
    _run(submit);
  }

  Future<void> _run(FutureOr<void> Function() submit) async {
    try {
      await submit();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'sign-up',
          context: ErrorDescription('while running a sign-in step action'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _runningTag = null;
        });
        didFinishSubmit();
      }
    }
  }

  /// Called once a submit has finished and the step is free again.
  @protected
  void didFinishSubmit() {}
}
