// The glass menu: it grows out of the button that opened it, the way iOS 26
// menus do. The glass starts as the button's own shape, swells to the
// menu's size (sideways a little ahead of downwards, so it pours rather
// than scales), overshoots a touch and settles; the rows fade in once
// there is room for them. Closing runs it back into the button, faster.
import 'dart:math' as math;

import 'package:attune/core/ui/glass/liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One row of a glass menu.
@immutable
class GlassMenuItem<T> {
  const GlassMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Shown in the error colour (Delete, Remove, Leave).
  final bool destructive;
  final bool enabled;
}

/// Opens a glass menu grown from [anchorRect] (global coordinates); returns
/// the chosen item's value, or null when dismissed.
Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required Rect anchorRect,
  required List<GlassMenuItem<T>> items,
  double width = 248,
}) {
  HapticFeedback.selectionClick();
  return Navigator.of(context).push<T>(
    _GlassMenuRoute<T>(
      anchorRect: anchorRect,
      items: items,
      width: width,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context).context,
      ),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// A button that opens a glass menu (a stand-in for PopupMenuButton).
class GlassMenuButton<T> extends StatelessWidget {
  const GlassMenuButton({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    this.icon,
    this.tooltip,
    this.child,
    this.enabled = true,
  });

  final List<GlassMenuItem<T>> Function(BuildContext context) itemBuilder;
  final ValueChanged<T> onSelected;
  final Widget? icon;
  final String? tooltip;

  /// The anchor, instead of the default icon button.
  final Widget? child;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final items = itemBuilder(context);
    // As PopupMenuButton: no rows, no menu.
    if (items.isEmpty) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final value = await showGlassMenu<T>(context: context, anchorRect: rect, items: items);
    // The button may be gone by the time the menu closes (final review I2).
    if (value != null && context.mounted) onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    final label = tooltip ?? MaterialLocalizations.of(context).showMenuTooltip;
    return Builder(
      builder: (context) {
        if (child != null) {
          return Semantics(
            button: true,
            enabled: enabled,
            label: label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? () => _open(context) : null,
              child: child,
            ),
          );
        }
        // As PopupMenuButton: the platform's "more" icon, in the colour
        // around it (an app bar's, or the surrounding icon theme's).
        return IconButton(
          tooltip: label,
          icon: icon ?? Icon(Icons.adaptive.more),
          color: IconTheme.of(context).color,
          onPressed: enabled ? () => _open(context) : null,
        );
      },
    );
  }
}

class _GlassMenuRoute<T> extends PopupRoute<T> {
  _GlassMenuRoute({
    required this.anchorRect,
    required this.items,
    required this.width,
    required this.capturedThemes,
    required this.barrierLabel,
  });

  final Rect anchorRect;
  final List<GlassMenuItem<T>> items;
  final double width;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => const Color(0x14000000);

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 460);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return capturedThemes.wrap(
      _GlassMenuBody<T>(
        animation: animation,
        anchorRect: anchorRect,
        items: items,
        width: width,
      ),
    );
  }
}

/// A gentle overshoot, like a drop settling.
const Curve _pour = Cubic(0.22, 1.28, 0.36, 1);

class _GlassMenuBody<T> extends StatelessWidget {
  const _GlassMenuBody({
    required this.animation,
    required this.anchorRect,
    required this.items,
    required this.width,
  });

  final Animation<double> animation;
  final Rect anchorRect;
  final List<GlassMenuItem<T>> items;
  final double width;

  static const double _rowHeight = 48;
  static const double _pad = 6;
  static const double _radius = 22;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final textScale = media.textScaler.scale(16) / 16;
    final rowHeight = _rowHeight * math.max(1.0, textScale);
    final screen = media.size;
    final safe = media.padding;
    final menuWidth = math.min(width * math.max(1.0, textScale * 0.9), screen.width - 32);
    final menuHeight = math.min(
      items.length * rowHeight + _pad * 2,
      screen.height - safe.top - safe.bottom - 32,
    );

    // Hang the menu from the side of the button nearer the screen's edge.
    final openRight = anchorRect.center.dx < screen.width / 2;
    final left = (openRight ? anchorRect.left : anchorRect.right - menuWidth)
        .clamp(16.0, screen.width - menuWidth - 16);
    final roomBelow = screen.height - safe.bottom - anchorRect.bottom - 8;
    final below = roomBelow >= menuHeight || roomBelow >= anchorRect.top - safe.top;
    final top = below
        ? math.min(anchorRect.bottom + 8, screen.height - safe.bottom - menuHeight - 8)
        : math.max(anchorRect.top - 8 - menuHeight, safe.top + 8);
    final target = Rect.fromLTWH(left, top, menuWidth, menuHeight);
    final reduceMotion = media.disableAnimations;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final raw = animation.value;
        final forward = animation.status != AnimationStatus.reverse;
        double ease(double begin, double end) {
          final t = ((raw - begin) / (end - begin)).clamp(0.0, 1.0);
          return forward ? _pour.transform(t) : Curves.easeInCubic.transform(t);
        }

        // Sideways a little ahead of downwards: it pours out of the button.
        final tx = reduceMotion ? 1.0 : ease(0.0, 0.78);
        final ty = reduceMotion ? 1.0 : ease(0.08, 1.0);
        final rect = Rect.fromLTRB(
          _lerp(anchorRect.left, target.left, tx),
          _lerp(anchorRect.top, target.top, ty),
          _lerp(anchorRect.right, target.right, tx),
          _lerp(anchorRect.bottom, target.bottom, ty),
        );
        final radius = _lerp(anchorRect.shortestSide / 2, _radius, math.min(tx, ty).clamp(0.0, 1.0));
        final contentOpacity = reduceMotion
            ? raw
            : ((raw - (forward ? 0.32 : 0.0)) / (forward ? 0.5 : 0.6)).clamp(0.0, 1.0);

        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: LiquidGlass(
                variant: GlassVariant.thick,
                borderRadius: BorderRadius.circular(radius),
                refraction: 16,
                // It repaints every frame of its own growth.
                followRoute: false,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: OverflowBox(
                    alignment: below
                        ? (openRight ? Alignment.topLeft : Alignment.topRight)
                        : (openRight ? Alignment.bottomLeft : Alignment.bottomRight),
                    minWidth: target.width,
                    maxWidth: target.width,
                    minHeight: target.height,
                    maxHeight: target.height,
                    child: Opacity(
                      opacity: contentOpacity,
                      child: _MenuRows<T>(items: items, rowHeight: rowHeight),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class _MenuRows<T> extends StatelessWidget {
  const _MenuRows({required this.items, required this.rowHeight});

  final List<GlassMenuItem<T>> items;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // As PopupMenu's: a route of its own to a screen reader (review I4).
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: MaterialLocalizations.of(context).popupMenuLabel,
      child: Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(_GlassMenuBody._pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              _MenuRow<T>(item: item, height: rowHeight, scheme: scheme, theme: theme),
          ],
        ),
      ),
      ),
    );
  }
}

class _MenuRow<T> extends StatelessWidget {
  const _MenuRow({required this.item, required this.height, required this.scheme, required this.theme});

  final GlassMenuItem<T> item;
  final double height;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final base = item.destructive ? scheme.error : scheme.onSurface;
    final fg = item.enabled ? base : base.withValues(alpha: 0.38);
    return Semantics(
      button: true,
      enabled: item.enabled,
      child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: item.enabled
          ? () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(item.value);
            }
          : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: 21, color: fg),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: theme.textTheme.bodyLarge?.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
