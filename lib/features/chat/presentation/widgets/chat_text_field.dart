import 'dart:async';

import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/core/ui/motion/icon_crossfade.dart';
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
    this.showAttachImage = false,
    this.showAttachVideo = false,
    this.showTranslator = false,
    this.showVoiceMessage = false,
    this.showCaptureVideo = false,
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

  /// Opens the ephemeral (view-once) camera capture flow. Purely additive
  /// alongside onAttachImage/onAttachVideo/onVoiceMessageRecorded — a new,
  /// dedicated leading icon, not folded into the existing Photo/Video
  /// attach-sheet dispatcher.
  final VoidCallback? onCaptureVideo;

  final bool showAttachImage;
  final bool showAttachVideo;
  final bool showTranslator;
  final bool showVoiceMessage;
  final bool showCaptureVideo;
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
    if (!widget.showAttachVideo || widget.onAttachVideo == null) {
      widget.onAttachImage?.call();
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo Library'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onAttachImage?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video Library'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onAttachVideo?.call();
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
      if (recording.durationMs >= VoiceRecorderService.minDuration.inMilliseconds) {
        widget.onVoiceMessageRecorded?.call(recording);
      }
      // A too-short recording is silently discarded per the design spec —
      // no callback, no error.
    } on VoiceRecordingException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That recording could not be sent. Please try again.'),
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
    return SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.showAttachImage)
            IconButton(
              onPressed: widget.enabled ? () => _handleAttachTap(context) : null,
              icon: const Icon(Icons.photo_outlined),
              tooltip: widget.showAttachVideo ? 'Add media' : 'Add image',
            ),
          if (widget.showCaptureVideo)
            IconButton(
              onPressed: widget.enabled ? widget.onCaptureVideo : null,
              icon: const Icon(Icons.camera_alt_outlined),
              tooltip: 'Record a video',
            ),
          if (widget.showTranslator && _hasText)
            IconButton(
              onPressed: widget.enabled ? widget.onOpenTranslator : null,
              icon: const Icon(Icons.help_outline_rounded),
              tooltip: 'Help me say this',
            ),
          Expanded(
            child: _isRecording
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
                : CardInkWell(
                    borderRadius: BorderRadius.circular(BorderRadiusTokens.xl),
                    padding: const EdgeInsets.all(0),
                    margin: const EdgeInsets.all(0),
                    elevation: ElevationTokens.sm,
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
          ),
          const SizedBox(width: 8),
          if (widget.showVoiceMessage && !_hasText)
            Semantics(
              button: true,
              label: 'Hold to record a voice message',
              child: GestureDetector(
                onLongPressStart: (_) => unawaited(_startRecording()),
                onLongPressMoveUpdate: _onLongPressMoveUpdate,
                onLongPressEnd: (details) =>
                    unawaited(_onLongPressEnd(details)),
                // No `tooltip:` here deliberately — IconButton's tooltip
                // wraps its child in its own long-press-to-show
                // GestureDetector, which wins the gesture arena against
                // this widget's own onLongPressStart and silently eats the
                // hold-to-record gesture (confirmed empirically: with
                // `tooltip` set, onLongPressStart never fires). The
                // Semantics label above covers the accessibility purpose
                // the tooltip would have served.
                child: IconButton.filled(
                  onPressed: widget.enabled ? () {} : null,
                  style: widget.sendButtonColor == null
                      ? null
                      : IconButton.styleFrom(
                          backgroundColor: widget.sendButtonColor,
                          foregroundColor: widget.onSendButtonColor,
                        ),
                  icon: IconCrossfade(
                    child: Icon(
                      Icons.mic_none_rounded,
                      key: ValueKey(_isRecording),
                    ),
                  ),
                ),
              ),
            )
          else
            IconButton.filled(
              onPressed: widget.enabled && _hasText ? _handleSend : null,
              tooltip: 'Send message',
              style: widget.sendButtonColor == null
                  ? null
                  : IconButton.styleFrom(
                      backgroundColor: widget.sendButtonColor,
                      foregroundColor: widget.onSendButtonColor,
                    ),
              icon: IconCrossfade(
                child: ScalePop(
                  key: const ValueKey('send'),
                  trigger: _sendPulse,
                  child: const Icon(Icons.send_rounded),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
