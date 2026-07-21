import 'package:attune/core/utils/exports/export_screens.dart';

class AnimatedSteppedProgressBar extends StatefulWidget {
  final double progressValue;
  final int totalSegments;
  final Color? activeColor;
  final Color? inactiveColor;
  final double height;

  const AnimatedSteppedProgressBar({
    super.key,
    required this.progressValue,
    required this.totalSegments,
    this.activeColor,
    this.inactiveColor,
    this.height = 5,
  });

  @override
  State<AnimatedSteppedProgressBar> createState() =>
      _AnimatedSteppedProgressBarState();
}

class _AnimatedSteppedProgressBarState extends State<AnimatedSteppedProgressBar>
    with SingleTickerProviderStateMixin {
  // ✅ This is the key fix
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this, // ✅ Now works
    );
    _animation = Tween<double>(
      begin: 0,
      end: widget.progressValue,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedSteppedProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progressValue != widget.progressValue) {
      _animation = Tween<double>(
        begin: oldWidget.progressValue,
        end: widget.progressValue,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final currentValue = _animation.value;
        final filledSegments = (currentValue * widget.totalSegments).ceil();
        final colorScheme = Theme.of(context).colorScheme;

        return Row(
          children: List.generate(widget.totalSegments, (index) {
            final isFilled = index < filledSegments;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOut,
                margin: EdgeInsets.only(
                  right: index < widget.totalSegments - 1 ? 4.w : 0,
                ),
                height: widget.height,
                decoration: BoxDecoration(
                  color:
                      isFilled
                          ? (widget.activeColor ?? colorScheme.primary)
                          : (widget.inactiveColor ??
                              colorScheme.surfaceVariant),
                  borderRadius: BorderRadius.circular(isFilled ? 20.r : 100.r),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
