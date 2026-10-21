import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Reports its child's laid-out [Size] whenever it changes.
///
/// Delivered in a post-frame callback so the receiver can call setState
/// (changing layout during layout is forbidden); the dependent widget
/// therefore follows one frame behind, which is invisible for the chat's
/// composer overlays and far better than guessing their height.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({
    super.key,
    required this.onChange,
    required Widget super.child,
  });

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMeasureSize).onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (_reported == size) return;
    _reported = size;
    final reported = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) onChange(reported);
    });
  }
}
