import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:attune/core/widgets/animated_rolling_counter.dart';

/// Which stage of the recording gesture the composer is in.
///
/// Mirrors WhatsApp: a recording starts [held] (finger down, slide away to
/// cancel) and becomes [locked] once the user slides up to the lock — at
/// which point the finger can lift and the bar grows its own transport
/// controls (delete / pause / send).
enum VoiceRecordingStage { held, locked }

/// Replaces ChatTextField's text input area while a voice message is being
/// recorded.
///
/// Purely presentational: ChatTextField owns the recording lifecycle and
/// feeds this widget its state. Both stages render here rather than in two
/// separate widgets so the transition between them animates in place
/// instead of swapping one subtree for another.
class VoiceRecordingBar extends StatelessWidget {
  const VoiceRecordingBar({
    super.key,
    required this.elapsed,
    required this.amplitude,
    required this.isCancelling,
    this.stage = VoiceRecordingStage.held,
    this.levels = const <double>[],
    this.isPaused = false,
    this.onCancel,
    this.onTogglePause,
    this.onSend,
  });

  final Duration elapsed;

  /// Current normalized amplitude (0.0-1.0) — the newest sample, drawn as
  /// the rightmost (leading) bar of the live waveform.
  final double amplitude;

  /// True once the press has been dragged past the slide-to-cancel
  /// threshold — the bar re-colors to signal "release here to cancel."
  final bool isCancelling;

  final VoiceRecordingStage stage;

  /// Rolling history of recent amplitude samples, oldest first. Only the
  /// tail is drawn (whatever fits the available width), so an arbitrarily
  /// long recording never grows this widget's paint cost.
  final List<double> levels;

  final bool isPaused;

  /// Locked-stage transport. Null in the held stage, where the gesture
  /// itself (release / slide away) drives send and cancel instead.
  final VoidCallback? onCancel;
  final VoidCallback? onTogglePause;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLocked = stage == VoiceRecordingStage.locked;

    // The recording dot reads as "armed" in both stages, but the cancel
    // affordance is what turns the bar destructive — so error coloring is
    // driven by the drag, not by the stage.
    final accent = isCancelling ? colorScheme.error : colorScheme.primary;

    return Semantics(
      liveRegion: true,
      label:
          isCancelling
              ? 'Release to cancel recording'
              : 'Recording voice message, ${elapsed.inSeconds} seconds',
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: EdgeInsets.symmetric(
          horizontal: isLocked ? Spacing.sm : Spacing.smMd,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.onSurface, width: .2),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.full),
        ),
        child: Row(
          children: [
            // Discarding stays on the left where it was; the trailing
            // pause/send pair is unchanged. Wiring a stop icon to onSend
            // here would have given the locked bar TWO send controls and
            // no way to throw a take away.
            if (isLocked)
              _RecordingIconButton(
                icon: Icons.delete_outline_rounded,
                color: colorScheme.onSurfaceVariant,
                tooltip: 'Delete recording',
                onTap: onCancel,
              )
            else
              _PulsingDot(
                key: const ValueKey('voice-recording-dot'),
                color: accent,
                isAnimating: !isPaused,
              ),
            SizedBox(width: isLocked ? 0 : Spacing.sm),
            SizedBox(
              // Fixed width so the waveform beside it doesn't reflow on
              // every tick as the digits change width.
              width: 52,
              child: AnimatedRollingCounter(
                // Rolls rather than jumps, so a glance registers the
                // change without re-reading the digits.
                count: elapsed.inSeconds,
                suffix: 's',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child:
                  isCancelling
                      ? Text(
                        'Release to cancel',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                      : isLocked
                      ? SizedBox(
                        height: 28,
                        child: _LiveWaveform(
                          levels: levels,
                          current: amplitude,
                          color: accent,
                        ),
                      )
                      : Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 28,
                              child: _LiveWaveform(
                                levels: levels,
                                current: amplitude,
                                color: accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: Spacing.sm),
                          Icon(
                            Icons.keyboard_arrow_left_rounded,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          // Flexible + ellipsis: on a narrow composer the
                          // hint gives way rather than overflowing the row
                          // (the waveform's Expanded can't absorb this on
                          // its own — the text has its own intrinsic
                          // width).
                          Flexible(
                            child: Text(
                              'slide to cancel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
            ),
            if (isLocked) ...[
              const SizedBox(width: Spacing.sm),
              _RecordingIconButton(
                icon: isPaused ? Icons.mic_rounded : Icons.pause_rounded,
                color: colorScheme.error,
                tooltip: isPaused ? 'Resume recording' : 'Pause recording',
                onTap: onTogglePause,
              ),
              const SizedBox(width: Spacing.xs),
              _RecordingIconButton(
                icon: Icons.send_rounded,
                color: colorScheme.onPrimary,
                fillColor: colorScheme.primary,
                tooltip: 'Send voice message',
                onTap: onSend,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The blinking record indicator. Stops animating while paused so the
/// paused state is legible at a glance rather than only from the icon.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({
    super.key,
    required this.color,
    required this.isAnimating,
  });

  final Color color;
  final bool isAnimating;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isAnimating) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimating == oldWidget.isAnimating) return;
    if (widget.isAnimating) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1.0).animate(_controller),
      child: Icon(Icons.fiber_manual_record, color: widget.color, size: 12),
    );
  }
}

/// Right-anchored live waveform: newest sample at the right edge, older
/// samples scrolling off the left. Only the visible tail is painted.
class _LiveWaveform extends StatelessWidget {
  const _LiveWaveform({
    required this.levels,
    required this.current,
    required this.color,
  });

  final List<double> levels;
  final double current;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _LiveWaveformPainter(
        levels: levels,
        current: current,
        color: color,
      ),
    );
  }
}

class _LiveWaveformPainter extends CustomPainter {
  const _LiveWaveformPainter({
    required this.levels,
    required this.current,
    required this.color,
  });

  final List<double> levels;
  final double current;
  final Color color;

  static const double _barWidth = 3.0;
  static const double _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    const stride = _barWidth + _gap;
    final capacity = (size.width / stride).floor();
    if (capacity <= 0) return;

    // Draw only the newest `capacity` samples, right-anchored, so the
    // waveform appears to scroll leftward as it fills.
    final visible =
        levels.length > capacity
            ? levels.sublist(levels.length - capacity)
            : levels;

    final paint =
        Paint()
          ..color = color
          ..strokeCap = StrokeCap.round
          ..strokeWidth = _barWidth;

    final centerY = size.height / 2;
    // Right-align: the last bar's right edge sits at the canvas's right
    // edge regardless of how few samples exist yet.
    var x = size.width - stride * visible.length + _barWidth / 2;

    for (final level in visible) {
      // A floor keeps silence visible as a dot rather than nothing at all,
      // matching how WhatsApp renders quiet passages.
      final h = (level.clamp(0.0, 1.0) * size.height).clamp(2.0, size.height);
      canvas.drawLine(
        Offset(x, centerY - h / 2),
        Offset(x, centerY + h / 2),
        paint,
      );
      x += stride;
    }
  }

  @override
  bool shouldRepaint(_LiveWaveformPainter old) =>
      old.current != current ||
      old.color != color ||
      old.levels.length != levels.length;
}

class _RecordingIconButton extends StatelessWidget {
  const _RecordingIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.fillColor,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final Color? fillColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fillColor ?? Colors.transparent,
            ),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}
