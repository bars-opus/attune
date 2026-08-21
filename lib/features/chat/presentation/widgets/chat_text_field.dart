import 'dart:async';

import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/core/ui/motion/icon_crossfade.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/motion/scale_pop.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:permission_handler/permission_handler.dart';

import 'voice_recording_bar.dart';

class ChatTextField extends StatefulWidget {
  const ChatTextField({
    super.key,
    required this.controller,
    required this.onSend,
    this.onAttachImage,
    this.onAttachVideo,
    this.onOpenTranslator,
    this.onVoiceMessageRecorded,
    this.onCaptureVideo,
    this.onAttachFile,
    this.onOpenGames,
    this.showAttachImage = false,
    this.showAttachVideo = false,
    this.showTranslator = false,
    this.showVoiceMessage = false,
    this.showCaptureVideo = false,
    this.showGames = false,
    this.enabled = true,
    this.hintText = 'Type a message...',
    this.focusNode,
    this.sendButtonColor,
    this.onSendButtonColor,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachVideo;
  final VoidCallback? onOpenTranslator;

  /// Called once a press-and-hold recording completes with a valid
  /// (>= VoiceRecorderService.minDuration) recording. Not called at all for
  /// a slide-to-cancel or a too-short tap — those are silently discarded
  /// per the design spec.
  final void Function(VoiceRecording recording)? onVoiceMessageRecorded;

  /// Opens the ephemeral (view-once) "streak" camera capture flow. Surfaced
  /// as a dedicated trailing icon (next to mic/games) rather than inside the
  /// '+' attach sheet, since it's a capture action, not a library pick.
  final VoidCallback? onCaptureVideo;

  /// File attach — placeholder for now, wired into the '+' sheet.
  final VoidCallback? onAttachFile;

  /// Games entry point — placeholder for now, both the trailing icon and the
  /// '+' sheet's "Games" row call this.
  final VoidCallback? onOpenGames;

  final bool showAttachImage;
  final bool showAttachVideo;
  final bool showTranslator;
  final bool showVoiceMessage;
  final bool showCaptureVideo;
  final bool showGames;
  final bool enabled;
  final String hintText;

  /// Overrides the send button's fill AND the text field's focused border
  /// color, which otherwise both default to colorScheme.primary. Null (the
  /// default) keeps those defaults — 1:1 chat has no notion of "side" to
  /// tint by. DebateRoomScreen passes its FOR/AGAINST color here so the
  /// whole composer matches the side it's about to post to, the same way
  /// ForumPostBubble's own bubbles are tinted by side rather than always
  /// primary. Ignored when null.
  final Color? sendButtonColor;

  /// The icon's contrast color against [sendButtonColor] — e.g.
  /// colorScheme.onPrimary / colorScheme.onError, the same token pairing
  /// ForumPostBubble uses for its own bubble content. Only meaningful
  /// alongside [sendButtonColor]; ignored when that's null (the theme
  /// default IconButtonTheme already supplies the right onPrimary pairing).
  final Color? onSendButtonColor;

  /// Optional external focus node — e.g. so a caller can programmatically
  /// focus the field (tapping "Reply" on a comment) without owning its
  /// own separately-created, never-attached FocusNode.
  final FocusNode? focusNode;

  @override
  State<ChatTextField> createState() => _ChatTextFieldState();
}

/// A tappable icon with a small, fixed hit box — deliberately NOT
/// IconButton/AppIconButton, both of which reserve a much larger padded
/// tap target that made the composer row look sparse. GestureDetector
/// around a bare Icon keeps the row visually tight while still giving a
/// full, comfortable ~40x40 tap target via a transparent HitTestBehavior.
class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.child,
    this.filled = false,
    this.fillColor,
    this.iconColor,
  }) : assert(icon != null || child != null, 'Provide either icon or child');

  final IconData? icon;
  final VoidCallback? onTap;
  final String? tooltip;

  /// Overrides the default Icon(icon) — used by the mic/send slots, which
  /// need IconCrossfade wrapping the glyph rather than a bare Icon.
  final Widget? child;

  /// Send button's filled-circle treatment; every other composer icon is
  /// unfilled (plain glyph, theme's default icon color).
  final bool filled;
  final Color? fillColor;
  final Color? iconColor;

  static const double _tapSize = 40;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final resolvedIconColor =
        iconColor ?? (filled ? color.onPrimary : color.onSurfaceVariant);
    final content = IconTheme.merge(
      data: IconThemeData(color: resolvedIconColor, size: 24),
      child: child ?? Icon(icon),
    );

    final button = Opacity(
      opacity: onTap != null ? 1.0 : 0.38,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: _tapSize,
          height: _tapSize,
          alignment: Alignment.center,
          decoration:
              filled
                  ? BoxDecoration(
                    color: fillColor ?? color.primary,
                    shape: BoxShape.circle,
                  )
                  : null,
          child: content,
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _ChatTextFieldState extends State<ChatTextField> {
  int _sendPulse = 0;
  VoiceRecorderService? _recorder;
  bool _isRecording = false;
  bool _isCancelling = false;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTicker;
  DateTime? _recordingStartedAt;

  // Drag-up-to-cancel threshold, in logical pixels from the initial press
  // point. Chosen to be comfortably beyond an accidental small finger
  // wobble during a normal hold, but well within a deliberate upward drag.
  static const double _cancelDragThreshold = 80.0;

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _elapsedTicker?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleSend() {
    if (!(widget.enabled && _hasText)) return;
    setState(() => _sendPulse++);
    widget.onSend();
  }

  void _handleAttachTap(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showAttachImage)
                  ListTile(
                    leading: const Icon(Icons.photo_outlined),
                    title: const Text('Photos'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      widget.onAttachImage?.call();
                    },
                  ),
                if (widget.showAttachVideo)
                  ListTile(
                    leading: const Icon(Icons.videocam_outlined),
                    title: const Text('Video'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      widget.onAttachVideo?.call();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: const Text('Files'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    widget.onAttachFile?.call();
                  },
                ),
                if (widget.showGames)
                  ListTile(
                    leading: const Icon(Icons.sports_esports_outlined),
                    title: const Text('Games'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      widget.onOpenGames?.call();
                    },
                  ),
              ],
            ),
          ),
    );
  }

  Future<void> _startRecording() async {
    if (!widget.enabled || _isRecording) return;

    final recorder = VoiceRecorderService();
    final granted = await recorder.requestPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Attune needs microphone access to send voice messages',
          ),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () {
              openAppSettings();
            },
          ),
        ),
      );
      return;
    }

    try {
      await recorder.start();
    } on VoiceRecordingException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start recording. Please try again.'),
        ),
      );
      return;
    }

    _recordingStartedAt = DateTime.now();
    _elapsedTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(_recordingStartedAt!);
      });
    });

    setState(() {
      _recorder = recorder;
      _isRecording = true;
      _isCancelling = false;
      _elapsed = Duration.zero;
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isRecording) return;
    final isCancelling = -details.offsetFromOrigin.dy > _cancelDragThreshold;
    if (isCancelling != _isCancelling) {
      setState(() => _isCancelling = isCancelling);
    }
  }

  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    if (!_isRecording) return;
    final recorder = _recorder;
    final wasCancelling = _isCancelling;
    _elapsedTicker?.cancel();
    _elapsedTicker = null;

    setState(() {
      _isRecording = false;
      _isCancelling = false;
    });

    if (recorder == null) return;

    if (wasCancelling) {
      await recorder.cancel();
      recorder.dispose();
      _recorder = null;
      return;
    }

    try {
      final recording = await recorder.stop();
      if (recording.durationMs >=
          VoiceRecorderService.minDuration.inMilliseconds) {
        widget.onVoiceMessageRecorded?.call(recording);
      }
      // A too-short recording is silently discarded per the design spec —
      // no callback, no error.
    } on VoiceRecordingException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That recording could not be sent. Please try again.',
            ),
          ),
        );
      }
    } finally {
      recorder.dispose();
      _recorder = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showAttachSheet = widget.showAttachImage || widget.showAttachVideo;
    return SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showAttachSheet)
            _ComposerIcon(
              icon: Icons.add,
              onTap: widget.enabled ? () => _handleAttachTap(context) : null,
              tooltip: 'Add',
            ),
          if (widget.showTranslator)
            AnimatedSize(
              duration:
                  reduceMotionOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerLeft,
              child: AnimatedOpacity(
                duration:
                    reduceMotionOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                opacity: _hasText ? 1.0 : 0.0,
                child:
                    _hasText
                        ? _ComposerIcon(
                          icon: Icons.help_outline_rounded,
                          onTap:
                              widget.enabled ? widget.onOpenTranslator : null,
                          tooltip: 'Help me say this',
                        )
                        : const SizedBox(height: _ComposerIcon._tapSize),
              ),
            ),
          Expanded(
            child:
                _isRecording
                    ? VoiceRecordingBar(
                      elapsed: _elapsed,
                      // Live per-frame amplitude isn't wired to this bar in
                      // this task — VoiceRecorderService exposes the final
                      // downsampled waveform via stop(), not a live stream
                      // consumable outside the service. A constant mid-level
                      // fill keeps the bar visually alive without
                      // overengineering a live-amplitude plumbing path that
                      // the design spec didn't require for the recording BAR
                      // specifically (only the SENT bubble's waveform must
                      // reflect real amplitude data).
                      amplitude: 0.5,
                      isCancelling: _isCancelling,
                    )
                    : TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: ElevationTokens.sm,
                        end: _hasText ? 0 : ElevationTokens.sm,
                      ),
                      duration:
                          reduceMotionOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      builder: (context, elevation, child) {
                        // Interpolates Material's own elevation shadow
                        // (kElevationToShadow — the same subtle, tight,
                        // near-zero-spread double-shadow Card.elevation uses)
                        // between two whole-number presets, since the lookup
                        // table only has integer keys. A flat, hand-tuned
                        // BoxShadow (higher opacity, wider blur/spread) read
                        // too heavy next to send button next to it.
                        final lower = elevation.floor().clamp(0, 24);
                        final upper = elevation.ceil().clamp(0, 24);
                        final t = elevation - lower;
                        final lowerShadows =
                            kElevationToShadow[lower] ?? const [];
                        final upperShadows =
                            kElevationToShadow[upper] ?? const [];
                        final shadows =
                            lowerShadows.isEmpty || upperShadows.isEmpty
                                ? (t < 0.5 ? lowerShadows : upperShadows)
                                : List<BoxShadow>.generate(
                                  lowerShadows.length,
                                  (i) =>
                                      BoxShadow.lerp(
                                        lowerShadows[i],
                                        upperShadows[i],
                                        t,
                                      )!,
                                );
                        return Container(
                          margin: const EdgeInsets.only(right: Spacing.md),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              BorderRadiusTokens.xl,
                            ),
                            boxShadow: shadows,
                          ),
                          child: child,
                        );
                      },
                      // CardInkWell's own elevation stays 0 — the animated
                      // shadow above replaces it, since Card's elevation
                      // can't be tweened smoothly (it snaps between fixed
                      // Material shadow presets, which read as a glitch when
                      // toggled on every keystroke).
                      child: CardInkWell(
                        color: _hasText ? Colors.transparent : null,
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.xl,
                        ),
                        padding: const EdgeInsets.all(0),
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        child: Row(
                          children: [
                            Expanded(
                              child: AppTextFormField(
                                controller: widget.controller,
                                focusNode: widget.focusNode,
                                hintText: widget.hintText,
                                minLines: 1,
                                maxLines: 5,
                                showBorder: true,
                                focusedBorderColor: widget.sendButtonColor,
                                onFieldSubmitted: (_) => _handleSend(),
                                label: '',
                              ),
                            ),
                            // Trailing icons moved inside the pill, alongside
                            // the field, as an experiment — was previously a
                            // separate Row sibling outside CardInkWell.
                            if (widget.showGames && !_hasText)
                              _ComposerIcon(
                                icon: Icons.sports_esports_outlined,
                                onTap:
                                    widget.enabled ? widget.onOpenGames : null,
                                tooltip: 'Games',
                              ),
                            if (widget.showCaptureVideo && !_hasText)
                              _ComposerIcon(
                                icon: Icons.camera_alt_outlined,
                                onTap:
                                    widget.enabled
                                        ? widget.onCaptureVideo
                                        : null,
                                tooltip: 'Streak',
                              ),
                            if (widget.showVoiceMessage && !_hasText)
                              Semantics(
                                button: true,
                                label: 'Hold to record a voice message',
                                child: GestureDetector(
                                  onLongPressStart:
                                      (_) => unawaited(_startRecording()),
                                  onLongPressMoveUpdate: _onLongPressMoveUpdate,
                                  onLongPressEnd:
                                      (details) =>
                                          unawaited(_onLongPressEnd(details)),
                                  child: _ComposerIcon(
                                    icon: null,
                                    onTap: widget.enabled ? () {} : null,
                                    child: IconCrossfade(
                                      child: Icon(
                                        Icons.mic_none_rounded,
                                        key: ValueKey(_isRecording),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              _ComposerIcon(
                                icon: null,
                                onTap:
                                    widget.enabled && _hasText
                                        ? _handleSend
                                        : null,
                                tooltip: 'Send message',
                                filled: true,
                                fillColor:
                                    widget.sendButtonColor ?? Colors.green,
                                iconColor:
                                    widget.onSendButtonColor ?? Colors.white,
                                child: IconCrossfade(
                                  child: ScalePop(
                                    key: const ValueKey('send'),
                                    trigger: _sendPulse,
                                    child: const Icon(Icons.send_rounded),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
