import 'dart:async';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Re-runs the provider that owns [_ref] after a delay, but only while
/// Attune's content is on screen (stories Wave 3): a timer that comes due
/// behind the privacy cover or the Safety lock waits for the next return
/// instead of fetching for nobody. One pending timer per provider build,
/// cancelled with the build.
///
/// [onReturn] runs just before a return re-runs the provider, so the
/// provider can tell that build apart (final review M-4).
class StoryVisibleRefresh {
  StoryVisibleRefresh(this._ref, {void Function()? onReturn})
    : _onReturn = onReturn {
    _ref.onDispose(() {
      disposed = true;
      _timer?.cancel();
    });
    _ref.listen<bool>(appContentVisibleProvider, (previous, next) {
      if (next && (_dueWhileHidden || _dueOnReturn) && !disposed) {
        _dueWhileHidden = false;
        _dueOnReturn = false;
        _onReturn?.call();
        _ref.invalidateSelf();
      }
    });
  }

  final Ref _ref;
  final void Function()? _onReturn;
  Timer? _timer;
  bool _dueWhileHidden = false;
  bool _dueOnReturn = false;

  /// Re-runs the provider once, the next time Attune comes back on screen
  /// (not visible -> visible), with no timer: for work that has spent its
  /// automatic retries (final review I-1).
  void onNextReturn() {
    if (!disposed) _dueOnReturn = true;
  }

  /// True once this build was replaced or disposed. Work that finishes
  /// after that must schedule nothing and record nothing.
  bool disposed = false;

  void after(Duration delay) {
    if (disposed) return;
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (disposed) return;
      if (_ref.read(appContentVisibleProvider)) {
        _ref.invalidateSelf();
      } else {
        _dueWhileHidden = true;
      }
    });
  }
}
