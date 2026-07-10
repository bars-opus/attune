import 'dart:ui' as ui;

import 'package:attune/core/utils/exports/export_screens.dart';

class AnimatedCircle extends StatefulWidget {
  final bool animateSize;
  final bool animateShape;
  final double size;
  final double stroke;
  final Color firstColor;
  final Color secondColor;

  const AnimatedCircle({
    super.key,
    this.animateSize = false,
    this.animateShape = false,
    this.size = 100,
    this.stroke = 5,
    this.firstColor = Colors.red,
    this.secondColor = Colors.blue,
  });

  @override
  State<AnimatedCircle> createState() => _AnimatedCircleState();
}

class _AnimatedCircleState extends State<AnimatedCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _shapeAnimation;
  late Animation<double> _sizeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _buildAnimations();
  }

  @override
  void didUpdateWidget(AnimatedCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.size != oldWidget.size) {
      _buildAnimations();
    }
  }

  void _buildAnimations() {
    _shapeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _sizeAnimation = Tween<double>(
      begin: widget.size * 0.40,
      end: widget.size,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildCircle() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final size =
            (widget.animateSize ? _sizeAnimation.value : widget.size).r;
        final shapeProgress =
            widget.animateShape
                ? ((_shapeAnimation.value - 0.18) / 0.82).clamp(0.0, 1.0)
                : 0.0;

        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _FavoriteMorphPainter(
              progress: shapeProgress,
              color: widget.firstColor,
              stroke: widget.stroke.w,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => _buildCircle();
}

class _FavoriteMorphPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double stroke;

  const _FavoriteMorphPainter({
    required this.progress,
    required this.color,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final start = _lerpPoint(
      const Offset(50, 10),
      const Offset(50, 30),
      progress,
    );

    path.moveTo(start.dx, start.dy);
    _cubicTo(
      path,
      square: _CubicPoints(
        const Offset(27.9, 10),
        const Offset(10, 27.9),
        const Offset(10, 50),
      ),
      favorite: _CubicPoints(
        const Offset(44, 18),
        const Offset(25, 14),
        const Offset(18, 30),
      ),
    );
    _cubicTo(
      path,
      square: _CubicPoints(
        const Offset(10, 72.1),
        const Offset(27.9, 90),
        const Offset(50, 90),
      ),
      favorite: _CubicPoints(
        const Offset(8, 48),
        const Offset(28, 66),
        const Offset(50, 86),
      ),
    );
    _cubicTo(
      path,
      square: _CubicPoints(
        const Offset(72.1, 90),
        const Offset(90, 72.1),
        const Offset(90, 50),
      ),
      favorite: _CubicPoints(
        const Offset(72, 66),
        const Offset(92, 48),
        const Offset(82, 30),
      ),
    );
    _cubicTo(
      path,
      square: _CubicPoints(
        const Offset(90, 27.9),
        const Offset(72.1, 10),
        const Offset(50, 10),
      ),
      favorite: _CubicPoints(
        const Offset(75, 14),
        const Offset(56, 18),
        const Offset(50, 30),
      ),
    );
    path.close();

    final shortestSide = size.shortestSide;
    canvas.save();
    canvas.scale(shortestSide / 100, shortestSide / 100);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _cubicTo(
    Path path, {
    required _CubicPoints square,
    required _CubicPoints favorite,
  }) {
    final control1 = _lerpPoint(square.control1, favorite.control1, progress);
    final control2 = _lerpPoint(square.control2, favorite.control2, progress);
    final end = _lerpPoint(square.end, favorite.end, progress);
    path.cubicTo(
      control1.dx,
      control1.dy,
      control2.dx,
      control2.dy,
      end.dx,
      end.dy,
    );
  }

  Offset _lerpPoint(Offset begin, Offset end, double progress) {
    return Offset(
      ui.lerpDouble(begin.dx, end.dx, progress)!,
      ui.lerpDouble(begin.dy, end.dy, progress)!,
    );
  }

  @override
  bool shouldRepaint(covariant _FavoriteMorphPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.stroke != stroke;
  }
}

class _CubicPoints {
  final Offset control1;
  final Offset control2;
  final Offset end;

  const _CubicPoints(this.control1, this.control2, this.end);
}
