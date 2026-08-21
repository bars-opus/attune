import 'dart:io';
import 'dart:typed_data';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Full-screen trim UI shown unconditionally after every gallery video pick,
/// before ChatVideoPreparer.prepare() runs, so the transcode encodes exactly
/// the range the user selects. Reached via the 'videoTrim' named route
/// (registered in app_router.dart), which takes a VideoTrimRouteArgs via
/// `extra` and returns the confirmed {start, end} window as a typed pop
/// result — null means the user backed out.
///
/// Selection is physically clamped to
/// [ChatVideoPreparer.minDuration, ChatVideoPreparer.maxDuration] by the
/// handle-drag logic itself — ChatVideoPreparer's own duration-bounds check
/// is a defense-in-depth backstop, not the primary enforcement mechanism.
class VideoTrimScreen extends StatefulWidget {
  const VideoTrimScreen({
    super.key,
    required this.sourcePath,
    required this.sourceDuration,
  });

  final String sourcePath;
  final Duration sourceDuration;

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  static const int _filmstripFrameCount = 8;

  late Duration _windowStart;
  late Duration _windowEnd;
  VideoPlayerController? _controller;
  bool _controllerFailed = false;
  List<Uint8List?>? _filmstripFrames;

  @override
  void initState() {
    super.initState();
    // Pre-position: full clip if already under the cap, else a
    // maxDuration-wide window at the start.
    if (widget.sourceDuration <= ChatVideoPreparer.maxDuration) {
      _windowStart = Duration.zero;
      _windowEnd = widget.sourceDuration;
    } else {
      _windowStart = Duration.zero;
      _windowEnd = ChatVideoPreparer.maxDuration;
    }

    _initController();
    _loadFilmstrip();
  }

  // VideoPlayerController.file() opens a real platform channel that has no
  // implementation in the flutter_test VM host (no engine/native side), so
  // both construction and initialize() can throw or leave the future
  // unresolved there. Neither case should crash this screen — the
  // confirm-button/pre-positioning logic this screen is tested on doesn't
  // depend on playback actually working. Errors are swallowed and recorded
  // via _controllerFailed so the UI falls back to a static placeholder
  // instead of a spinner that would never resolve.
  void _initController() {
    try {
      final controller = VideoPlayerController.file(File(widget.sourcePath));
      _controller = controller;
      controller
          .initialize()
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((_) {
            if (mounted) setState(() => _controllerFailed = true);
          });
    } catch (_) {
      _controllerFailed = true;
    }
  }

  // video_thumbnail's platform channel has the same test-host limitation as
  // VideoPlayerController above — swallow failures per-frame and just leave
  // that slot blank in the filmstrip.
  Future<void> _loadFilmstrip() async {
    final frames = List<Uint8List?>.filled(_filmstripFrameCount, null);
    final totalMicros = widget.sourceDuration.inMicroseconds;
    for (var i = 0; i < _filmstripFrameCount; i++) {
      final atMicros =
          totalMicros <= 0
              ? 0
              : (totalMicros * i / _filmstripFrameCount).round();
      try {
        frames[i] = await VideoThumbnail.thumbnailData(
          video: widget.sourcePath,
          timeMs: Duration(microseconds: atMicros).inMilliseconds,
          quality: 50,
          maxWidth: 120,
        );
      } catch (_) {
        // Leave this slot blank — filmstrip is a visual aid only.
      }
      if (!mounted) return;
    }
    if (mounted) setState(() => _filmstripFrames = frames);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Duration get _selectedDuration => _windowEnd - _windowStart;

  bool get _canConfirm => _selectedDuration >= ChatVideoPreparer.minDuration;

  // Duration doesn't implement num, so it has no built-in clamp — this
  // mirrors num.clamp's semantics for the Duration comparisons below.
  static Duration _clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _onStartHandleChanged(Duration newStart) {
    final clampedStart = _clampDuration(newStart, Duration.zero, _windowEnd);
    final maxAllowedStart = _windowEnd - ChatVideoPreparer.minDuration;
    final minAllowedStart = _clampDuration(
      _windowEnd - ChatVideoPreparer.maxDuration,
      Duration.zero,
      widget.sourceDuration,
    );
    setState(() {
      _windowStart = _clampDuration(
        clampedStart,
        minAllowedStart < Duration.zero ? Duration.zero : minAllowedStart,
        maxAllowedStart < Duration.zero ? Duration.zero : maxAllowedStart,
      );
    });
  }

  void _onEndHandleChanged(Duration newEnd) {
    final maxAllowedEnd = _clampDuration(
      _windowStart + ChatVideoPreparer.maxDuration,
      Duration.zero,
      widget.sourceDuration,
    );
    final minAllowedEnd = _windowStart + ChatVideoPreparer.minDuration;
    setState(() {
      _windowEnd = _clampDuration(newEnd, minAllowedEnd, maxAllowedEnd);
    });
  }

  void _handleDragDelta(
    double dxMicrosPerPixel,
    double dx, {
    required bool isStart,
  }) {
    final deltaMicros = (dx * dxMicrosPerPixel).round();
    if (deltaMicros == 0) return;
    if (isStart) {
      _onStartHandleChanged(_windowStart + Duration(microseconds: deltaMicros));
    } else {
      _onEndHandleChanged(_windowEnd + Duration(microseconds: deltaMicros));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Trim video')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child:
                  _controller?.value.isInitialized == true
                      ? AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      )
                      : _controllerFailed
                      ? ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Icon(
                            Icons.movie_outlined,
                            size: 48,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                      : const Center(child: CircularProgressIndicator()),
            ),
            Padding(
              padding: EdgeInsets.all(Spacing.md),
              child: Text(
                '${_formatDuration(_selectedDuration)} / ${_formatDuration(ChatVideoPreparer.maxDuration)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            // Filmstrip scrubber with draggable handles. Handle drag calls
            // _onStartHandleChanged/_onEndHandleChanged, both of which
            // physically clamp the resulting selection to
            // [minDuration, maxDuration] before it's ever applied to state.
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;
                  final totalMicros = widget.sourceDuration.inMicroseconds
                      .clamp(1, double.maxFinite.toInt());
                  final microsPerPixel = totalMicros / trackWidth;
                  final startX =
                      _windowStart.inMicroseconds / totalMicros * trackWidth;
                  final endX =
                      _windowEnd.inMicroseconds / totalMicros * trackWidth;

                  return SizedBox(
                    height: 64,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadiusTokens.mdAll,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: colorScheme.outline),
                              borderRadius: BorderRadiusTokens.mdAll,
                            ),
                            child: Row(
                              children: List.generate(_filmstripFrameCount, (
                                i,
                              ) {
                                final frame = _filmstripFrames?[i];
                                return Expanded(
                                  child:
                                      frame != null
                                          ? Image.memory(
                                            frame,
                                            fit: BoxFit.cover,
                                            height: 64,
                                            gaplessPlayback: true,
                                          )
                                          : Container(
                                            color:
                                                colorScheme
                                                    .surfaceContainerHighest,
                                          ),
                                );
                              }),
                            ),
                          ),
                        ),
                        // Dim the unselected regions either side of the window.
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: startX.clamp(0, trackWidth),
                          child: ColoredBox(
                            color: colorScheme.scrim.withValues(alpha: 0.55),
                          ),
                        ),
                        Positioned(
                          left: endX.clamp(0, trackWidth),
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: ColoredBox(
                            color: colorScheme.scrim.withValues(alpha: 0.55),
                          ),
                        ),
                        // Selection border.
                        Positioned(
                          left: startX.clamp(0, trackWidth),
                          width: (endX - startX).clamp(0, trackWidth),
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: colorScheme.primary,
                                    width: 3,
                                  ),
                                  bottom: BorderSide(
                                    color: colorScheme.primary,
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Start handle — 48dp minimum touch target.
                        Positioned(
                          left: (startX - 24).clamp(0, trackWidth - 48),
                          top: 0,
                          bottom: 0,
                          width: 48,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate:
                                (details) => _handleDragDelta(
                                  microsPerPixel,
                                  details.delta.dx,
                                  isStart: true,
                                ),
                            child: Center(
                              child: Container(
                                width: 4,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // End handle — 48dp minimum touch target.
                        Positioned(
                          left: (endX - 24).clamp(0, trackWidth - 48),
                          top: 0,
                          bottom: 0,
                          width: 48,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate:
                                (details) => _handleDragDelta(
                                  microsPerPixel,
                                  details.delta.dx,
                                  isStart: false,
                                ),
                            child: Center(
                              child: Container(
                                width: 4,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.all(Spacing.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      _canConfirm
                          ? () => context.pop((
                            start: _windowStart,
                            end: _windowEnd,
                          ))
                          : null,
                  child: const Text('Use this clip'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
