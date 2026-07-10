import 'dart:async';
import 'package:flutter/material.dart';
import 'package:attune/core/utils/exports/export_packages.dart';
import 'package:attune/core/widgets/feedback/circular_loading_indicator.dart';

class AppleVerificationAnimation extends StatefulWidget {
  final VoidCallback? onComplete;
  final Duration verificationDuration;
  final double size;
  final String message;

  const AppleVerificationAnimation({
    Key? key,
    this.onComplete,
    this.verificationDuration = const Duration(seconds: 2),
    this.size = 100,
    this.message = '',
  }) : super(key: key);

  @override
  State<AppleVerificationAnimation> createState() =>
      _AppleVerificationAnimationState();
}

class _AppleVerificationAnimationState extends State<AppleVerificationAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _transitionController;
  bool _isComplete = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    // Controller for the transition animation (scale + fade)
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Start verification automatically
    _startVerification();
  }

  void _startVerification() {
    // Set a timer to complete after the specified duration
    _timer = Timer(
      widget.verificationDuration - Duration(milliseconds: 700),
      () {
        // Trigger the transition to the checkmark
        _transitionController.forward().then((_) {
          setState(() {
            _isComplete = true;
          });
          widget.onComplete?.call();
        });
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _transitionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: widget.size,
          height: widget.size,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeInOutCubic,
            switchOutCurve: Curves.easeInOutCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child:
                _isComplete
                    ? _buildCheckmark(colorScheme)
                    : _buildSpinner(colorScheme),
          ),
        ),
        Gap(20.w),

        // Text animation with SizeTransition + FadeTransition
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(
              milliseconds: 400,
            ), // Slightly longer to appreciate the effect
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: 0.0, // Grows from left
                  child: child,
                ),
              );
            },
            child: Text(
              _isComplete ? 'Done' : widget.message.trim(),
              key: ValueKey(_isComplete ? 'Done' : widget.message.trim()),
              style: theme.bodyMedium?.copyWith(
                color:
                    _isComplete
                        ? colorScheme.primary
                        : colorScheme.onBackground,
                fontWeight: _isComplete ? FontWeight.w600 : FontWeight.normal,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpinner(ColorScheme colorScheme) {
    return SizedBox(
      key: const ValueKey('spinner'),
      width: widget.size,
      height: widget.size,
      child:  CircularLoadingIndicator(
        size:  widget.size,
      )
      
     
     
    );
  }

  Widget _buildCheckmark(ColorScheme colorScheme) {
    return Container(
      key: const ValueKey('checkmark'),
      width: widget.size + 10,
      height: widget.size + 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.green, // Solid blue background
      ),
      child: Icon(Icons.check, color: Colors.white, size: widget.size),
    );
  }
}
