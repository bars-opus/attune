// The first screen before any account (`/start`, owner 2026-11-26).
// English only for now.
//
// Top: the couple, no words. Their photo arrives as the website's calendar
// of dots: quiet dots fill in, the patterns light up green with a thread
// through each, then every dot opens, from the faces out, into a window
// onto the two of them. A tap on the photo runs it to the end; reduce
// motion shows the end at once.
// Bottom, on a deep green that warms at the foot (as Netflix's dark-to-red):
// "Attune", one line that changes every few seconds, and two buttons. The
// words and buttons are there at once; nobody waits for the scene.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:attune/app/documentations/user_manual/widgets/all_manual_widget.dart';
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/core/ui/glass/glass.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
import 'package:flutter/foundation.dart' show ValueListenable, compute;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sensors_plus/sensors_plus.dart';

const _paper = Color(0xFFFBFAF8);
const _quiet = Color(0xFFCFCAC0);

/// Dark ink for the words on the image's light background.
const _ink = Color(0xFF1C1B18);
const _green = Color(0xFF3A7629);

/// The deep greens the words sit on (as Netflix's dark-to-red).
const _deep = Color(0xFF0B1A09);
const _glow = Color(0xFF16310F); // darker (owner 2026-11-26)

/// The website's dark-mode accent: the primary button on the green.
const _leaf = Color(0xFFA8E88C);

/// Where the image sits in the top area of [area] size: its scale and
/// offset. One place, shared by the painter and the foot-colour sampling.
({double scale, double dx, double dy}) _imageLayout(
  Size area,
  double iw,
  double ih,
) {
  // 30% past covering (larger), the faces a little below the middle.
  final s = math.max(area.width / iw, area.height / ih) * 1.3;
  final dw = iw * s, dh = ih * s;
  // May sit below the top (owner 2026-11-26: lower); never leaves a gap
  // at the bottom.
  return (
    scale: s,
    dx: (area.width - dw) / 2,
    dy: math.max(area.height * 0.69 - dh * 0.42, area.height - dh),
  );
}

/// The couple at the top. Trying the illustration (owner 2026-11-26); the
/// photo is 'assets/images/intro_couple.jpg'.
const _coupleImage = 'assets/images/intro_couple_illustration.jpg';

/// How much of the screen the photo takes.
const double _photoShare = 0.75;

/// The scene (dots, patterns, the faces), in seconds. The words and the
/// buttons don't wait for it.
const double _total = 4.4;

/// The lines under the wordmark, in turn.
/// Each one two lines, broken by hand (owner 2026-11-26).
const _lines = [
  'Relationship intelligence\nfor two.',
  'Understand your patterns.\nHeal your cycles.',
  'Grow together,\nor grow wiser alone.',
];

class StartIntroScreen extends ConsumerStatefulWidget {
  const StartIntroScreen({super.key});

  @override
  ConsumerState<StartIntroScreen> createState() => _StartIntroScreenState();
}

class _StartIntroScreenState extends ConsumerState<StartIntroScreen>
    with TickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_total * 1000).round()),
  );
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  ui.Image? _photo;

  /// The photo's own background colour (its top row, averaged): the band
  /// above the photo once it sits lower than the top of the screen.
  Color _backdrop = _paper;

  /// The image's pixels (RGBA), kept to sample the colour of its visible
  /// foot for the area's size.
  ByteData? _pixels;
  Size? _footFor;
  Color _foot = _glow;
  Timer? _ticker;
  int _line = 0;

  // The tilt depth (owner 2026-11-26): the couple, cut out of the cream,
  // floats over it and follows the phone's tilt with a little 3D turn and a
  // sheen; the cream barely moves. Off with reduce motion.
  ui.Image? _figures;
  StreamSubscription<AccelerometerEvent>? _accel;
  Ticker? _tiltTicker;
  ValueListenable<bool>? _tickerMode;
  final ValueNotifier<Offset> _tilt = ValueNotifier(Offset.zero);
  Offset _target = Offset.zero;
  Offset? _rest;
  late final AnimationController _depthIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    _enter.forward();
    _ticker = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (mounted) {
        setState(() => _line = (_line % _lines.length + 1) % _lines.length);
      }
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await rootBundle.load(_coupleImage);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      final backdrop = await _topRowColor(frame.image);
      final pixels = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _photo = frame.image;
        _backdrop = backdrop;
        _pixels = pixels;
        _footFor = null;
      });
      unawaited(_makeFigures(frame.image, pixels, backdrop));
    } catch (_) {
      // No photo: the dots stay dots.
    }
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.value = 1;
    } else {
      _t.forward();
    }
  }

  /// The guides from Settings (signed out: the topics for always-on
  /// features only).
  void _openGuides(BuildContext context) {
    BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      showButtons: false,
      // The app's neutral background (the search field is the lighter
      // surface on it).
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      widget: const Padding(
        padding: EdgeInsets.only(top: 16),
        // Every section starts closed: the headings first.
        child: DocumentationList(),
      ),
    );
  }

  /// The average colour of the image's top row.
  static Future<Color> _topRowColor(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null || image.width == 0) return _paper;
    var r = 0, g = 0, b = 0;
    for (var x = 0; x < image.width; x++) {
      r += data.getUint8(x * 4);
      g += data.getUint8(x * 4 + 1);
      b += data.getUint8(x * 4 + 2);
    }
    final n = image.width;
    return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  }

  /// The average colour of the image's row that shows at the bottom of an
  /// [area]-sized top area, over the columns that show.
  Color _footColor(Size area) {
    final image = _photo, data = _pixels;
    if (image == null || data == null || area.isEmpty) return _glow;
    final iw = image.width, ih = image.height;
    final l = _imageLayout(area, iw.toDouble(), ih.toDouble());
    final y = ((area.height - 1 - l.dy) / l.scale).floor().clamp(0, ih - 1);
    final x0 = (-l.dx / l.scale).floor().clamp(0, iw - 1);
    final x1 = ((area.width - l.dx) / l.scale).ceil().clamp(x0 + 1, iw);
    // The image's own colour at its foot, leaving out its cream (the gap
    // between the shoulders): the green under the image is the clothes'
    // green (owner 2026-11-26). All cream: the plain average.
    final cream = _backdrop;
    final cr = (cream.r * 255).round(),
        cg = (cream.g * 255).round(),
        cb = (cream.b * 255).round();
    var r = 0, g = 0, b = 0, n = 0;
    var ar = 0, ag = 0, ab = 0;
    for (var x = x0; x < x1; x++) {
      final i = (y * iw + x) * 4;
      final pr = data.getUint8(i),
          pg = data.getUint8(i + 1),
          pb = data.getUint8(i + 2);
      ar += pr;
      ag += pg;
      ab += pb;
      final dr = pr - cr, dg = pg - cg, db = pb - cb;
      if (dr * dr + dg * dg + db * db < 40 * 40) continue;
      r += pr;
      g += pg;
      b += pb;
      n++;
    }
    if (n == 0) {
      final all = x1 - x0;
      return Color.fromARGB(255, ar ~/ all, ag ~/ all, ab ~/ all);
    }
    return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  }

  void _skip() {
    if (_t.value < 1) {
      _t.animateTo(
        1,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Cuts the couple out of the image's cream (off the main thread), then
  /// starts following the tilt.
  Future<void> _makeFigures(
    ui.Image image,
    ByteData? pixels,
    Color cream,
  ) async {
    if (pixels == null || !mounted || MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    try {
      final cut = await compute(_cutOut, (
        rgba: pixels.buffer.asUint8List(
          pixels.offsetInBytes,
          pixels.lengthInBytes,
        ),
        r: (cream.r * 255).round(),
        g: (cream.g * 255).round(),
        b: (cream.b * 255).round(),
      ));
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        cut,
        image.width,
        image.height,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      final figures = await done.future;
      if (!mounted) {
        figures.dispose();
        return;
      }
      setState(() => _figures = figures);
      _startTilt();
    } catch (_) {
      // No depth: the flat image stays.
    }
  }

  void _startTilt() {
    _tiltTicker ??= createTicker((_) {
      // Ease toward the tilt: a float, not a jitter.
      final now = _tilt.value;
      final next = now + (_target - now) * 0.12;
      if ((next - now).distance > 0.0005) _tilt.value = next;
    })..start();
    _accel ??= accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      (e) {
        // Neutral is however the phone is being held: a slow average of the
        // readings, so holding it at an angle settles back to centre.
        final raw = Offset(e.x, e.y);
        final rest =
            _rest = _rest == null ? raw : _rest! + (raw - _rest!) * 0.004;
        final d = raw - rest;
        _target = Offset(
          (-d.dx / 3.0).clamp(-1.0, 1.0),
          (d.dy / 3.0).clamp(-1.0, 1.0),
        );
      },
      onError: (Object _) {},
      cancelOnError: true,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Covered by another page (TickerMode off): the sensor rests too.
    final mode = TickerMode.getNotifier(context);
    if (mode != _tickerMode) {
      _tickerMode?.removeListener(_onTickerMode);
      _tickerMode = mode..addListener(_onTickerMode);
    }
  }

  void _onTickerMode() {
    final on = _tickerMode?.value ?? true;
    if (on) {
      _accel?.resume();
    } else if (!(_accel?.isPaused ?? true)) {
      _accel?.pause();
    }
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_onTickerMode);
    _accel?.cancel();
    _tiltTicker?.dispose();
    _tilt.dispose();
    _depthIn.dispose();
    _figures?.dispose();
    _ticker?.cancel();
    _t.dispose();
    _enter.dispose();
    _photo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduceMotion = media.disableAnimations;
    final photoHeight = media.size.height * _photoShare;
    final area = Size(media.size.width, photoHeight);
    if (_footFor != area) {
      _footFor = area;
      _foot = _footColor(area);
    }
    final foot = _foot;
    // The platform's own sizes (owner 2026-11-26): the theme's type scale.
    final type = Theme.of(context).textTheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Dark status icons on the photo's paper; light home bar on the green.
      value: SystemUiOverlayStyle.dark.copyWith(
        systemNavigationBarColor: _deep,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _deep,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // The background: deep green, a lighter green glow at the foot.
            // Starts as the image's own foot colour right under it (a
            // seamless join), deepening to the bottom of the screen.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [foot, foot, _deep],
                  stops: const [0.0, _photoShare, 1.0],
                ),
              ),
            ),
            // The photo (dots first), its foot melting into the green.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: photoHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _skip,
                child: ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _t,
                    builder: (context, _) {
                      // Once the faces are whole and the cut-out is ready,
                      // the couple moves to its own layer over the cream.
                      final depth = _figures != null && _t.isCompleted;
                      if (depth && _depthIn.isDismissed) _depthIn.forward();
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(
                            // The scene's own clock runs a little faster than
                            // the spike's (its 5.8 s in [_total]).
                            painter: _ScenePainter(
                              seconds: _t.value * 5.8,
                              photo: _photo,
                              backdrop: _backdrop,
                              hideCouple: depth,
                            ),
                          ),
                          if (depth)
                            AnimatedBuilder(
                              animation: Listenable.merge([_tilt, _depthIn]),
                              builder:
                                  (context, _) => CustomPaint(
                                    painter: _FiguresPainter(
                                      figures: _figures!,
                                      tilt:
                                          _tilt.value *
                                          Curves.easeOut.transform(
                                            _depthIn.value,
                                          ),
                                    ),
                                  ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            // Below the image: its own bottom row, stretched down, so every
            // column meets the image in exactly its colour (no fade over the
            // image, owner 2026-11-26), deepening into the green behind the
            // buttons. It moves with the couple when the phone tilts.
            Positioned(
              left: 0,
              right: 0,
              // The green starts a little above the image's edge (owner
              // 2026-11-26): [_FootPainter.lead] points over the image.
              top: photoHeight - _FootPainter.lead,
              bottom: 0,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_t, _tilt, _depthIn]),
                  builder: (context, _) {
                    final photo = _photo;
                    // In once the faces are whole (the scene's 5.2–5.8 s).
                    final whole = ((_t.value * 5.8 - 5.2) / 0.6).clamp(
                      0.0,
                      1.0,
                    );
                    final depth = _figures != null && _t.isCompleted;
                    // Before the faces are whole: the dots' cream melting
                    // into the green (no hard edge under the dots); it
                    // crossfades into the image's own continuation.
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (whole < 1)
                          Opacity(
                            opacity: 1 - whole,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    _backdrop.withValues(alpha: 0),
                                    _backdrop,
                                    Color.lerp(_backdrop, _deep, 0.55)!,
                                    _deep,
                                  ],
                                  stops: const [0.0, 0.12, 0.45, 1.0],
                                ),
                              ),
                            ),
                          ),
                        if (whole > 0 && photo != null)
                          Opacity(
                            opacity: whole,
                            child: CustomPaint(
                              painter: _FootPainter(
                                image: photo,
                                area: Size(media.size.width, photoHeight),
                                tilt: depth
                                    ? _tilt.value * Curves.easeOut.transform(_depthIn.value)
                                    : Offset.zero,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // The words on the image's light background, above the couple
            // (owner 2026-11-26): the changing line and "Read more", dark.
            Positioned(
              left: 24,
              right: 24,
              top: media.padding.top + 70,
              child: FadeTransition(
                opacity: CurvedAnimation(parent: _enter, curve: Curves.easeOut),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The changing line takes the wordmark's place, large
                    // (owner 2026-11-26). Two lines of room, so nothing
                    // below jumps.
                    SizedBox(
                      height:
                          (type.headlineMedium?.fontSize ?? 28) *
                          1.2 *
                          2 *
                          MediaQuery.textScalerOf(context).scale(1),
                      child: Semantics(
                        label: _lines
                            .map((l) => l.replaceAll('\n', ' '))
                            .join(' '),
                        child: ExcludeSemantics(
                          child: AnimatedSwitcher(
                            duration: Duration(
                              milliseconds: reduceMotion ? 1 : 800,
                            ),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            layoutBuilder:
                                (current, previous) => Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ...previous,
                                    if (current != null) current,
                                  ],
                                ),
                            // The new line rises in from below; the old
                            // one rises out above it, gone by halfway, so
                            // the two never sit on top of each other.
                            transitionBuilder: (child, animation) {
                              final incoming =
                                  child.key == ValueKey(_line % _lines.length);
                              // Outgoing runs 1 -> 0, so both use the
                              // upper half: out by halfway, then in.
                              final fade = CurvedAnimation(
                                parent: animation,
                                curve: const Interval(
                                  0.5,
                                  1,
                                  curve: Curves.easeOut,
                                ),
                              );
                              if (reduceMotion) {
                                return FadeTransition(
                                  opacity: fade,
                                  child: child,
                                );
                              }
                              return FadeTransition(
                                opacity: fade,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: Offset(0, incoming ? 0.3 : -0.3),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            // Modulo: a hot reload can keep an index
                            // from a longer list.
                            child: Text(
                              _lines[_line % _lines.length],
                              key: ValueKey(_line % _lines.length),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: type.headlineMedium?.copyWith(
                                height: 1.2,
                                color: _ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // "Read more" alone under the phrase (owner 2026-11-26):
                    // opens the guides.
                    Center(
                      child: TextButton(
                        onPressed: () => _openGuides(context),
                        style: TextButton.styleFrom(
                          foregroundColor: _green,
                          // Tight above (close to the phrase), still a
                          // 44-point tap target.
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: type.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: _green.withValues(alpha: 0.6),
                          ),
                        ),
                        child: const Text('Read more'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // The buttons, alone on the green.
            Positioned(
              left: 24,
              right: 24,
              bottom: media.padding.bottom + 12,
              child: FadeTransition(
                opacity: CurvedAnimation(parent: _enter, curve: Curves.easeOut),
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.06),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Button(
                        label: 'Get started',
                        background: _leaf,
                        foreground: _deep,
                        // Welcome on top, so its back button returns here.
                        onTap: () => context.push(RouteNames.welcome),
                      ),
                      const SizedBox(height: 10),
                      _Button(
                        label: 'I already have an account',
                        // Transparent: reads as text (owner 2026-11-26).
                        background: Colors.transparent,
                        foreground: Colors.white,
                        // Marks first launch done, as Welcome's cards do.
                        onTap:
                            () => WelcomeScreen.leave(
                              context,
                              ref,
                              // Back, Not now and DM1 return here (fix
                              // round M-4), not to the path question.
                              WelcomeScreen.signUpLocation(
                                'returning',
                                back: RouteNames.start,
                              ),
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-width button, as Netflix's: a rounded bar, one bold label.
class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GlassPressable(
        onTap: onTap,
        pressedScale: 0.97,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // Radius 30: the design token (owner 2026-11-26).
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadiusTokens.floatingNavAll,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// A deterministic 0..1 value per cell.
double _rand(int i) {
  final x = math.sin(i * 12.9898 + 78.233) * 43758.5453;
  return x - x.floorToDouble();
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.seconds,
    required this.photo,
    this.backdrop = _paper,
    this.hideCouple = false,
  });

  final double seconds;
  final ui.Image? photo;

  /// The couple is drawn by [_FiguresPainter] on its own layer: only the
  /// cream here.
  final bool hideCouple;

  /// Fills the space above the photo, blended into its top edge.
  final Color backdrop;

  static const int _cols = 13;

  double _seg(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((seconds - a) / (b - a)).clamp(0.0, 1.0));

  /// The threads: diagonals (the hard day that keeps coming back), columns
  /// (a habit, same day every week), rows (a good stretch).
  static List<List<(int, int)>> _threads(int rows) {
    final out = <List<(int, int)>>[];
    void add(List<(int, int)> cells) {
      final kept = [
        for (final c in cells)
          if (c.$1 >= 0 && c.$1 < _cols && c.$2 >= 0 && c.$2 < rows) c,
      ];
      if (kept.length >= 3) out.add(kept);
    }

    for (final s in const [(1, 1), (7, 0), (2, 8), (8, 9), (0, 15)]) {
      add([for (var i = 0; i < 5; i++) (s.$1 + i, s.$2 + i)]);
    }
    add([for (var r = 2; r < 8; r++) (11, r)]);
    add([for (var r = 13; r < 18; r++) (5, r)]);
    add([for (var c = 3; c < 8; c++) (c, 5)]);
    add([for (var c = 6; c < 11; c++) (c, 18)]);
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Nothing draws outside the top area: the enlarged photo is taller than
    // it, and below it is the green.
    canvas.clipRect(Offset.zero & size);
    // What the dots sit on, under the photo: the image's own cream, so the
    // reveal never changes the colour around the couple (owner 2026-11-26).
    canvas.drawRect(Offset.zero & size, Paint()..color = backdrop);
    if (hideCouple) {
      canvas.drawRect(Offset.zero & size, Paint()..color = backdrop);
      return;
    }
    final gap = size.width / _cols;
    final rows = (size.height / gap).ceil();
    Offset at(int c, int r) => Offset((c + 0.5) * gap, (r + 0.5) * gap);

    final threads = _threads(rows);
    final threadOf = <int, (int, int)>{}; // cell -> (thread, position)
    for (var t = 0; t < threads.length; t++) {
      for (var i = 0; i < threads[t].length; i++) {
        threadOf[threads[t][i].$2 * _cols + threads[t][i].$1] = (t, i);
      }
    }

    // The photo covers the top of the screen, the faces in the middle of
    // it (the sides crop, as a poster does).
    Matrix4? photoMatrix;
    Offset face = Offset(size.width / 2, size.height * 0.5);
    Rect photoRect = Rect.zero;
    if (photo != null) {
      final iw = photo!.width.toDouble(), ih = photo!.height.toDouble();
      final layout = _imageLayout(size, iw, ih);
      final s = layout.scale;
      final dw = iw * s, dh = ih * s;
      final dx = layout.dx;
      final dy = layout.dy;
      photoMatrix =
          Matrix4.identity()
            ..translate(dx, dy)
            ..scale(s, s);
      face = Offset(dx + dw * 0.5, dy + dh * 0.42);
      photoRect = Rect.fromLTWH(dx, dy, dw, dh);
    }
    final photoPaint = Paint()..isAntiAlias = true;
    if (photo != null) {
      photoPaint.shader = ImageShader(
        photo!,
        TileMode.clamp,
        TileMode.clamp,
        photoMatrix!.storage,
        filterQuality: FilterQuality.medium,
      );
    }
    final maxDist = math.sqrt(
      size.width * size.width + size.height * size.height,
    );
    final reveal = _seg(3.4, 5.6, Curves.linear);

    // Threads first, under the dots.
    final threadFade = 1 - _seg(3.6, 4.4);
    for (var t = 0; t < threads.length; t++) {
      final start = 1.6 + t * 0.2;
      final draw = _seg(start + 0.25, start + 0.95, Curves.easeInOutCubic);
      if (draw <= 0 || threadFade <= 0) continue;
      final cells = threads[t];
      final first = at(cells.first.$1, cells.first.$2);
      final path = Path()..moveTo(first.dx, first.dy);
      for (final c in cells.skip(1)) {
        final p = at(c.$1, c.$2);
        path.lineTo(p.dx, p.dy);
      }
      for (final m in path.computeMetrics()) {
        canvas.drawPath(
          m.extractPath(0, m.length * draw),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = _green.withValues(alpha: 0.5 * threadFade),
        );
      }
    }

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final i = r * _cols + c;
        final p = at(c, r);
        final appear = _seg(
          c * 0.035 + r * 0.05,
          c * 0.035 + r * 0.05 + 0.5,
          Curves.easeOutBack,
        );
        if (appear <= 0) continue;
        final base = 1.5 + _rand(i) * 1.7;
        final pattern = threadOf[i];
        double lit = 0;
        if (pattern != null) {
          final start = 1.6 + pattern.$1 * 0.2 + pattern.$2 * 0.07;
          lit = _seg(start, start + 0.35, Curves.easeOutBack);
        }
        final r0 = (base + (4.6 - base) * lit) * appear;

        // The window onto the photo, opening from the faces outwards.
        final d = (p - face).distance / maxDist;
        final open = ((reveal - d * 0.55) / 0.45).clamp(0.0, 1.0);
        final grown = Curves.easeInOutCubic.transform(open);
        if (photo != null && grown > 0 && photoRect.contains(p)) {
          canvas.save();
          canvas.clipRect(photoRect);
          canvas.drawCircle(p, r0 + (gap * 0.74 - r0) * grown, photoPaint);
          canvas.restore();
        }
        final dotAlpha = 1 - grown;
        if (dotAlpha > 0) {
          final color = Color.lerp(_quiet, _green, lit)!;
          canvas.drawCircle(
            p,
            r0,
            Paint()..color = color.withValues(alpha: color.a * dotAlpha),
          );
        }
      }
    }

    // Seal the gaps once the windows have met.
    final whole = _seg(5.2, 5.8);
    if (photo != null && whole > 0) {
      canvas.drawRect(
        photoRect,
        photoPaint..color = Color.fromRGBO(0, 0, 0, whole),
      );
      // Above a lowered photo: its own background colour, blended into its
      // top edge so no line shows.
      if (photoRect.top > 0) {
        final fill = backdrop.withValues(alpha: whole);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, photoRect.top + 1),
          Paint()..color = fill,
        );
        final blend = Rect.fromLTWH(0, photoRect.top, size.width, 48);
        canvas.drawRect(
          blend,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [fill, backdrop.withValues(alpha: 0)],
            ).createShader(blend),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.seconds != seconds ||
      old.photo != photo ||
      old.backdrop != backdrop ||
      old.hideCouple != hideCouple;
}

/// The couple cut out of its cream background: a pixel's alpha falls off as
/// its colour nears the cream (soft, so the edges stay anti-aliased). Runs
/// in an isolate.
Uint8List _cutOut(({Uint8List rgba, int r, int g, int b}) a) {
  final src = a.rgba;
  final out = Uint8List.fromList(src);
  for (var i = 0; i < out.length; i += 4) {
    final dr = src[i] - a.r, dg = src[i + 1] - a.g, db = src[i + 2] - a.b;
    final d = math.sqrt(dr * dr + dg * dg + db * db);
    final t = ((d - 14) / (40 - 14)).clamp(0.0, 1.0);
    final a01 = src[i + 3] / 255 * t * t * (3 - 2 * t);
    // Premultiplied: decodeImageFromPixels' rgba8888 is drawn as
    // premultiplied, so a clear pixel that kept its colour added it as light
    // (the white band above the couple, owner 2026-11-26).
    out[i] = (src[i] * a01).round();
    out[i + 1] = (src[i + 1] * a01).round();
    out[i + 2] = (src[i + 2] * a01).round();
    out[i + 3] = (a01 * 255).round();
  }
  return out;
}

/// The cut-out couple, nearer than the cream: shifted with the tilt, turned
/// a little in 3D about their faces, with a sheen that slides as it turns.
class _FiguresPainter extends CustomPainter {
  _FiguresPainter({required this.figures, required this.tilt});

  final ui.Image figures;

  /// -1..1 on each axis.
  final Offset tilt;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final iw = figures.width.toDouble(), ih = figures.height.toDouble();
    final l = _imageLayout(size, iw, ih);
    final dst = Rect.fromLTWH(l.dx, l.dy, iw * l.scale, ih * l.scale);
    final face = Offset(
      dst.left + dst.width * 0.5,
      dst.top + dst.height * 0.42,
    );
    final m = _depthMatrix(face, tilt);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.transform(m.storage);
    canvas.drawImageRect(
      figures,
      Rect.fromLTWH(0, 0, iw, ih),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    // The sheen: a soft band of light across the figures only.
    canvas.drawRect(
      dst,
      Paint()
        ..blendMode = BlendMode.srcATop
        ..shader = LinearGradient(
          begin: Alignment(-1.4 + tilt.dx * 0.8, -1),
          end: Alignment(0.6 + tilt.dx * 0.8, 1),
          colors: const [
            Color(0x00FFFFFF),
            Color(0x24FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: const [0.35, 0.5, 0.65],
        ).createShader(dst),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FiguresPainter old) =>
      old.tilt != tilt || old.figures != figures;
}

/// The couple's move for a [tilt]: shifted, and turned a little in 3D about
/// their [face]. Shared by the couple and the image's continuation below.
Matrix4 _depthMatrix(Offset face, Offset tilt) {
  final shift = Offset(tilt.dx * 14, tilt.dy * 10);
  return Matrix4.identity()
    ..translate(face.dx + shift.dx, face.dy + shift.dy)
    ..setEntry(3, 2, 0.0015)
    ..rotateY(tilt.dx * 0.08)
    ..rotateX(-tilt.dy * 0.06)
    ..translate(-face.dx, -face.dy);
}

/// Under the image: the image's last visible row stretched down (so each
/// column continues in exactly its own colour), then a smooth deepening into
/// [_deep]. Drawn in the image's own coordinates (the top area of [area]
/// size), moved by the same tilt as the couple.
class _FootPainter extends CustomPainter {
  _FootPainter({required this.image, required this.area, required this.tilt});

  final ui.Image image;
  final Size area;
  final Offset tilt;

  /// How far above the image's edge the canvas (and the green) begins.
  static const double lead = 36;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || area.isEmpty) return;
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final l = _imageLayout(area, iw, ih);
    final dst = Rect.fromLTWH(l.dx, l.dy, iw * l.scale, ih * l.scale);
    final face = Offset(
      dst.left + dst.width * 0.5,
      dst.top + dst.height * 0.42,
    );
    // The image row at the top area's bottom edge.
    final row = ((area.height - 1 - l.dy) / l.scale).clamp(0.0, ih - 1);

    canvas.save();
    // The stretched row only below the edge; above it the image shows.
    canvas.clipRect(Rect.fromLTWH(0, lead, size.width, size.height - lead));
    canvas.translate(0, lead - area.height);
    if (tilt != Offset.zero) canvas.transform(_depthMatrix(face, tilt).storage);
    // From a little above the edge (the tilt may move it), down past the
    // bottom of the screen.
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, row, iw, 1),
      Rect.fromLTRB(
        dst.left,
        area.height - 24,
        dst.right,
        area.height + size.height + 24,
      ),
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.restore();

    // Deepening into the green (smootherstep), so the buttons sit on it.
    const n = 12;
    double ease(double t) => t * t * t * (t * (t * 6 - 15) + 10);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            // Denser than at first, a touch under the strongest try
            // (owner 2026-11-26): 96% by 90% of the way down.
            for (var i = 0; i <= n; i++)
              _deep.withValues(alpha: 0.96 * ease(math.min(1.0, i / n * 1.12))),
          ],
          stops: [for (var i = 0; i <= n; i++) i / n],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_FootPainter old) =>
      old.image != image || old.area != area || old.tilt != tilt;
}
