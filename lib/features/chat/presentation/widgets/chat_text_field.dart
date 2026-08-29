import 'dart:async';

import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/motion/icon_crossfade.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/motion/scale_pop.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:permission_handler/permission_handler.dart';

import 'voice_recording_bar.dart';
import 'voice_recording_scrim.dart';
import 'package:attune/features/chat/presentation/widgets/voice_mic_halo.dart';
import 'package:attune/features/chat/presentation/widgets/voice_lock_pill.dart';

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
    this.recorderFactory,
    this.showCaptureVideo = false,
    this.showGames = false,
    this.enabled = true,
    this.hintText = 'Type a message...',
    this.focusNode,
    this.sendButtonColor,
    this.onSendButtonColor,
    this.haptics = const SystemHaptics(),
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
  /// as the dedicated leading camera icon rather than inside the '+' attach
  /// sheet, since it's a capture action, not a library pick.
  final VoidCallback? onCaptureVideo;

  /// File attach — placeholder for now, wired into the '+' sheet.
  final VoidCallback? onAttachFile;

  /// Games entry point — placeholder for now, surfaced as its own composer
  /// action rather than hidden inside the '+' sheet.
  final VoidCallback? onOpenGames;

  final bool showAttachImage;
  final bool showAttachVideo;
  final bool showTranslator;
  final bool showVoiceMessage;

  /// Builds the recorder. Injectable so widget tests can drive the
  /// press/lock/cancel gestures without a microphone.
  final VoiceRecorderService Function()? recorderFactory;
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

  /// Injected so tests can count the three transitions that must buzz:
  /// press-to-record, swipe-to-lock, and crossing into cancel.
  final Haptics haptics;

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

class _ChatAttachSheet extends StatelessWidget {
  const _ChatAttachSheet({
    required this.showPhotos,
    required this.showVideo,
    required this.showFiles,
    required this.onAttachImage,
    required this.onAttachVideo,
    required this.onAttachFile,
  });

  final bool showPhotos;
  final bool showVideo;
  final bool showFiles;
  final VoidCallback? onAttachImage;
  final VoidCallback? onAttachVideo;
  final VoidCallback? onAttachFile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BottomSheetHeader(title: ''),
          Gap(Spacing.lg),
          if (showPhotos)
            _ChatAttachRow(
              title: 'Photos',
              subtitle: 'Choose an image from your library',
              icon: Icons.photo_outlined,
              onTap: onAttachImage,
            ),
          if (showVideo)
            _ChatAttachRow(
              title: 'Video',
              subtitle: 'Share a video from your library',
              icon: Icons.videocam_outlined,
              onTap: onAttachVideo,
            ),
          if (showFiles)
            _ChatAttachRow(
              title: 'Files',
              subtitle: 'Attach a document or file',
              icon: Icons.insert_drive_file_outlined,
              onTap: onAttachFile,
            ),

          _ChatAttachRow(
            title: 'Location',
            subtitle: 'Attach location',
            icon: Icons.location_on_outlined,
            onTap: onAttachFile,
          ),
        ],
      ),
    );
  }
}

class _ChatAttachRow extends StatelessWidget {
  const _ChatAttachRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: InfoRowWidget(
        title: title,
        subtitle: ' ',
        icon: icon,
        iconColor: colorScheme.primary,
        showAvatar: false,
        disableTrailing: true,
        showTrailingArrow: false,
        showDivider: false,
        onTap: () {
          Navigator.of(context).pop();
          onTap?.call();
        },
      ),
    );
  }
}

class _ChatTextFieldState extends State<ChatTextField>
    with SingleTickerProviderStateMixin {
  int _sendPulse = 0;
  VoiceRecorderService? _recorder;
  bool _isRecording = false;

  /// True between the press and start() completing. The gesture can end
  /// inside that window, which must not be dropped.
  bool _startInFlight = false;
  bool _releasedDuringStart = false;
  bool _isCancelling = false;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTicker;

  /// Held vs locked. In the locked stage the finger is up and the bar's own
  /// delete/pause/send controls drive the recording instead of the gesture.
  VoiceRecordingStage _stage = VoiceRecordingStage.held;
  bool _isPaused = false;

  /// How far the finger has travelled toward the lock (0.0-1.0), driving
  /// the lock pill's fill/rise.
  double _lockProgress = 0.0;

  /// Rolling live-amplitude history for the recording waveform. Capped at
  /// [_maxLevels] because only the newest samples are ever drawn — an
  /// unbounded list would grow for the full 5-minute maximum recording
  /// while the extra samples stayed permanently off-screen.
  final List<double> _levels = <double>[];
  static const int _maxLevels = 96;

  // Drag-LEFT-to-cancel threshold, in logical pixels from the initial press
  // point. Chosen to be comfortably beyond an accidental small finger
  // wobble during a normal hold, but well within a deliberate drag.
  /// Deliberately BELOW the lock threshold. A leftward swipe carries
  /// upward drift, so a cancel that completes later than the lock never
  /// fires at all -- the recording locks and then sends, which is the
  /// opposite of what the user asked for.
  static const double _cancelDragThreshold = 56.0;

  /// Upward drag distance that locks the recording. Larger than the cancel
  /// threshold's counterpart because locking is the stickier, harder-to-
  /// undo outcome — an accidental lock strands the user in a recording
  /// they have to explicitly delete.
  /// Matches where VoiceLockPill is actually drawn (62px above the
  /// composer). The threshold was 100px against a pill at 62, so the
  /// finger reached the padlock and nothing happened -- it locked only
  /// 38px PAST the visible target, which reads as the gesture not
  /// working at all.
  static const double _lockDragThreshold = 62.0;

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  /// Drives the recording scrim's fade. An OverlayEntry rather than a
  /// route: a route pushed mid-gesture moves the pointer to a new
  /// Navigator layer and breaks the drag lock and cancel both read from.
  late final AnimationController _scrimController;
  OverlayEntry? _scrimEntry;

  /// The scrim reads its live values from here rather than from a rebuild
  /// of this State. An OverlayEntry is a separate element subtree, so
  /// marking it dirty from this widget's build() is the framework's
  /// "markNeedsBuild during build" error; a notifier lets the overlay
  /// rebuild itself on its own schedule.
  final ValueNotifier<VoiceScrimData> _scrimData = ValueNotifier(
    const VoiceScrimData(),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _scrimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
  }

  /// Icons the idle row draws AFTER the mic — games, plus the send button
  /// shown when the mic is hidden.
  int get _trailingIconCount =>
      (widget.showGames ? 1 : 0) + (widget.showVoiceMessage ? 0 : 1);

  void _showScrim() {
    if (_scrimEntry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder:
          (_) => VoiceRecordingScrim(
            animation: _scrimController,
            data: _scrimData,
          ),
    );
    _scrimEntry = entry;
    overlay.insert(entry);
    _syncScrim();
    _scrimController.forward();
  }

  /// Pushes the live values the scrim draws. Writing a notifier rather
  /// than marking the entry dirty keeps this safe to call from build.
  void _syncScrim() {
    if (_scrimEntry == null) return;
    _scrimData.value = VoiceScrimData(
      elapsed: _elapsed,
      amplitude: _levels.isEmpty ? 0.0 : _levels.last,
      levels: List<double>.unmodifiable(_levels),
      isCancelling: _isCancelling,
    );
  }

  Future<void> _hideScrim() async {
    final entry = _scrimEntry;
    if (entry == null) return;
    _scrimEntry = null;
    await _scrimController.reverse();
    entry.remove();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _elapsedTicker?.cancel();
    // Removed directly, not via _hideScrim: an overlay entry outlives this
    // State unless taken down here, and awaiting a reverse during dispose
    // would tick a disposed controller.
    _scrimEntry?.remove();
    _scrimEntry = null;
    _scrimController.dispose();
    _scrimData.dispose();
    // Detach the level listener before disposing — the service disposes its
    // ValueNotifier, and a listener still attached to it would fire against
    // a disposed notifier.
    final recorder = _recorder;
    if (recorder != null) _releaseRecorder(recorder);
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
    BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      maxHeight: 360.h,
      padding: Spacing.md,
      widget: _ChatAttachSheet(
        showPhotos: widget.showAttachImage,
        showVideo: widget.showAttachVideo,
        showFiles: widget.onAttachFile != null,
        onAttachImage: widget.onAttachImage,
        onAttachVideo: widget.onAttachVideo,
        onAttachFile: widget.onAttachFile,
      ),
    );
  }

  Future<void> _startRecording() async {
    if (!widget.enabled || _isRecording || _startInFlight) return;
    _startInFlight = true;
    _releasedDuringStart = false;
    _dragOffset = Offset.zero;
    widget.haptics.light();

    final recorder = (widget.recorderFactory ?? VoiceRecorderService.new)();
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
      _startInFlight = false;
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
      _startInFlight = false;
      return;
    }

    // Elapsed comes from the service (which subtracts paused spans) rather
    // than a local wall-clock difference, so the timer the user watches and
    // the durationMs eventually persisted can never disagree.
    _elapsedTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _elapsed = recorder.elapsed);
      _syncScrim();
    });

    recorder.currentLevel.addListener(_onLevel);

    _showScrim();

    setState(() {
      _recorder = recorder;
      _isRecording = true;
      _isCancelling = false;
      _stage = VoiceRecordingStage.held;
      _isPaused = false;
      _lockProgress = 0.0;
      _levels.clear();
      _elapsed = Duration.zero;
    });

    _startInFlight = false;

    // The finger came up while start() was still awaiting permission or the
    // plugin. Without this the end handler already returned (it saw
    // _isRecording == false) and nothing would ever stop the recorder --
    // the mic would stay live with no UI attached to it.
    if (_releasedDuringStart) {
      _releasedDuringStart = false;
      await _finishRecording();
    }
  }

  /// Appends one live amplitude sample, dropping the oldest once the
  /// on-screen capacity is exceeded.
  void _onLevel() {
    final recorder = _recorder;
    if (recorder == null || !mounted) return;
    setState(() {
      _levels.add(recorder.currentLevel.value);
      if (_levels.length > _maxLevels) _levels.removeAt(0);
    });
    _syncScrim();
  }

  /// Detaches this widget from a recorder and releases it. Centralized
  /// because every teardown path (cancel, send, dispose, error) must
  /// remove the level listener before disposing — a listener left attached
  /// to a disposed notifier throws on the next sample.
  void _releaseRecorder(VoiceRecorderService recorder) {
    recorder.currentLevel.removeListener(_onLevel);
    recorder.dispose();
    if (identical(_recorder, recorder)) _recorder = null;
  }

  /// Accumulated drag from the press origin. Pan reports deltas, where
  /// long-press reported an absolute offset from origin.
  Offset _dragOffset = Offset.zero;

  void _onRecordPointerMove(Offset delta) {
    _dragOffset += delta;
    _applyRecordDrag(_dragOffset);
  }

  void _applyRecordDrag(Offset offset) {
    if (!_isRecording) return;
    // Once locked the finger is irrelevant — the bar's own controls take
    // over, and further drag must not re-arm cancel.
    if (_stage == VoiceRecordingStage.locked) return;

    final up = -offset.dy;

    // Cancel is a LEFTWARD drag (matching the "slide to cancel ‹" hint and
    // WhatsApp's own gesture); lock is an UPWARD one. Previously cancel was
    // bound to the upward drag, which is the same direction as the lock —
    // the two would have been indistinguishable.
    final isCancelling = -offset.dx > _cancelDragThreshold;
    final lockProgress = (up / _lockDragThreshold).clamp(0.0, 1.0);

    if (up >= _lockDragThreshold && !isCancelling) {
      _lockRecording();
      return;
    }

    // Rising edge only: firing on every move while the finger is left of
    // the threshold turns one gesture into a continuous rattle.
    if (isCancelling && !_isCancelling) widget.haptics.medium();

    if (isCancelling != _isCancelling || lockProgress != _lockProgress) {
      setState(() {
        _isCancelling = isCancelling;
        _lockProgress = lockProgress;
      });
      _syncScrim();
    }
  }

  /// Promotes a held recording to the locked stage: the finger can lift
  /// and recording continues under the bar's delete/pause/send controls.
  void _lockRecording() {
    if (_stage == VoiceRecordingStage.locked) return;
    widget.haptics.medium();
    setState(() {
      _stage = VoiceRecordingStage.locked;
      _isCancelling = false;
      _lockProgress = 1.0;
    });
  }

  Future<void> _onRecordDragEnd() async {
    // Released before start() finished: remember it, and _startRecording
    // finishes the recording as soon as it has one to finish.
    if (_startInFlight) {
      _releasedDuringStart = true;
      return;
    }
    if (!_isRecording) return;
    // Locked: lifting the finger is exactly what locking is FOR. Recording
    // continues; the bar's delete/pause/send controls own it from here.
    if (_stage == VoiceRecordingStage.locked) return;

    if (_isCancelling) {
      await _cancelRecording();
      return;
    }
    await _finishRecording();
  }

  /// Discards the recording and its file. Shared by the slide-to-cancel
  /// gesture and the locked stage's delete button.
  Future<void> _cancelRecording() async {
    final recorder = _recorder;
    _stopTicker();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _isCancelling = false;
        _stage = VoiceRecordingStage.held;
        _isPaused = false;
        _lockProgress = 0.0;
        _levels.clear();
      });
    }
    if (recorder == null) return;
    await recorder.cancel();
    _releaseRecorder(recorder);
  }

  /// Stops and hands off the recording. Shared by releasing the hold and
  /// the locked stage's send button.
  Future<void> _finishRecording() async {
    final recorder = _recorder;
    _stopTicker();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _isCancelling = false;
        _stage = VoiceRecordingStage.held;
        _isPaused = false;
        _lockProgress = 0.0;
        _levels.clear();
      });
    }

    if (recorder == null) return;

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
      _releaseRecorder(recorder);
    }
  }

  /// Locked-stage pause/resume. A failure here leaves the recording
  /// running rather than desyncing the UI from the recorder's real state.
  Future<void> _togglePause() async {
    final recorder = _recorder;
    if (recorder == null) return;
    try {
      if (recorder.isPaused) {
        await recorder.resume();
      } else {
        await recorder.pause();
      }
    } on VoiceRecordingException {
      return;
    }
    if (mounted) setState(() => _isPaused = recorder.isPaused);
  }

  /// Called by both stop paths — cancel and finish — and nowhere else,
  /// so taking the scrim down here means neither path can leave it up.
  void _stopTicker() {
    _elapsedTicker?.cancel();
    _elapsedTicker = null;
    unawaited(_hideScrim());
  }

  @override
  Widget build(BuildContext context) {
    final showAttachSheet =
        widget.showAttachImage ||
        widget.showAttachVideo ||
        widget.onAttachFile != null;
    final colorScheme = Theme.of(context).colorScheme;
    final leadingAction =
        widget.showCaptureVideo
            ? _ComposerIcon(
              icon: Icons.camera_alt_rounded,
              onTap: widget.enabled ? widget.onCaptureVideo : null,
              tooltip: 'Camera',
              filled: true,
              fillColor: colorScheme.primary,
              iconColor: colorScheme.onPrimary,
            )
            : null;

    // Extracted so the recording composer can place the SAME mic
    // beside the bar. Previously the bar replaced the entire icon
    // row, so the mic, its halo and its progress ring were not on
    // screen at all while recording.
    final micSlot = Semantics(
      button: true,
      label: 'Hold to record a voice message',
      // Press, not long-press: the mic is a
      // press-and-hold control, so binding start to
      // onLongPressStart gave it a ~500ms dead zone in
      // which the user is already holding, sees nothing,
      // and gets no recording at all if they release.
      // A raw pan recognizer starts on touch-down and
      // reports drags in the same gesture, which is what
      // lock (up) and cancel (left) need.
      // A raw Listener rather than GestureDetector's
      // pan callbacks: pan does not report an end for a
      // press with no movement, so a quick
      // press-and-release never stopped the recorder.
      // Pointer events always pair down with up/cancel.
      child: Listener(
        onPointerDown: (_) => unawaited(_startRecording()),
        onPointerMove: (event) => _onRecordPointerMove(event.delta),
        onPointerUp: (_) => unawaited(_onRecordDragEnd()),
        onPointerCancel: (_) => unawaited(_onRecordDragEnd()),
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.38,
          child: SizedBox(
            width: _ComposerIcon._tapSize,
            height: _ComposerIcon._tapSize,
            child: Center(
              child: VoiceMicHalo(
                amplitude: _levels.isEmpty ? 0.0 : _levels.last,
                isRecording: _isRecording,
                isLocked: _stage == VoiceRecordingStage.locked,
                progress:
                    _elapsed.inMilliseconds /
                    VoiceRecorderService.maxDuration.inMilliseconds,
                // While recording, VoiceMicHalo sets onPrimary against
                // its filled disc; overriding it here would paint the
                // glyph the same colour as the surface behind it.
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: _isRecording ? null : colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                  child: IconCrossfade(
                    child: Icon(
                      _isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
                      key: ValueKey(_isRecording),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final composer = Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child:
          // Held stage keeps the ordinary icon row: the scrim above now
          // carries the counter, waveform and slide-to-cancel hint, so a
          // second bar down here would compete with it. The locked stage
          // still needs the bar for its delete/pause/send controls.
          _isRecording && _stage == VoiceRecordingStage.locked
              ? _RecordingComposer(
                // Mirrors the idle row's trailing icons exactly: games,
                // plus the send button it shows when the mic is hidden.
                trailingSlots:
                    (widget.showGames ? 1 : 0) +
                    (widget.showVoiceMessage ? 0 : 1),
                elapsed: _elapsed,
                amplitude: _levels.isEmpty ? 0.0 : _levels.last,
                levels: _levels,
                isCancelling: _isCancelling,
                stage: _stage,
                isPaused: _isPaused,
                micSlot: micSlot,
                onCancel: () => unawaited(_cancelRecording()),
                onTogglePause: () => unawaited(_togglePause()),
                onSend: () => unawaited(_finishRecording()),
              )
              : Container(
                constraints: const BoxConstraints(minHeight: 54),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border.all(color: colorScheme.onSurface, width: .2),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.full),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (leadingAction != null) ...[
                      leadingAction,
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        enabled: widget.enabled,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        onSubmitted: (_) => _handleSend(),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 18,
                          height: 1.25,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          hintStyle: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: Spacing.sm,
                            horizontal: Spacing.sm,
                          ),
                        ),
                      ),
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
                                        widget.enabled
                                            ? widget.onOpenTranslator
                                            : null,
                                    tooltip: 'Help me say this',
                                  )
                                  : const SizedBox(
                                    height: _ComposerIcon._tapSize,
                                  ),
                        ),
                      ),
                    if (!_hasText && showAttachSheet)
                      _ComposerIcon(
                        icon: Icons.add_circle_outline_rounded,
                        onTap:
                            widget.enabled
                                ? () => _handleAttachTap(context)
                                : null,
                        tooltip: 'More',
                      ),
                    if (!_hasText && widget.showVoiceMessage) micSlot,
                    if (!_hasText && widget.showGames)
                      _ComposerIcon(
                        icon: Icons.sports_esports_outlined,
                        onTap: widget.enabled ? widget.onOpenGames : null,
                        tooltip: 'Games',
                      ),
                    if (_hasText || !widget.showVoiceMessage)
                      _ComposerIcon(
                        icon: null,
                        onTap: widget.enabled && _hasText ? _handleSend : null,
                        tooltip: 'Send message',
                        filled: _hasText,
                        fillColor:
                            widget.sendButtonColor ?? colorScheme.primary,
                        iconColor: widget.onSendButtonColor,
                        child: IconCrossfade(
                          child: ScalePop(
                            key: const ValueKey('send'),
                            trigger: _sendPulse,
                            child: const Icon(Icons.send_rounded),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
    );

    return SafeArea(
      top: false,
      child: Stack(
        // The lock pill deliberately overflows the composer's top edge, the
        // way WhatsApp floats it over the message list.
        clipBehavior: Clip.none,
        alignment: Alignment.bottomRight,
        children: [
          composer,
          // Held stage only: once locked the pill has served its purpose,
          // and the bar's own controls replace it.
          if (_isRecording && _stage == VoiceRecordingStage.held)
            Positioned(
              // Centred on the mic rather than at a fixed inset: the pill
              // is the target of an upward drag that STARTS on the mic, so
              // any horizontal offset between them reads as the gesture
              // pointing somewhere the finger is not going.
              //
              // Right edge (12 outer + 6 inner padding) to the mic's
              // centre: half the mic's own hit box, plus every trailing
              // icon after it.
              right:
                  12.0 +
                  6.0 +
                  _ComposerIcon._tapSize / 2 +
                  _trailingIconCount * _ComposerIcon._tapSize -
                  VoiceLockPill.width / 2,
              bottom: 62,
              child: VoiceLockPill(dragProgress: _lockProgress),
            ),
        ],
      ),
    );
  }
}

/// The composer while a voice note is being recorded: the bar on the
/// left, the mic still in its own place on the right.
///
/// Previously VoiceRecordingBar replaced the entire icon row, which meant
/// the mic — and therefore its halo and progress ring — was not rendered
/// at all mid-recording. Keeping it in place also means the button under
/// the user's finger never moves, which is what makes swipe-to-lock and
/// slide-to-cancel feel anchored.
class _RecordingComposer extends StatelessWidget {
  const _RecordingComposer({
    required this.elapsed,
    required this.amplitude,
    required this.levels,
    required this.isCancelling,
    required this.stage,
    required this.isPaused,
    required this.micSlot,
    required this.trailingSlots,
    this.onCancel,
    this.onTogglePause,
    this.onSend,
  });

  final Duration elapsed;
  final double amplitude;
  final List<double> levels;
  final bool isCancelling;
  final VoiceRecordingStage stage;
  final bool isPaused;
  final Widget micSlot;

  /// How many icons the idle composer draws AFTER the mic. Reserved here
  /// so the mic does not shift horizontally when recording starts.
  final int trailingSlots;
  final VoidCallback? onCancel;
  final VoidCallback? onTogglePause;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: VoiceRecordingBar(
            elapsed: elapsed,
            amplitude: amplitude,
            levels: levels,
            isCancelling: isCancelling,
            stage: stage,
            isPaused: isPaused,
            onCancel: onCancel,
            onTogglePause: onTogglePause,
            onSend: onSend,
          ),
        ),
        const SizedBox(width: Spacing.sm),
        micSlot,
        // Matches the idle composer's inner horizontal padding, which the
        // recording row does not otherwise have. Without it the mic sits
        // 6px right of where the finger pressed it.
        const SizedBox(width: 6),
        // The trailing icons the idle composer draws to the right of the
        // mic (games, send) are replaced one-for-one, so the mic keeps its
        // horizontal position when recording begins. The finger is already
        // on that button — moving it under the touch makes the lock and
        // cancel drags read from a shifted origin.
        for (var i = 0; i < trailingSlots; i++)
          const SizedBox(
            width: _ComposerIcon._tapSize,
            height: _ComposerIcon._tapSize,
          ),
      ],
    );
  }
}
