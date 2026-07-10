// lib/features/pulse/presentation/widgets/radar_chart.dart
import 'dart:math';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class RadarChart extends StatefulWidget {
  final Map<String, int> dimensions;
  final Size size;

  const RadarChart({
    super.key,
    required this.dimensions,
    this.size = const Size(280, 280),
  });

  @override
  State<RadarChart> createState() => _RadarChartState();
}

class _RadarChartState extends State<RadarChart> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Column(
          children: [
            SizedBox(
              width: widget.size.width,
              height: widget.size.height,
              child: CustomPaint(
                painter: _RadarPainter(
                  dimensions: widget.dimensions,
                  animationValue: _animation.value,
                  color: colorScheme.primary,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            Gap(Spacing.md.h),
            // Legend
            Wrap(
              spacing: Spacing.md.w,
              runSpacing: Spacing.sm.h,
              alignment: WrapAlignment.center,
              children: widget.dimensions.keys.map((key) {
                return _buildLegendItem(key, widget.dimensions[key]!, colorScheme, textTheme);
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLegendItem(String label, int score, ColorScheme colorScheme, TextTheme textTheme) {
    return GestureDetector(
      onTap: () {
        _showTooltip(label, score);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w, vertical: Spacing.xs.h),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary,
              ),
            ),
            Gap(Spacing.xs.w),
            Text(
              _getShortLabel(label),
              style: textTheme.labelSmall,
            ),
            Gap(Spacing.xs.w),
            Text(
              score.toString(),
              style: textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTooltip(String label, int score) {
    final descriptions = {
      'Communication': 'How clearly and kindly you express yourselves',
      'Connection': 'Emotional closeness and warmth',
      'Conflict Health': 'How well you navigate disagreements',
      'Alignment': 'Shared values and direction',
      'Emotional Safety': 'Feeling safe to be vulnerable',
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Score: $score/100',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(descriptions[label] ?? ''),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _getShortLabel(String label) {
    switch (label) {
      case 'Communication': return 'Comm';
      case 'Connection': return 'Conn';
      case 'Conflict Health': return 'Conflict';
      case 'Alignment': return 'Align';
      case 'Emotional Safety': return 'Safety';
      default: return label;
    }
  }
}

class _RadarPainter extends CustomPainter {
  final Map<String, int> dimensions;
  final double animationValue;
  final Color color;
  final Color backgroundColor;

  _RadarPainter({
    required this.dimensions,
    required this.animationValue,
    required this.color,
    required this.backgroundColor,
  });

  final List<String> _order = [
    'Communication',
    'Connection',
    'Conflict Health',
    'Alignment',
    'Emotional Safety',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2.2;
    final angles = _getAngles();

    // Draw background pentagon
    final backgroundPath = Path();
    for (int i = 0; i < angles.length; i++) {
      final point = _getPoint(center, radius, angles[i], 1.0);
      if (i == 0) {
        backgroundPath.moveTo(point.dx, point.dy);
      } else {
        backgroundPath.lineTo(point.dx, point.dy);
      }
    }
    backgroundPath.close();
    canvas.drawPath(backgroundPath, Paint()..color = backgroundColor.withOpacity(0.3));

    // Draw grid lines
    final gridPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (double i = 0.2; i <= 1.0; i += 0.2) {
      final gridPath = Path();
      for (int j = 0; j < angles.length; j++) {
        final point = _getPoint(center, radius, angles[j], i);
        if (j == 0) {
          gridPath.moveTo(point.dx, point.dy);
        } else {
          gridPath.lineTo(point.dx, point.dy);
        }
      }
      gridPath.close();
      canvas.drawPath(gridPath, gridPaint);
    }

    // Draw axis lines
    final axisPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = 1;
    for (final angle in angles) {
      final point = _getPoint(center, radius, angle, 1.0);
      canvas.drawLine(center, point, axisPaint);
    }

    // Draw data polygon (animated)
    final dataPath = Path();
    for (int i = 0; i < angles.length; i++) {
      final dimension = _order[i];
      final score = dimensions[dimension] ?? 50;
      final normalizedScore = (score / 100) * animationValue;
      final point = _getPoint(center, radius, angles[i], normalizedScore);
      if (i == 0) {
        dataPath.moveTo(point.dx, point.dy);
      } else {
        dataPath.lineTo(point.dx, point.dy);
      }
    }
    dataPath.close();
    canvas.drawPath(dataPath, Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.fill);
    canvas.drawPath(dataPath, Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke);
  }

  List<double> _getAngles() {
    const startAngle = -90.0;
    final step = 360.0 / _order.length;
    return List.generate(_order.length, (i) => (startAngle + step * i) * pi / 180);
  }

  Offset _getPoint(Offset center, double radius, double angle, double scale) {
    final x = center.dx + radius * cos(angle) * scale;
    final y = center.dy + radius * sin(angle) * scale;
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
