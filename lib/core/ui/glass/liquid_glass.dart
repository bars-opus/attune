// Liquid glass: the one surface every glass control is built from.
//
// Layers, back to front:
//   1. a soft shadow under the shape (outside the clip);
//   2. the backdrop, blurred, saturated and, on Impeller, bent at the rim
//      by shaders/liquid_glass.frag (_GlassBackdrop);
//   3. a tint, so text on the glass stays readable;
//   4. the rim: a bright specular edge where the light falls (top left)
//      fading round to a dim edge, plus a faint inner sheen;
//   5. the child.
//
// Without Impeller (tests, older Android GPUs) the bending is skipped and the
// rest still draws. With the system's high-contrast setting the glass turns
// into a plain opaque surface: nothing shows through it.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// How much of the background a glass surface lets through.
enum GlassVariant {
  /// Mostly clear: a light blur, a thin tint (floating buttons over content).
  clear,

  /// The default: frosted enough for text (bars, capsules).
  regular,

  /// Dense: for menus and sheets that hold a lot of text.
  thick,
}

/// The values a [GlassVariant] stands for, light or dark.
@immutable
class GlassLook {
  const GlassLook({
    required this.blur,
    required this.saturation,
    required this.tint,
    required this.rimLight,
    required this.rimShade,
    required this.shadow,
  });

  final double blur;
  final double saturation;
  final Color tint;
  final Color rimLight;
  final Color rimShade;
  final Color shadow;

  static GlassLook of(BuildContext context, GlassVariant variant) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (variant) {
      case GlassVariant.clear:
        return GlassLook(
          blur: 1.5,
          saturation: 1.4,
          tint: dark ? const Color(0x2E1C1C1E) : const Color(0x33FFFFFF),
          rimLight: dark ? const Color(0x59FFFFFF) : const Color(0xCCFFFFFF),
          rimShade: dark ? const Color(0x14FFFFFF) : const Color(0x1A000000),
          shadow: dark ? const Color(0x40000000) : const Color(0x1F000000),
        );
      case GlassVariant.regular:
        return GlassLook(
          blur: 5,
          saturation: 1.6,
          tint: dark ? const Color(0x661C1C1E) : const Color(0x73F8F8FA),
          rimLight: dark ? const Color(0x4DFFFFFF) : const Color(0xE6FFFFFF),
          rimShade: dark ? const Color(0x14FFFFFF) : const Color(0x14000000),
          shadow: dark ? const Color(0x4D000000) : const Color(0x24000000),
        );
      case GlassVariant.thick:
        return GlassLook(
          // Kept low: a heavier blur reaches the shader at low resolution
          // and its bent rim turns blocky (seen on the simulator).
          blur: 6,
          saturation: 1.8,
          tint: dark ? const Color(0xC71C1C1E) : const Color(0xD1F7F7F9),
          rimLight: dark ? const Color(0x40FFFFFF) : const Color(0xF2FFFFFF),
          rimShade: dark ? const Color(0x14FFFFFF) : const Color(0x12000000),
          shadow: dark ? const Color(0x66000000) : const Color(0x2E000000),
        );
    }
  }
}

/// Loads the refraction shader once, on Impeller only.
class LiquidGlassShader {
  LiquidGlassShader._();

  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// The loaded program, or null (not loaded yet, or no Impeller).
  static ui.FragmentProgram? get program => _program;

  /// Whether this renderer can bend the backdrop at all.
  static bool get supported => ui.ImageFilter.isShaderFilterSupported;

  /// Starts loading (once); completes when loaded or when it failed.
  static Future<void> ensureLoaded() {
    if (!supported) return Future<void>.value();
    return _loading ??= ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag')
        .then<void>((p) => _program = p)
        .catchError((Object _) {});
  }

  /// Development only: paint the shader's texture coordinates.
  static bool debugCoordinates = false;
}

/// A glass surface in the shape of [borderRadius] (a capsule by default).
class LiquidGlass extends StatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.variant = GlassVariant.regular,
    this.borderRadius,
    this.tint,
    this.refract = true,
    this.refraction = 11,
    this.shadow = true,
    this.padding,
    this.followRoute = true,
  });

  final Widget child;
  final GlassVariant variant;

  /// The shape; null is a capsule (half the shorter side).
  final BorderRadius? borderRadius;

  /// Mixed over the variant's tint (for a coloured, selected or primary glass).
  final Color? tint;

  /// Bend the backdrop at the rim. Use it for glass that stays where it is
  /// on screen (bars, floating buttons, menus): glass inside a scrolling list
  /// moves without repainting, and its bend would lag behind it.
  final bool refract;

  /// The largest bend at the rim, in logical pixels.
  final double refraction;

  final bool shadow;
  final EdgeInsetsGeometry? padding;

  /// Drop the bend while this glass's page is sliding in or out. Glass that
  /// repaints every frame of its own animation (the menu) turns this off.
  final bool followRoute;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  ModalRoute<Object?>? _route;

  // True while this glass's page slides in or out: the page moves without
  // repainting the glass, so the bend would lag behind it (final review I1).
  bool _routeMoving = false;

  @override
  void initState() {
    super.initState();
    if (widget.refract && LiquidGlassShader.program == null && LiquidGlassShader.supported) {
      LiquidGlassShader.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = widget.followRoute ? ModalRoute.of(context) : null;
    if (route == _route) return;
    _route?.animation?.removeStatusListener(_onRouteStatus);
    _route?.secondaryAnimation?.removeStatusListener(_onRouteStatus);
    _route = route;
    _route?.animation?.addStatusListener(_onRouteStatus);
    _route?.secondaryAnimation?.addStatusListener(_onRouteStatus);
    _routeMoving = _isMoving();
  }

  bool _isMoving() {
    bool moving(Animation<double>? a) => a != null && (a.status == AnimationStatus.forward || a.status == AnimationStatus.reverse);
    return moving(_route?.animation) || moving(_route?.secondaryAnimation);
  }

  void _onRouteStatus(AnimationStatus _) {
    final moving = _isMoving();
    if (moving != _routeMoving && mounted) setState(() => _routeMoving = moving);
  }

  @override
  void dispose() {
    _route?.animation?.removeStatusListener(_onRouteStatus);
    _route?.secondaryAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = GlassLook.of(context, widget.variant);
    final highContrast = MediaQuery.highContrastOf(context);
    final scheme = Theme.of(context).colorScheme;
    // A null radius is a capsule: RRect clamps a very large radius.
    final radius = widget.borderRadius ?? const BorderRadius.all(Radius.circular(999));

    Widget content = widget.padding == null
        ? widget.child
        : Padding(padding: widget.padding!, child: widget.child);

    if (highContrast) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: widget.tint ?? scheme.surfaceContainerHighest,
          borderRadius: radius,
          border: Border.all(color: scheme.outline, width: 1),
        ),
        child: content,
      );
    }

    final tint = widget.tint == null ? look.tint : Color.alphaBlend(widget.tint!, look.tint);

    content = CustomPaint(
      foregroundPainter: _RimPainter(radius: radius, light: look.rimLight, shade: look.rimShade),
      child: DecoratedBox(
        decoration: BoxDecoration(color: tint, borderRadius: radius),
        child: content,
      ),
    );

    final glass = _GlassBackdrop(
      borderRadius: radius,
      blur: look.blur,
      saturation: look.saturation,
      refraction: widget.refract && !_routeMoving ? widget.refraction : 0,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shaderReady: LiquidGlassShader.program != null,
      child: content,
    );

    if (!widget.shadow) return glass;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(color: look.shadow, blurRadius: 24, spreadRadius: -4, offset: const Offset(0, 8)),
          BoxShadow(
            color: look.shadow.withValues(alpha: look.shadow.a * 0.5),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: glass,
    );
  }
}

/// The specular rim: bright where the light falls, dim on the far side.
class _RimPainter extends CustomPainter {
  _RimPainter({required this.radius, required this.light, required this.shade});

  final BorderRadius radius;
  final Color light;
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(0.5);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [light, shade, shade, light.withValues(alpha: light.a * 0.55)],
        stops: const [0.0, 0.35, 0.7, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, rim);

    // A soft sheen along the top inside edge.
    final sheenRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.5);
    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [light.withValues(alpha: light.a * 0.22), light.withValues(alpha: 0)],
      ).createShader(sheenRect);
    canvas.save();
    canvas.clipRRect(radius.toRRect(rect));
    canvas.drawRect(sheenRect, sheen);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.light != light || old.shade != shade;
}

/// Clips to the shape and filters what is behind it.
class _GlassBackdrop extends SingleChildRenderObjectWidget {
  const _GlassBackdrop({
    required this.borderRadius,
    required this.blur,
    required this.saturation,
    required this.refraction,
    required this.devicePixelRatio,
    required this.shaderReady,
    super.child,
  });

  final BorderRadius borderRadius;
  final double blur;
  final double saturation;
  final double refraction;
  final double devicePixelRatio;

  /// Changes once, when the shader has loaded: the glass repaints with it.
  final bool shaderReady;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGlassBackdrop(
        borderRadius: borderRadius,
        blur: blur,
        saturation: saturation,
        refraction: refraction,
        devicePixelRatio: devicePixelRatio,
        shaderReady: shaderReady,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderGlassBackdrop renderObject) {
    renderObject
      ..borderRadius = borderRadius
      ..blur = blur
      ..saturation = saturation
      ..refraction = refraction
      ..devicePixelRatio = devicePixelRatio
      ..shaderReady = shaderReady;
  }
}

class _RenderGlassBackdrop extends RenderProxyBox {
  _RenderGlassBackdrop({
    required BorderRadius borderRadius,
    required double blur,
    required double saturation,
    required double refraction,
    required double devicePixelRatio,
    required bool shaderReady,
  })  : _shaderReady = shaderReady,
        _borderRadius = borderRadius,
        _blur = blur,
        _saturation = saturation,
        _refraction = refraction,
        _devicePixelRatio = devicePixelRatio;

  BorderRadius _borderRadius;
  set borderRadius(BorderRadius v) {
    if (v == _borderRadius) return;
    _borderRadius = v;
    markNeedsPaint();
  }

  double _blur;
  set blur(double v) {
    if (v == _blur) return;
    _blur = v;
    markNeedsPaint();
  }

  double _saturation;
  set saturation(double v) {
    if (v == _saturation) return;
    _saturation = v;
    markNeedsPaint();
  }

  double _refraction;
  set refraction(double v) {
    if (v == _refraction) return;
    _refraction = v;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double v) {
    if (v == _devicePixelRatio) return;
    _devicePixelRatio = v;
    markNeedsPaint();
  }

  bool _shaderReady;
  set shaderReady(bool v) {
    if (v == _shaderReady) return;
    _shaderReady = v;
    markNeedsPaint();
  }

  ui.FragmentShader? _shader;
  final LayerHandle<ClipRRectLayer> _clip = LayerHandle<ClipRRectLayer>();
  final LayerHandle<BackdropFilterLayer> _backdrop = LayerHandle<BackdropFilterLayer>();

  @override
  bool get alwaysNeedsCompositing => true;

  static List<double> _saturationMatrix(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final i = 1 - s;
    return <double>[
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0, //
      r * i, g * i, b * i + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  ui.ImageFilter _filter() {
    ui.ImageFilter filter = ui.ImageFilter.blur(
      sigmaX: _blur,
      sigmaY: _blur,
      tileMode: TileMode.mirror,
    );
    if (_saturation != 1) {
      filter = ui.ImageFilter.compose(
        outer: ui.ColorFilter.matrix(_saturationMatrix(_saturation)),
        inner: filter,
      );
    }
    final program = LiquidGlassShader.program;
    if (_refraction > 0 && program != null && LiquidGlassShader.supported) {
      final shader = _shader ??= program.fragmentShader();
      final toScreen = getTransformTo(null);
      final rect = MatrixUtils.transformRect(toScreen, Offset.zero & size);
      final scale = size.width > 0 ? rect.width / size.width : 1.0;
      final px = _devicePixelRatio;
      final radius = _borderRadius.topLeft.x
          .clamp(0.0, size.shortestSide / 2) * scale * px;
      shader
        ..setFloat(0, 0) // uSize: the engine's
        ..setFloat(1, 0)
        ..setFloat(2, rect.left * px)
        ..setFloat(3, rect.top * px)
        ..setFloat(4, rect.width * px)
        ..setFloat(5, rect.height * px)
        ..setFloat(6, radius)
        ..setFloat(7, _refraction * scale * px)
        ..setFloat(8, (size.shortestSide * 0.42).clamp(8.0, 40.0) * scale * px)
        ..setFloat(9, 0.6)
        ..setFloat(10, LiquidGlassShader.debugCoordinates ? 1 : 0);
      // The bend goes last: composed the other way round (bend, then
      // frost), Impeller dropped the shader for most glass on screen.
      filter = ui.ImageFilter.compose(outer: ui.ImageFilter.shader(shader), inner: filter);
    }
    return filter;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final rrect = _borderRadius.toRRect(bounds);
    _clip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      bounds,
      rrect,
      (context, offset) {
        final layer = _backdrop.layer ?? BackdropFilterLayer();
        // A shader filter equals the last one whenever it wraps the same
        // shader, so the layer would keep the old filter and its old
        // uniforms (final review C1): clear it so the new one is taken.
        layer.filter = null;
        layer.filter = _filter();
        _backdrop.layer = layer;
        context.pushLayer(layer, super.paint, offset);
      },
      oldLayer: _clip.layer,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    _backdrop.layer = null;
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }
}
